use crate::manifest::{
    bytes, fields, get_array, get_hash, get_text, get_uint, map, one_of, text, File,
};
use crate::merkle::Hash;
use ciborium::value::Value;

pub const VERSION: u64 = 1;
pub const KINDS: [&str; 7] = [
    "return",
    "delivery",
    "acceptance",
    "claim",
    "settlement",
    "dispute",
    "auto_acceptance",
];

#[derive(Debug, Clone, PartialEq)]
pub struct Act {
    pub basa_hash: Hash,
    pub previous: Hash,
    pub kind: String,
    pub author: String,
    pub created_at: String,
    pub files: Vec<File>,
    pub terms: Vec<(String, String)>,
}

impl Act {
    fn check(&self) -> Result<(), String> {
        one_of("act kind", &self.kind, &KINDS)?;
        one_of("act author", &self.author, &["offeror", "acceptor", "basa"])?;
        if self.created_at.is_empty() {
            return Err("time is empty".into());
        }
        for f in &self.files {
            one_of(
                "file kind",
                &f.kind,
                &["contract", "photo", "voice", "other"],
            )?;
        }
        for (k, _) in &self.terms {
            if k.is_empty() || k.len() >= 24 {
                return Err(format!("term key must be 1..23 bytes: {k}"));
            }
        }
        Ok(())
    }

    fn sorted_terms(&self) -> Vec<(String, String)> {
        let mut terms = self.terms.clone();
        terms.sort_by(|a, b| (a.0.len(), a.0.as_bytes()).cmp(&(b.0.len(), b.0.as_bytes())));
        terms.dedup_by(|a, b| a.0 == b.0);
        terms
    }

    pub fn encode(&self) -> Result<Vec<u8>, String> {
        self.check()?;
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
        let terms = Value::Map(
            self.sorted_terms()
                .iter()
                .map(|(k, v)| (text(k), text(v)))
                .collect(),
        );

        let value = map(vec![
            (0, Value::Integer(VERSION.into())),
            (1, bytes(&self.basa_hash)),
            (2, bytes(&self.previous)),
            (3, text(&self.kind)),
            (4, text(&self.author)),
            (5, text(&self.created_at)),
            (6, Value::Array(files)),
            (7, terms),
        ]);
        let mut out = Vec::new();
        ciborium::into_writer(&value, &mut out).map_err(|e| e.to_string())?;
        Ok(out)
    }

    pub fn decode(data: &[u8]) -> Result<Act, String> {
        let value: Value = ciborium::from_reader(data).map_err(|e| format!("not CBOR: {e}"))?;
        let mut m = fields(&value, 0..=7)?;
        if get_uint(&mut m, 0)? != VERSION {
            return Err("unknown version".into());
        }
        let files = get_array(&mut m, 6)?
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
        let terms = match m.remove(&7) {
            Some(Value::Map(entries)) => entries
                .into_iter()
                .map(|(k, v)| match (k, v) {
                    (Value::Text(k), Value::Text(v)) => Ok((k, v)),
                    _ => Err("terms must map text to text".to_string()),
                })
                .collect::<Result<Vec<_>, String>>()?,
            _ => return Err("field 7 must be a map".into()),
        };
        let act = Act {
            basa_hash: get_hash(&mut m, 1)?,
            previous: get_hash(&mut m, 2)?,
            kind: get_text(&mut m, 3)?,
            author: get_text(&mut m, 4)?,
            created_at: get_text(&mut m, 5)?,
            files,
            terms,
        };
        if act.encode()? != data {
            return Err("not canonical CBOR".into());
        }
        Ok(act)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::merkle::sha256;

    fn sample() -> Act {
        Act {
            basa_hash: sha256(b"manifest"),
            previous: sha256(b"manifest"),
            kind: "claim".into(),
            author: "offeror".into(),
            created_at: "2026-11-04T10:00:00Z".into(),
            files: vec![File {
                sha256: sha256(b"scratch"),
                kind: "photo".into(),
                size: 7,
                media_type: "image/jpeg".into(),
            }],
            terms: vec![
                ("note".into(), "scratch on the grille".into()),
                ("amount".into(), "500".into()),
            ],
        }
    }

    #[test]
    fn round_trip_and_order_independence() {
        let a = sample();
        let bytes = a.encode().unwrap();
        let back = Act::decode(&bytes).unwrap();
        assert_eq!(back.terms[0].0, "note");
        let mut b = sample();
        b.terms.reverse();
        assert_eq!(b.encode().unwrap(), bytes);
    }

    #[test]
    fn rejects_bad_acts() {
        let mut a = sample();
        a.kind = "gift".into();
        assert!(a.encode().is_err());
        let mut a = sample();
        a.terms
            .push(("a-very-long-key-over-23-bytes".into(), "x".into()));
        assert!(a.encode().is_err());
    }
}
