use std::net::IpAddr;

pub fn private_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            let [a, b, _, _] = v4.octets();
            a == 0
                || a == 10
                || a == 127
                || (a == 100 && (64..=127).contains(&b))
                || (a == 169 && b == 254)
                || (a == 172 && (16..=31).contains(&b))
                || (a == 192 && b == 168)
                || a >= 224
        }
        IpAddr::V6(v6) => {
            if let Some(v4) = v6.to_ipv4_mapped() {
                return private_ip(IpAddr::V4(v4));
            }
            let first = v6.segments()[0];
            v6.is_unspecified()
                || v6.is_loopback()
                || (0xFC00..=0xFDFF).contains(&first)
                || (0xFE80..=0xFEBF).contains(&first)
                || first >= 0xFF00
        }
    }
}

pub async fn allowed(url: &str, allow_private: bool) -> bool {
    let Ok(parsed) = url::Url::parse(url) else {
        return false;
    };

    match parsed.scheme() {
        "data" | "blob" => return true,
        "http" | "https" | "ws" | "wss" => {}
        _ => return false,
    }

    if allow_private {
        return true;
    }

    let Some(host) = parsed.host() else {
        return false;
    };

    match host {
        url::Host::Ipv4(ip) => !private_ip(IpAddr::V4(ip)),
        url::Host::Ipv6(ip) => !private_ip(IpAddr::V6(ip)),
        url::Host::Domain(name) => {
            let port = parsed.port_or_known_default().unwrap_or(443);
            match tokio::net::lookup_host((name, port)).await {
                Ok(addrs) => {
                    let addrs: Vec<_> = addrs.collect();
                    !addrs.is_empty() && addrs.iter().all(|a| !private_ip(a.ip()))
                }
                Err(_) => false,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_ranges() {
        for ip in [
            "127.0.0.1",
            "10.1.2.3",
            "172.16.0.1",
            "192.168.1.1",
            "169.254.169.254",
            "100.64.0.1",
            "0.0.0.0",
            "224.0.0.1",
            "::1",
            "fd00::1",
            "fe80::1",
            "::ffff:10.0.0.1",
        ] {
            assert!(private_ip(ip.parse().unwrap()), "{ip}");
        }

        for ip in ["8.8.8.8", "172.32.0.1", "100.128.0.1", "2a00:1450:4001::1"] {
            assert!(!private_ip(ip.parse().unwrap()), "{ip}");
        }
    }

    #[tokio::test]
    async fn schemes_and_hosts() {
        assert!(allowed("data:text/plain,hi", false).await);
        assert!(!allowed("file:///etc/passwd", false).await);
        assert!(!allowed("chrome://settings", false).await);
        assert!(!allowed("http://127.0.0.1:4000/", false).await);
        assert!(!allowed("http://[::1]/", false).await);
        assert!(!allowed("http://localhost/", false).await);
        assert!(allowed("http://localhost/", true).await);
        assert!(allowed("http://8.8.8.8/", false).await);
    }
}
