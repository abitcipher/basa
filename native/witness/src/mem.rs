use crate::manifest::{bytes, fields, get_text, get_uint, map, take, text};
use ciborium::value::Value;
use ed25519_dalek::{Signature, VerifyingKey};

const DOMAIN: &[u8] = b"MEM/v1/attestation";
const MAX_ATTESTATION: usize = 640;

#[derive(Debug, Clone, PartialEq)]
pub struct Attester {
    pub public_key: [u8; 32],
    pub role: String,
    pub nonce: [u8; 16],
}

#[derive(Debug, Clone, PartialEq)]
pub struct Attestation {
    pub origin: String,
    pub subject: [u8; 32],
    pub lo: Attester,
    pub hi: Attester,
    pub challenge: [u8; 16],
    pub signer: [u8; 32],
    pub statement: Vec<u8>,
}

pub fn request(
    origin: &str,
    subject: &[u8],
    label: &str,
    role: &str,
    challenge: &[u8],
    submit_url: &str,
) -> Result<Vec<u8>, String> {
    if subject.len() != 32 || challenge.len() != 16 {
        return Err("subject is 32 bytes, challenge 16".into());
    }
    check_role(role)?;
    if !submit_url.starts_with(&format!("{origin}/")) {
        return Err("the submit URL must be on the origin".into());
    }
    encode(&map(vec![
        (0, Value::Integer(1.into())),
        (1, text(origin)),
        (2, bytes(subject)),
        (3, text(label)),
        (4, text(role)),
        (5, bytes(challenge)),
        (6, text(submit_url)),
    ]))
}

pub fn verify(data: &[u8]) -> Result<Attestation, String> {
    if data.len() > MAX_ATTESTATION {
        return Err("attestation too large".into());
    }
    let value: Value = ciborium::from_reader(data).map_err(|_| "not CBOR")?;
    let mut m = fields(&value, 0..=4)?;
    version(&mut m)?;
    let statement = get_bytes(&mut m, 1)?;
    let challenge: [u8; 16] = fixed(get_bytes(&mut m, 2)?, "challenge")?;
    let signer: [u8; 32] = fixed(get_bytes(&mut m, 3)?, "signer")?;
    let signature: [u8; 64] = fixed(get_bytes(&mut m, 4)?, "signature")?;

    let s: Value =
        ciborium::from_reader(statement.as_slice()).map_err(|_| "statement is not CBOR")?;
    let mut f = fields(&s, 0..=8)?;
    version(&mut f)?;
    let origin = get_text(&mut f, 1)?;
    let subject = fixed(get_bytes(&mut f, 2)?, "subject")?;
    let lo = Attester {
        public_key: fixed(get_bytes(&mut f, 3)?, "key")?,
        role: get_text(&mut f, 4)?,
        nonce: fixed(get_bytes(&mut f, 5)?, "nonce")?,
    };
    let hi = Attester {
        public_key: fixed(get_bytes(&mut f, 6)?, "key")?,
        role: get_text(&mut f, 7)?,
        nonce: fixed(get_bytes(&mut f, 8)?, "nonce")?,
    };
    check_role(&lo.role)?;
    check_role(&hi.role)?;
    if lo.public_key >= hi.public_key || lo.role == hi.role {
        return Err("the statement needs two different attesters in order".into());
    }
    if signer != lo.public_key && signer != hi.public_key {
        return Err("the signer is not in the statement".into());
    }

    let rebuilt_statement = encode(&map(vec![
        (0, Value::Integer(1.into())),
        (1, text(&origin)),
        (2, bytes(&subject)),
        (3, bytes(&lo.public_key)),
        (4, text(&lo.role)),
        (5, bytes(&lo.nonce)),
        (6, bytes(&hi.public_key)),
        (7, text(&hi.role)),
        (8, bytes(&hi.nonce)),
    ]))?;
    let rebuilt = encode(&map(vec![
        (0, Value::Integer(1.into())),
        (1, bytes(&rebuilt_statement)),
        (2, bytes(&challenge)),
        (3, bytes(&signer)),
        (4, bytes(&signature)),
    ]))?;
    if rebuilt_statement != statement || rebuilt != data {
        return Err("not canonical CBOR".into());
    }

    let key = VerifyingKey::from_bytes(&signer).map_err(|_| "bad signer key")?;
    if key.is_weak() {
        return Err("bad signer key".into());
    }
    let mut message = Vec::with_capacity(DOMAIN.len() + 16 + statement.len());
    message.extend_from_slice(DOMAIN);
    message.extend_from_slice(&challenge);
    message.extend_from_slice(&statement);
    key.verify_strict(&message, &Signature::from_bytes(&signature))
        .map_err(|_| "bad signature")?;

    Ok(Attestation {
        origin,
        subject,
        lo,
        hi,
        challenge,
        signer,
        statement,
    })
}

pub fn qr_svg(data: &str) -> Result<String, String> {
    let code = qrcode::QrCode::with_error_correction_level(data.as_bytes(), qrcode::EcLevel::M)
        .map_err(|e| e.to_string())?;
    Ok(code
        .render::<qrcode::render::svg::Color>()
        .min_dimensions(240, 240)
        .quiet_zone(true)
        .dark_color(qrcode::render::svg::Color("#000000"))
        .light_color(qrcode::render::svg::Color("#ffffff"))
        .build())
}

fn encode(v: &Value) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    ciborium::into_writer(v, &mut out).map_err(|e| e.to_string())?;
    Ok(out)
}

fn version(m: &mut std::collections::BTreeMap<u64, Value>) -> Result<(), String> {
    if get_uint(m, 0)? == 1 {
        Ok(())
    } else {
        Err("unknown version".into())
    }
}

fn get_bytes(m: &mut std::collections::BTreeMap<u64, Value>, k: u64) -> Result<Vec<u8>, String> {
    match take(m, k)? {
        Value::Bytes(b) => Ok(b),
        _ => Err(format!("field {k} must be bytes")),
    }
}

fn fixed<const N: usize>(b: Vec<u8>, what: &str) -> Result<[u8; N], String> {
    b.try_into()
        .map_err(|_| format!("{what} must be {N} bytes"))
}

fn check_role(role: &str) -> Result<(), String> {
    if !role.is_empty()
        && role.len() <= 16
        && role.bytes().all(|b| b.is_ascii_lowercase() || b == b'_')
    {
        Ok(())
    } else {
        Err("bad role".into())
    }
}
