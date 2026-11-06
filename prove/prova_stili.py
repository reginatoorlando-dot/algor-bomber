"""Stili del campo: tastino, tendina con le anteprime, ogni stile sul campo vero; foto di tutti in un'unica immagine."""
from PIL import Image
from playwright.async_api import async_playwright
from comune import open_demo, check, run, out, console_errors, open_match, pd, center, touch, label


async def main():
    async with async_playwright() as p:
        browser, page, errors = await open_demo(p)
        cdp = await page.context.new_cdp_session(page)
        await open_match(page, 2)
        btn = page.locator('.pitch-wrap .pt-style-btn')
        check(await btn.count() == 1, 'il tastino dello stile è sul campo')
        await btn.click()
        await page.wait_for_timeout(400)
        names = await page.locator('.sheet .cm-opt span').all_inner_texts()
        print('  stili:', names)
        check(len(names) == 12 and names[0] == 'Erba a strisce', '12 stili nella tendina, il primo è quello di sempre')
        await page.screenshot(path=out('stili-tendina.png'))
        await page.keyboard.press('Escape')
        await page.wait_for_timeout(300)
        shots = []
        for i, name in enumerate(names):
            await page.locator('.pitch-wrap .pt-style-btn').click()
            await page.wait_for_timeout(300)
            await page.locator('.sheet .cm-opt').nth(i).click()
            await page.wait_for_timeout(500)
            cls = await page.locator('svg.pitch').first.get_attribute('class')
            check(await page.locator('.sheet').count() == 0 and cls.startswith('pitch st-'), f'"{name}": la tendina si chiude e il campo cambia ({cls})')
            el = page.locator('.pitch-wrap').first
            await el.scroll_into_view_if_needed()
            f = out(f'stile-{i:02d}.png')
            await el.screenshot(path=f)
            shots.append((name, f))
        # lo stile resta dopo aver riaperto l'app (sta sul telefono)
        saved = await page.evaluate("localStorage.getItem('sc-campo')")
        check(saved == 'notturno', "lo stile scelto resta sul telefono (sc-campo = " + str(saved) + ")")
        # con uno stile si trascina come prima (calcio balilla)
        await page.locator('.pitch-wrap .pt-style-btn').click()
        await page.wait_for_timeout(300)
        await page.locator('.sheet .cm-opt', has_text='Calcio balilla').click()
        await page.wait_for_timeout(400)
        await pd(page, 'Stef').scroll_into_view_if_needed()
        await page.evaluate('window.scrollBy(0, 140)')
        b_stef, b_dave = await label(page, 'Stef'), await label(page, 'Dave')
        a, b = await center(pd(page, 'Stef')), await center(pd(page, 'Dave'))
        await touch(cdp, 'touchStart', *a)
        await page.wait_for_timeout(520)
        for i in range(1, 13):
            await touch(cdp, 'touchMove', a[0] + (b[0] - a[0]) * i / 12, a[1] + (b[1] - a[1]) * i / 12)
            await page.wait_for_timeout(18)
        await page.wait_for_timeout(100)
        await touch(cdp, 'touchEnd')
        await page.wait_for_timeout(500)
        check(await label(page, 'Stef') != b_stef, 'col calcio balilla lo scambio trascinando funziona come prima')
        # anche nelle partite chiuse e nelle Impostazioni
        await page.get_by_role('button', name='Indietro').first.click()
        await page.wait_for_timeout(400)
        await open_match(page, 4)
        check(await page.locator('.pitch-wrap .pt-style-btn').count() == 1 and 'st-balilla' in await page.locator('svg.pitch').first.get_attribute('class'), 'partita chiusa: c\'è il tastino e lo stile scelto')
        await page.get_by_role('button', name='Indietro').first.click()
        await page.wait_for_timeout(400)
        await page.locator('.nav-btn', has_text='Profilo').click()
        await page.wait_for_timeout(400)
        await page.get_by_role('button', name='Menu').first.click()
        await page.wait_for_timeout(300)
        await page.locator('.sheet').get_by_role('button', name='Impostazioni').click()
        await page.wait_for_timeout(500)
        check(await page.get_by_role('button', name='Stile del campo: Calcio balilla').count() == 1, 'Impostazioni → Aspetto: "Stile del campo: Calcio balilla"')
        check(not console_errors(errors), 'nessun errore in console' + ''.join('\n     ' + e for e in console_errors(errors)[:5]))
        await browser.close()
    # tutte le foto in una griglia 6×2
    ims = [Image.open(f).convert('RGB') for _, f in shots]
    w, h = ims[0].size
    cols, gap = 6, 16
    rows = (len(ims) + cols - 1) // cols
    img = Image.new('RGB', (cols * w + (cols - 1) * gap, rows * h + (rows - 1) * gap), (236, 240, 236))
    for k, im in enumerate(ims):
        img.paste(im.resize((w, h)), ((k % cols) * (w + gap), (k // cols) * (h + gap)))
    img = img.resize((img.width * 30 // 100, img.height * 30 // 100), Image.LANCZOS)
    img.save(out('stili-campo.png'), optimize=True)
    print('griglia', img.size)


if __name__ == '__main__':
    run(main)
