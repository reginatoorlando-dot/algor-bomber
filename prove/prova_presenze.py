"""Presenze degli altri: toccare di nuovo «Ci sono» su chi è già iscritto non lo manda in fondo alla lista."""
from playwright.async_api import async_playwright
from comune import check, console_errors, open_demo, open_match, run


async def roster(page):
    sec = page.locator('section.sec', has=page.locator('h2', has_text='Giocatori'))
    return [t.split('\n')[0].strip() for t in await sec.locator('.card.pad0.divided').first.locator('button.row .row-t').all_inner_texts()]


async def main():
    async with async_playwright() as p:
        browser, page, errors = await open_demo(p)
        # una partita con la lista piena e la lista d'attesa
        await open_match(page, 2, 'Dettagli')
        before = await roster(page)
        check(len(before) >= 3, 'la partita ha i suoi iscritti (' + ', '.join(before) + ')')
        first = before[0]
        sec = page.locator('section.sec', has=page.locator('h2', has_text='Giocatori'))
        await sec.locator('button.row', has_text=first).first.click()
        await page.wait_for_timeout(400)
        await page.locator('.sheet .seg.rsvp button', has_text='Ci sono').click()
        await page.wait_for_timeout(600)
        await page.keyboard.press('Escape')
        await page.wait_for_timeout(300)
        after = await roster(page)
        check(after == before, f'ritoccando «Ci sono» su {first} la lista resta uguale ({after[0] if after else "-"} primo)')
        # cambiare davvero la presenza funziona ancora
        await sec.locator('button.row', has_text=first).first.click()
        await page.wait_for_timeout(400)
        await page.locator('.sheet .seg.rsvp button', has_text='Forse').click()
        await page.wait_for_timeout(600)
        await page.keyboard.press('Escape')
        await page.wait_for_timeout(300)
        check(first not in await roster(page), f'segnare {first} come «Forse» lo toglie dagli iscritti')
        bad = console_errors(errors)
        check(not bad, 'nessun errore in console' + ''.join('\n     ' + e for e in bad[:5]))
        await browser.close()


if __name__ == '__main__':
    run(main)
