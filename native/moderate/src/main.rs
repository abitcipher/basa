mod fetch;
mod manifest;
mod models;
mod prep;

use std::io::{self, Read, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::thread;

use base64::Engine;
use serde::Deserialize;
use serde_json::{json, Value};

use models::{Models, Phrase};

const MAX_MESSAGE: usize = 32 * 1024 * 1024;

#[derive(Default)]
struct Status {
    preparing: Option<u8>,
    done: u64,
    total: u64,
    error: Option<String>,
    wanted: Option<(u8, Vec<Phrase>)>,
}

#[derive(Deserialize)]
struct Request {
    id: Value,
    op: String,
    #[serde(default)]
    level: Option<u8>,
    #[serde(default)]
    phrases: Vec<Phrase>,
    #[serde(default)]
    image: Option<String>,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let dir = args
        .iter()
        .position(|a| a == "--models")
        .and_then(|i| args.get(i + 1))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/models"));

    let env = match ort::init().with_name("basa-moderate").build() {
        Ok(env) => env,
        Err(e) => {
            eprintln!("basa-moderate: ONNX Runtime did not start: {e}");
            std::process::exit(1);
        }
    };

    let models: Arc<Mutex<Option<Models>>> = Arc::new(Mutex::new(None));
    let status = Arc::new(Mutex::new(Status::default()));
    let stdin = io::stdin();
    let mut input = stdin.lock();
    let stdout = io::stdout();

    while let Some(message) = read_message(&mut input) {
        let reply = match serde_json::from_slice::<Request>(&message) {
            Ok(req) => {
                let id = req.id.clone();
                match handle(req, &env, &dir, &models, &status) {
                    Ok(result) => json!({"id": id, "ok": true, "result": result}),
                    Err(error) => json!({"id": id, "ok": false, "error": error}),
                }
            }
            Err(e) => json!({"id": null, "ok": false, "error": format!("bad request: {e}")}),
        };
        let mut out = stdout.lock();
        if write_message(&mut out, &serde_json::to_vec(&reply).unwrap_or_default()).is_err() {
            break;
        }
    }
}

fn handle(
    req: Request,
    env: &ort::environment::Environment,
    dir: &PathBuf,
    models: &Arc<Mutex<Option<Models>>>,
    status: &Arc<Mutex<Status>>,
) -> Result<Value, String> {
    match req.op.as_str() {
        "status" => Ok(status_json(models, status)),
        "set_level" => {
            let level = req.level.ok_or("level missing")?;
            if !manifest::LEVELS.contains(&level) {
                return Err(format!("unknown level {level}"));
            }
            let wanted = (level, req.phrases.clone());
            {
                let mut s = status.lock().unwrap();
                let same_ready = s.wanted.as_ref() == Some(&wanted)
                    && s.preparing.is_none()
                    && models.lock().unwrap().as_ref().map(|m| m.level) == Some(level);
                if same_ready || (s.preparing == Some(level) && s.wanted.as_ref() == Some(&wanted))
                {
                    drop(s);
                    return Ok(status_json(models, status));
                }
                s.wanted = Some(wanted);
                s.preparing = Some(level);
                s.done = 0;
                s.total = manifest::level_bytes(level);
                s.error = None;
            }
            prepare(
                env.clone(),
                dir.clone(),
                level,
                req.phrases,
                models.clone(),
                status.clone(),
            );
            Ok(status_json(models, status))
        }
        "check" => {
            let data = req.image.ok_or("image missing")?;
            let bytes = base64::engine::general_purpose::STANDARD
                .decode(data)
                .map_err(|_| "image is not base64")?;
            let mut guard = models.lock().unwrap();
            let m = guard.as_mut().ok_or("not_ready")?;
            let scores = m.check(&bytes)?;
            serde_json::to_value(scores).map_err(|e| e.to_string())
        }
        other => Err(format!("unknown op {other}")),
    }
}

fn prepare(
    env: ort::environment::Environment,
    dir: PathBuf,
    level: u8,
    phrases: Vec<Phrase>,
    models: Arc<Mutex<Option<Models>>>,
    status: Arc<Mutex<Status>>,
) {
    thread::spawn(move || {
        let progress_status = status.clone();
        let loaded = Models::load(&env, &dir, level, &phrases, move |done, total| {
            let mut s = progress_status.lock().unwrap();
            s.done = done;
            s.total = total;
        });
        let mut s = status.lock().unwrap();
        let still_wanted = s.wanted.as_ref().map(|(l, p)| (*l, p)) == Some((level, &phrases));
        match loaded {
            Ok(m) if still_wanted => {
                *models.lock().unwrap() = Some(m);
                s.preparing = None;
                s.error = None;
            }
            Ok(_) => {}
            Err(e) if still_wanted => {
                s.preparing = None;
                s.error = Some(e);
            }
            Err(_) => {}
        }
    });
}

fn status_json(models: &Arc<Mutex<Option<Models>>>, status: &Arc<Mutex<Status>>) -> Value {
    let in_use = models.lock().unwrap().as_ref().map(|m| (m.level, m.ids()));
    let s = status.lock().unwrap();
    json!({
        "level": in_use.as_ref().map(|(l, _)| *l),
        "models": in_use.map(|(_, ids)| ids).unwrap_or_default(),
        "preparing": s.preparing,
        "done": s.done,
        "total": s.total,
        "error": s.error,
        "levels": manifest::LEVELS.iter().map(|l| json!({"level": l, "bytes": manifest::level_bytes(*l)})).collect::<Vec<_>>(),
    })
}

fn read_message(input: &mut impl Read) -> Option<Vec<u8>> {
    let mut len = [0u8; 4];
    input.read_exact(&mut len).ok()?;
    let len = u32::from_be_bytes(len) as usize;
    if len > MAX_MESSAGE {
        return None;
    }
    let mut buf = vec![0u8; len];
    input.read_exact(&mut buf).ok()?;
    Some(buf)
}

fn write_message(out: &mut impl Write, payload: &[u8]) -> io::Result<()> {
    out.write_all(&(payload.len() as u32).to_be_bytes())?;
    out.write_all(payload)?;
    out.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn messages_are_length_prefixed() {
        let mut buf = Vec::new();
        write_message(&mut buf, b"{\"a\":1}").unwrap();
        assert_eq!(&buf[..4], &[0, 0, 0, 7]);
        assert_eq!(read_message(&mut &buf[..]).unwrap(), b"{\"a\":1}");
        let big = ((MAX_MESSAGE + 1) as u32).to_be_bytes();
        assert!(read_message(&mut &big[..]).is_none());
    }
}
