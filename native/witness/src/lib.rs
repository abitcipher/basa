mod act;
mod keys;
mod manifest;
mod mem;
mod merkle;
mod qes;

use manifest::{File, Manifest, Party};
use merkle::Hash;
use rustler::{Binary, Env, NewBinary, NifMap};

fn bin<'a>(env: Env<'a>, data: &[u8]) -> Binary<'a> {
    let mut b = NewBinary::new(env, data.len());
    b.as_mut_slice().copy_from_slice(data);
    b.into()
}

fn hash(b: &Binary) -> Result<Hash, String> {
    b.as_slice()
        .try_into()
        .map_err(|_| "a hash must be 32 bytes".to_string())
}

fn hashes(list: &[Binary]) -> Result<Vec<Hash>, String> {
    list.iter().map(hash).collect()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn sha256<'a>(env: Env<'a>, data: Binary<'a>) -> Binary<'a> {
    bin(env, &merkle::sha256(&data))
}

#[rustler::nif]
fn merkle_root<'a>(env: Env<'a>, leaves: Vec<Binary<'a>>) -> Result<Binary<'a>, String> {
    let root = merkle::root(&hashes(&leaves)?).ok_or("no leaves")?;
    Ok(bin(env, &root))
}

#[rustler::nif]
fn merkle_proof<'a>(
    env: Env<'a>,
    leaves: Vec<Binary<'a>>,
    index: usize,
) -> Result<Vec<Binary<'a>>, String> {
    let path = merkle::proof(&hashes(&leaves)?, index).ok_or("index out of range")?;
    Ok(path.iter().map(|h| bin(env, h)).collect())
}

#[rustler::nif]
fn merkle_verify(root: Binary, leaf: Binary, index: u64, size: u64, proof: Vec<Binary>) -> bool {
    match (hash(&root), hash(&leaf), hashes(&proof)) {
        (Ok(r), Ok(l), Ok(p)) => merkle::verify(&r, &l, index, size, &p),
        _ => false,
    }
}

#[derive(NifMap)]
struct PartyTerm<'a> {
    role: String,
    user_id: String,
    public_key: Binary<'a>,
}

#[derive(NifMap)]
struct FileTerm<'a> {
    sha256: Binary<'a>,
    kind: String,
    size: u64,
    media_type: String,
}

#[derive(NifMap)]
struct ManifestTerm<'a> {
    transaction_id: String,
    contract_type: String,
    template: String,
    jurisdiction: String,
    consumer: bool,
    parties: Vec<PartyTerm<'a>>,
    files: Vec<FileTerm<'a>>,
    created_at: String,
    geo: Option<(i64, i64)>,
    merkle_root: Option<Binary<'a>>,
}

impl ManifestTerm<'_> {
    fn to_manifest(&self) -> Result<Manifest, String> {
        Ok(Manifest {
            transaction_id: self.transaction_id.clone(),
            contract_type: self.contract_type.clone(),
            template: self.template.clone(),
            jurisdiction: self.jurisdiction.clone(),
            consumer: self.consumer,
            parties: self
                .parties
                .iter()
                .map(|p| {
                    Ok(Party {
                        role: p.role.clone(),
                        user_id: p.user_id.clone(),
                        public_key: hash(&p.public_key)?,
                    })
                })
                .collect::<Result<_, String>>()?,
            files: self
                .files
                .iter()
                .map(|f| {
                    Ok(File {
                        sha256: hash(&f.sha256)?,
                        kind: f.kind.clone(),
                        size: f.size,
                        media_type: f.media_type.clone(),
                    })
                })
                .collect::<Result<_, String>>()?,
            created_at: self.created_at.clone(),
            geo: self.geo,
        })
    }

    fn from_manifest<'a>(env: Env<'a>, m: &Manifest) -> ManifestTerm<'a> {
        ManifestTerm {
            transaction_id: m.transaction_id.clone(),
            contract_type: m.contract_type.clone(),
            template: m.template.clone(),
            jurisdiction: m.jurisdiction.clone(),
            consumer: m.consumer,
            parties: m
                .parties
                .iter()
                .map(|p| PartyTerm {
                    role: p.role.clone(),
                    user_id: p.user_id.clone(),
                    public_key: bin(env, &p.public_key),
                })
                .collect(),
            files: m
                .files
                .iter()
                .map(|f| FileTerm {
                    sha256: bin(env, &f.sha256),
                    kind: f.kind.clone(),
                    size: f.size,
                    media_type: f.media_type.clone(),
                })
                .collect(),
            created_at: m.created_at.clone(),
            geo: m.geo,
            merkle_root: m.merkle_root().map(|r| bin(env, &r)),
        }
    }
}

#[rustler::nif]
fn manifest_encode<'a>(env: Env<'a>, manifest: ManifestTerm<'a>) -> Result<Binary<'a>, String> {
    Ok(bin(env, &manifest.to_manifest()?.encode()?))
}

#[rustler::nif]
fn manifest_decode<'a>(env: Env<'a>, data: Binary<'a>) -> Result<ManifestTerm<'a>, String> {
    Ok(ManifestTerm::from_manifest(env, &Manifest::decode(&data)?))
}

