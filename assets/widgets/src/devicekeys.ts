import { Aes128Gcm, CipherSuite, DhkemX25519HkdfSha256, HkdfSha256 } from "@hpke/core";

const suite = new CipherSuite({
  kem: new DhkemX25519HkdfSha256(),
  kdf: new HkdfSha256(),
  aead: new Aes128Gcm(),
});

const INFO = new TextEncoder().encode("BASA/v1/share");
const ENCAPPED = 32;

export async function newBoxKey(): Promise<CryptoKeyPair> {
  return (await crypto.subtle.generateKey({ name: "X25519" }, false, ["deriveBits"])) as CryptoKeyPair;
}

export async function boxPublicKey(pair: CryptoKeyPair): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
}

export async function openShare(pair: CryptoKeyPair, sealed: Uint8Array, aad: Uint8Array): Promise<Uint8Array> {
  const plain = await suite.open(
    { recipientKey: pair, enc: sealed.slice(0, ENCAPPED), info: INFO },
    sealed.slice(ENCAPPED),
    aad,
  );
  return new Uint8Array(plain);
}
