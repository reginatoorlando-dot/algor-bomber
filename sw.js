// Service worker: permette l'installazione e l'apertura anche con rete debole,
// e mostra le notifiche dei messaggi (anche ad app chiusa).
// La pagina viene sempre scaricata nuova se c'è rete, così gli aggiornamenti arrivano da soli.
const CACHE = 'algor-bomber-v15';
self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(['./', 'manifest.webmanifest', 'icon-192.png'])).catch(() => {}));
});
self.addEventListener('activate', (e) => {
  // si tolgono solo le versioni vecchie dell'app: foto e vocali della chat restano sul telefono
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k.startsWith('algor-bomber-') && k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const r = e.request;
  if (r.method !== 'GET' || new URL(r.url).origin !== location.origin) return;
  e.respondWith(
    fetch(r).then((res) => { if (res.ok) { const cp = res.clone(); caches.open(CACHE).then((c) => c.put(r, cp)); } return res; })
      .catch(() => caches.match(r).then((m) => m || caches.match('./')))
  );
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

// notifiche: le manda la funzione "notify" di Supabase a ogni messaggio nuovo
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
      data: { url: './' + open },
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
