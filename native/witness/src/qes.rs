use std::str::FromStr;
use std::time::{Duration, SystemTime};

use cms::builder::{create_signing_time_attribute, SignedDataBuilder, SignerInfoBuilder};
use cms::cert::{CertificateChoices, IssuerAndSerialNumber};
use cms::content_info::ContentInfo;
use cms::signed_data::{EncapsulatedContentInfo, SignedData, SignerIdentifier};
use der::asn1::{OctetString, SetOfVec, Utf8StringRef};
use der::{Any, Decode, Encode};
use p256::ecdsa::signature::Verifier;
use p256::ecdsa::{DerSignature, SigningKey, VerifyingKey};
use spki::{AlgorithmIdentifierOwned, DecodePublicKey, EncodePublicKey, SubjectPublicKeyInfoOwned};
use x509_cert::attr::{Attribute, AttributeTypeAndValue};
use x509_cert::builder::{Builder, CertificateBuilder, Profile};
use x509_cert::ext::pkix::name::GeneralName;
use x509_cert::name::{Name, RdnSequence, RelativeDistinguishedName};
use x509_cert::serial_number::SerialNumber;
use x509_cert::time::{Time, Validity};
use x509_cert::Certificate;

const ECDSA_SHA256: der::oid::ObjectIdentifier =
    der::oid::ObjectIdentifier::new_unwrap("1.2.840.10045.4.3.2");
const RSA_ENCRYPTION: der::oid::ObjectIdentifier =
    der::oid::ObjectIdentifier::new_unwrap("1.2.840.113549.1.1.1");
const RSA_SHA256: der::oid::ObjectIdentifier =
    der::oid::ObjectIdentifier::new_unwrap("1.2.840.113549.1.1.11");
const SIGNING_CERTIFICATE_V2: der::oid::ObjectIdentifier =
    der::oid::ObjectIdentifier::new_unwrap("1.2.840.113549.1.9.16.2.47");
const CA_NAME: &str = "CN=BASA test CA (not qualified),O=BASA development";

pub struct Verified {
    pub certificate: Vec<u8>,
    pub certificates: Vec<Vec<u8>>,
    pub subject: String,
    pub serial: String,
    pub issuer: String,
    pub signing_time: Option<u64>,
}

#[derive(der::Sequence)]
struct IssuerSerial {
    issuer: Vec<GeneralName>,
    serial_number: SerialNumber,
}

#[derive(der::Sequence)]
struct EssCertIdV2 {
    cert_hash: OctetString,
    issuer_serial: IssuerSerial,
}

#[derive(der::Sequence)]
struct SigningCertificateV2 {
    certs: Vec<EssCertIdV2>,
}

fn signing_certificate_attribute(cert: &Certificate) -> Result<Attribute, String> {
    let der = cert.to_der().map_err(|e| e.to_string())?;
    let value = SigningCertificateV2 {
        certs: vec![EssCertIdV2 {
            cert_hash: OctetString::new(sha2_10::Sha256::digest_bytes(&der).to_vec())
                .map_err(|e| e.to_string())?,
            issuer_serial: IssuerSerial {
                issuer: vec![GeneralName::DirectoryName(
                    cert.tbs_certificate.issuer.clone(),
                )],
                serial_number: cert.tbs_certificate.serial_number.clone(),
            },
        }],
    };
    let any = Any::encode_from(&value).map_err(|e| e.to_string())?;
    Ok(Attribute {
        oid: SIGNING_CERTIFICATE_V2,
        values: SetOfVec::try_from(vec![any]).map_err(|e| e.to_string())?,
    })
}

fn key(seed: &[u8], label: &str) -> Result<SigningKey, String> {
    let hk = hkdf::Hkdf::<sha2_10::Sha256>::new(None, seed);
    for counter in 0u8..=255 {
        let mut okm = [0u8; 32];
        hk.expand_multi_info(
            &[b"BASA/v1/dev-qes/", label.as_bytes(), &[counter]],
            &mut okm,
        )
        .map_err(|_| "key derivation failed")?;
        if let Ok(k) = SigningKey::from_slice(&okm) {
            return Ok(k);
        }
    }
    Err("no valid key".into())
}

