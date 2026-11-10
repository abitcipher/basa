use crate::merkle::{self, Hash};
use ciborium::value::Value;

pub const VERSION: u64 = 1;

#[derive(Debug, Clone, PartialEq)]
pub struct Party {
    pub role: String,
    pub user_id: String,
    pub public_key: Hash,
}

#[derive(Debug, Clone, PartialEq)]
pub struct File {
    pub sha256: Hash,
    pub kind: String,
    pub size: u64,
    pub media_type: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Manifest {
    pub transaction_id: String,
    pub contract_type: String,
    pub template: String,
    pub jurisdiction: String,
    pub consumer: bool,
    pub parties: Vec<Party>,
    pub files: Vec<File>,
    pub created_at: String,
    pub geo: Option<(i64, i64)>,
}

impl Manifest {
    pub fn merkle_root(&self) -> Option<Hash> {
        let leaves: Vec<Hash> = self.files.iter().map(|f| f.sha256).collect();
        merkle::root(&leaves)
    }

    fn check(&self) -> Result<(), String> {
        one_of("contract type", &self.contract_type, &["lease", "sale"])?;
        one_of("jurisdiction", &self.jurisdiction, &["ua", "eu"])?;
        let roles: Vec<&str> = self.parties.iter().map(|p| p.role.as_str()).collect();
        if roles != ["offeror", "acceptor"] {
            return Err("parties must be the offeror, then the acceptor".into());
        }
        if self.files.is_empty() {
            return Err("a manifest needs at least one file".into());
        }
        for f in &self.files {
            one_of(
                "file kind",
                &f.kind,
                &["contract", "photo", "voice", "other"],
            )?;
        }
        if let Some((lat, lon)) = self.geo {
            if !(-90_000_000..=90_000_000).contains(&lat)
                || !(-180_000_000..=180_000_000).contains(&lon)
            {
                return Err("location out of range".into());
            }
        }
        for (name, s) in [
            ("transaction id", &self.transaction_id),
            ("template", &self.template),
            ("time", &self.created_at),
        ] {
            if s.is_empty() {
                return Err(format!("{name} is empty"));
            }
        }
        Ok(())
    }

    pub fn encode(&self) -> Result<Vec<u8>, String> {
        self.check()?;
        let root = self.merkle_root().ok_or("no files")?;

        let parties = self
            .parties
            .iter()
            .map(|p| {
                map(vec![
                    (0, text(&p.role)),
                    (1, text(&p.user_id)),
                    (2, bytes(&p.public_key)),
                ])
            })
            .collect();
        let files = self
            .files
            .iter()
            .map(|f| {
                map(vec![
                    (0, bytes(&f.sha256)),
                    (1, text(&f.kind)),
                    (2, Value::Integer(f.size.into())),
                    (3, text(&f.media_type)),
                ])
            })
            .collect();

        let mut fields = vec![
            (0, Value::Integer(VERSION.into())),
            (1, text(&self.transaction_id)),
            (2, text(&self.contract_type)),
            (3, text(&self.template)),
            (4, text(&self.jurisdiction)),
            (5, Value::Bool(self.consumer)),
            (6, Value::Array(parties)),
            (7, Value::Array(files)),
            (8, bytes(&root)),
            (9, text(&self.created_at)),
        ];
        if let Some((lat, lon)) = self.geo {
            fields.push((
                10,
                Value::Array(vec![Value::Integer(lat.into()), Value::Integer(lon.into())]),
            ));
        }

        let mut out = Vec::new();
        ciborium::into_writer(&map(fields), &mut out).map_err(|e| e.to_string())?;
        Ok(out)
    }

