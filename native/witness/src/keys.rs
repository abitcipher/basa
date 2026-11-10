use blahaj::{Share, Sharks};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use hpke::aead::ChaCha20Poly1305 as HpkeAead;
use hpke::kdf::HkdfSha256;
use hpke::kem::X25519HkdfSha256;
use hpke::{Deserializable, Kem as _, OpModeR, OpModeS, Serializable};
use zeroize::Zeroizing;

pub const KEY_LEN: usize = 32;
const NONCE_LEN: usize = 24;
const RECOVERY_INFO: &[u8] = b"BASA/v1/recovery";
const ENCAPPED_LEN: usize = 32;

pub fn random(n: usize) -> Result<Vec<u8>, String> {
    let mut out = vec![0u8; n];
    getrandom::fill(&mut out).map_err(|e| e.to_string())?;
    Ok(out)
}

pub fn data_key() -> Result<Zeroizing<Vec<u8>>, String> {
    random(KEY_LEN).map(Zeroizing::new)
}

fn cipher(key: &[u8]) -> Result<XChaCha20Poly1305, String> {
    if key.len() != KEY_LEN {
        return Err("the data key must be 32 bytes".into());
    }
    XChaCha20Poly1305::new_from_slice(key).map_err(|_| "bad key".to_string())
}

pub fn encrypt(key: &[u8], plain: &[u8], aad: &[u8]) -> Result<Vec<u8>, String> {
    let nonce_bytes = random(NONCE_LEN)?;
    let nonce = XNonce::try_from(nonce_bytes.as_slice()).map_err(|_| "bad nonce")?;
    let sealed = cipher(key)?
        .encrypt(&nonce, Payload { msg: plain, aad })
        .map_err(|_| "encryption failed".to_string())?;
    let mut out = nonce_bytes;
    out.extend_from_slice(&sealed);
    Ok(out)
}

pub fn decrypt(key: &[u8], sealed: &[u8], aad: &[u8]) -> Result<Vec<u8>, String> {
    if sealed.len() < NONCE_LEN + 16 {
        return Err("too short".into());
    }
    let (nonce_bytes, body) = sealed.split_at(NONCE_LEN);
    let nonce = XNonce::try_from(nonce_bytes).map_err(|_| "bad nonce")?;
    cipher(key)?
        .decrypt(&nonce, Payload { msg: body, aad })
        .map_err(|_| "cannot decrypt: wrong key or changed data".to_string())
}

pub fn split(secret: &[u8]) -> Result<Vec<Vec<u8>>, String> {
    if secret.len() != KEY_LEN {
        return Err("the data key must be 32 bytes".into());
    }
    let shares: Vec<Vec<u8>> = Sharks(2)
        .dealer(secret)
        .take(3)
        .map(|s| Vec::from(&s))
        .collect();
    if shares.iter().map(|s| s[0]).collect::<Vec<_>>() != [1, 2, 3] {
        return Err("unexpected share numbering".into());
    }
    Ok(shares)
}

pub fn combine(shares: &[Vec<u8>]) -> Result<Zeroizing<Vec<u8>>, String> {
    let parsed = shares
        .iter()
        .map(|s| Share::try_from(s.as_slice()).map_err(|e| e.to_string()))
        .collect::<Result<Vec<_>, _>>()?;
    Sharks(2)
        .recover(&parsed)
        .map(Zeroizing::new)
        .map_err(|e| e.to_string())
}

pub fn recovery_keypair() -> (Vec<u8>, Vec<u8>) {
    let (sk, pk) = X25519HkdfSha256::gen_keypair();
    (sk.to_bytes().to_vec(), pk.to_bytes().to_vec())
}

pub fn recovery_seal(
    public: &[u8],
    data_key: &[u8],
    transaction_id: &[u8],
) -> Result<Vec<u8>, String> {
    let pk = <X25519HkdfSha256 as hpke::Kem>::PublicKey::from_bytes(public)
        .map_err(|_| "bad recovery public key")?;
    let (encapped, ct) = hpke::single_shot_seal::<HpkeAead, HkdfSha256, X25519HkdfSha256>(
        &OpModeS::Base,
        &pk,
        RECOVERY_INFO,
        data_key,
        transaction_id,
    )
    .map_err(|e| format!("recovery seal failed: {e:?}"))?;
    let mut out = encapped.to_bytes().to_vec();
    out.extend_from_slice(&ct);
    Ok(out)
}

pub fn recovery_open(
    private: &[u8],
    sealed: &[u8],
    transaction_id: &[u8],
) -> Result<Zeroizing<Vec<u8>>, String> {
    if sealed.len() <= ENCAPPED_LEN {
        return Err("too short".into());
    }
    let sk = <X25519HkdfSha256 as hpke::Kem>::PrivateKey::from_bytes(private)
        .map_err(|_| "bad recovery private key")?;
    let (enc, ct) = sealed.split_at(ENCAPPED_LEN);
    let encapped = <X25519HkdfSha256 as hpke::Kem>::EncappedKey::from_bytes(enc)
        .map_err(|_| "bad sealed key")?;
    hpke::single_shot_open::<HpkeAead, HkdfSha256, X25519HkdfSha256>(
        &OpModeR::Base,
        &sk,
        &encapped,
        RECOVERY_INFO,
        ct,
        transaction_id,
    )
    .map(Zeroizing::new)
    .map_err(|_| "cannot open: wrong recovery key or changed data".to_string())
}

const DEVICE_INFO: &[u8] = b"BASA/v1/share";

