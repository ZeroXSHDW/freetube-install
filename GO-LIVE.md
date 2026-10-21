# Go-Live Checklist

Everything is code-complete and tested. To take it from "working demo" to "accepting
real money", run through this once (≈ 20 minutes). Most of it is one-time Stripe /
Cloudflare setup that can't be pre-committed because it involves your secrets.

## 1. Stripe account

- [ ] Create an account at <https://dashboard.stripe.com> (or use your existing one).
- [ ] Confirm your business/email so you can go **live**.

## 2. Sell immediately (Payment Link — no backend)

- [ ] Create a **Payment Link** for a one-time **€5** product at
      <https://dashboard.stripe.com/payment-links>.
- [ ] It's already wired into `docs/buy.html` (`paymentLink: https://buy.stripe.com/8x29AU6OY0z3bsF0MB14402`).
      If you make a *new* link, paste its URL there.
- [ ] Set the Payment Link's **confirmation page** to
      `https://zeroxshdw.github.io/freetube-install/thanks.html` (so buyers get the download).
- [ ] Make sure the displayed price (`priceLabel: '€5'`) matches what Stripe charges.

This alone is a complete, working checkout — it delivers the download but no license key.

## 3. License keys (optional Pro unlock)

To issue license keys the macOS app verifies offline:

- [ ] Install Wrangler: `npm i -g wrangler` and `wrangler login`.
- [ ] `wrangler kv namespace create LICENSES` → paste the id into `worker/wrangler.toml`.
- [ ] Generate your keypair: `swift scripts/gen-license-keypair.swift`.
      - Paste `PUBLIC_KEY_BASE64` into `Sources/FreeTubeApp/Services/LicenseService.swift`.
      - Keep `PRIVATE_KEY_PKCS8_BASE64` secret (it's the Worker's `LICENSE_PRIVATE_KEY`).
- [ ] Set the three secrets:
      ```
      wrangler secret put STRIPE_SECRET_KEY      # sk_live_…
      wrangler secret put STRIPE_WEBHOOK_SECRET  # whsec_…
      wrangler secret put LICENSE_PRIVATE_KEY    # your private key
      ```
- [ ] `wrangler deploy` (note the `https://….workers.dev` URL).
- [ ] Stripe Dashboard → Webhooks → add `https://<worker>/webhook` for
      `checkout.session.completed`, then copy the signing secret into `STRIPE_WEBHOOK_SECRET`.
- [ ] In `docs/buy.html`, set `licenseServer: 'https://<worker>'`.
- [ ] Rebuild the app so it embeds your new public key: `./scripts/build-app.sh --install`.

## 4. Ship

- [ ] Tag & release: `git tag -a v1.3.1 -m "…" && git push origin v1.3.1`
      (the GitHub Action builds and attaches `FreeTubeInstaller-macOS.zip`).
- [ ] Send buyers to <https://zeroxshdw.github.io/freetube-install/buy.html>.

## Verification (already proven in CI + locally)

- `swift build` ✅ · `node --check` on the viewer + Worker ✅ · shellcheck ✅
- Ed25519 license round-trip (sign → verify) ✅ · Web Crypto ↔ CryptoKit interop ✅
- Stripe Payment Link live at the configured URL ✅

## Licensing reminder

[FreeTube](https://freetubeapp.io/) is **AGPL-3.0** and free. You are selling the
**FreeTubeInstaller Pro add-on** (your own MIT-licensed installer + Swift app), not
FreeTube itself. Both the buy page and README state this and link the free source.