#[rustler::nif]
fn data_key(env: Env) -> Result<Binary, String> {
    Ok(bin(env, &keys::data_key()?))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encrypt<'a>(
    env: Env<'a>,
    key: Binary<'a>,
    plain: Binary<'a>,
    aad: Binary<'a>,
) -> Result<Binary<'a>, String> {
    Ok(bin(env, &keys::encrypt(&key, &plain, &aad)?))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decrypt<'a>(
    env: Env<'a>,
    key: Binary<'a>,
    sealed: Binary<'a>,
    aad: Binary<'a>,
) -> Result<Binary<'a>, String> {
    Ok(bin(env, &keys::decrypt(&key, &sealed, &aad)?))
}

#[rustler::nif]
fn split<'a>(env: Env<'a>, secret: Binary<'a>) -> Result<Vec<Binary<'a>>, String> {
    Ok(keys::split(&secret)?.iter().map(|s| bin(env, s)).collect())
}

#[rustler::nif]
fn combine<'a>(env: Env<'a>, shares: Vec<Binary<'a>>) -> Result<Binary<'a>, String> {
    let owned: Vec<Vec<u8>> = shares.iter().map(|s| s.to_vec()).collect();
    Ok(bin(env, &keys::combine(&owned)?))
}

#[rustler::nif]
fn recovery_keypair(env: Env) -> (Binary, Binary) {
    let (sk, pk) = keys::recovery_keypair();
    (bin(env, &sk), bin(env, &pk))
}

#[rustler::nif]
fn recovery_seal<'a>(
    env: Env<'a>,
    public: Binary<'a>,
    key: Binary<'a>,
    transaction_id: Binary<'a>,
) -> Result<Binary<'a>, String> {
    Ok(bin(
        env,
        &keys::recovery_seal(&public, &key, &transaction_id)?,
    ))
}

#[rustler::nif]
fn recovery_open<'a>(
    env: Env<'a>,
    private: Binary<'a>,
    sealed: Binary<'a>,
    transaction_id: Binary<'a>,
) -> Result<Binary<'a>, String> {
    Ok(bin(
        env,
        &keys::recovery_open(&private, &sealed, &transaction_id)?,
    ))
}

#[rustler::nif]
fn device_seal<'a>(
    env: Env<'a>,
    public: Binary<'a>,
    plain: Binary<'a>,
    aad: Binary<'a>,
) -> Result<Binary<'a>, String> {
    Ok(bin(env, &keys::device_seal(&public, &plain, &aad)?))
}

#[rustler::nif]
fn device_open<'a>(
    env: Env<'a>,
    private: Binary<'a>,
    sealed: Binary<'a>,
    aad: Binary<'a>,
) -> Result<Binary<'a>, String> {
    Ok(bin(env, &keys::device_open(&private, &sealed, &aad)?))
}

#[rustler::nif]
fn signing_keypair(env: Env) -> Result<(Binary, Binary), String> {
    let (sk, pk) = keys::signing_keypair()?;
    Ok((bin(env, &sk), bin(env, &pk)))
}

#[rustler::nif]
fn sign<'a>(env: Env<'a>, private: Binary<'a>, message: Binary<'a>) -> Result<Binary<'a>, String> {
    Ok(bin(env, &keys::sign(&private, &message)?))
}

#[rustler::nif]
fn verify(public: Binary, message: Binary, signature: Binary) -> bool {
    keys::verify(&public, &message, &signature)
}

#[derive(NifMap)]
struct ActTerm<'a> {
    basa_hash: Binary<'a>,
    previous: Binary<'a>,
    kind: String,
    author: String,
    created_at: String,
    files: Vec<FileTerm<'a>>,
    terms: Vec<(String, String)>,
}

impl ActTerm<'_> {
    fn to_act(&self) -> Result<act::Act, String> {
        Ok(act::Act {
            basa_hash: hash(&self.basa_hash)?,
            previous: hash(&self.previous)?,
            kind: self.kind.clone(),
            author: self.author.clone(),
            created_at: self.created_at.clone(),
            files: self
                .files
                .iter()
                .map(|f| {
                    Ok(File {
                        sha256: hash(&f.sha256)?,
                        kind: f.kind.clone(),
                        size: f.size,
                        media_type: f.media_type.clone(),
                    })
                })
                .collect::<Result<_, String>>()?,
            terms: self.terms.clone(),
        })
    }

    fn from_act<'a>(env: Env<'a>, a: &act::Act) -> ActTerm<'a> {
        ActTerm {
            basa_hash: bin(env, &a.basa_hash),
            previous: bin(env, &a.previous),
            kind: a.kind.clone(),
            author: a.author.clone(),
            created_at: a.created_at.clone(),
            files: a
                .files
                .iter()
                .map(|f| FileTerm {
                    sha256: bin(env, &f.sha256),
                    kind: f.kind.clone(),
                    size: f.size,
                    media_type: f.media_type.clone(),
                })
                .collect(),
            terms: a.terms.clone(),
        }
    }
}

