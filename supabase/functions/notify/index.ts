// Algor Bomber · funzione "notify": manda le notifiche sul telefono per i messaggi della chat.
//
// - La chiama il database (pg_net) a ogni messaggio nuovo, con {"path": "g/.../chat/..."}:
//   chi avvisare e cosa scrivere lo decide la funzione del database push_targets
//   (una volta sola per messaggio, solo nei primi 10 minuti, rispettando chi ha silenziato la chat).
// - Dall'app: {"key": true} restituisce la chiave pubblica delle notifiche (la crea la prima volta);
//   {"test": true}, con l'accesso dell'utente, manda una notifica di prova ai suoi telefoni.
//
// Le chiavi delle notifiche (VAPID) le crea questa funzione la prima volta e le tiene nel database
// (tabella push_keys, che l'app non può leggere): non ci sono segreti da impostare a mano.
// Si pubblica con "Verify JWT" spento (chi chiama lo controlla la funzione stessa).
// La cifratura dei messaggi segue gli standard Web Push (RFC 8291, 8292 e 8188), senza librerie esterne.

const SB_URL = (Deno.env.get('SUPABASE_URL') || '').replace(/\/+$/, '');

function serviceKey(): string {
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) return legacy;
  try { return JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}').default || ''; } catch (_e) { return ''; }
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

/* ---------- base64url ---------- */
export function b64uDecode(s: string): Uint8Array {
  let t = String(s || '').replace(/-/g, '+').replace(/_/g, '/');
  while (t.length % 4) t += '=';
  const bin = atob(t);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
export function b64uEncode(b: Uint8Array): string {
  let s = '';
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}
const utf8 = (s: string) => new TextEncoder().encode(s);

async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, len: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, len * 8);
  return new Uint8Array(bits);
}

/* ---------- cifratura del contenuto (RFC 8291, aes128gcm) ---------- */
export async function encryptPayload(p256dh: string, authSecret: string, payload: Uint8Array): Promise<Uint8Array> {
  const uaPub = b64uDecode(p256dh);
  const auth = b64uDecode(authSecret);
  if (uaPub.length !== 65 || uaPub[0] !== 4 || auth.length < 16) throw new Error('chiavi del telefono non valide');
  const as = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']) as CryptoKeyPair;
  const asPub = new Uint8Array(await crypto.subtle.exportKey('raw', as.publicKey));
  const uaKey = await crypto.subtle.importKey('raw', uaPub, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, as.privateKey, 256));
  const ikm = await hkdf(auth, shared, concat(utf8('WebPush: info'), new Uint8Array([0]), uaPub, asPub), 32);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, concat(utf8('Content-Encoding: aes128gcm'), new Uint8Array([0])), 16);
  const nonce = await hkdf(salt, ikm, concat(utf8('Content-Encoding: nonce'), new Uint8Array([0])), 12);
  const key = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  /* un solo blocco: il contenuto, poi il delimitatore 0x02 di ultimo blocco */
  const plain = concat(payload, new Uint8Array([2]));
  const cipher = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, tagLength: 128 }, key, plain));
  const rs = 4096;
  const header = new Uint8Array(16 + 4 + 1 + asPub.length);
  header.set(salt, 0);
  new DataView(header.buffer).setUint32(16, rs, false);
  header[20] = asPub.length;
  header.set(asPub, 21);
  return concat(header, cipher);
}

/* ---------- chiavi VAPID: create una volta, poi sempre le stesse ---------- */
export type Vapid = { pub: string; jwk: JsonWebKey };
export async function makeVapidKeys(): Promise<Vapid> {
  const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
  const pub = new Uint8Array(await crypto.subtle.exportKey('raw', kp.publicKey));
  const jwk = await crypto.subtle.exportKey('jwk', kp.privateKey) as JsonWebKey;
  return { pub: b64uEncode(pub), jwk: { kty: 'EC', crv: 'P-256', d: jwk.d, x: jwk.x, y: jwk.y } };
}

