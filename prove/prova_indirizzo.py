"""Un indirizzo solo: dagli indirizzi vecchi (algor-bomber-4aox, algor-bomber-67f5) si arriva su algor-bomber.vercel.app,
portandosi dietro le preferenze del telefono; l'app installata dall'indirizzo vecchio spiega cosa fare."""
import base64
import json
from urllib.parse import urlparse
from playwright.async_api import async_playwright
from comune import APP, check, console_errors, launch, listen, out, phone, run

OLD = 'https://algor-bomber-4aox.vercel.app'
HOME = 'https://algor-bomber.vercel.app'
HOSTS = {'algor-bomber-4aox.vercel.app', 'algor-bomber-67f5.vercel.app', 'algor-bomber.vercel.app'}
GROUP_KEY = 'sc-group-0f6c2a3e-1b7d-4c55-9a0e-2f4b8c9d1e7a'
PREFS = {
    'sc-theme': 'dark', 'sc-accent': 'blu', 'sc-campo': 'neve', 'sc-start': 'chat', 'sc-feste': 'off',
    'sc-home': json.dumps({'order': ['next', 'todo'], 'seen': ['next', 'todo']}),
    'sc-emoji-recent': json.dumps(['⚽', '🔥']),
    GROUP_KEY: 'g_abc123',
}
NOT_MOVED = {'sc-push-on': '1', 'sc-festa-seen': '2026-11-06', 'sc-read-moved-x': '1'}
# le preferenze sul telefono, messe una volta sola sull'indirizzo vecchio prima che parta l'app
SEED = """(() => {
  if (location.hostname !== 'algor-bomber-4aox.vercel.app' || localStorage.getItem('__seed')) return;
  localStorage.setItem('__seed', '1');
  const o = %s;
  Object.keys(o).forEach((k) => localStorage.setItem(k, o[k]));
})();""" % json.dumps({**PREFS, **NOT_MOVED})
STANDALONE = """(() => {
  const mm = window.matchMedia.bind(window);
  window.matchMedia = (q) => (/display-mode:\\s*standalone/.test(q) ? { matches: true, media: q, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {} } : mm(q));
})();"""


async def serve_hosts(route):
    """gli indirizzi dell'app rispondono con i file di questa cartella; tutto il resto è bloccato"""
    u = urlparse(route.request.url)
    if u.hostname in HOSTS:
        f = APP / (u.path.lstrip('/') or 'index.html')
        if f.is_file():
            await route.fulfill(path=str(f))
        else:
            await route.fulfill(status=404, body='')
    else:
        await route.abort()


async def new_page(browser, *scripts):
    ctx = await browser.new_context(**phone(), service_workers='block')
    for s in scripts:
        await ctx.add_init_script(s)
    await ctx.route('**/*', serve_hosts)
    page = await ctx.new_page()
    errors, navs = [], []
    listen(page, errors)
    page.on('framenavigated', lambda f: navs.append(f.url) if f == page.main_frame else None)
    return ctx, page, errors, navs


async def ls(page, k):
    return await page.evaluate('(k) => localStorage.getItem(k)', k)


