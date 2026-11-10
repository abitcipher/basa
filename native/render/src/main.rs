mod guard;
mod proxy;
mod render;

use std::sync::Arc;
use std::time::{Duration, Instant};

use chromiumoxide::{Browser, BrowserConfig};
use futures::StreamExt;
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{mpsc, Mutex, Semaphore};

#[derive(Clone)]
struct Options {
    chrome: Option<String>,
    max_tabs: usize,
    idle: Duration,
    no_sandbox: bool,
    allow_private: bool,
}

struct Running {
    browser: Arc<Browser>,
    handler: tokio::task::JoinHandle<()>,
}

struct State {
    opts: Options,
    proxy_port: u16,
    browser: Mutex<Option<Running>>,
    last_used: Mutex<Instant>,
    tabs: Semaphore,
}

#[derive(Deserialize)]
struct Message {
    id: Value,
    op: String,
    #[serde(flatten)]
    rest: Value,
}

#[tokio::main]
async fn main() {
    let opts = parse_args();
    let proxy_port = match proxy::start(opts.allow_private).await {
        Ok(port) => port,
        Err(e) => {
            eprintln!("basa-render: proxy did not start: {e}");
            std::process::exit(1);
        }
    };
    let state = Arc::new(State {
        proxy_port,
        tabs: Semaphore::new(opts.max_tabs),
        opts,
        browser: Mutex::new(None),
        last_used: Mutex::new(Instant::now()),
    });

    let (tx, mut rx) = mpsc::unbounded_channel::<Value>();

    let writer = tokio::spawn(async move {
        let mut out = tokio::io::stdout();
        while let Some(msg) = rx.recv().await {
            let bytes = serde_json::to_vec(&msg).unwrap_or_default();
            if out.write_u32(bytes.len() as u32).await.is_err()
                || out.write_all(&bytes).await.is_err()
                || out.flush().await.is_err()
            {
                break;
            }
        }
    });

    tokio::spawn(close_when_idle(state.clone()));

    let mut input = tokio::io::stdin();
    while let Ok(len) = input.read_u32().await {
        if len > 1_000_000 {
            break;
        }
        let mut buf = vec![0u8; len as usize];
        if input.read_exact(&mut buf).await.is_err() {
            break;
        }

        let state = state.clone();
        let tx = tx.clone();
        tokio::spawn(async move {
            let reply = match serde_json::from_slice::<Message>(&buf) {
                Ok(msg) => handle(&state, msg).await,
                Err(e) => json!({"id": null, "ok": false, "error": format!("bad message: {e}")}),
            };
            let _ = tx.send(reply);
        });
    }

    if let Some(running) = state.browser.lock().await.take() {
        if let Ok(browser) = Arc::try_unwrap(running.browser) {
            shut(browser, running.handler).await;
        }
    }
    drop(tx);
    let _ = writer.await;
}

async fn handle(state: &Arc<State>, msg: Message) -> Value {
    match msg.op.as_str() {
        "ping" => {
            json!({"id": msg.id, "ok": true, "result": {"version": env!("CARGO_PKG_VERSION")}})
        }
        "render" => {
            let req: render::Request = match serde_json::from_value(msg.rest) {
                Ok(r) => r,
                Err(e) => {
                    return json!({"id": msg.id, "ok": false, "error": format!("bad request: {e}")})
                }
            };

            let _tab = state.tabs.acquire().await.expect("semaphore open");
            *state.last_used.lock().await = Instant::now();

            let result = match browser(state).await {
                Ok(browser) => render::render(&browser, req, state.opts.allow_private).await,
                Err(e) => Err(e),
            };

            *state.last_used.lock().await = Instant::now();

            match result {
                Ok(r) => json!({"id": msg.id, "ok": true, "result": r}),
                Err(e) => json!({"id": msg.id, "ok": false, "error": e}),
            }
        }
        other => json!({"id": msg.id, "ok": false, "error": format!("unknown op: {other}")}),
    }
}

async fn browser(state: &Arc<State>) -> Result<Arc<Browser>, String> {
    let mut guard = state.browser.lock().await;
    if let Some(running) = guard.as_ref() {
        if !running.handler.is_finished() {
            return Ok(running.browser.clone());
        }
        guard.take();
    }

    let mut config = BrowserConfig::builder()
        .respect_https_errors()
        .request_timeout(Duration::from_secs(30))
        .arg(format!(
            "--proxy-server=http://127.0.0.1:{}",
            state.proxy_port
        ))
        .arg("--proxy-bypass-list=<-loopback>")
        .args([
            "--disable-dev-shm-usage",
            "--disable-gpu",
            "--mute-audio",
            "--no-first-run",
        ]);

    if let Some(path) = state
        .opts
        .chrome
        .clone()
        .or_else(|| std::env::var("CHROME_PATH").ok())
    {
        config = config.chrome_executable(path);
    }
    if state.opts.no_sandbox {
        config = config.no_sandbox();
    }

    let config = config.build().map_err(|e| format!("chrome: {e}"))?;
    let (browser, mut handler) = Browser::launch(config)
        .await
        .map_err(|e| format!("launch: {e}"))?;
    let handler = tokio::spawn(async move { while handler.next().await.is_some() {} });

    let browser = Arc::new(browser);
    *guard = Some(Running {
        browser: browser.clone(),
        handler,
    });
    Ok(browser)
}

async fn close_when_idle(state: Arc<State>) {
    loop {
        tokio::time::sleep(Duration::from_secs(5)).await;

        let idle = state.last_used.lock().await.elapsed() >= state.opts.idle;
        let busy = state.tabs.available_permits() < state.opts.max_tabs;

        if idle && !busy {
            let mut guard = state.browser.lock().await;
            if let Some(running) = guard.take() {
                match Arc::try_unwrap(running.browser) {
                    Ok(browser) => shut(browser, running.handler).await,
                    Err(browser) => {
                        *guard = Some(Running {
                            browser,
                            handler: running.handler,
                        })
                    }
                }
            }
        }
    }
}

async fn shut(mut browser: Browser, handler: tokio::task::JoinHandle<()>) {
    let _ = browser.close().await;
    let _ = browser.wait().await;
    handler.abort();
}

fn parse_args() -> Options {
    let mut opts = Options {
        chrome: None,
        max_tabs: 3,
        idle: Duration::from_secs(120),
        no_sandbox: false,
        allow_private: false,
    };

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--chrome" => opts.chrome = args.next(),
            "--max-tabs" => {
                opts.max_tabs = args.next().and_then(|n| n.parse().ok()).unwrap_or(3).max(1)
            }
            "--idle-secs" => {
                opts.idle =
                    Duration::from_secs(args.next().and_then(|n| n.parse().ok()).unwrap_or(120))
            }
            "--no-sandbox" => opts.no_sandbox = true,
            "--allow-private" => opts.allow_private = true,
            other => eprintln!("basa-render: unknown option {other}"),
        }
    }

    opts
}