    pub fn decode(data: &[u8]) -> Result<Manifest, String> {
        let value: Value = ciborium::from_reader(data).map_err(|e| format!("not CBOR: {e}"))?;
        let mut m = fields(&value, 0..=10)?;

        if get_uint(&mut m, 0)? != VERSION {
            return Err("unknown version".into());
        }
        let parties = get_array(&mut m, 6)?
            .iter()
            .map(|p| {
                let mut f = fields(p, 0..=2)?;
                Ok(Party {
                    role: get_text(&mut f, 0)?,
                    user_id: get_text(&mut f, 1)?,
                    public_key: get_hash(&mut f, 2)?,
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        let files = get_array(&mut m, 7)?
            .iter()
            .map(|v| {
                let mut f = fields(v, 0..=3)?;
                Ok(File {
                    sha256: get_hash(&mut f, 0)?,
                    kind: get_text(&mut f, 1)?,
                    size: get_uint(&mut f, 2)?,
                    media_type: get_text(&mut f, 3)?,
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        let root = get_hash(&mut m, 8)?;
        let geo = match m.remove(&10) {
            None => None,
            Some(Value::Array(a)) if a.len() == 2 => Some((int(&a[0])?, int(&a[1])?)),
            Some(_) => return Err("location must be [lat, lon]".into()),
        };

        let manifest = Manifest {
            transaction_id: get_text(&mut m, 1)?,
            contract_type: get_text(&mut m, 2)?,
            template: get_text(&mut m, 3)?,
            jurisdiction: get_text(&mut m, 4)?,
            consumer: match m.remove(&5) {
                Some(Value::Bool(b)) => b,
                _ => return Err("field 5 must be a bool".into()),
            },
            parties,
            files,
            created_at: get_text(&mut m, 9)?,
            geo,
        };

        if manifest.merkle_root() != Some(root) {
            return Err("Merkle root does not match the files".into());
        }
        if manifest.encode()? != data {
            return Err("not canonical CBOR".into());
        }
        Ok(manifest)
    }
}

pub(crate) fn one_of(what: &str, value: &str, allowed: &[&str]) -> Result<(), String> {
    if allowed.contains(&value) {
        Ok(())
    } else {
        Err(format!("unknown {what}: {value}"))
    }
}

pub(crate) fn text(s: &str) -> Value {
    Value::Text(s.to_owned())
}

pub(crate) fn bytes(b: &[u8]) -> Value {
    Value::Bytes(b.to_vec())
}

pub(crate) fn map(entries: Vec<(u64, Value)>) -> Value {
    Value::Map(
        entries
            .into_iter()
            .map(|(k, v)| (Value::Integer(k.into()), v))
            .collect(),
    )
}

pub(crate) fn fields(
    value: &Value,
    allowed: std::ops::RangeInclusive<u64>,
) -> Result<std::collections::BTreeMap<u64, Value>, String> {
    let entries = value.as_map().ok_or("expected a map")?;
    let mut out = std::collections::BTreeMap::new();
    for (k, v) in entries {
        let key = k
            .as_integer()
            .and_then(|i| u64::try_from(i).ok())
            .ok_or("map keys must be unsigned integers")?;
        if !allowed.contains(&key) {
            return Err(format!("unknown field {key}"));
        }
        if out.insert(key, v.clone()).is_some() {
            return Err(format!("field {key} twice"));
        }
    }
    Ok(out)
}

pub(crate) fn take(
    m: &mut std::collections::BTreeMap<u64, Value>,
    k: u64,
) -> Result<Value, String> {
    m.remove(&k).ok_or_else(|| format!("field {k} missing"))
}

pub(crate) fn get_text(
    m: &mut std::collections::BTreeMap<u64, Value>,
    k: u64,
) -> Result<String, String> {
    match take(m, k)? {
        Value::Text(s) => Ok(s),
        _ => Err(format!("field {k} must be text")),
    }
}

pub(crate) fn get_uint(
    m: &mut std::collections::BTreeMap<u64, Value>,
    k: u64,
) -> Result<u64, String> {
    match take(m, k)? {
        Value::Integer(i) => u64::try_from(i).map_err(|_| format!("field {k} must be unsigned")),
        _ => Err(format!("field {k} must be an integer")),
    }
}

pub(crate) fn get_hash(
    m: &mut std::collections::BTreeMap<u64, Value>,
    k: u64,
) -> Result<Hash, String> {
    match take(m, k)? {
        Value::Bytes(b) => b
            .try_into()
            .map_err(|_| format!("field {k} must be 32 bytes")),
        _ => Err(format!("field {k} must be bytes")),
    }
}

pub(crate) fn get_array(
    m: &mut std::collections::BTreeMap<u64, Value>,
    k: u64,
) -> Result<Vec<Value>, String> {
    match take(m, k)? {
        Value::Array(a) => Ok(a),
        _ => Err(format!("field {k} must be an array")),
    }
}

fn int(v: &Value) -> Result<i64, String> {
    match v {
        Value::Integer(i) => i64::try_from(*i).map_err(|_| "integer out of range".into()),
        _ => Err("expected an integer".into()),
    }
}

#[cfg(test)]
pub mod tests {
    use super::*;

    pub fn sample() -> Manifest {
        Manifest {
            transaction_id: "0b6f5f6e-3c1a-4d8e-9b7a-2f4c6d8e0a12".into(),
            contract_type: "lease".into(),
            template: "lease-ua@1".into(),
            jurisdiction: "ua".into(),
            consumer: true,
            parties: vec![
                Party {
                    role: "offeror".into(),
                    user_id: "u-1".into(),
                    public_key: [1; 32],
                },
                Party {
                    role: "acceptor".into(),
                    user_id: "u-2".into(),
                    public_key: [2; 32],
                },
            ],
            files: vec![
                File {
                    sha256: merkle::sha256(b"contract"),
                    kind: "contract".into(),
                    size: 8,
                    media_type: "application/pdf".into(),
                },
                File {
                    sha256: merkle::sha256(b"photo"),
                    kind: "photo".into(),
                    size: 5,
                    media_type: "image/jpeg".into(),
                },
            ],
            created_at: "2026-11-01T12:00:00Z".into(),
            geo: Some((46_482_500, 30_723_300)),
        }
    }

    #[test]
    fn round_trip_is_canonical() {
        let m = sample();
        let bytes = m.encode().unwrap();
        assert_eq!(Manifest::decode(&bytes).unwrap(), m);
        assert_eq!(m.encode().unwrap(), bytes);
    }

    #[test]
    fn rejects_bad_manifests() {
        let mut m = sample();
        m.parties.reverse();
        assert!(m.encode().is_err());

        let mut m = sample();
        m.files.clear();
        assert!(m.encode().is_err());

        let m = sample();
        let mut bytes = m.encode().unwrap();
        let root = m.merkle_root().unwrap();
        let at = bytes.windows(32).position(|w| w == root).unwrap();
        bytes[at] ^= 1;
        assert_eq!(
            Manifest::decode(&bytes),
            Err("Merkle root does not match the files".into())
        );

        let swapped = map(vec![(1, text("x")), (0, Value::Integer(1u64.into()))]);
        let mut out = Vec::new();
        ciborium::into_writer(&swapped, &mut out).unwrap();
        assert!(Manifest::decode(&out).is_err());
    }
}