async def main():
    async with async_playwright() as p:
        browser = await launch(p)

        # --- nel browser: dall'indirizzo vecchio si va subito su quello nuovo, con le preferenze
        ctx, page, errors, navs = await new_page(browser, SEED)
        await page.goto(OLD + '/?m=g_abc123.m1')
        await page.wait_for_url(HOME + '/**', timeout=10000)
        await page.wait_for_timeout(1200)
        first = next((u for u in navs if u.startswith(HOME)), '')
        check('#sc=' in first, 'il browser passa su algor-bomber.vercel.app con le preferenze nell\'indirizzo')
        kept = await page.evaluate("JSON.parse(sessionStorage.getItem('sc-link') || 'null')")
        check('#' not in page.url and kept and kept.get('gid') == 'g_abc123' and kept.get('mid') == 'm1',
              'arrivati, l\'indirizzo è pulito e il link della partita è tenuto da parte per dopo l\'accesso (' + page.url + ' ' + json.dumps(kept) + ')')
        got = {k: await ls(page, k) for k in PREFS}
        check(got == PREFS, 'le preferenze arrivano tutte: ' + ', '.join(k for k in PREFS if got[k] == PREFS[k]))
        left = {k: await ls(page, k) for k in NOT_MOVED}
        check(all(v is None for v in left.values()), 'notifiche, feste viste e letture restano sull\'indirizzo vecchio')
        note = page.locator('.note', has_text='L\'app adesso sta qui')
        check(await note.count() == 1 and 'Accedi' in await page.locator('#app').inner_text(), 'la schermata di accesso spiega che l\'app adesso sta qui')
        bad = console_errors(errors)
        check(not bad, 'nessun errore in console' + ''.join('\n     ' + e for e in bad[:5]))
        await ctx.close()

        # --- le preferenze già scelte sull'indirizzo nuovo non si toccano
        ctx, page, errors, navs = await new_page(browser, SEED)
        await page.goto(HOME + '/')
        await page.evaluate("localStorage.setItem('sc-theme', 'light')")
        await page.goto(OLD + '/')
        await page.wait_for_url(HOME + '/**', timeout=10000)
        await page.wait_for_timeout(800)
        check(await ls(page, 'sc-theme') == 'light' and await ls(page, 'sc-campo') == 'neve', 'una preferenza già scelta qui resta (tema chiaro), le altre arrivano (neve)')
        await ctx.close()

        # --- link con qualcosa dopo # (per esempio quello per cambiare la password): si lascia com'è
        ctx, page, errors, navs = await new_page(browser, SEED)
        await page.goto(OLD + '/#access_token=abc&type=recovery')
        await page.wait_for_url(HOME + '/**', timeout=10000)
        first = next((u for u in navs if u.startswith(HOME)), '')
        check(first == HOME + '/#access_token=abc&type=recovery', 'il link per la password passa così com\'è (' + first + ')')
        await ctx.close()

        # --- l'app installata dall'indirizzo vecchio: spiega cosa fare, e si può continuare per ora
        ctx, page, errors, navs = await new_page(browser, SEED, STANDALONE)
        await page.goto(OLD + '/')
        await page.wait_for_timeout(2500)
        check(page.url.startswith(OLD), 'l\'app installata resta sull\'indirizzo vecchio (' + page.url + ')')
        txt = await page.locator('#app').inner_text()
        check("L'app ha cambiato indirizzo" in txt and 'algor-bomber.vercel.app' in txt, 'e spiega che l\'app ha cambiato indirizzo')
        steps = await page.locator('.moved-steps li').all_inner_texts()
        check(len(steps) == 5 and 'Accedi' in steps[1] and 'notifiche' in steps[3], 'cinque passi: apri, accedi, schermata Home, notifiche, cancella la vecchia')
        link = page.get_by_role('link', name='Apri il nuovo indirizzo')
        href = await link.get_attribute('href') or ''
        check(href.startswith(HOME + '/') and '#sc=' in href and await link.get_attribute('target') == '_blank', 'il pulsante apre il nuovo indirizzo nel browser, con le preferenze')
        check(await page.evaluate('Moved.home()') == HOME + '/', 'i link d\'invito fatti da qui puntano già al nuovo indirizzo')
        await page.screenshot(path=out('indirizzo-vecchio.png'))
        await page.get_by_role('button', name='Per ora continua qui').click()
        await page.wait_for_timeout(800)
        check('Accedi' in await page.locator('#app').inner_text(), '"Per ora continua qui" apre l\'app di sempre')
        bad = console_errors(errors)
        check(not bad, 'nessun errore in console (app installata)' + ''.join('\n     ' + e for e in bad[:5]))
        await ctx.close()

        # --- un indirizzo scritto a mano non può mettere valori strani nel telefono
        evil = {'sc-theme': '<img src=x onerror=alert(1)>', 'sc-home': '[1,2]', 'sc-emoji-recent': '{"a":1}', 'evil': 'x',
                'sc-group-abcdef12': '../x', 'sc-accent': 'a' * 60, 'sc-campo': 'neve'}
        h = base64.urlsafe_b64encode(json.dumps(evil).encode()).decode().rstrip('=')
        ctx, page, errors, navs = await new_page(browser)
        dialogs = []
        page.on('dialog', lambda d: (dialogs.append(d.message), d.dismiss()))
        await page.goto(HOME + '/#sc=' + h)
        await page.wait_for_timeout(1000)
        vals = {k: await ls(page, k) for k in evil}
        check(vals['sc-campo'] == 'neve' and all(vals[k] is None for k in evil if k != 'sc-campo'), 'da un indirizzo scritto a mano passano solo i valori in regola')
        check(not dialogs and page.url == HOME + '/', 'nessun effetto strano, e l\'indirizzo si pulisce')
        rx = await page.evaluate("""() => ['algor-bomber-4aox.vercel.app', 'algor-bomber-67f5.vercel.app', 'algor-bomber-4aox-git-main-orlando.vercel.app',
            'algor-bomber.vercel.app', 'algor-bomber-git-main-orlando.vercel.app', 'algor-bomber-67f5abc12-orlando.vercel.app'].map((h) => OLD_HOST.test(h))""")
        check(rx == [True, True, True, False, False, False], 'indirizzi vecchi riconosciuti (anche le anteprime dei progetti vecchi), le anteprime del progetto giusto no')
        await ctx.close()
        await browser.close()


if __name__ == '__main__':
    run(main)