fn at(unix: u64) -> Result<Time, String> {
    Time::try_from(SystemTime::UNIX_EPOCH + Duration::from_secs(unix)).map_err(|e| e.to_string())
}

fn validity() -> Result<Validity, String> {
    Ok(Validity {
        not_before: at(1_767_225_600)?,
        not_after: at(2_082_758_400)?,
    })
}

fn cn(name: &str) -> Result<Name, String> {
    let atv = AttributeTypeAndValue {
        oid: der::oid::db::rfc4519::CN,
        value: Any::from(Utf8StringRef::new(name).map_err(|e| e.to_string())?),
    };
    let set = SetOfVec::try_from(vec![atv]).map_err(|e| e.to_string())?;
    Ok(RdnSequence(vec![RelativeDistinguishedName::from(set)]))
}

fn spki(k: &SigningKey) -> Result<SubjectPublicKeyInfoOwned, String> {
    let der = k
        .verifying_key()
        .to_public_key_der()
        .map_err(|e| e.to_string())?;
    SubjectPublicKeyInfoOwned::from_der(der.as_bytes()).map_err(|e| e.to_string())
}

fn ca(seed: &[u8]) -> Result<(SigningKey, Certificate), String> {
    let k = key(seed, "ca")?;
    let subject = Name::from_str(CA_NAME).map_err(|e| e.to_string())?;
    let serial = SerialNumber::new(&[1]).map_err(|e| e.to_string())?;
    let cert = CertificateBuilder::new(Profile::Root, serial, validity()?, subject, spki(&k)?, &k)
        .map_err(|e| e.to_string())?
        .build::<DerSignature>()
        .map_err(|e| e.to_string())?;
    Ok((k, cert))
}

pub fn dev_ca_cert(seed: &[u8]) -> Result<Vec<u8>, String> {
    ca(seed)?.1.to_der().map_err(|e| e.to_string())
}

fn user_cert(
    seed: &[u8],
    ca_key: &SigningKey,
    ca_cert: &Certificate,
    user_id: &str,
    name: &str,
) -> Result<(SigningKey, Certificate), String> {
    let user_key = key(seed, &format!("user/{user_id}"))?;
    let mut serial = sha2_10::Sha256::digest_bytes(user_id.as_bytes());
    serial[0] &= 0x7f;
    serial[0] |= 0x01;
    let serial = SerialNumber::new(&serial[..8]).map_err(|e| e.to_string())?;
    let profile = Profile::Leaf {
        issuer: ca_cert.tbs_certificate.subject.clone(),
        enable_key_agreement: false,
        enable_key_encipherment: false,
    };
    let cert = CertificateBuilder::new(
        profile,
        serial,
        validity()?,
        cn(name)?,
        spki(&user_key)?,
        ca_key,
    )
    .map_err(|e| e.to_string())?
    .build::<DerSignature>()
    .map_err(|e| e.to_string())?;
    Ok((user_key, cert))
}

