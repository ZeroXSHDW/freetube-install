// gen-license-keypair.swift — generate an Ed25519 keypair for license signing.
//
// Usage: swift gen-license-keypair.swift
//
// Outputs:
//   PUBLIC_KEY_BASE64        -> paste into LicenseService.swift (the app)
//   PRIVATE_KEY_PKCS8_BASE64 -> set as the Cloudflare Worker secret LICENSE_PRIVATE_KEY
//
// The private key is a SECRET. Keep it out of the repo. The public key can be
// committed (it only verifies signatures, it cannot create them).
import Foundation
import CryptoKit

let privateKey = Curve25519.Signing.PrivateKey()
let publicKey = privateKey.publicKey

let seed = privateKey.rawRepresentation      // 32 bytes
let pub = publicKey.rawRepresentation        // 32 bytes

// Wrap the raw seed in an RFC 8410 Ed25519 PKCS8 DER structure so the
// Cloudflare Worker (Web Crypto) can import it as "pkcs8".
let pkcs8Prefix = Data([
    0x30, 0x2e,                         // SEQUENCE (46 bytes)
    0x02, 0x01, 0x00,                   // INTEGER version 0
    0x30, 0x05,                         // SEQUENCE (algorithm)
    0x06, 0x03, 0x2b, 0x65, 0x70,       // OID 1.3.101.112 (Ed25519)
    0x04, 0x22,                         // OCTET STRING (34 bytes)
    0x04, 0x20                          // OCTET STRING (32 bytes) = seed
])
let pkcs8 = pkcs8Prefix + seed

print("PUBLIC_KEY_BASE64=\(pub.base64EncodedString())")
print("PRIVATE_KEY_PKCS8_BASE64=\(pkcs8.base64EncodedString())")
print("")
print("→ Embed the public key in LicenseService.swift (publicKeyBase64).")
print("→ Set the private key as the Cloudflare Worker secret LICENSE_PRIVATE_KEY.")
