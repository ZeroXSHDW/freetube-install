// FreeTubeInstaller — license server (Cloudflare Worker)
//
// This single file is the whole backend: it creates Stripe Checkout sessions,
// receives Stripe webhooks, issues Ed25519-signed license keys, and verifies them.
// The macOS app verifies keys OFFLINE with the matching public key, so after a
// purchase the app never needs to phone home again.
//
// Routes:
//   GET  /                     -> health + status
//   POST /checkout             -> create a Stripe Checkout session; returns { url }
//   GET  /redeem?session_id=.. -> post-payment page with the license key + download
//   POST /webhook              -> Stripe `checkout.session.completed` handler
//   GET  /verify?key=..        -> { valid, email, product, expiry }
//
// Required secrets (set with `wrangler secret put`):
//   STRIPE_SECRET_KEY       (sk_live_...)
//   STRIPE_WEBHOOK_SECRET   (whsec_...)
//   LICENSE_PRIVATE_KEY     (base64 PKCS8 Ed25519, from scripts/gen-license-keypair.swift)
//
// Required KV namespace: LICENSES
//
// Optional [vars]: PRICE_ID (Stripe Price ID), or AMOUNT_CENTS + CURRENCY.

const PRODUCT = 'freetube-installer-pro';
const DOWNLOAD_URL = 'https://github.com/ZeroXSHDW/freetube-install/releases/latest/download/FreeTubeInstaller-macOS.zip';

