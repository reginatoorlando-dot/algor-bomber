"""Pezzi in comune alle prove: il server con l'app, il telefono simulato con i dati di esempio, i controlli.

Ogni prova (prova_*.py) si può lanciare da sola (python3 prove/prova_campo.py) oppure tutte insieme
con python3 prove/esegui.py, che è quello che fa GitHub a ogni pull request.
"""
import asyncio
import atexit
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

PROVE = Path(__file__).resolve().parent
APP = PROVE.parent                      # la cartella dell'app: index.html, sw.js, config.js…
RISULTATI = PROVE / 'risultati'         # foto e immagini fatte durante le prove (non vanno nel repository)
FAIL = []


def check(cond, msg):
    print(('OK   ' if cond else 'FAIL ') + msg, flush=True)
    if not cond:
        FAIL.append(msg)


def done():
    """riepilogo finale: esce con errore se qualche controllo è fallito"""
    print('\nFALLITE:', len(FAIL))
    for f in FAIL:
        print(' -', f)
    sys.exit(1 if FAIL else 0)


def out(name):
    """percorso per salvare una foto della prova"""
    RISULTATI.mkdir(exist_ok=True)
    return str(RISULTATI / name)


def console_errors(errors):
    """errori in console, tolti quelli delle richieste fuori dall'app, bloccate apposta (Supabase, caratteri, servizi esterni)"""
    def external(e):
        if 'ERR_FAILED' in e or 'ERR_BLOCKED' in e or 'blocked by Playwright' in e:
            return True
        return 'Failed to load resource' in e and '[http://127.0.0.1' not in e
    return [e for e in errors if not external(e)]


# ---------- server statico con l'app ----------
def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def serve(folder=APP, port=None):
    """avvia un server statico sulla cartella e aspetta che risponda; torna (indirizzo base, processo)"""
    port = port or free_port()
    proc = subprocess.Popen([sys.executable, '-m', 'http.server', str(port), '--bind', '127.0.0.1', '--directory', str(folder)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    atexit.register(proc.terminate)
    for _ in range(100):
        try:
            socket.create_connection(('127.0.0.1', port), timeout=0.2).close()
            break
        except OSError:
            time.sleep(0.1)
    return f'http://127.0.0.1:{port}/', proc


def base():
    """indirizzo dell'app: quello passato da esegui.py (PROVE_URL) o un server avviato qui"""
    u = os.environ.get('PROVE_URL')
    if not u:
        u, _ = serve()
        os.environ['PROVE_URL'] = u
    return u


# ---------- browser ----------
def chrome():
    for p in [os.environ.get('CHROME'), '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium', '/usr/bin/chromium-browser']:
        if p and os.path.exists(p):
            return p
    return None  # si usa quello di Playwright (python3 -m playwright install chromium)


async def launch(p, args=()):
    kw = {'args': ['--no-sandbox'] + list(args)}
    exe = chrome()
    if exe:
        kw['executable_path'] = exe
    return await p.chromium.launch(**kw)


def phone(dark=False, w=390, h=844):
    return dict(viewport={'width': w, 'height': h}, device_scale_factor=2, has_touch=True, is_mobile=True,
                color_scheme='dark' if dark else 'light', locale='it-IT')


def listen(page, errors):
    def con(m):
        if m.type in ('error', 'warning'):
            u = (m.location or {}).get('url') or ''
            errors.append('console.' + m.type + ': ' + m.text + (' [' + u + ']' if u else ''))
    page.on('pageerror', lambda e: errors.append('pageerror: ' + str(e)))
    page.on('console', con)


# senza intercettare le richieste (che scavalcherebbero il service worker): i nomi diversi da 127.0.0.1 non esistono
NO_NET = '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1'


async def only_local(page, prefix):
    """niente rete verso Supabase e servizi esterni: passano solo le richieste all'app"""
    async def block(route):
        if route.request.url.startswith(prefix):
            await route.continue_()
        else:
            await route.abort()
    await page.route('**/*', block)


async def open_demo(p, dark=False, w=390, h=844):
    """apre l'app con i dati di esempio su un telefono simulato; torna (browser, pagina, errori in console)"""
    browser = await launch(p)
    ctx = await browser.new_context(**phone(dark, w, h))
    page = await ctx.new_page()
    errors = []
    listen(page, errors)
    url = base()
    await only_local(page, url)
    await page.goto(url + 'index.html')
    await page.wait_for_timeout(1200)
    # senza accesso a Supabase: si monta direttamente l'app, che offre i dati di esempio
    await page.evaluate("() => { const el = document.getElementById('app'); render(null, el); render(html`<${App} />`, el); }")
    await page.wait_for_timeout(600)
    for label_ in ["Prova con dati di esempio", "Dai un'occhiata con dati di esempio"]:
        b = page.get_by_role('button', name=label_)
        if await b.count():
            await b.first.click()
            break
    await page.wait_for_timeout(1600)
    # il riepilogo "Com'è andata?" si apre da solo: si torna all'elenco delle partite
    back = page.get_by_role('button', name='Indietro')
    if await back.count():
        await back.first.click()
        await page.wait_for_timeout(500)
    return browser, page, errors


# ---------- dito sul campo (eventi touch veri via CDP) ----------
async def touch(cdp, kind, x=None, y=None):
    pts = [] if kind == 'touchEnd' else [{'x': x, 'y': y, 'radiusX': 4, 'radiusY': 4, 'force': 1}]
    await cdp.send('Input.dispatchTouchEvent', {'type': kind, 'touchPoints': pts})


async def long_drag(page, cdp, a, b, hold=520, steps=14):
    """tiene premuto in a, poi trascina fino a b e lascia"""
    await touch(cdp, 'touchStart', *a)
    await page.wait_for_timeout(hold)
    for i in range(1, steps + 1):
        x = a[0] + (b[0] - a[0]) * i / steps
        y = a[1] + (b[1] - a[1]) * i / steps
        await touch(cdp, 'touchMove', x, y)
        await page.wait_for_timeout(18)
    await page.wait_for_timeout(60)
    await touch(cdp, 'touchEnd')
    await page.wait_for_timeout(350)


async def center(loc):
    bb = await loc.bounding_box()
    return (bb['x'] + bb['width'] / 2, bb['y'] + bb['height'] * 0.38)


def pd(page, name):
    return page.locator('svg.pitch g.pd[aria-label^="' + name + ',"]')


async def label(page, name):
    return await pd(page, name).get_attribute('aria-label')


async def open_match(page, idx, tab='Campo'):
    await page.locator('button.card.match').nth(idx).click()
    await page.wait_for_timeout(700)
    if tab:
        await page.locator('.seg.mtabs button', has_text=tab).click()
        await page.wait_for_timeout(600)


def run(main):
    asyncio.run(main())
    done()