#[rustler::nif]
fn act_encode<'a>(env: Env<'a>, act: ActTerm<'a>) -> Result<Binary<'a>, String> {
    Ok(bin(env, &act.to_act()?.encode()?))
}

#[rustler::nif]
fn act_decode<'a>(env: Env<'a>, data: Binary<'a>) -> Result<ActTerm<'a>, String> {
    Ok(ActTerm::from_act(env, &act::Act::decode(&data)?))
}

#[derive(NifMap)]
struct AttesterTerm<'a> {
    public_key: Binary<'a>,
    role: String,
    nonce: Binary<'a>,
}

#[derive(NifMap)]
struct MemAttestationTerm<'a> {
    origin: String,
    subject: Binary<'a>,
    lo: AttesterTerm<'a>,
    hi: AttesterTerm<'a>,
    challenge: Binary<'a>,
    signer: Binary<'a>,
    statement: Binary<'a>,
}

#[rustler::nif]
fn mem_request<'a>(
    env: Env<'a>,
    origin: String,
    subject: Binary<'a>,
    label: String,
    role: String,
    challenge: Binary<'a>,
    submit_url: String,
) -> Result<Binary<'a>, String> {
    Ok(bin(
        env,
        &mem::request(&origin, &subject, &label, &role, &challenge, &submit_url)?,
    ))
}

#[rustler::nif]
fn mem_verify<'a>(env: Env<'a>, data: Binary<'a>) -> Result<MemAttestationTerm<'a>, String> {
    let a = mem::verify(&data)?;
    let side = |s: &mem::Attester| AttesterTerm {
        public_key: bin(env, &s.public_key),
        role: s.role.clone(),
        nonce: bin(env, &s.nonce),
    };
    Ok(MemAttestationTerm {
        origin: a.origin.clone(),
        subject: bin(env, &a.subject),
        lo: side(&a.lo),
        hi: side(&a.hi),
        challenge: bin(env, &a.challenge),
        signer: bin(env, &a.signer),
        statement: bin(env, &a.statement),
    })
}

#[rustler::nif]
fn qr_svg(text: String) -> Result<String, String> {
    mem::qr_svg(&text)
}

#[derive(NifMap)]
struct QesTerm<'a> {
    certificate: Binary<'a>,
    certificates: Vec<Binary<'a>>,
    subject: String,
    serial: String,
    issuer: String,
    signing_time: Option<u64>,
}

#[rustler::nif]
fn qes_dev_ca<'a>(env: Env<'a>, seed: Binary<'a>) -> Result<Binary<'a>, String> {
    Ok(bin(env, &qes::dev_ca_cert(&seed)?))
}

#[rustler::nif]
fn qes_dev_sign<'a>(
    env: Env<'a>,
    seed: Binary<'a>,
    user_id: String,
    name: String,
    digest: Binary<'a>,
) -> Result<Binary<'a>, String> {
    Ok(bin(env, &qes::dev_sign(&seed, &user_id, &name, &digest)?))
}

#[rustler::nif]
fn qes_verify<'a>(
    env: Env<'a>,
    data: Binary<'a>,
    digest: Binary<'a>,
) -> Result<QesTerm<'a>, String> {
    let v = qes::verify(&data, &digest)?;
    Ok(QesTerm {
        certificate: bin(env, &v.certificate),
        certificates: v.certificates.iter().map(|c| bin(env, c)).collect(),
        subject: v.subject,
        serial: v.serial,
        issuer: v.issuer,
        signing_time: v.signing_time,
    })
}

#[rustler::nif]
fn qes_issued_by(cert: Binary, issuer: Binary) -> bool {
    qes::issued_by(&cert, &issuer)
}

#[rustler::nif]
fn qes_prepare<'a>(
    env: Env<'a>,
    digest: Binary<'a>,
    cert: Binary<'a>,
) -> Result<Binary<'a>, String> {
    Ok(bin(env, &qes::prepare(&digest, &cert)?))
}

#[rustler::nif]
fn qes_assemble<'a>(
    env: Env<'a>,
    certs: Vec<Binary<'a>>,
    signed_attrs: Binary<'a>,
    signature: Binary<'a>,
    alg: String,
) -> Result<Binary<'a>, String> {
    let certs: Vec<Vec<u8>> = certs.iter().map(|c| c.as_slice().to_vec()).collect();
    Ok(bin(
        env,
        &qes::assemble(&certs, &signed_attrs, &signature, &alg)?,
    ))
}

#[rustler::nif]
fn qes_dev_remote<'a>(
    env: Env<'a>,
    seed: Binary<'a>,
    user_id: String,
    name: String,
    hash: Option<Binary<'a>>,
) -> Result<(Vec<Binary<'a>>, Option<Binary<'a>>), String> {
    let (certs, sig) =
        qes::dev_remote(&seed, &user_id, &name, hash.as_ref().map(|h| h.as_slice()))?;
    Ok((
        certs.iter().map(|c| bin(env, c)).collect(),
        sig.map(|s| bin(env, &s)),
    ))
}

rustler::init!("Elixir.Basa.Witness.Native");
