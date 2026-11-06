"""Giro di tutta l'app con i dati di esempio: ogni partita e ogni scheda si aprono senza errori."""
from playwright.async_api import async_playwright
from comune import open_demo, check, run, console_errors


async def main():
    async with async_playwright() as p:
        browser, page, errors = await open_demo(p)
        n = await page.locator('button.card.match').count()
        for i in range(n):
            await page.locator('button.card.match').nth(i).click()
            await page.wait_for_timeout(500)
            for t in ['Campo', 'Squadre', 'Dettagli']:
                b = page.locator('.seg.mtabs button', has_text=t)
                if await b.count():
                    await b.click(); await page.wait_for_timeout(350)
            await page.get_by_role('button', name='Indietro').first.click()
            await page.wait_for_timeout(400)
        for t in ['Storico', 'Giocatori', 'Profilo', 'Partite']:
            await page.locator('.nav-btn', has_text=t).click(); await page.wait_for_timeout(500)
        await page.locator('.nav-btn', has_text='Profilo').click(); await page.wait_for_timeout(400)
        menu = page.get_by_role('button', name='Menu')
        if await menu.count():
            await menu.first.click(); await page.wait_for_timeout(300)
            ch = page.locator('.sheet').get_by_role('button', name='Come funziona')
            if await ch.count():
                await ch.first.click(); await page.wait_for_timeout(400)
                txt = await page.locator('.sheet').inner_text()
                check('Il Campo' in txt and 'ti manda in panchina' in txt, 'Come funziona: voce "Il Campo" e notifica della panchina')
        errs = console_errors(errors)
        check(not errs, 'nessun errore in console nel giro dell\'app' + ('' if not errs else ': ' + ' | '.join(errs[:5])))
        await browser.close()


if __name__ == '__main__':
    run(main)
