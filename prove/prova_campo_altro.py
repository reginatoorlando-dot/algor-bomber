"""Altre prove del Campo: scorrimento automatico, squadre scelte, campo svuotato, mouse, tastiera, collegamenti tra le schede."""
from playwright.async_api import async_playwright
from comune import base, launch, only_local, open_demo, check, run, out, console_errors, touch, center, pd, label, open_match


async def back_to_list(page):
    while await page.locator('button.card.match').count() == 0:
        await page.get_by_role('button', name='Indietro').first.click()
        await page.wait_for_timeout(400)


async def main():
    async with async_playwright() as p:
        # --- telefono basso: da un portiere all'altro, la pagina scorre da sola
        browser, page, errors = await open_demo(p, h=640)
        cdp = await page.context.new_cdp_session(page)
        await open_match(page, 2)
        await pd(page, 'Matte').scroll_into_view_if_needed()
        await page.wait_for_timeout(200)
        b_matte, b_paolino = await label(page, 'Matte'), await label(page, 'Paolino')
        a = await center(pd(page, 'Matte'))
        await touch(cdp, 'touchStart', *a)
        await page.wait_for_timeout(520)
        y0 = await page.evaluate('window.scrollY')
        # il dito scende fino in fondo allo schermo e resta lì: la pagina scorre
        for i in range(1, 16):
            await touch(cdp, 'touchMove', a[0], a[1] + (600 - a[1]) * i / 15)
            await page.wait_for_timeout(16)
        for _ in range(60):
            await page.wait_for_timeout(50)
            bb = await pd(page, 'Paolino').bounding_box()
            if bb and bb['y'] + bb['height'] < 560:
                break
        y1 = await page.evaluate('window.scrollY')
        # il dito va su Paolino; se intanto la pagina scorre ancora, lo si rincorre finché sta ferma
        cur = (a[0], 600)
        for _ in range(8):
            tgt = await center(pd(page, 'Paolino'))
            for i in range(1, 7):
                await touch(cdp, 'touchMove', cur[0] + (tgt[0] - cur[0]) * i / 6, cur[1] + (tgt[1] - cur[1]) * i / 6)
                await page.wait_for_timeout(16)
            cur = tgt
            s0 = await page.evaluate('window.scrollY')
            await page.wait_for_timeout(250)
            if await page.evaluate('window.scrollY') == s0 and await center(pd(page, 'Paolino')) == tgt:
                break
        await touch(cdp, 'touchEnd')
        await page.wait_for_timeout(600)
        print('  scroll', y0, '->', y1)
        check(y1 > y0 + 100, 'trascinando verso il bordo la pagina scorre da sola')
        check('Bianchi' in await label(page, 'Matte') and 'Neri' in await label(page, 'Paolino'), 'Matte e Paolino si scambiano porta e squadra')
        check(not console_errors(errors), 'nessun errore in console' + ''.join('\n     ' + e for e in console_errors(errors)[:5]))
        await browser.close()

        # --- squadre scelte dai giocatori: Nico (senza squadra) in un posto libero dei Blu
        browser, page, errors = await open_demo(p)
        cdp = await page.context.new_cdp_session(page)
        await open_match(page, 1)
        check(await page.locator('.note', has_text='Devono ancora scegliere la squadra: Nico').count() == 1, 'squadre scelte: avviso per Nico senza squadra')
        await page.locator('.bench-tab').click()
        await page.wait_for_timeout(400)
        item = page.locator('.bn-item[data-kind="f"]', has_text='Nico')
        check(await item.count() == 1, 'Nico è nella panchina, tra quelli senza squadra')
        slot = page.locator('svg.pitch g.pslot[aria-label="Posto libero a centrocampo dei Blu"]').first
        a = await center(item)
        await touch(cdp, 'touchStart', *a)
        await page.wait_for_timeout(520)
        bb = await slot.bounding_box()
        tgt = (bb['x'] + bb['width'] / 2, bb['y'] + bb['height'] / 2)
        for i in range(1, 13):
            await touch(cdp, 'touchMove', a[0] + (tgt[0] - a[0]) * i / 12, a[1] + (tgt[1] - a[1]) * i / 12)
            await page.wait_for_timeout(18)
        await page.wait_for_timeout(150)
        await touch(cdp, 'touchEnd')
        await page.wait_for_timeout(700)
        check(await pd(page, 'Nico').count() == 1 and 'centrocampista dei Blu' in await label(page, 'Nico'), 'Nico va a centrocampo con i Blu (' + (await label(page, 'Nico') if await pd(page, 'Nico').count() else '-') + ')')
        check(await page.locator('.note', has_text='Devono ancora scegliere').count() == 0, "l'avviso sparisce")
        chips = await page.locator('.pitch-h .chip.warn').all_inner_texts()
        check(chips[0] == '4/5', 'i Blu sono 4 su 5 (' + ', '.join(chips) + ')')
        # nei Dettagli Nico ora ha la squadra (la scelta sta nella sua risposta)
        await page.locator('.seg.mtabs button', has_text='Dettagli').click()
        await page.wait_for_timeout(500)
        mine = page.locator('.pick-side.on')
        await page.locator('.seg.mtabs button', has_text='Squadre').click()
        await page.wait_for_timeout(500)
        vs = await page.locator('.vs-cols').inner_text()
        check('Nico' in vs, 'nella scheda Squadre Nico compare nel confronto')
        btn = page.get_by_role('button', name='Modifica nel Campo')
        check(await btn.count() == 1, 'la scheda Squadre ha "Modifica nel Campo"')
        await btn.click()
        await page.wait_for_timeout(500)
        check('on' in (await page.locator('.seg.mtabs button', has_text='Campo').get_attribute('class') or ''), '"Modifica nel Campo" porta al Campo')
        # tastiera: spazio su Ale (portiere dei Blu) e poi spazio su Fede: si scambiano
        b_ale, b_fede = await label(page, 'Ale'), await label(page, 'Fede')
        await pd(page, 'Ale').focus()
        await page.keyboard.press('Space')
        await page.wait_for_timeout(200)
        await pd(page, 'Fede').focus()
        await page.keyboard.press('Space')
        await page.wait_for_timeout(600)
        check(await label(page, 'Ale') != b_ale and await label(page, 'Fede') != b_fede, 'con la tastiera (spazio, spazio) Ale e Fede si scambiano')
        check(not console_errors(errors), 'nessun errore in console' + ''.join('\n     ' + e for e in console_errors(errors)[:5]))
        await back_to_list(page)

        # --- Dettagli: "Squadre in campo" porta al Campo; poi svuota e rifai
        await open_match(page, 2, tab=None)
        card = page.locator('button.card', has_text='Squadre in campo')
        check(await card.count() == 1, 'nei Dettagli c\'è "Squadre in campo"')
        await card.click()
        await page.wait_for_timeout(500)
        check(await page.locator('svg.pitch').count() == 1, '"Squadre in campo" apre il Campo')
        await page.get_by_role('button', name='Svuota il campo').click()
        await page.wait_for_timeout(300)
        await page.locator('.sheet').get_by_role('button', name='Svuota').click()
        await page.wait_for_timeout(700)
        check(await page.locator('svg.pitch g.pd').count() == 0 and await page.locator('svg.pitch g.pslot').count() == 14, 'campo svuotato: 14 posti liberi')
        n_free = await page.locator('.bn-item[data-kind="f"]').count()
        check(n_free == 14, f'tutti e 14 da schierare in panchina ({n_free})')
        await page.get_by_role('button', name='Crea squadre').click()
        await page.wait_for_timeout(700)
        check(await page.locator('svg.pitch g.pd').count() == 14 and await page.locator('svg.pitch g.pslot').count() == 0, '"Crea squadre" rifà le squadre')
        check(not console_errors(errors), 'nessun errore in console' + ''.join('\n     ' + e for e in console_errors(errors)[:5]))
        await browser.close()

        # --- computer: si trascina col mouse, senza pressione lunga
        browser = await launch(p)
        ctx = await browser.new_context(viewport={'width': 1280, 'height': 900}, locale='it-IT')
        page = await ctx.new_page()
        errs = []
        page.on('pageerror', lambda e: errs.append(str(e)))
        await only_local(page, base())
        await page.goto(base() + 'index.html')
        await page.wait_for_timeout(1200)
        await page.evaluate("() => { const el = document.getElementById('app'); render(null, el); render(html`<${App} />`, el); }")
        await page.wait_for_timeout(500)
        await page.get_by_role('button', name='Prova con dati di esempio').click()
        await page.wait_for_timeout(1500)
        await back_to_list(page)
        await open_match(page, 2)
        # Stef a metà schermo: vicino al bordo il campo scorrerebbe da solo durante il trascinamento
        await page.evaluate("() => document.querySelector('svg.pitch g.pd[aria-label^=\"Stef,\"]').scrollIntoView({ block: 'center' })")
        await page.wait_for_timeout(300)
        b_stef, b_marc = await label(page, 'Stef'), await label(page, 'Marchino')
        a, b = await center(pd(page, 'Stef')), await center(pd(page, 'Marchino'))
        await page.mouse.move(*a)
        await page.mouse.down()
        for i in range(1, 16):
            await page.mouse.move(a[0] + (b[0] - a[0]) * i / 15, a[1] + (b[1] - a[1]) * i / 15)
            await page.wait_for_timeout(16)
        await page.mouse.up()
        await page.wait_for_timeout(600)
        a_stef, a_marc = await label(page, 'Stef'), await label(page, 'Marchino')
        print('  mouse:', b_stef, '|', b_marc, '->', a_stef, '|', a_marc)
        # i due si scambiano posto: Stef prende ruolo e squadra di Marchino e viceversa (qualunque sia la squadra di partenza)
        check(a_stef.split(', ', 1)[1] == b_marc.split(', ', 1)[1] and a_marc.split(', ', 1)[1] == b_stef.split(', ', 1)[1],
              'col mouse si trascina Stef su Marchino (' + b_stef + ' -> ' + a_stef + ')')
        await page.screenshot(path=out('campo-desktop.png'), full_page=True)
        print('\n'.join(errs) or 'nessun errore in console')
        await browser.close()


if __name__ == '__main__':
    run(main)
