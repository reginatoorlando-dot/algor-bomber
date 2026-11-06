"""Service worker: l'app si apre dalla copia sul telefono, la versione nuova arriva con «Aggiorna», funziona senza rete,
e il passaggio dal service worker di prima (v18, sempre dalla rete) avviene senza ricariche a vuoto."""
import os
import re
import shutil
import tempfile
import time
from pathlib import Path
from playwright.async_api import async_playwright
from comune import APP, NO_NET, PROVE, check, console_errors, launch, listen, out, phone, run, serve

SRC = (APP / 'index.html').read_text(encoding='utf-8')
V = re.search(r"\bconst APP_VER = '([0-9][0-9.]*)';", SRC).group(1)
NEW = '2099.1.1'


def site(folder):
    """copia dei file dell'app (senza cartelle) in una cartella a parte, da poter cambiare durante la prova"""
    for f in APP.iterdir():
        if f.is_file() and not f.name.startswith('.'):
            shutil.copy(f, folder / f.name)


def write(p, text):
    """scrive il file con la data di modifica più avanti: il server di prova la dà al secondo, e a parità risponderebbe «non cambiato»"""
    p.write_text(text, encoding='utf-8')
    t = max(time.time(), p.stat().st_mtime) + 5 + write.n
    write.n += 5
    os.utime(p, (t, t))


write.n = 0


def bump(folder, frm=None, to=NEW):
    """esce una versione nuova: cambia APP_VER (e la prima voce delle Novità)"""
    frm = frm or V
    p = folder / 'index.html'
    s = p.read_text(encoding='utf-8').replace(f"const APP_VER = '{frm}';", f"const APP_VER = '{to}';", 1)
    s = s.replace(f"{{ v: '{frm}', d: ", f"{{ v: '{to}', d: ", 1)
    write(p, s)


async def ver(page):
    return await page.evaluate("typeof APP_VER === 'undefined' ? null : APP_VER")


async def new_page(p):
    # niente page.route: con le richieste intercettate il service worker verrebbe scavalcato
    browser = await launch(p, [NO_NET])
    ctx = await browser.new_context(**phone())
    page = await ctx.new_page()
    errors = []
    listen(page, errors)
    return browser, page, errors


async def update_flow(p):
    tmp = Path(tempfile.mkdtemp(prefix='ab-agg-'))
    site(tmp)
    url, proc = serve(tmp)
    browser, page, errors = await new_page(p)
    await page.goto(url)
    await page.wait_for_function('navigator.serviceWorker && navigator.serviceWorker.controller !== null', timeout=20000)
    check(await ver(page) == V, f'prima apertura: versione {V}, e il service worker prende in mano la pagina')
    keys = await page.evaluate('caches.keys()')
    check('algor-bomber-v19' in keys, 'la copia dell\'app è salvata (' + ', '.join(keys) + ')')

    # esce una versione nuova: la riapertura è immediata con la copia, poi arriva la barra
    bump(tmp)
    await page.reload()
    await page.wait_for_timeout(500)
    check(await ver(page) == V, 'riaprendo, parte subito la copia sul telefono (' + str(await ver(page)) + ')')
    bar = page.locator('.upd')
    try:
        await bar.wait_for(timeout=12000)
    except Exception:
        pass
    check(await bar.count() == 1 and 'Nuova versione pronta' in await bar.inner_text(), 'compare la barra «Nuova versione pronta» con Aggiorna')
    await page.screenshot(path=out('barra-aggiorna.png'))
    async with page.expect_navigation():
        await bar.get_by_role('button', name='Aggiorna').click()
    await page.wait_for_timeout(800)
    check(await ver(page) == NEW, f'«Aggiorna» porta alla versione {NEW} (' + str(await ver(page)) + ')')
    await page.wait_for_timeout(3500)
    check(await page.locator('.upd').count() == 0, 'dopo l\'aggiornamento la barra non c\'è più')

    # «Più tardi»: la barra si chiude; la versione nuova parte comunque alla prossima apertura
    bump(tmp, NEW, '2099.1.2')
    await page.reload()
    try:
        await page.locator('.upd').wait_for(timeout=12000)
    except Exception:
        pass
    await page.locator('.upd').get_by_role('button', name='Più tardi').click()
    await page.wait_for_timeout(300)
    check(await page.locator('.upd').count() == 0, '«Più tardi» chiude la barra')
    await page.reload()
    await page.wait_for_timeout(600)
    check(await ver(page) == '2099.1.2', 'alla riapertura dopo parte la versione nuova (' + str(await ver(page)) + ')')

    # se il sito risponde con una pagina che non è l'app (un errore, una pagina di accesso…) la copia non si tocca
    good = (tmp / 'index.html').read_text(encoding='utf-8')
    write(tmp / 'index.html', '<!doctype html><title>Errore</title><h1>Qualcosa è andato storto</h1>')
    await page.reload()
    await page.wait_for_timeout(2500)
    await page.reload()
    await page.wait_for_timeout(800)
    check(await ver(page) == '2099.1.2' and await page.locator('.upd').count() == 0, 'una pagina d\'errore dal sito non prende il posto dell\'app')
    write(tmp / 'index.html', good)

    # senza rete: l'app si apre lo stesso, con i suoi file
    proc.terminate()
    proc.wait()
    await page.reload()
    await page.wait_for_timeout(1200)
    check(await ver(page) == '2099.1.2', 'senza rete l\'app si apre dalla copia')
    txt = await page.locator('#app').inner_text()
    check('Accedi' in txt and 'Senza rete' not in txt, 'senza rete si vede la schermata di accesso, non un errore')
    st = await page.evaluate("Promise.all(['config.js', 'icon.svg', 'manifest.webmanifest'].map((u) => fetch(u).then((r) => r.status, () => 0)))")
    check(st == [200, 200, 200], 'senza rete config, icona e manifest arrivano dalla copia (' + ', '.join(map(str, st)) + ')')
    bad = console_errors(errors)
    check(not bad, 'nessun errore in console' + ''.join('\n     ' + e for e in bad[:5]))
    await browser.close()


