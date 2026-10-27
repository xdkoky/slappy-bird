// Slappy Fih - Copyright (c) 2026 xdkoky. All rights reserved. See LICENSE.
// Offline cache for the Home Screen web app. Bump VERSION whenever the game changes.
const VERSION = 'slappy-202610122980000';
const FILES = ['./', 'index.html', 'manifest.webmanifest', 'icon-180.png', 'icon-192.png', 'icon-512.png', 'favicon.ico', 'favicon-32.png', 'favicon-16.png'];
self.addEventListener('install', e => e.waitUntil(caches.open(VERSION).then(c => c.addAll(FILES)).then(() => self.skipWaiting())));
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim())));
// network first (so updates arrive when online), cache when offline
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET' || new URL(e.request.url).origin !== location.origin) return;   // only the game's own files (never ads etc.)
  e.respondWith(fetch(e.request, { cache: 'no-cache' }).then(r => {
    const copy = r.clone(); caches.open(VERSION).then(c => c.put(e.request, copy)); return r;
  }).catch(() => caches.match(e.request, { ignoreSearch: true })));
});
// reminders and message alerts (see supabase/push.sql, push_dm.sql): show the one sent; a tap on it opens the game
// (on a message alert: that chat)
self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Slappy Fih', { body: d.body || '', icon: 'icon-192.png', badge: 'favicon-32.png', tag: d.tag || 'slappy', data: { url: d.url || './', chat: d.chat || null } }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
    const chat = e.notification.data && e.notification.data.chat;
    for (const c of cs) if ('focus' in c) { if (chat) c.postMessage({ chat }); return c.focus(); }
    return self.clients.openWindow((e.notification.data && e.notification.data.url) || './');
  }));
});