/* ---------- firma VAPID (RFC 8292, ES256) ---------- */
const signKeys = new Map<string, CryptoKey>();
async function signKey(v: Vapid): Promise<CryptoKey> {
  if (signKeys.has(v.pub)) return signKeys.get(v.pub)!;
  const key = await crypto.subtle.importKey('jwk', { ...v.jwk, ext: true }, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  signKeys.set(v.pub, key);
  return key;
}
export async function vapidHeader(endpoint: string, v: Vapid, subject: string): Promise<string> {
  const aud = new URL(endpoint).origin;
  const head = b64uEncode(utf8(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const claims = b64uEncode(utf8(JSON.stringify({ aud, exp: Math.floor(Date.now() / 1000) + 3600, sub: subject })));
  const data = utf8(head + '.' + claims);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, await signKey(v), data));
  return 'vapid t=' + head + '.' + claims + '.' + b64uEncode(sig) + ', k=' + v.pub;
}

type Sub = { endpoint: string; p256dh: string; auth: string };

export async function sendPush(sub: Sub, message: unknown, v: Vapid, subject: string): Promise<number> {
  const body = await encryptPayload(sub.p256dh, sub.auth, utf8(JSON.stringify(message)));
  const res = await fetch(sub.endpoint, {
    method: 'POST',
    headers: {
      Authorization: await vapidHeader(sub.endpoint, v, subject),
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      TTL: '86400',
      Urgency: 'high',
    },
    body,
  });
  try { await res.arrayBuffer(); } catch (_e) { /* niente da leggere */ }
  return res.status;
}

/* ---------- chiamate al database con la chiave di servizio ---------- */
function dbHeaders(): Record<string, string> {
  const key = serviceKey();
  const h: Record<string, string> = { apikey: key, 'Content-Type': 'application/json' };
  /* le chiavi nuove (sb_secret_...) non sono JWT: vanno solo in apikey */
  if (!key.startsWith('sb_')) h.Authorization = 'Bearer ' + key;
  return h;
}
async function rpc(fn: string, args: unknown): Promise<unknown> {
  const res = await fetch(SB_URL + '/rest/v1/rpc/' + fn, { method: 'POST', headers: dbHeaders(), body: JSON.stringify(args) });
  if (!res.ok) throw new Error(fn + ': ' + res.status + ' ' + (await res.text()).slice(0, 300));
  const txt = await res.text();
  return txt ? JSON.parse(txt) : null;
}

/* le chiavi dal database; la prima volta si creano e si salvano (se due chiamate arrivano insieme vince la prima) */
let vapidNow: Vapid | null = null;
export async function vapid(): Promise<Vapid> {
  if (vapidNow) return vapidNow;
  let v = await rpc('push_keys_get', {}) as Vapid | null;
  if (!v || !v.pub || !v.jwk) {
    const k = await makeVapidKeys();
    v = await rpc('push_keys_put', { p_pub: k.pub, p_jwk: k.jwk }) as Vapid | null;
  }
  if (!v || !v.pub || !v.jwk || !v.jwk.d) throw new Error('chiavi delle notifiche non disponibili');
  vapidNow = v;
  return v;
}
const subject = () => Deno.env.get('VAPID_SUBJECT') || SB_URL || 'mailto:notifiche@example.com';

async function deliver(subs: Sub[], message: unknown) {
  const v = await vapid();
  const out = await Promise.allSettled(subs.map((s) => sendPush(s, message, v, subject())));
  const gone: string[] = [], ok: string[] = [];
  let failed = 0;
  out.forEach((r, i) => {
    if (r.status === 'fulfilled' && r.value >= 200 && r.value < 300) ok.push(subs[i].endpoint);
    else if (r.status === 'fulfilled' && (r.value === 404 || r.value === 410)) gone.push(subs[i].endpoint);
    else { failed++; console.log('notifica non consegnata', r.status === 'fulfilled' ? r.value : String(r.reason)); }
  });
  if (gone.length) await rpc('push_gone', { p_endpoints: gone }).catch((e) => console.log(String(e)));
  if (ok.length) await rpc('push_ok', { p_endpoints: ok }).catch((e) => console.log(String(e)));
  return { sent: ok.length, gone: gone.length, failed };
}

/* chi chiama dall'app: serve un accesso valido */
async function userOf(req: Request): Promise<{ id: string } | null> {
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const who = await fetch(SB_URL + '/auth/v1/user', { headers: { apikey: serviceKey(), Authorization: 'Bearer ' + jwt } });
  if (!who.ok) return null;
  const user = await who.json();
  return user && user.id ? user : null;
}

/* notifica di prova: solo ai telefoni di chi la chiede */
async function testFor(req: Request) {
  const user = await userOf(req);
  if (!user) return reply(401, { error: 'accesso non valido' });
  const res = await fetch(SB_URL + '/rest/v1/push_subs?select=endpoint,p256dh,auth&uid=eq.' + encodeURIComponent(user.id), { headers: dbHeaders() });
  if (!res.ok) return reply(500, { error: 'telefoni non trovati' });
  const subs = await res.json() as Sub[];
  if (!subs.length) return reply(200, { sent: 0, gone: 0, failed: 0 });
  const r = await deliver(subs, { title: 'Algor Bomber', body: 'Le notifiche funzionano ✅', tag: 'test', url: './', t: Date.now() });
  return reply(200, r);
}

export async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return reply(405, { error: 'solo POST' });
  let body: { path?: string; test?: boolean; key?: boolean } = {};
  try { body = await req.json(); } catch (_e) { body = {}; }
  try {
    if (body.key) {
      if (!(await userOf(req))) return reply(401, { error: 'accesso non valido' });
      return reply(200, { pub: (await vapid()).pub });
    }
    if (body.test) return await testFor(req);
    const path = String(body.path || '');
    if (!/^g\/[A-Za-z0-9_-]{2,90}\/chat\/[^/]{3,120}$/.test(path)) return reply(400, { error: 'messaggio non valido' });
    const t = await rpc('push_targets', { p_path: path }) as null | { subs: Sub[]; title: string; body: string; tag: string; url: string; t: number };
    if (!t || !Array.isArray(t.subs) || !t.subs.length) return reply(200, { sent: 0 });
    const msg = { title: t.title, body: t.body, tag: t.tag, url: t.url, t: t.t, chat: t.tag.replace(/^chat-/, '') };
    const r = await deliver(t.subs, msg);
    console.log('notifiche', path, JSON.stringify(r));
    return reply(200, r);
  } catch (e) {
    console.log('errore', String(e));
    return reply(500, { error: String(e) });
  }
}

Deno.serve(handle);