async def migration(p):
    """chi ha già l'app con il service worker di prima: passa al nuovo senza ricariche continue"""
    tmp = Path(tempfile.mkdtemp(prefix='ab-mig-'))
    site(tmp)
    shutil.copy(PROVE / 'dati' / 'pagina-vecchia.html', tmp / 'index.html')
    shutil.copy(PROVE / 'dati' / 'sw-v18.js', tmp / 'sw.js')
    url, proc = serve(tmp)
    browser, page, errors = await new_page(p)
    navs = []
    page.on('framenavigated', lambda f: navs.append(f.url) if f == page.main_frame else None)
    await page.goto(url)
    await page.wait_for_function('navigator.serviceWorker && navigator.serviceWorker.controller !== null', timeout=20000)
    await page.reload()
    await page.wait_for_timeout(500)
    check(await page.locator('#vecchia').count() == 1 and 'algor-bomber-v18' in await page.evaluate('caches.keys()'), 'situazione di partenza: pagina e service worker di prima (v18)')

    # esce la versione nuova mentre la pagina vecchia è aperta
    site(tmp)
    for f in ('index.html', 'sw.js'):
        write(tmp / f, (tmp / f).read_text(encoding='utf-8'))
    await page.evaluate("navigator.serviceWorker.getRegistration().then((r) => r.update())")
    await page.wait_for_function(f"typeof APP_VER !== 'undefined' && APP_VER === '{V}'", timeout=20000)
    n0 = len(navs)
    keys = await page.evaluate('caches.keys()')
    check('algor-bomber-v19' in keys and 'algor-bomber-v18' not in keys, 'la pagina vecchia passa da sola alla nuova, e la copia v18 è tolta (' + ', '.join(keys) + ')')
    await page.wait_for_timeout(4000)
    check(len(navs) == n0, f'poi niente altre ricariche ({len(navs) - n0})')
    check(await page.locator('.upd').count() == 0, 'e nessuna barra «Aggiorna» (la versione è già quella giusta)')

    # riaprendo, parte dalla copia del service worker nuovo
    bump(tmp)
    await page.reload()
    await page.wait_for_timeout(500)
    check(await ver(page) == V, 'riaprendo, parte dalla copia del nuovo service worker')
    try:
        await page.locator('.upd').wait_for(timeout=12000)
    except Exception:
        pass
    check(await page.locator('.upd').count() == 1, 'e quando esce una versione nuova compare «Aggiorna»')
    bad = console_errors(errors)
    check(not bad, 'nessun errore in console' + ''.join('\n     ' + e for e in bad[:5]))
    await browser.close()
    proc.terminate()


async def main():
    async with async_playwright() as p:
        await update_flow(p)
        await migration(p)


if __name__ == '__main__':
    run(main)
