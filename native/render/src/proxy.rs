use std::net::SocketAddr;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

use crate::guard;

const MAX_HEAD: usize = 64 * 1024;

pub async fn start(allow_private: bool) -> std::io::Result<u16> {
    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let port = listener.local_addr()?.port();

    tokio::spawn(async move {
        while let Ok((client, _)) = listener.accept().await {
            tokio::spawn(async move {
                let _ = serve(client, allow_private).await;
            });
        }
    });

    Ok(port)
}

async fn serve(mut client: TcpStream, allow_private: bool) -> std::io::Result<()> {
    let (head, rest) = read_head(&mut client).await?;
    let text = String::from_utf8_lossy(&head).to_string();
    let mut lines = text.split("\r\n");
    let request_line = lines.next().unwrap_or_default();
    let mut parts = request_line.split(' ');
    let (method, target, version) = (
        parts.next().unwrap_or_default(),
        parts.next().unwrap_or_default(),
        parts.next().unwrap_or("HTTP/1.1"),
    );

    if method == "CONNECT" {
        let Some((host, port)) = split_host_port(target, 443) else {
            return refuse(&mut client, 400).await;
        };
        let Some(addr) = resolve(&host, port, allow_private).await else {
            return refuse(&mut client, 403).await;
        };
        let mut upstream = TcpStream::connect(addr).await?;
        client
            .write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            .await?;
        if !rest.is_empty() {
            upstream.write_all(&rest).await?;
        }
        tokio::io::copy_bidirectional(&mut client, &mut upstream).await?;
        return Ok(());
    }

    let Ok(url) = url::Url::parse(target) else {
        return refuse(&mut client, 400).await;
    };
    if url.scheme() != "http" {
        return refuse(&mut client, 400).await;
    }
    let Some(host) = url
        .host_str()
        .map(|h| h.trim_matches(['[', ']']).to_string())
    else {
        return refuse(&mut client, 400).await;
    };
    let port = url.port_or_known_default().unwrap_or(80);
    let Some(addr) = resolve(&host, port, allow_private).await else {
        return refuse(&mut client, 403).await;
    };

    let path = match url.query() {
        Some(q) => format!("{}?{q}", url.path()),
        None => url.path().to_string(),
    };

    let mut forwarded = format!("{method} {path} {version}\r\n");
    for line in lines.take_while(|l| !l.is_empty()) {
        let name = line
            .split(':')
            .next()
            .unwrap_or_default()
            .to_ascii_lowercase();
        if !matches!(
            name.as_str(),
            "connection" | "proxy-connection" | "keep-alive"
        ) {
            forwarded.push_str(line);
            forwarded.push_str("\r\n");
        }
    }
    forwarded.push_str("Connection: close\r\n\r\n");

    let mut upstream = TcpStream::connect(addr).await?;
    upstream.write_all(forwarded.as_bytes()).await?;
    if !rest.is_empty() {
        upstream.write_all(&rest).await?;
    }
    tokio::io::copy_bidirectional(&mut client, &mut upstream).await?;
    Ok(())
}

async fn read_head(client: &mut TcpStream) -> std::io::Result<(Vec<u8>, Vec<u8>)> {
    let mut buf = Vec::with_capacity(4096);
    let mut chunk = [0u8; 4096];

    loop {
        let n = client.read(&mut chunk).await?;
        if n == 0 {
            return Err(std::io::ErrorKind::UnexpectedEof.into());
        }
        buf.extend_from_slice(&chunk[..n]);

        if let Some(end) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            let rest = buf.split_off(end + 4);
            return Ok((buf, rest));
        }
        if buf.len() > MAX_HEAD {
            return Err(std::io::ErrorKind::InvalidData.into());
        }
    }
}

async fn refuse(client: &mut TcpStream, status: u16) -> std::io::Result<()> {
    let reason = if status == 403 {
        "Forbidden"
    } else {
        "Bad Request"
    };
    client
        .write_all(
            format!("HTTP/1.1 {status} {reason}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                .as_bytes(),
        )
        .await
}

fn split_host_port(target: &str, default: u16) -> Option<(String, u16)> {
    if let Some(stripped) = target.strip_prefix('[') {
        let (host, rest) = stripped.split_once(']')?;
        let port = rest
            .strip_prefix(':')
            .and_then(|p| p.parse().ok())
            .unwrap_or(default);
        return Some((host.to_string(), port));
    }
    match target.rsplit_once(':') {
        Some((host, port)) => Some((host.to_string(), port.parse().ok()?)),
        None => Some((target.to_string(), default)),
    }
}

async fn resolve(host: &str, port: u16, allow_private: bool) -> Option<SocketAddr> {
    let addrs: Vec<SocketAddr> = tokio::net::lookup_host((host, port)).await.ok()?.collect();

    if addrs.is_empty() || (!allow_private && addrs.iter().any(|a| guard::private_ip(a.ip()))) {
        return None;
    }

    addrs.into_iter().next()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_and_port() {
        assert_eq!(
            split_host_port("example.com:8443", 443),
            Some(("example.com".into(), 8443))
        );
        assert_eq!(
            split_host_port("example.com", 443),
            Some(("example.com".into(), 443))
        );
        assert_eq!(split_host_port("[::1]:443", 443), Some(("::1".into(), 443)));
        assert_eq!(split_host_port("example.com:x", 443), None);
    }

    #[tokio::test]
    async fn refuses_private_addresses() {
        assert!(resolve("127.0.0.1", 80, false).await.is_none());
        assert!(resolve("localhost", 80, false).await.is_none());
        assert!(resolve("localhost", 80, true).await.is_some());
        assert!(resolve("8.8.8.8", 53, false).await.is_some());
    }

    #[tokio::test]
    async fn tunnels_only_to_public_hosts() {
        let port = start(false).await.unwrap();
        let mut c = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        c.write_all(b"CONNECT 127.0.0.1:22 HTTP/1.1\r\nHost: 127.0.0.1:22\r\n\r\n")
            .await
            .unwrap();
        let mut reply = String::new();
        c.read_to_string(&mut reply).await.unwrap();
        assert!(reply.starts_with("HTTP/1.1 403"), "{reply}");

        let mut c = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        c.write_all(b"GET http://10.0.0.1/ HTTP/1.1\r\nHost: 10.0.0.1\r\n\r\n")
            .await
            .unwrap();
        let mut reply = String::new();
        c.read_to_string(&mut reply).await.unwrap();
        assert!(reply.starts_with("HTTP/1.1 403"), "{reply}");
    }
}
