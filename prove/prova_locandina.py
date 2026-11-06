"""Locandina con lo stile del campo scelto: la genera davvero l'app (stesso codice di "Condividi la locandina")."""
import base64
from PIL import Image
from playwright.async_api import async_playwright
from comune import open_demo, check, run, out, console_errors, open_match

STILI = ['Erba a strisce', 'Neve', 'Calcio balilla', 'Marte', "Sull'acqua", 'Lavagna', 'Palazzetto', 'Sotto i riflettori']


async def main():
    async with async_playwright() as p:
        browser, page, errors = await open_demo(p)
        await open_match(page, 2)
        files = []
        for k, name in enumerate(STILI):
            await page.locator('.pitch-wrap .pt-style-btn').click()
            await page.wait_for_timeout(300)
            await page.locator('.sheet .cm-opt', has_text=name).click()
            await page.wait_for_timeout(300)
            await page.get_by_role('button', name='Condividi la locandina').click()
            img = page.locator('.sheet img.share-prev')
            await img.wait_for(timeout=15000)
            src = await img.get_attribute('src')
            b64 = await page.evaluate("""async (u) => { const b = await (await fetch(u)).blob(); return await new Promise((r) => { const f = new FileReader(); f.onload = () => r(f.result.split(',')[1]); f.readAsDataURL(b); }); }""", src)
            f = out(f'locandina-{k:02d}.png')
            open(f, 'wb').write(base64.b64decode(b64))
            im = Image.open(f).convert('RGB')
            # un punto del prato vicino a un angolo del campo: il colore deve cambiare con lo stile
            px = im.getpixel((220, 640))
            print(f'  {name}: {im.size}, colore del campo vicino all\'angolo {px}')
            files.append((name, f, px))
            await page.keyboard.press('Escape')
            await page.wait_for_timeout(300)
        cols = {n: px for n, _, px in files}
        check(len(set(cols.values())) == len(cols), 'ogni stile dà un campo di colore diverso sulla locandina')
        check(min(cols['Neve']) > 175, 'neve: campo chiaro ' + str(cols['Neve']))
        check(cols['Marte'][0] > cols['Marte'][1] + 40, 'Marte: campo rosso')
        check(cols["Sull'acqua"][2] > cols["Sull'acqua"][0] + 60, "sull'acqua: campo blu")
        check(not console_errors(errors), 'nessun errore in console' + ''.join('\n     ' + e for e in console_errors(errors)[:5]))
        await browser.close()
    ims = [Image.open(f).convert('RGB') for _, f, _ in files]
    w, h = ims[0].size
    gap = 30
    img = Image.new('RGB', (4 * w + 3 * gap, 2 * h + gap), (236, 240, 236))
    for k, im in enumerate(ims):
        img.paste(im, ((k % 4) * (w + gap), (k // 4) * (h + gap)))
    img = img.resize((img.width * 16 // 100, img.height * 16 // 100), Image.LANCZOS)
    img.save(out('locandine.png'), optimize=True)
    print('griglia', img.size)


if __name__ == '__main__':
    run(main)