const b64url = (bytes) => {
  let s = btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const b64urlToBytes = (s) => {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
};

async function signLicense(payload) {
  const keyBytes = b64urlToBytes(LICENSE_PRIVATE_KEY.replace(/-/g, '+').replace(/_/g, '/'));
  const key = await crypto.subtle.importKey('pkcs8', keyBytes, { name: 'Ed25519' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('Ed25519', key, new TextEncoder().encode(payload)));
  return `FT1.${b64url(new TextEncoder().encode(payload))}.${b64url(sig)}`;
}

function buildPayload(email, expiry, issuedAt) {
  return [email, PRODUCT, String(expiry), String(issuedAt)].join('|');
}

async function issueLicense(email, env) {
  const issuedAt = Math.floor(Date.now() / 1000);
  const expiryDays = parseInt(env.EXPIRY_DAYS || '0', 10);
  const expiry = expiryDays > 0 ? issuedAt + expiryDays * 86400 : 0; // 0 = lifetime
  const payload = buildPayload(email, expiry, issuedAt);
  const key = await signLicense(payload);
  await env.LICENSES.put(`key:${key}`, JSON.stringify({ email, product: PRODUCT, expiry, issuedAt }));
  await env.LICENSES.put(`email:${email}`, key);
  return { key, email, expiry, issuedAt };
}

async function createCheckoutSession(env, origin, email) {
  const lineItems = env.PRICE_ID
    ? { 'line_items[0][price]': env.PRICE_ID, 'line_items[0][quantity]': '1' }
    : {
        'line_items[0][quantity]': '1',
        'line_items[0][price_data][currency]': env.CURRENCY || 'eur',
        'line_items[0][price_data][unit_amount]': env.AMOUNT_CENTS || '500',
        'line_items[0][price_data][product_data][name]': 'FreeTubeInstaller Pro',
      };
  const body = new URLSearchParams({
    mode: 'payment',
    'success_url': `${origin}/redeem?session_id={CHECKOUT_SESSION_ID}`,
    'cancel_url': `${origin}/buy.html`,
    ...(email ? { customer_email: email } : {}),
    ...lineItems,
  });
  const res = await fetch('https://api.stripe.com/v1/checkout/sessions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });
  return res.json();
}

async function verifyStripeSignature(request, secret) {
  const sig = request.headers.get('stripe-signature') || '';
  const raw = await request.text();
  const m = sig.match(/t=(\d+),v1=([a-f0-9]+)/);
  if (!m) return null;
  const ts = m[1], v1 = m[2];
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${ts}.${raw}`));
  const expected = Array.from(new Uint8Array(mac)).map((b) => b.toString(16).padStart(2, '0')).join('');
  if (expected !== v1) return null;
  return JSON.parse(raw);
}

const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*' },
});

const redeemPage = (email, key, expiry) => `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Your license — FreeTubeInstaller Pro</title>
<style>body{font-family:-apple-system,Inter,sans-serif;background:#0b1020;color:#eaf0ff;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px}
.c{max-width:520px;width:100%;background:#131a30;border:1px solid rgba(255,255,255,.09);border-radius:16px;padding:34px 30px;text-align:center}
h1{font-size:24px;margin:0 0 8px}.s{color:#8b96b8;font-size:14px;margin-bottom:22px}
.key{background:rgba(0,0,0,.35);border:1px solid rgba(255,255,255,.12);border-radius:8px;padding:12px;font-family:ui-monospace,Menlo,monospace;font-size:12px;word-break:break-all;color:#fde68a;margin-bottom:14px}
button{background:linear-gradient(135deg,#fbbf24,#d97736);color:#0b1020;font-weight:700;border:0;border-radius:9px;padding:11px 22px;cursor:pointer;font-size:14px;margin:4px}
a.dl{display:inline-block;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.18);color:#eaf0ff;text-decoration:none;border-radius:9px;padding:11px 22px;font-size:14px;margin:4px}
.note{color:#8b96b8;font-size:12px;margin-top:18px}</style></head><body>
<div class="c"><h1>🎉 Thanks${email ? ', ' + email : ''}!</h1>
<p class="s">Your license key is below. Copy it, then paste it into the app (Extras → License → Activate).</p>
<div class="key" id="k">${key}</div>
<button onclick="navigator.clipboard.writeText('${key}')">Copy key</button>
<a class="dl" href="${DOWNLOAD_URL}">⬇ Download FreeTubeInstaller</a>
<p class="note">${expiry === 0 ? 'Lifetime license' : 'Valid until ' + new Date(expiry * 1000).toLocaleDateString()} · the key is verified offline — no account needed.</p>
</div></body></html>`;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = url.origin;
    const method = request.method;

    if (method === 'OPTIONS') {
      return new Response(null, { headers: { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET,POST,OPTIONS', 'access-control-allow-headers': '*' } });
    }

    if (url.pathname === '/' && method === 'GET') {
      return json({ ok: true, product: PRODUCT });
    }

    if (url.pathname === '/checkout' && method === 'POST') {
      const body = await request.json().catch(() => ({}));
      const session = await createCheckoutSession(env, origin, body.email);
      if (session.error) return json(session, 400);
      return json({ url: session.url, id: session.id });
    }

    if (url.pathname === '/redeem' && method === 'GET') {
      const sessionId = url.searchParams.get('session_id');
      if (!sessionId) return new Response('Missing session_id', { status: 400 });
      const res = await fetch(`https://api.stripe.com/v1/checkout/sessions/${sessionId}`, {
        headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
      });
      const session = await res.json();
      if (session.payment_status !== 'paid') {
        return new Response('Payment not completed', { status: 402 });
      }
      const email = session.customer_details?.email || session.customer_email || '';
      let existing = await env.LICENSES.get(`email:${email}`);
      if (existing) {
        return new Response(redeemPage(email, existing, 0), { headers: { 'content-type': 'text/html' } });
      }
      const { key, expiry } = await issueLicense(email, env);
      return new Response(redeemPage(email, key, expiry), { headers: { 'content-type': 'text/html' } });
    }

    if (url.pathname === '/webhook' && method === 'POST') {
      const event = await verifyStripeSignature(request, env.STRIPE_WEBHOOK_SECRET);
      if (!event) return new Response('Invalid signature', { status: 400 });
      if (event.type === 'checkout.session.completed') {
        const email = event.data.object.customer_details?.email || event.data.object.customer_email || '';
        await issueLicense(email, env);
      }
      return json({ received: true });
    }

    if (url.pathname === '/verify' && method === 'GET') {
      const key = url.searchParams.get('key') || '';
      const stored = await env.LICENSES.get(`key:${key}`);
      if (stored) return json({ valid: true, ...JSON.parse(stored) });
      return json({ valid: false }, 404);
    }

    return new Response('Not found', { status: 404 });
  },
};
