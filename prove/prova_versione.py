"""Versione dell'app e Novità: la versione è una sola dappertutto, le Novità si aprono da sole una volta dopo un aggiornamento."""
import re
from playwright.async_api import async_playwright
from comune import APP, base, check, console_errors, launch, listen, only_local, open_demo, phone, run

SRC = (APP / 'index.html').read_text(encoding='utf-8')
SW = (APP / 'sw.js').read_text(encoding='utf-8')

# il backend di prova: i dati di esempio, ma l'app li tratta come quelli veri (Novità, notifiche, riepilogo…)
FAKE_REAL = """() => {
  localStorage.setItem('sc-group-' + Demo.ME, Demo.GID);
  window.claude = { use: async (n) => (n === 'db' ? (window.__db = window.__db || Demo.createSeeded())
    : n === 'user' ? { id: async () => Demo.ME, can: async () => true, isOwner: async () => true } : null) };
  const el = document.getElementById('app'); render(null, el); render(html`<${App} />`, el);
}"""


def static_checks():
    ver = re.search(r"\bconst APP_VER = '([0-9][0-9.]*)';", SRC)
    check(ver is not None, 'index.html ha APP_VER')
    v = ver.group(1) if ver else ''
    first = re.search(r"const NOVITA = \[\s*\{ v: '([0-9.]+)', d: '([^']+)'", SRC)
    check(first is not None and first.group(1) == v, f'la prima voce delle Novità è della versione {v} ({first.group(1) if first else "-"})')
    # il service worker trova la versione con la sua espressione (la stessa scritta qui)
    m = re.search(r"const verOf = .*?/(\\b.*?)/\.exec", SW)
    check(m is not None, 'sw.js legge APP_VER')
    if m:
        rx = m.group(1).replace('\\\\', '\\')
        found = re.search(rx, SRC)
        check(found is not None and found.group(1) == v, 'la lettura del service worker dà ' + (found.group(1) if found else '-'))
    check(re.search(r"const CACHE = 'algor-bomber-v\d+';", SW) is not None, 'sw.js ha il nome della sua copia (algor-bomber-vNN)')
    # versioni in ordine, dalla più nuova
    vs = re.findall(r"\{ v: '([0-9.]+)', d: '", SRC)
    key = lambda s: [int(x) for x in s.split('.')]
    check(vs == sorted(vs, key=key, reverse=True) and len(set(vs)) == len(vs), 'Novità in ordine dalla più nuova, senza doppioni: ' + ', '.join(vs))
    return v


async def main():
    v = static_checks()
    async with async_playwright() as p:
        # --- dati di esempio: menu, Novità, Impostazioni
        browser, page, errors = await open_demo(p)
        check(await page.evaluate('verCmp("2026.11.10", "2026.11.6")') == 1 and await page.evaluate('verCmp("2026.11.6", "2026.11.6.2")') == -1
              and await page.evaluate('verCmp("2026.11.6", "2026.11.6")') == 0, 'confronto tra versioni (11.10 dopo 11.6, 11.6.2 dopo 11.6)')
        await page.locator('.nav-btn', has_text='Profilo').click()
        await page.wait_for_timeout(400)
        await page.get_by_role('button', name='Menu').first.click()
        await page.wait_for_timeout(300)
        sheet = page.locator('.sheet')
        check('versione ' + v in await sheet.inner_text(), 'in fondo al menu: "versione ' + v + '"')
        await sheet.get_by_role('button', name='Novità').click()
        await page.wait_for_timeout(400)
        txt = await page.locator('.sheet').inner_text()
        check(txt.startswith('Novità') and 'Hai la versione ' + v in txt and 'Questa versione' in txt, 'il menu apre le Novità, con la versione di adesso in cima')
        check('Il Campo' in txt and 'algor-bomber.vercel.app' in txt, 'le Novità raccontano le ultime due versioni')
        await page.locator('.sheet').get_by_role('button', name='Ok', exact=True).click()
        await page.wait_for_timeout(300)
        check(await page.locator('.sheet').count() == 0, '"Ok" chiude le Novità')
        await page.get_by_role('button', name='Menu').first.click()
        await page.wait_for_timeout(300)
        await page.locator('.sheet').get_by_role('button', name='Impostazioni').click()
        await page.wait_for_timeout(500)
        app = page.locator('section.sec', has=page.locator('h2', has_text='App'))
        check(await app.count() == 1 and 'Versione ' + v in await app.inner_text(), 'Impostazioni → App: la versione')
        await page.wait_for_function('navigator.serviceWorker && navigator.serviceWorker.controller !== null', timeout=20000)
        await app.get_by_role('button', name='Cerca aggiornamenti').click()
        await page.wait_for_timeout(200)
        toast = page.locator('.toast')
        await toast.wait_for(timeout=12000)
        t = await toast.inner_text()
        check("Hai già l'ultima versione" in t, 'Cerca aggiornamenti risponde: ' + t)
        await app.get_by_role('button', name='Novità').click()
        await page.wait_for_timeout(300)
        check(await page.locator('.sheet .sheet-head', has_text='Novità').count() == 1, 'Impostazioni → Novità')
        await page.keyboard.press('Escape')
        bad = console_errors(errors)
        check(not bad, 'nessun errore in console (dati di esempio)' + ''.join('\n     ' + e for e in bad[:5]))
        await browser.close()

        # --- come un utente vero dopo un aggiornamento: le Novità si aprono da sole, una volta sola
        browser = await launch(p)
        ctx = await browser.new_context(**phone())
        page = await ctx.new_page()
        errors = []
        listen(page, errors)
        await only_local(page, base())
        await page.goto(base() + 'index.html')
        await page.wait_for_timeout(800)
        await page.evaluate("localStorage.setItem('sc-ver', '2026.11.5')")
        await page.evaluate(FAKE_REAL)
        nov = page.locator('.sheet .sheet-head', has_text='Novità')
        for _ in range(40):
            if await nov.count():
                break
            # il riepilogo della partita ha la precedenza: lo si chiude e poi arrivano le Novità
            back = page.get_by_role('button', name='Indietro')
            if await back.count() and await page.locator('.sheet').count() == 0:
                await back.first.click()
            await page.wait_for_timeout(250)
        check(await nov.count() == 1, 'dopo l\'aggiornamento le Novità si aprono da sole')
        check(await page.evaluate("localStorage.getItem('sc-ver')") == v, 'e il telefono si segna di averle viste (sc-ver = ' + v + ')')
        await page.locator('.sheet').get_by_role('button', name='Ok', exact=True).click()
        await page.wait_for_timeout(300)
        await page.evaluate(FAKE_REAL)
        await page.wait_for_timeout(3500)
        back = page.get_by_role('button', name='Indietro')
        if await back.count():
            await back.first.click()
            await page.wait_for_timeout(2500)
        check(await nov.count() == 0, 'riaprendo l\'app non si aprono più')
        bad = console_errors(errors)
        check(not bad, 'nessun errore in console (utente vero)' + ''.join('\n     ' + e for e in bad[:5]))
        await browser.close()


if __name__ == '__main__':
    run(main)
