// Service worker di Algor Bomber.
// - L'app si apre subito con la copia salvata sul telefono, anche con poca rete o senza.
//   Intanto controlla se in rete c'è una versione nuova: se c'è la salva e lo dice alla pagina,
//   che mostra «Aggiorna». Se non lo tocchi, la versione nuova parte la volta dopo che apri l'app.
// - Icone, comuni, emoji e config arrivano dalla copia e si rinfrescano dietro le quinte.
// - Mostra le notifiche dei messaggi e delle partite (anche ad app chiusa).
const CACHE = 'algor-bomber-v19';
const SCOPE = self.registration.scope;
const SHELL = SCOPE; // la pagina dell'app (index.html), una sola copia per tutti gli indirizzi dell'app (?chat=…, ?m=…)
const SHELL_PATHS = [new URL(SCOPE).pathname, new URL('index.html', SCOPE).pathname];
const PRE = [SHELL].concat(['manifest.webmanifest', 'icon-192.png', 'icon.svg', 'config.js'].map((p) => new URL(p, SCOPE).href));

const okRes = (res) => !!res && res.status === 200 && res.type === 'basic' && !res.redirected;
const verOf = (text) => { const m = /\bconst APP_VER = '([0-9][0-9.]*)'/.exec(text || ''); return m ? m[1] : ''; };
// la copia della pagina dell'app (si salva solo se è davvero lei, cioè se ha APP_VER: mai una pagina d'errore)
const shellOf = (text, res) => {
  const h = { 'Content-Type': 'text/html; charset=utf-8' };
  ['etag', 'last-modified'].forEach((k) => { const x = res.headers.get(k); if (x) h[k] = x; });
  return new Response(text, { status: 200, headers: h });
};

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    await Promise.all(PRE.map(async (u) => {
      try {
        const res = await fetch(new Request(u, { cache: 'no-cache' }));
        if (okRes(res)) {
          if (u !== SHELL) { await c.put(u, res); return; }
          const text = await res.text();
          if (verOf(text)) { await c.put(u, shellOf(text, res)); return; }
        }
      } catch (x) { /* senza rete */ }
      /* senza rete si tiene la copia della versione di prima, così l'app si apre lo stesso */
      try { const old = await caches.match(u); if (old) await c.put(u, old); } catch (x) { /* niente */ }
    }));
  })());
});
self.addEventListener('activate', (e) => {
  // si tolgono solo le versioni vecchie dell'app: foto e vocali della chat restano sul telefono
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k.startsWith('algor-bomber-') && k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});

// la versione dell'app salvata sul telefono (si legge da APP_VER dentro la pagina)
let ver = null;
async function savedVer() {
  if (ver !== null) return ver;
  try { const c = await caches.open(CACHE); const hit = await c.match(SHELL); ver = hit ? verOf(await hit.text()) : ''; } catch (x) { ver = ''; }
  return ver;
}
async function tellAll(msg) {
  const ws = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  ws.forEach((w) => { try { w.postMessage(msg); } catch (x) { /* finestra chiusa */ } });
}

// c'è una versione nuova in rete? Se sì si salva e si avvisano le pagine aperte.
// Un controllo alla volta; a ogni apertura dell'app sempre, alle domande della pagina al massimo ogni 15 secondi.
let checking = null, checkedAt = 0, again = null;
function refresh(force) {
  if (checking) {
    if (!force) return checking;
    // controllo esplicito mentre ne è già partito uno (magari prima della versione nuova): se ne fa un altro subito dopo
    if (!again) again = checking.then(() => { again = null; return refresh(true); });
    return again;
  }
  if (!force && Date.now() - checkedAt < 15000) return Promise.resolve(false);
  checking = (async () => {
    try {
      const res = await fetch(new Request(SHELL, { cache: 'no-cache' }));
      if (!okRes(res)) return false;
      const c = await caches.open(CACHE);
      const old = await c.match(SHELL);
      const a = res.headers.get('etag'), b = old && old.headers.get('etag');
      if (old && a && b && a === b) return false;
      const text = await res.text();
      const v = verOf(text);
      if (!v) return false; // non è la pagina dell'app: la copia resta com'è
      if (old && !(a && b) && (await old.text()) === text) return false;
      await c.put(SHELL, shellOf(text, res));
      ver = v;
      await tellAll({ type: 'version', v });
      return true;
    } catch (x) { return false; } finally { checkedAt = Date.now(); checking = null; }
  })();
  return checking;
}