pub fn device_seal(public: &[u8], plain: &[u8], aad: &[u8]) -> Result<Vec<u8>, String> {
    let pk = <X25519HkdfSha256 as hpke::Kem>::PublicKey::from_bytes(public)
        .map_err(|_| "bad device public key")?;
    let (encapped, ct) = hpke::single_shot_seal::<
        hpke::aead::AesGcm128,
        HkdfSha256,
        X25519HkdfSha256,
    >(&OpModeS::Base, &pk, DEVICE_INFO, plain, aad)
    .map_err(|e| format!("device seal failed: {e:?}"))?;
    let mut out = encapped.to_bytes().to_vec();
    out.extend_from_slice(&ct);
    Ok(out)
}

pub fn device_open(private: &[u8], sealed: &[u8], aad: &[u8]) -> Result<Vec<u8>, String> {
    if sealed.len() <= ENCAPPED_LEN {
        return Err("too short".into());
    }
    let sk = <X25519HkdfSha256 as hpke::Kem>::PrivateKey::from_bytes(private)
        .map_err(|_| "bad device private key")?;
    let (enc, ct) = sealed.split_at(ENCAPPED_LEN);
    let encapped = <X25519HkdfSha256 as hpke::Kem>::EncappedKey::from_bytes(enc)
        .map_err(|_| "bad sealed share")?;
    hpke::single_shot_open::<hpke::aead::AesGcm128, HkdfSha256, X25519HkdfSha256>(
        &OpModeR::Base,
        &sk,
        &encapped,
        DEVICE_INFO,
        ct,
        aad,
    )
    .map_err(|_| "cannot open: wrong device key or changed data".to_string())
}

pub fn signing_keypair() -> Result<(Vec<u8>, Vec<u8>), String> {
    let seed: [u8; 32] = random(32)?.try_into().map_err(|_| "rng")?;
    let key = SigningKey::from_bytes(&seed);
    Ok((
        key.to_bytes().to_vec(),
        key.verifying_key().to_bytes().to_vec(),
    ))
}

pub fn sign(private: &[u8], message: &[u8]) -> Result<Vec<u8>, String> {
    let seed: [u8; 32] = private
        .try_into()
        .map_err(|_| "the private key must be 32 bytes")?;
    Ok(SigningKey::from_bytes(&seed)
        .sign(message)
        .to_bytes()
        .to_vec())
}

pub fn verify(public: &[u8], message: &[u8], signature: &[u8]) -> bool {
    let (Ok(pk), Ok(sig)) = (
        <[u8; 32]>::try_from(public),
        <[u8; 64]>::try_from(signature),
    ) else {
        return false;
    };
    match VerifyingKey::from_bytes(&pk) {
        Ok(key) => key
            .verify_strict(message, &Signature::from_bytes(&sig))
            .is_ok(),
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_pair_opens_one_share_does_not() {
        let key = data_key().unwrap();
        let file = b"photo of the microphone";
        let aad = crate::merkle::sha256(file);
        let sealed = encrypt(&key, file, &aad).unwrap();
        let shares = split(&key).unwrap();

        for (a, b) in [(0, 1), (0, 2), (1, 2)] {
            let k = combine(&[shares[a].clone(), shares[b].clone()]).unwrap();
            assert_eq!(decrypt(&k, &sealed, &aad).unwrap(), file);
        }
        assert!(combine(&[shares[0].clone()]).is_err());
        assert!(combine(&[shares[1].clone(), shares[1].clone()]).is_err());
    }

    #[test]
    fn decrypt_checks_key_data_and_aad() {
        let key = data_key().unwrap();
        let sealed = encrypt(&key, b"x", b"aad").unwrap();
        assert!(decrypt(&data_key().unwrap(), &sealed, b"aad").is_err());
        assert!(decrypt(&key, &sealed, b"other").is_err());
        let mut changed = sealed.clone();
        changed[30] ^= 1;
        assert!(decrypt(&key, &changed, b"aad").is_err());
    }

    #[test]
    fn recovery_opens_only_with_its_key_and_transaction() {
        let (sk, pk) = recovery_keypair();
        let key = data_key().unwrap();
        let sealed = recovery_seal(&pk, &key, b"tx-1").unwrap();
        assert_eq!(*recovery_open(&sk, &sealed, b"tx-1").unwrap(), *key);
        assert!(recovery_open(&sk, &sealed, b"tx-2").is_err());
        let (other, _) = recovery_keypair();
        assert!(recovery_open(&other, &sealed, b"tx-1").is_err());
    }

    #[test]
    fn device_seal_opens_only_with_its_key_and_aad() {
        let (sk, pk) = recovery_keypair();
        let sealed = device_seal(&pk, b"share", b"tx-1").unwrap();
        assert_eq!(device_open(&sk, &sealed, b"tx-1").unwrap(), b"share");
        assert!(device_open(&sk, &sealed, b"tx-2").is_err());
        let (other, _) = recovery_keypair();
        assert!(device_open(&other, &sealed, b"tx-1").is_err());
    }

    #[test]
    fn signatures() {
        let (sk, pk) = signing_keypair().unwrap();
        let sig = sign(&sk, b"BASA/v1/seal hash").unwrap();
        assert!(verify(&pk, b"BASA/v1/seal hash", &sig));
        assert!(!verify(&pk, b"BASA/v1/seal other", &sig));
        let (_, other) = signing_keypair().unwrap();
        assert!(!verify(&other, b"BASA/v1/seal hash", &sig));
    }
}
