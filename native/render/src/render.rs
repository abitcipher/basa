use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use base64::Engine;
use chromiumoxide::cdp::browser_protocol::fetch::{
    self, ContinueRequestParams, EventRequestPaused, FailRequestParams,
};
use chromiumoxide::cdp::browser_protocol::network::{
    ErrorReason, EventLoadingFailed, EventLoadingFinished, EventRequestWillBeSent,
    EventResponseReceived, GetResponseBodyParams, RequestId, ResourceType,
    SetUserAgentOverrideParams,
};
use chromiumoxide::cdp::browser_protocol::security::SetIgnoreCertificateErrorsParams;
use chromiumoxide::cdp::browser_protocol::target::{
    CreateBrowserContextParams, CreateTargetParams,
};
use chromiumoxide::Browser;
use futures::StreamExt;
use serde::{Deserialize, Serialize};

use crate::guard;

#[derive(Debug, Deserialize)]
pub struct Request {
    pub url: String,
    #[serde(default)]
    pub insecure: bool,
    #[serde(default = "default_timeout")]
    pub timeout_ms: u64,
    #[serde(default = "default_idle")]
    pub idle_ms: u64,
    #[serde(default = "default_settle")]
    pub settle_ms: u64,
    #[serde(default = "default_block")]
    pub block: Vec<String>,
    #[serde(default)]
    pub user_agent: Option<String>,
}

fn default_timeout() -> u64 {
    30_000
}
fn default_settle() -> u64 {
    5_000
}
fn default_idle() -> u64 {
    800
}
fn default_block() -> Vec<String> {
    vec!["image".into(), "media".into(), "font".into()]
}

#[derive(Debug, Serialize)]
pub struct Rendered {
    pub url: String,
    pub status: Option<i64>,
    pub html: String,
    pub json: Vec<JsonResponse>,
    pub source: Option<String>,
    pub ms: u128,
    pub load_ms: u128,
}

#[derive(Debug, Serialize)]
pub struct JsonResponse {
    pub url: String,
    pub status: i64,
    pub body: String,
}

const MAX_HTML: usize = 5_000_000;
const MAX_JSON_BODY: usize = 1_000_000;
const MAX_JSON: usize = 40;

#[derive(Default)]
struct Net {
    inflight: HashMap<RequestId, Instant>,
    last_activity: Option<Instant>,
    status: Option<i64>,
    document: Option<RequestId>,
    json: Vec<(RequestId, String, i64)>,
    finished: Vec<RequestId>,
}

pub async fn render(
    browser: &Browser,
    req: Request,
    allow_private: bool,
) -> Result<Rendered, String> {
    let started = Instant::now();

    if !guard::allowed(&req.url, allow_private).await {
        return Err("private_address".into());
    }

    let context = browser
        .create_browser_context(CreateBrowserContextParams::default())
        .await
        .map_err(|e| format!("context: {e}"))?;

    let target = CreateTargetParams::builder()
        .url("about:blank")
        .browser_context_id(context.clone())
        .build()
        .map_err(|e| format!("target: {e}"))?;

    let page = browser
        .new_page(target)
        .await
        .map_err(|e| format!("page: {e}"))?;
    let result = tokio::time::timeout(
        Duration::from_millis(req.timeout_ms),
        run(&page, &req, started),
    )
    .await
    .unwrap_or_else(|_| Err("timeout".into()));

    let _ = page.close().await;
    let _ = browser.dispose_browser_context(context).await;
    result
}

async fn run(
    page: &chromiumoxide::Page,
    req: &Request,
    started: Instant,
) -> Result<Rendered, String> {
    let net = Arc::new(Mutex::new(Net::default()));
    let block: Vec<String> = req.block.iter().map(|b| b.to_lowercase()).collect();

    if req.insecure {
        page.execute(SetIgnoreCertificateErrorsParams::new(true))
            .await
            .map_err(|e| format!("insecure: {e}"))?;
    }

    if let Some(ua) = &req.user_agent {
        page.execute(SetUserAgentOverrideParams::new(ua.clone()))
            .await
            .map_err(|e| format!("user agent: {e}"))?;
    }

    let mut paused = page
        .event_listener::<EventRequestPaused>()
        .await
        .map_err(|e| e.to_string())?;
    let intercept_page = page.clone();
    let intercept = tokio::spawn(async move {
        while let Some(event) = paused.next().await {
            let kind = format!("{:?}", event.resource_type).to_lowercase();
            let id = event.request_id.clone();

            let _ = if block.contains(&kind) {
                intercept_page
                    .execute(FailRequestParams::new(id, ErrorReason::BlockedByClient))
                    .await
                    .map(|_| ())
            } else {
                intercept_page
                    .execute(ContinueRequestParams::new(id))
                    .await
                    .map(|_| ())
            };
        }
    });

    page.execute(fetch::EnableParams::default())
        .await
        .map_err(|e| format!("intercept: {e}"))?;

    let watchers = watch_network(page, net.clone()).await?;

    let nav = page.goto(req.url.as_str()).await;
    let load_ms = started.elapsed().as_millis();

    if let Err(e) = nav {
        stop(intercept, watchers);
        return Err(format!("navigate: {e}"));
    }

    wait_idle(
        &net,
        Duration::from_millis(req.idle_ms),
        Duration::from_millis(req.settle_ms),
        started,
        req.timeout_ms,
    )
    .await;

    let html = page.content().await.map_err(|e| format!("content: {e}"))?;
    let url = page
        .url()
        .await
        .ok()
        .flatten()
        .unwrap_or_else(|| req.url.clone());
    let json = json_bodies(page, &net).await;
    let document = net.lock().unwrap().document.clone();
    let source = match document {
        Some(id) => body(page, id).await.filter(|b| b.len() <= MAX_HTML),
        None => None,
    };
    let status = net.lock().unwrap().status;

    stop(intercept, watchers);

    if html.len() > MAX_HTML {
        return Err("too_large".into());
    }

    Ok(Rendered {
        url,
        status,
        html,
        json,
        source,
        ms: started.elapsed().as_millis(),
        load_ms,
    })
}

