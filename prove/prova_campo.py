"""Prove del Campo sul telefono simulato: pressione lunga e trascinamento con il dito (eventi touch veri via CDP)."""
from playwright.async_api import async_playwright
from comune import open_demo, check, run, out, console_errors, touch, long_drag, center, pd, label, open_match


async def main():
    async with async_playwright() as p:
        browser, page, errors = await open_demo(p)
        cdp = await page.context.new_cdp_session(page)
        await open_match(page, 2)
        tabs = await page.locator('.seg.mtabs button').all_inner_texts()
        check(tabs == ['Dettagli', 'Campo', 'Squadre'], 'ordine delle schede: ' + ', '.join(tabs))

        # --- 1. scambio nella stessa squadra, tenendo premuto e trascinando
        names = [await g.get_attribute('aria-label') for g in await page.locator('svg.pitch g.pd').all()]
        print('in campo:', names)
        await pd(page, 'Stef').scroll_into_view_if_needed()
        await page.evaluate('window.scrollBy(0, 120)')
        await page.wait_for_timeout(200)
        before_stef, before_dave = await label(page, 'Stef'), await label(page, 'Dave')
        y0 = await page.evaluate('window.scrollY')
        await long_drag(page, cdp, await center(pd(page, 'Stef')), await center(pd(page, 'Dave')))
        y1 = await page.evaluate('window.scrollY')
        after_stef, after_dave = await label(page, 'Stef'), await label(page, 'Dave')
        print('  Stef:', before_stef, '->', after_stef, '| Dave:', before_dave, '->', after_dave)
        check(after_stef.split(', ')[1] == before_dave.split(', ')[1] and after_dave.split(', ')[1] == before_stef.split(', ')[1], 'Stef e Dave si scambiano il ruolo')
        check(abs(y1 - y0) < 2, f'la pagina non scorre mentre si trascina ({y0} -> {y1})')
        bar = page.locator('.pitch-bar')
        check(await bar.count() == 1 and 'Scambiati Stef e Dave' in await bar.inner_text(), 'compare "Scambiati Stef e Dave · Annulla"')
        await page.wait_for_timeout(400)
        man = page.locator('.note', has_text='Squadre cambiate a mano')
        check(await man.count() == 1, 'le squadre automatiche diventano fatte a mano')

        # --- 2. Annulla
        await bar.get_by_role('button', name='Annulla').click()
        await page.wait_for_timeout(700)
        check(await label(page, 'Stef') == before_stef and await label(page, 'Dave') == before_dave, 'Annulla rimette Stef e Dave al loro posto')
        check(await page.locator('.note', has_text='Squadre cambiate a mano').count() == 0, "dopo Annulla le squadre tornano automatiche")

        # --- 3. scambio tra le due squadre
        b_fede, b_dave = await label(page, 'Fede'), await label(page, 'Dave')
        await long_drag(page, cdp, await center(pd(page, 'Fede')), await center(pd(page, 'Dave')))
        a_fede, a_dave = await label(page, 'Fede'), await label(page, 'Dave')
        print('  Fede:', b_fede, '->', a_fede, '| Dave:', b_dave, '->', a_dave)
        team = lambda l: l.rsplit(' ', 1)[-1]
        check(team(b_fede) != team(b_dave) and team(a_fede) == team(b_dave) and team(a_dave) == team(b_fede),
              f'Fede passa ai {team(b_dave)} e Dave ai {team(b_fede)}')

        # --- 4. tocco veloce: apre la scheda del giocatore
        await page.wait_for_timeout(300)
        await pd(page, 'Simo').tap()
        await page.wait_for_timeout(600)
        h1 = await page.locator('h1').first.inner_text()
        check('Simo' in h1 or await page.locator('text=Simo').count() > 0 and await page.locator('svg.pitch').count() == 0, 'un tocco su Simo apre la sua scheda (' + h1.replace('\n', ' ') + ')')
        await page.get_by_role('button', name='Indietro').first.click()
        await page.wait_for_timeout(600)
        if await page.locator('svg.pitch').count() == 0:
            await page.locator('.seg.mtabs button', has_text='Campo').click()
            await page.wait_for_timeout(500)

        # --- 5. pressione lunga senza muoversi: selezione, poi tocco su un altro
        b_matte, b_simo = await label(page, 'Matte'), await label(page, 'Simo')
        a = await center(pd(page, 'Andre'))
        await touch(cdp, 'touchStart', *a)
        await page.wait_for_timeout(520)
        await touch(cdp, 'touchEnd')
        await page.wait_for_timeout(500)
        check('sel' in (await pd(page, 'Andre').get_attribute('class')), 'pressione lunga: Andre resta selezionato')
        check('Tocca dove mettere Andre' in await page.locator('.pitch-bar').inner_text(), 'compare "Tocca dove mettere Andre"')
        b_andre, b_tommy = await label(page, 'Andre'), await label(page, 'Tommy')
        await pd(page, 'Tommy').tap()
        await page.wait_for_timeout(500)
        check(await label(page, 'Andre') != b_andre and await label(page, 'Tommy') != b_tommy, 'poi un tocco su Tommy li scambia')

        # --- 6. formazioni
        await page.locator('.pitch-h .fm-chip').first.click()
        await page.wait_for_timeout(400)
        opts = await page.locator('.sheet .fm-opt b').all_inner_texts()
        print('  moduli a 7:', opts)
        check(opts == ['1-2-3-1', '1-3-1-2', '1-3-2-1'], 'a 7 i moduli sono 1-2-3-1, 1-3-1-2, 1-3-2-1')
        await page.locator('.sheet .fm-opt', has_text='1-3-1-2').click()
        await page.wait_for_timeout(600)
        chip = await page.locator('.pitch-h .fm-chip').first.inner_text()
        check(chip.strip() == '1-3-1-2' and await page.locator('.sheet').count() == 0, 'la squadra in alto passa a 1-3-1-2 e il foglio si chiude (' + chip.strip() + ')')
        roles = [await g.get_attribute('aria-label') for g in await page.locator('svg.pitch g.pd').all()]
        neri = [r for r in roles if 'Neri' in r]
        cnt = {k: sum(1 for r in neri if k in r) for k in ['portiere', 'difensore', 'centrocampista', 'attaccante']}
        print('  Neri:', cnt)
        check(cnt == {'portiere': 1, 'difensore': 3, 'centrocampista': 1, 'attaccante': 2}, 'i Neri sono schierati 1-3-1-2')

        # --- 7. panchina: dalla lista d'attesa al campo
        await page.locator('.bench-tab').click()
        await page.wait_for_timeout(400)
        check('open' in await page.locator('.bench-panel').get_attribute('class'), 'la linguetta apre la panchina')
        item = page.locator('.bn-item[data-kind="w"]').first
        wname = (await item.locator('.bn-n').inner_text()).strip()
        print('  in lista d\'attesa:', wname)
        target = 'Marchino'
        await long_drag(page, cdp, await center(item), await center(pd(page, target)))
        await page.wait_for_timeout(300)
        sheet = page.locator('.sheet')
        txt = await sheet.inner_text() if await sheet.count() else ''
        print('  foglio:', txt.replace('\n', ' | '))
        check(f'Entra {wname}, esce {target}' in txt, 'chiede conferma: "Entra ' + wname + ', esce ' + target + '"')
        await sheet.get_by_role('button', name='Fai entrare ' + wname).click()
        await page.wait_for_timeout(800)
        check(await pd(page, wname).count() == 1 and await pd(page, target).count() == 0, wname + ' è in campo e ' + target + ' no')
        await page.locator('.bench-tab').click()
        await page.wait_for_timeout(400)
        bench = await page.locator('.bn-item[data-kind="w"] .bn-n').all_inner_texts()
        check(bench == [target], target + ' è in panchina, n° 1 (' + ', '.join(bench) + ')')
        await page.locator('.bp-x').click()
        await page.wait_for_timeout(300)
        # nei Dettagli la lista d'attesa è cambiata davvero
        await page.locator('.seg.mtabs button', has_text='Dettagli').click()
        await page.wait_for_timeout(500)
        wl = page.locator('section.sec .stack-8', has_text="Lista d'attesa")
        wtxt = await wl.inner_text() if await wl.count() else ''
        check(target in wtxt and wname not in wtxt, "nei Dettagli: " + target + " in lista d'attesa al posto di " + wname)
        await page.locator('.seg.mtabs button', has_text='Campo').click()
        await page.wait_for_timeout(400)

        check(not console_errors(errors), 'nessun errore in console' + ''.join('\n     ' + e for e in console_errors(errors)[:5]))
        await page.screenshot(path=out('campo-dopo.png'), full_page=True)
        await browser.close()


if __name__ == '__main__':
    run(main)
