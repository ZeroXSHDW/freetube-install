# FreeTubeInstaller — License Server (Cloudflare Worker)

This folder is the entire backend for selling FreeTubeInstaller Pro with **license keys**.
It's a single Cloudflare Worker that:

- `POST /checkout` — creates a Stripe Checkout session (returns a checkout URL)
- `GET /redeem?session_id=…` — the post-payment page that shows the license key + download
- `POST /webhook` — receives Stripe `checkout.session.completed`, issues the key (idempotent)
- `GET /verify?key=…` — online key check (the macOS app also verifies offline)

The app verifies keys **offline** using an Ed25519 public key, so after purchase it never
phones home.

## Deploy (one-time)

1. **Install Wrangler**: `npm i -g wrangler` and `wrangler login`

2. **Create the KV namespace** and paste its id into `wrangler.toml`:
   ```bash
   wrangler kv namespace create LICENSES
   ```

3. **Generate a license keypair** (in the repo root):
   ```bash
   swift scripts/gen-license-keypair.swift
   ```
   It prints two values:
   - `PUBLIC_KEY_BASE64` → paste into `Sources/FreeTubeApp/Services/LicenseService.swift` (`publicKeyBase64`)
   - `PRIVATE_KEY_PKCS8_BASE64` → set as a Worker secret below (never commit it)

4. **Set the secrets**:
   ```bash
   wrangler secret put STRIPE_SECRET_KEY       # sk_live_…
   wrangler secret put STRIPE_WEBHOOK_SECRET   # whsec_…
   wrangler secret put LICENSE_PRIVATE_KEY     # the PRIVATE_KEY_PKCS8_BASE64 above
   ```

5. **Deploy**:
   ```bash
   wrangler deploy
   ```
   Note the worker URL (e.g. `https://freetube-license.<you>.workers.dev`).

6. **Point Stripe webhooks at it**: in the Stripe Dashboard → Developers → Webhooks →
   add endpoint `https://<worker-url>/webhook`, subscribing to `checkout.session.completed`.
   Copy the signing secret into `STRIPE_WEBHOOK_SECRET` (step 4).

7. **Wire the buy page**: in `docs/buy.html`, set
   ```js
   licenseServer: 'https://<worker-url>'
   ```
   Now "Buy now" goes through Stripe Checkout → the worker → a license key page.

8. **Rebuild the app** so it embeds your new public key:
   ```bash
   ./scripts/build-app.sh --install
   ```

## Pricing

By default the worker charges a one-time **€5** (`AMOUNT_CENTS=500`, `CURRENCY=eur`).
Set `PRICE_ID` in `wrangler.toml` to use a pre-created Stripe Price object instead.

## Notes

- Keys are `FT1.<payload>.<signature>`; the payload is `email|product|expiry|issuedAt`
  (`expiry=0` means lifetime). They are Ed25519-signed and verifiable offline.
- The `LICENSES` KV store is only a convenience for online lookup / idempotency —
  verification doesn't depend on it.
- Rotate the keypair with `scripts/gen-license-keypair.swift` anytime; old keys keep
  verifying only if you keep the old public key in the app.