fn stop(intercept: tokio::task::JoinHandle<()>, watchers: Vec<tokio::task::JoinHandle<()>>) {
    intercept.abort();
    watchers.into_iter().for_each(|w| w.abort());
}

async fn watch_network(
    page: &chromiumoxide::Page,
    net: Arc<Mutex<Net>>,
) -> Result<Vec<tokio::task::JoinHandle<()>>, String> {
    let mut sent = page
        .event_listener::<EventRequestWillBeSent>()
        .await
        .map_err(|e| e.to_string())?;
    let mut received = page
        .event_listener::<EventResponseReceived>()
        .await
        .map_err(|e| e.to_string())?;
    let mut finished = page
        .event_listener::<EventLoadingFinished>()
        .await
        .map_err(|e| e.to_string())?;
    let mut failed = page
        .event_listener::<EventLoadingFailed>()
        .await
        .map_err(|e| e.to_string())?;

    let n = net.clone();
    let a = tokio::spawn(async move {
        while let Some(e) = sent.next().await {
            let mut n = n.lock().unwrap();
            n.inflight.insert(e.request_id.clone(), Instant::now());
            n.last_activity = Some(Instant::now());
        }
    });

    let n = net.clone();
    let b = tokio::spawn(async move {
        while let Some(e) = received.next().await {
            let mut n = n.lock().unwrap();
            n.last_activity = Some(Instant::now());

            if e.r#type == ResourceType::Document && n.status.is_none() {
                n.status = Some(e.response.status);
                n.document = Some(e.request_id.clone());
            }

            let json = e.response.mime_type.contains("json");
            if json
                && matches!(e.r#type, ResourceType::Xhr | ResourceType::Fetch)
                && n.json.len() < MAX_JSON
            {
                n.json.push((
                    e.request_id.clone(),
                    e.response.url.clone(),
                    e.response.status,
                ));
            }
        }
    });

    let n = net.clone();
    let c = tokio::spawn(async move {
        while let Some(e) = finished.next().await {
            let mut n = n.lock().unwrap();
            n.inflight.remove(&e.request_id);
            n.finished.push(e.request_id.clone());
            n.last_activity = Some(Instant::now());
        }
    });

    let n = net;
    let d = tokio::spawn(async move {
        while let Some(e) = failed.next().await {
            let mut n = n.lock().unwrap();
            n.inflight.remove(&e.request_id);
            n.last_activity = Some(Instant::now());
        }
    });

    Ok(vec![a, b, c, d])
}

const STALE: Duration = Duration::from_secs(5);

async fn wait_idle(
    net: &Arc<Mutex<Net>>,
    idle: Duration,
    settle: Duration,
    started: Instant,
    timeout_ms: u64,
) {
    let deadline = Duration::from_millis(timeout_ms.saturating_sub(2_000));
    let loaded = Instant::now();

    loop {
        let quiet = {
            let n = net.lock().unwrap();
            let since = n.last_activity.map(|t| t.elapsed()).unwrap_or(idle);
            let loading = n.inflight.values().any(|t| t.elapsed() < STALE);
            !loading && since >= idle
        };

        if quiet || loaded.elapsed() >= settle || started.elapsed() >= deadline {
            return;
        }

        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

async fn json_bodies(page: &chromiumoxide::Page, net: &Arc<Mutex<Net>>) -> Vec<JsonResponse> {
    let wanted: Vec<(RequestId, String, i64)> = {
        let n = net.lock().unwrap();
        n.json
            .iter()
            .filter(|(id, _, _)| n.finished.contains(id))
            .cloned()
            .collect()
    };

    let mut out = Vec::new();

    for (id, url, status) in wanted {
        if let Some(body) = body(page, id).await.filter(|b| b.len() <= MAX_JSON_BODY) {
            out.push(JsonResponse { url, status, body });
        }
    }

    out
}

async fn body(page: &chromiumoxide::Page, id: RequestId) -> Option<String> {
    let resp = page.execute(GetResponseBodyParams::new(id)).await.ok()?;

    if resp.result.base64_encoded {
        base64::engine::general_purpose::STANDARD
            .decode(&resp.result.body)
            .ok()
            .and_then(|b| String::from_utf8(b).ok())
    } else {
        Some(resp.result.body.clone())
    }
}
