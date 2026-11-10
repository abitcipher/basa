import { readFileSync } from "node:fs";
import { Aes128Gcm, CipherSuite, DhkemX25519HkdfSha256, HkdfSha256 } from "@hpke/core";

const v = JSON.parse(readFileSync(new URL("../../../spec/vectors/witness.json", import.meta.url))).device_seal;
const hex = (s) => Uint8Array.from(s.match(/../g), (b) => parseInt(b, 16));
const b64url = (u) => Buffer.from(u).toString("base64url");

const jwk = { kty: "OKP", crv: "X25519", d: b64url(hex(v.private_key)), x: b64url(hex(v.public_key)) };
const privateKey = await crypto.subtle.importKey("jwk", jwk, { name: "X25519" }, false, ["deriveBits"]);
const publicKey = await crypto.subtle.importKey("raw", hex(v.public_key), { name: "X25519" }, true, []);

const suite = new CipherSuite({ kem: new DhkemX25519HkdfSha256(), kdf: new HkdfSha256(), aead: new Aes128Gcm() });
const sealed = hex(v.sealed);
const plain = await suite.open(
  { recipientKey: { privateKey, publicKey }, enc: sealed.slice(0, 32), info: new TextEncoder().encode("BASA/v1/share") },
  sealed.slice(32),
  new TextEncoder().encode(v.aad),
);

const got = Buffer.from(plain).toString("hex");
if (got !== v.plain) {
  console.error("FAIL: opened share differs");
  process.exit(1);
}

try {
  await suite.open(
    { recipientKey: { privateKey, publicKey }, enc: sealed.slice(0, 32), info: new TextEncoder().encode("BASA/v1/share") },
    sealed.slice(32),
    new TextEncoder().encode("another transaction"),
  );
  console.error("FAIL: opened with a wrong aad");
  process.exit(1);
} catch {}

console.log("ok: the browser code opens BASA's device seal");