// apertura dell'app: subito la copia salvata, e intanto il controllo della versione
function openApp(e) {
  let bg;
  e.waitUntil(new Promise((ok) => { bg = ok; }));
  e.respondWith((async () => {
    let c = null;
    try {
      c = await caches.open(CACHE);
      const hit = await c.match(SHELL);
      if (hit) { bg(refresh(true)); return hit; }
    } catch (x) { /* archivio non disponibile */ }
    try {
      const res = await fetch(e.request);
      if (okRes(res) && c) {
        bg(res.clone().text().then((t) => (verOf(t) ? c.put(SHELL, shellOf(t, res)).then(() => { ver = verOf(t); }) : null)).catch(() => {}));
      } else bg();
      return res;
    } catch (x) {
      bg();
      const any = await caches.match(SHELL).catch(() => null);
      return any || new Response('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Algor Bomber</title><p style="font:16px/1.5 system-ui,sans-serif;padding:24px">Senza rete l\'app non si apre la prima volta. Riprova quando sei connesso.</p>', { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
    }
  })());
}

// gli altri file: subito la copia, e intanto si scarica quella nuova per la volta dopo
function fromCopy(e, r) {
  let stored = Promise.resolve();
  const net = fetch(r).then((res) => {
    if (okRes(res)) { const cp = res.clone(); stored = caches.open(CACHE).then((c) => c.put(r, cp)).catch(() => {}); }
    return res;
  });
  e.waitUntil(net.then(() => stored, () => {}));
  return caches.open(CACHE).then((c) => c.match(r)).then((hit) => hit || net, () => net);
}

self.addEventListener('fetch', (e) => {
  const r = e.request;
  if (r.method !== 'GET') return;
  const u = new URL(r.url);
  if (u.origin !== location.origin) return;
  if (r.mode === 'navigate') {
    if (SHELL_PATHS.includes(u.pathname)) openApp(e);
    return;
  }
  // richieste che vogliono la rete per forza, pezzi di audio e video, il service worker stesso
  if (r.cache === 'no-store' || r.cache === 'reload' || r.headers.has('range') || u.pathname.endsWith('/sw.js') || u.pathname.includes('/__')) return;
  e.respondWith(fromCopy(e, r));
});

// la pagina chiede: «c'è una versione nuova?» (all'avvio, quando torna in primo piano, da Impostazioni)
self.addEventListener('message', (e) => {
  const d = (e && e.data) || {};
  if (d.type !== 'check') return;
  const src = e.source;
  e.waitUntil((async () => {
    await refresh(!!d.force);
    const v = await savedVer();
    if (src && v) { try { src.postMessage({ type: 'version', v }); } catch (x) { /* finestra chiusa */ } }
  })());
});

// numerino sull'icona dell'app (dove si può): +1 a ogni notifica, l'app lo rimette giusto quando si apre
async function bumpBadge() {
  try {
    if (!self.navigator.setAppBadge) return;
    const c = await caches.open('ab-state');
    const k = new URL('__badge', self.registration.scope).href;
    const r = await c.match(k);
    const n = (r ? Number(await r.text()) || 0 : 0) + 1;
    await c.put(k, new Response(String(n)));
    await self.navigator.setAppBadge(n);
  } catch (x) { /* non supportato */ }
}

// notifiche: le manda la funzione "notify" di Supabase (messaggi della chat e partite)
// su iPhone, iPad e Mac (Safari) ogni notifica arrivata va mostrata, anche con l'app aperta
const UA = self.navigator.userAgent || '';
const isIOS = /iPad|iPhone|iPod|Macintosh/.test(UA) && !/Chrome|CriOS|Android|Firefox|FxiOS|Edg/.test(UA);
self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (x) { d = { title: 'Algor Bomber', body: e.data ? e.data.text() : '' }; }
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const open = d.chat ? '?chat=' + d.chat : '';
    // se l'app è aperta e in primo piano proprio su quella chat, su Android non serve l'avviso
    const here = wins.some((w) => w.focused && w.visibilityState === 'visible');
    wins.forEach((w) => { try { w.postMessage({ type: 'push', data: d }); } catch (x) { /* finestra chiusa */ } });
    if (here && !isIOS) return;
    if (d.chat) await bumpBadge();
    await self.registration.showNotification(d.title || 'Algor Bomber', {
      body: d.body || '',
      icon: 'icon-192.png',
      badge: 'badge-96.png',
      tag: d.tag || 'algor-bomber',
      renotify: true,
      timestamp: d.t || Date.now(),
      /* toccandola si apre la chat o la partita (o il gruppo) */
      data: { url: typeof d.url === 'string' && /^\.\/\?(chat|m|g)=[A-Za-z0-9_.~-]+$/.test(d.url) ? d.url : './' + open },
    });
  })());
});
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || './', self.registration.scope).href;
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const w of wins) {
      if (w.url.startsWith(self.registration.scope)) {
        try { await w.focus(); } catch (x) { /* già in primo piano */ }
        w.postMessage({ type: 'open', url });
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});