pub fn dev_sign(seed: &[u8], user_id: &str, name: &str, digest: &[u8]) -> Result<Vec<u8>, String> {
    if digest.len() != 32 {
        return Err("the digest is 32 bytes".into());
    }
    let (ca_key, ca_cert) = ca(seed)?;
    let (user_key, cert) = user_cert(seed, &ca_key, &ca_cert, user_id, name)?;
    let serial = cert.tbs_certificate.serial_number.clone();
    let signing_certificate = signing_certificate_attribute(&cert)?;

    let content = EncapsulatedContentInfo {
        econtent_type: der::oid::db::rfc5911::ID_DATA,
        econtent: None,
    };
    let sid = SignerIdentifier::IssuerAndSerialNumber(IssuerAndSerialNumber {
        issuer: ca_cert.tbs_certificate.subject.clone(),
        serial_number: serial,
    });
    let digest_alg = AlgorithmIdentifierOwned {
        oid: der::oid::db::rfc5912::ID_SHA_256,
        parameters: None,
    };
    let mut signer =
        SignerInfoBuilder::new(&user_key, sid, digest_alg.clone(), &content, Some(digest))
            .map_err(|e| e.to_string())?;
    signer
        .add_signed_attribute(create_signing_time_attribute().map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    signer
        .add_signed_attribute(signing_certificate)
        .map_err(|e| e.to_string())?;
    let info = SignedDataBuilder::new(&content)
        .add_digest_algorithm(digest_alg)
        .map_err(|e| e.to_string())?
        .add_certificate(CertificateChoices::Certificate(cert))
        .map_err(|e| e.to_string())?
        .add_certificate(CertificateChoices::Certificate(ca_cert))
        .map_err(|e| e.to_string())?
        .add_signer_info::<SigningKey, DerSignature>(signer)
        .map_err(|e| e.to_string())?
        .build()
        .map_err(|e| e.to_string())?;
    info.to_der().map_err(|e| e.to_string())
}

pub fn verify(data: &[u8], digest: &[u8]) -> Result<Verified, String> {
    let info = ContentInfo::from_der(data).map_err(|_| "not a CMS structure")?;
    if info.content_type != der::oid::db::rfc5911::ID_SIGNED_DATA {
        return Err("not signed data".into());
    }
    let sd: SignedData = info.content.decode_as().map_err(|_| "not signed data")?;
    if sd.encap_content_info.econtent.is_some() {
        return Err("the document must not be inside the signature".into());
    }
    let signers: Vec<_> = sd.signer_infos.0.iter().collect();
    let [si] = signers.as_slice() else {
        return Err("exactly one signer expected".into());
    };
    if si.digest_alg.oid != der::oid::db::rfc5912::ID_SHA_256 {
        return Err("unsupported digest algorithm".into());
    }
    let attrs = si.signed_attrs.as_ref().ok_or("no signed attributes")?;

    let mut message_digest = None;
    let mut content_type_ok = false;
    let mut signing_time = None;
    let mut signing_cert_hash = None;
    for a in attrs.iter() {
        let value = a.values.iter().next().ok_or("empty attribute")?;
        if a.oid == der::oid::db::rfc5911::ID_MESSAGE_DIGEST {
            message_digest = Some(
                value
                    .decode_as::<OctetString>()
                    .map_err(|_| "bad digest")?
                    .as_bytes()
                    .to_vec(),
            );
        } else if a.oid == der::oid::db::rfc5911::ID_CONTENT_TYPE {
            content_type_ok = value.decode_as::<der::oid::ObjectIdentifier>().ok()
                == Some(der::oid::db::rfc5911::ID_DATA);
        } else if a.oid == der::oid::db::rfc5911::ID_SIGNING_TIME {
            signing_time = value
                .to_der()
                .ok()
                .and_then(|d| Time::from_der(&d).ok())
                .map(|t| t.to_unix_duration().as_secs());
        } else if a.oid == SIGNING_CERTIFICATE_V2 {
            let v = value
                .decode_as::<SigningCertificateV2>()
                .map_err(|_| "bad signing certificate")?;
            signing_cert_hash = Some(
                v.certs
                    .first()
                    .ok_or("bad signing certificate")?
                    .cert_hash
                    .as_bytes()
                    .to_vec(),
            );
        }
    }
    if message_digest.as_deref() != Some(digest) {
        return Err("signed a different document".into());
    }
    if !content_type_ok {
        return Err("bad content type".into());
    }

    let certs: Vec<Certificate> = sd
        .certificates
        .as_ref()
        .map(|set| {
            set.0
                .iter()
                .filter_map(|c| match c {
                    CertificateChoices::Certificate(c) => Some(c.clone()),
                    _ => None,
                })
                .collect()
        })
        .unwrap_or_default();
    let cert = certs
        .iter()
        .find(|c| match &si.sid {
            SignerIdentifier::IssuerAndSerialNumber(ias) => {
                c.tbs_certificate.issuer == ias.issuer
                    && c.tbs_certificate.serial_number == ias.serial_number
            }
            SignerIdentifier::SubjectKeyIdentifier(_) => false,
        })
        .ok_or("the signer's certificate is missing")?;

    let cert_der = cert.to_der().map_err(|e| e.to_string())?;
    if signing_cert_hash.is_some_and(|h| h != sha2_10::Sha256::digest_bytes(&cert_der)) {
        return Err("the signing certificate does not match".into());
    }
    let signed = attrs.to_der().map_err(|e| e.to_string())?;
    check_signature(
        cert,
        si.signature_algorithm.oid,
        &signed,
        si.signature.as_bytes(),
    )?;

    Ok(Verified {
        certificate: cert_der,
        certificates: certs.iter().filter_map(|c| c.to_der().ok()).collect(),
        subject: common_name(&cert.tbs_certificate.subject),
        serial: cert
            .tbs_certificate
            .serial_number
            .as_bytes()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect(),
        issuer: common_name(&cert.tbs_certificate.issuer),
        signing_time,
    })
}

pub fn issued_by(cert: &[u8], issuer: &[u8]) -> bool {
    let (Ok(c), Ok(i)) = (Certificate::from_der(cert), Certificate::from_der(issuer)) else {
        return false;
    };
    if c.tbs_certificate.issuer != i.tbs_certificate.subject {
        return false;
    }
    let (Ok(tbs), Some(sig)) = (c.tbs_certificate.to_der(), c.signature.as_bytes()) else {
        return false;
    };
    check_signature(&i, c.signature_algorithm.oid, &tbs, sig).is_ok()
}

fn check_signature(
    cert: &Certificate,
    alg: der::oid::ObjectIdentifier,
    message: &[u8],
    signature: &[u8],
) -> Result<(), String> {
    let spki = cert
        .tbs_certificate
        .subject_public_key_info
        .to_der()
        .map_err(|e| e.to_string())?;
    if alg == ECDSA_SHA256 {
        let key = VerifyingKey::from_public_key_der(&spki).map_err(|_| "the key is not P-256")?;
        let sig = DerSignature::from_bytes(signature).map_err(|_| "bad signature encoding")?;
        key.verify(message, &sig)
            .map_err(|_| "bad signature".to_string())
    } else if alg == RSA_ENCRYPTION || alg == RSA_SHA256 {
        use rsa::pkcs8::DecodePublicKey as _;
        use rsa::signature::Verifier as _;
        let public =
            rsa::RsaPublicKey::from_public_key_der(&spki).map_err(|_| "the key is not RSA")?;
        let key = rsa::pkcs1v15::VerifyingKey::<sha2_10::Sha256>::new(public);
        let sig =
            rsa::pkcs1v15::Signature::try_from(signature).map_err(|_| "bad signature encoding")?;
        key.verify(message, &sig)
            .map_err(|_| "bad signature".to_string())
    } else {
        Err("unsupported signature algorithm".into())
    }
}

pub fn prepare(digest: &[u8], cert: &[u8]) -> Result<Vec<u8>, String> {
    if digest.len() != 32 {
        return Err("the digest is 32 bytes".into());
    }
    let cert = Certificate::from_der(cert).map_err(|_| "bad certificate")?;
    let attrs = vec![
        signing_certificate_attribute(&cert)?,
        cms::builder::create_content_type_attribute(der::oid::db::rfc5911::ID_DATA)
            .map_err(|e| e.to_string())?,
        cms::builder::create_signing_time_attribute().map_err(|e| e.to_string())?,
        cms::builder::create_message_digest_attribute(digest).map_err(|e| e.to_string())?,
    ];
    let set = cms::signed_data::SignedAttributes::try_from(attrs).map_err(|e| e.to_string())?;
    set.to_der().map_err(|e| e.to_string())
}

pub fn assemble(
    certs: &[Vec<u8>],
    signed_attrs: &[u8],
    signature: &[u8],
    alg: &str,
) -> Result<Vec<u8>, String> {
    let alg = der::oid::ObjectIdentifier::new(alg).map_err(|_| "bad algorithm id")?;
    let chain: Vec<Certificate> = certs
        .iter()
        .map(|c| Certificate::from_der(c).map_err(|_| "bad certificate"))
        .collect::<Result<_, _>>()?;
    let signer = chain.first().ok_or("no certificate")?;
    let attrs = cms::signed_data::SignedAttributes::from_der(signed_attrs)
        .map_err(|_| "bad signed attributes")?;
    let signature = if alg == ECDSA_SHA256 && signature.len() == 64 {
        p256::ecdsa::Signature::from_slice(signature)
            .map_err(|_| "bad signature")?
            .to_der()
            .as_bytes()
            .to_vec()
    } else {
        signature.to_vec()
    };
    let parameters = (alg != ECDSA_SHA256).then(|| Any::from(der::asn1::Null));
    let sha256 = AlgorithmIdentifierOwned {
        oid: der::oid::db::rfc5912::ID_SHA_256,
        parameters: None,
    };
    let info = cms::signed_data::SignerInfo {
        version: cms::content_info::CmsVersion::V1,
        sid: SignerIdentifier::IssuerAndSerialNumber(IssuerAndSerialNumber {
            issuer: signer.tbs_certificate.issuer.clone(),
            serial_number: signer.tbs_certificate.serial_number.clone(),
        }),
        digest_alg: sha256.clone(),
        signed_attrs: Some(attrs),
        signature_algorithm: AlgorithmIdentifierOwned {
            oid: alg,
            parameters,
        },
        signature: der::asn1::OctetString::new(signature).map_err(|e| e.to_string())?,
        unsigned_attrs: None,
    };
    let sd = SignedData {
        version: cms::content_info::CmsVersion::V1,
        digest_algorithms: SetOfVec::try_from(vec![sha256]).map_err(|e| e.to_string())?,
        encap_content_info: EncapsulatedContentInfo {
            econtent_type: der::oid::db::rfc5911::ID_DATA,
            econtent: None,
        },
        certificates: Some(cms::signed_data::CertificateSet(
            SetOfVec::try_from(
                chain
                    .into_iter()
                    .map(CertificateChoices::Certificate)
                    .collect::<Vec<_>>(),
            )
            .map_err(|e| e.to_string())?,
        )),
        crls: None,
        signer_infos: cms::signed_data::SignerInfos(
            SetOfVec::try_from(vec![info]).map_err(|e| e.to_string())?,
        ),
    };
    let content = Any::encode_from(&sd).map_err(|e| e.to_string())?;
    ContentInfo {
        content_type: der::oid::db::rfc5911::ID_SIGNED_DATA,
        content,
    }
    .to_der()
    .map_err(|e| e.to_string())
}

pub type ChainAndSignature = (Vec<Vec<u8>>, Option<Vec<u8>>);

pub fn dev_remote(
    seed: &[u8],
    user_id: &str,
    name: &str,
    hash: Option<&[u8]>,
) -> Result<ChainAndSignature, String> {
    let (ca_key, ca_cert) = ca(seed)?;
    let (user_key, cert) = user_cert(seed, &ca_key, &ca_cert, user_id, name)?;
    let sig = match hash {
        Some(h) => {
            use p256::ecdsa::signature::hazmat::PrehashSigner;
            let s: p256::ecdsa::Signature = user_key.sign_prehash(h).map_err(|_| "cannot sign")?;
            Some(s.to_der().as_bytes().to_vec())
        }
        None => None,
    };
    Ok((
        vec![
            cert.to_der().map_err(|e| e.to_string())?,
            ca_cert.to_der().map_err(|e| e.to_string())?,
        ],
        sig,
    ))
}

fn common_name(name: &Name) -> String {
    for rdn in name.0.iter() {
        for atv in rdn.0.iter() {
            if atv.oid == der::oid::db::rfc4519::CN {
                if let Ok(s) = atv.value.decode_as::<der::asn1::Utf8StringRef>() {
                    return s.as_str().to_string();
                }
                if let Ok(s) = atv.value.decode_as::<der::asn1::PrintableStringRef>() {
                    return s.as_str().to_string();
                }
            }
        }
    }
    name.to_string()
}

trait DigestBytes {
    fn digest_bytes(data: &[u8]) -> [u8; 32];
}

impl DigestBytes for sha2_10::Sha256 {
    fn digest_bytes(data: &[u8]) -> [u8; 32] {
        use sha2_10::Digest;
        sha2_10::Sha256::digest(data).into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dev_signatures_verify_and_chain_to_the_test_ca() {
        let seed = b"seed";
        let digest = [7u8; 32];
        let cms = dev_sign(seed, "user-1", "Olena Kovalenko", &digest).unwrap();
        let v = verify(&cms, &digest).unwrap();
        assert_eq!(v.subject, "Olena Kovalenko");
        assert_eq!(v.issuer, "BASA test CA (not qualified)");
        assert!(v.signing_time.is_some());
        let ca = dev_ca_cert(seed).unwrap();
        assert!(issued_by(&v.certificate, &ca));
        assert!(!issued_by(&v.certificate, &dev_ca_cert(b"other").unwrap()));
        assert_eq!(
            verify(&cms, &[8u8; 32]).err().unwrap(),
            "signed a different document"
        );
        let mut bad = cms.clone();
        let n = bad.len();
        bad[n - 3] ^= 1;
        assert!(verify(&bad, &digest).is_err());
        assert!(verify(b"nope", &digest).is_err());
    }

    fn sha256(b: &[u8]) -> [u8; 32] {
        use sha2_10::Digest;
        sha2_10::Sha256::digest(b).into()
    }

    #[test]
    fn remote_signing_with_an_ecdsa_provider() {
        let seed = b"csc";
        let digest = [9u8; 32];
        let (certs, _) = dev_remote(seed, "u", "Max Berg", None).unwrap();
        let attrs = prepare(&digest, &certs[0]).unwrap();
        let (_, sig) = dev_remote(seed, "u", "Max Berg", Some(&sha256(&attrs))).unwrap();
        let cms = assemble(&certs, &attrs, &sig.unwrap(), "1.2.840.10045.4.3.2").unwrap();
        let v = verify(&cms, &digest).unwrap();
        assert_eq!(v.subject, "Max Berg");
        assert!(issued_by(&v.certificate, &dev_ca_cert(seed).unwrap()));
        let (_, other) = dev_remote(seed, "u", "Max Berg", Some(&[1u8; 32])).unwrap();
        let bad = assemble(&certs, &attrs, &other.unwrap(), "1.2.840.10045.4.3.2").unwrap();
        assert_eq!(verify(&bad, &digest).err().unwrap(), "bad signature");
        let (others, _) = dev_remote(seed, "v", "Someone Else", None).unwrap();
        let attrs = prepare(&digest, &others[0]).unwrap();
        let (_, sig) = dev_remote(seed, "u", "Max Berg", Some(&sha256(&attrs))).unwrap();
        let cms = assemble(&certs, &attrs, &sig.unwrap(), "1.2.840.10045.4.3.2").unwrap();
        assert_eq!(
            verify(&cms, &digest).err().unwrap(),
            "the signing certificate does not match"
        );
    }

    #[test]
    fn rsa_signatures_verify() {
        use rsa::pkcs1v15::SigningKey as RsaSigningKey;
        use rsa::signature::{Keypair, SignatureEncoding, Signer};
        let mut rng = rsa::rand_core::OsRng;
        let private = rsa::RsaPrivateKey::new(&mut rng, 2048).unwrap();
        let signer = RsaSigningKey::<sha2_10::Sha256>::new(private);
        let spki = SubjectPublicKeyInfoOwned::from_key(signer.verifying_key()).unwrap();
        let cert = CertificateBuilder::new(
            Profile::Root,
            SerialNumber::new(&[7]).unwrap(),
            validity().unwrap(),
            cn("RSA Signer").unwrap(),
            spki,
            &signer,
        )
        .unwrap()
        .build::<rsa::pkcs1v15::Signature>()
        .unwrap()
        .to_der()
        .unwrap();
        assert!(issued_by(&cert, &cert));

        let digest = [5u8; 32];
        let attrs = prepare(&digest, &cert).unwrap();
        let sig = signer.sign(&attrs).to_vec();
        let cms = assemble(&[cert.clone()], &attrs, &sig, "1.2.840.113549.1.1.1").unwrap();
        assert_eq!(verify(&cms, &digest).unwrap().subject, "RSA Signer");
        let mut bad = sig.clone();
        bad[10] ^= 1;
        let cms = assemble(&[cert], &attrs, &bad, "1.2.840.113549.1.1.1").unwrap();
        assert!(verify(&cms, &digest).is_err());
    }
}
