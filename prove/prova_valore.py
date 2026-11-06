"""Prove del valore in campo pesato per reparto: conti del motore, squadre automatiche, Confronto e Campo."""
import json
from playwright.async_api import async_playwright
from comune import open_demo, check, run, out, console_errors, long_drag, center, pd, label, open_match

ENGINE_JS = r"""
() => {
  const E = Engine;
  const out = {};
  const near = (a, b) => Math.abs(a - b) < 1e-9;
  const mk = (id, a, pref, sec, inj) => E.partOf(id, { att: a[0], cen: a[1], dif: a[2], gen: a[3], por: a[4] }, pref, sec || '', inj ? { level: inj } : null);
  // giocatori della demo
  const fede = mk('fede', [86, 66, 40, 76, 33], 'ATT');
  const andre = mk('andre', [50, 60, 78, 68, 45], 'DIF');
  const stef = mk('stef', [48, 62, 74, 66, 50], 'DIF', 'CEN');
  const ale = mk('ale', [66, 74, 56, 68, 40], 'CEN');
  const matte = mk('matte', [40, 48, 55, 58, 77], 'POR');
  out.base = {
    att: E.roleBase(fede, 'ATT'), cen: E.roleBase(fede, 'CEN'), dif: E.roleBase(fede, 'DIF'),
    ok: near(E.roleBase(fede, 'ATT'), (2 * 86 + 66 + 40 + 76) / 5) && near(E.roleBase(fede, 'DIF'), (86 + 66 + 2 * 40 + 76) / 5) && near(E.roleBase(fede, 'CEN'), (86 + 2 * 66 + 40 + 76) / 5),
  };
  out.valore = {
    attInAtt: E.valueIn(fede, 'ATT'), attInDif: E.valueIn(fede, 'DIF'), attInPor: E.valueIn(fede, 'POR'),
    ok: near(E.valueIn(fede, 'DIF'), (86 + 66 + 80 + 76) / 5 - 6) && near(E.valueIn(fede, 'POR'), 33) && near(E.natural(fede), (2 * 86 + 66 + 40 + 76) / 5),
    // secondo ruolo: nessun malus, ma conta il reparto
    stefInCen: E.valueIn(stef, 'CEN'), okSec: near(E.valueIn(stef, 'CEN'), (48 + 2 * 62 + 74 + 66) / 5),
    // infortunio
    okInj: near(E.valueIn(mk('x', [70, 70, 70, 70, 40], 'CEN', '', 'lieve'), 'CEN'), 65),
    // un giocatore tutto uguale vale uguale in ogni reparto
    okFlat: ['DIF', 'CEN', 'ATT'].every((r) => near(E.roleBase(mk('y', [64, 64, 64, 64, 40], 'CEN'), r), 64)),
  };
  // la squadra dell'esempio: Fede in attacco e Andre in difesa, poi scambiati
  const team = [matte, andre, stef, ale, fede];
  const other = [mk('o1', [40, 48, 55, 58, 70], 'POR'), mk('o2', [60, 60, 60, 60, 40], 'DIF'), mk('o3', [60, 60, 60, 60, 40], 'DIF'), mk('o4', [60, 60, 60, 60, 40], 'CEN'), mk('o5', [60, 60, 60, 60, 40], 'ATT')];
  const rolesO = { o1: 'POR', o2: 'DIF', o3: 'DIF', o4: 'CEN', o5: 'ATT' };
  const prima = Object.assign({ matte: 'POR', andre: 'DIF', stef: 'DIF', ale: 'CEN', fede: 'ATT' }, rolesO);
  const dopo = Object.assign({}, prima, { andre: 'ATT', fede: 'DIF' });
  const e1 = E.evaluate(team, other, prima, null), e2 = E.evaluate(team, other, dopo, null);
  const r1 = (x) => Math.round(x * 10) / 10;
  out.esempio = {
    prima: { media: r1(e1.a.mean), att: r1(e1.a.areas.att), cen: r1(e1.a.areas.cen), dif: r1(e1.a.areas.dif), gen: r1(e1.a.areas.gen), porta: e1.a.gkVal, eq: e1.balance },
    dopo: { media: r1(e2.a.mean), att: r1(e2.a.areas.att), cen: r1(e2.a.areas.cen), dif: r1(e2.a.areas.dif), gen: r1(e2.a.areas.gen), porta: e2.a.gkVal, eq: e2.balance },
    // l'altra squadra, tutta a 60, ha le aree a 60 qualunque siano i ruoli
    altra: e1.b.areas,
  };
  // perdita fuori ruolo: mai negativa
  const cenAtt = mk('ca', [85, 60, 60, 60, 40], 'CEN', 'ATT');
  const t1 = E.evalTeam([cenAtt], { ca: 'ATT' }, null);
  out.loss = { valAtt: E.valueIn(cenAtt, 'ATT'), valCen: E.valueIn(cenAtt, 'CEN'), loss: t1.loss };
  // squadra senza giocatori di movimento
  out.vuota = E.evalTeam([matte], { matte: 'POR' }, null).areas;
  return out;
}
"""

# ricerca completa: la divisione trovata da suggestTeams('exact') deve essere la migliore tra tutte
BRUTE_JS = r"""
({ n, format, seed, reps }) => {
  const E = Engine;
  let s = seed >>> 0;
  const rnd = () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const R = ['DIF', 'CEN', 'ATT'];
  const res = { runs: 0, hit: 0, worst: 0, ms: 0, roleCheck: true, sizes: true };
  for (let rep = 0; rep < reps; rep++) {
    const parts = [];
    const gks = 1 + Math.floor(rnd() * 3); // da 1 a 3 portieri
    for (let i = 0; i < n; i++) {
      const gk = i < gks;
      const pref = gk ? 'POR' : R[Math.floor(rnd() * 3)];
      const sec = gk || rnd() < 0.5 ? '' : R[Math.floor(rnd() * 3)];
      const lv = 50 + rnd() * 30;
      const a = [0, 1, 2, 3].map(() => Math.round(lv + (rnd() - 0.5) * 30));
      if (!gk) { const k = { DIF: 2, CEN: 1, ATT: 0 }[pref]; a[k] = Math.min(95, a[k] + 8); }
      parts.push(E.partOf('p' + i, { att: a[0], cen: a[1], dif: a[2], gen: a[3], por: gk ? Math.round(lv + 8) : Math.round(35 + rnd() * 15) }, pref, sec === pref ? '' : sec, null));
    }
    const t0 = performance.now();
    const sug = E.suggestTeams(parts, { mode: 'exact', format, rng: rnd });
    res.ms = Math.max(res.ms, performance.now() - t0);
    const byId = Object.fromEntries(parts.map((p) => [p.id, p]));
    const got = E.evaluate(sug.a.map((i) => byId[i]), sug.b.map((i) => byId[i]), sug.roles, null).cost;
    if (Math.abs(sug.a.length - sug.b.length) > 1) res.sizes = false;
    for (const side of [sug.a, sug.b]) if (side.filter((i) => sug.roles[i] === 'POR').length !== 1) res.roleCheck = false;
    // tutte le divisioni
    let best = Infinity;
    const small = Math.floor(n / 2);
    const rec = (i, pick) => {
      if (pick.length === small) {
        const set = new Set(pick);
        const A = parts.filter((_, k) => set.has(k)), B = parts.filter((_, k) => !set.has(k));
        const la = E.bestLineup(A, format), lb = E.bestLineup(B, format);
        const c = E.evaluate(A, B, Object.assign({}, la.roles, lb.roles), null).cost;
        if (c < best) best = c;
        return;
      }
      if (n - i < small - pick.length) return;
      pick.push(i); rec(i + 1, pick); pick.pop();
      if (!(n % 2 === 0 && i === 0)) rec(i + 1, pick);
    };
    rec(0, []);
    res.runs++;
    if (got <= best + 1e-6) res.hit++;
    res.worst = Math.max(res.worst, got - best);
  }
  return res;
}
"""


async def rows(page):
    """le righe del Confronto: {nome: (squadra a, squadra b)}"""
    out = {}
    for r in await page.locator('.tug-row').all():
        l = (await r.locator('.tl').inner_text()).strip().lower()
        a = float(await r.locator('.tug-v.a').inner_text())
        b = float(await r.locator('.tug-v.b').inner_text())
        out[l] = (a, b)
    return out


async def duel(page):
    v = await page.locator('.duel-v').all_inner_texts()
    return [float(x) for x in v]


async def main():
    async with async_playwright() as p:
        browser, page, errors = await open_demo(p)

        # --- 1. i conti del motore
        r = await page.evaluate(ENGINE_JS)
        print(json.dumps(r, indent=1))
        check(r['base']['ok'], 'attaccante: (2 × Attacco + Centrocampo + Difesa + Generale) / 5, e così per gli altri reparti')
        check(r['valore']['ok'], 'Fede in difesa: valore del reparto meno il malus lontano; in porta la sua Porta')
        check(r['valore']['okSec'], 'nel secondo ruolo nessun malus, ma conta il reparto')
        check(r['valore']['okInj'], 'il cerotto toglie ancora 5 punti')
        check(r['valore']['okFlat'], 'chi ha tutte le aree uguali vale uguale in ogni reparto')
        a, d = r['esempio']['prima'], r['esempio']['dopo']
        check(a['att'] == 67.2 and d['att'] == 60.0, f"riga Attacco: {a['att']} -> {d['att']} (atteso 67.2 -> 60.0)")
        check(a['dif'] == 66.7 and d['dif'] == 60.3, f"riga Difesa: {a['dif']} -> {d['dif']} (atteso 66.7 -> 60.3)")
        check(a['cen'] == d['cen'] and a['gen'] == d['gen'], 'Centrocampo e Generale non cambiano con lo scambio attacco-difesa')
        check(a['media'] == 69.4 and d['media'] == 64.0, f"valore medio: {a['media']} -> {d['media']} (atteso 69.4 -> 64.0)")
        check(a['porta'] == 77 and d['porta'] == 77, 'la riga In porta resta la Porta del portiere')
        check(d['eq'] != a['eq'], f"l'equilibrio cambia ({a['eq']}% -> {d['eq']}%)")
        check(all(abs(v - 60) < 1e-9 for v in r['esempio']['altra'].values()), 'squadra con aree tutte a 60: righe a 60')
        check(r['loss']['loss'] == 0 and r['loss']['valAtt'] > r['loss']['valCen'], f"chi rende di più nel secondo ruolo non conta come perdita (loss {r['loss']['loss']})")
        check(all(v == 0 for v in r['vuota'].values()), 'senza giocatori di movimento le righe sono a zero')

        # --- 2. squadre automatiche: la divisione scelta è la migliore tra tutte
        for n, fmt, reps in [(10, 5, 40), (14, 7, 25), (16, 8, 12), (9, 5, 20), (13, 7, 10)]:
            b = await page.evaluate(BRUTE_JS, {'n': n, 'format': fmt, 'seed': 1000 + n, 'reps': reps})
            # fino a 12 giocatori la ricerca è completa; da 13 rifà col calcolo vero le 480 divisioni più promettenti
            ok = b['hit'] == b['runs'] if n <= 12 else (b['hit'] >= 0.9 * b['runs'] and b['worst'] < 0.1)
            check(ok, f"{n} giocatori a {fmt}: migliore divisione trovata {b['hit']}/{b['runs']} (scarto max {b['worst']:.4f}, {b['ms']:.0f} ms al massimo)")
            check(b['roleCheck'] and b['sizes'], f'{n} giocatori a {fmt}: un portiere per squadra e squadre pari')

        # --- 3. Confronto e Campo nella demo: scambiare attacco e difesa cambia le righe
        await open_match(page, 2, 'Squadre')
        r0 = await rows(page)
        d0 = await duel(page)
        print('Confronto prima:', r0, d0)
        check(set(r0) == {'attacco', 'centrocampo', 'difesa', 'generale', 'in porta'}, 'il Confronto ha le 5 righe')
        await page.locator('.seg.mtabs button', has_text='Campo').click()
        await page.wait_for_timeout(600)
        cdp = await page.context.new_cdp_session(page)
        await pd(page, 'Stef').scroll_into_view_if_needed()
        await page.evaluate('window.scrollBy(0, 120)')
        await page.wait_for_timeout(200)
        ls, ld = await label(page, 'Stef'), await label(page, 'Dave')
        print('  ', ls, '|', ld)
        sum0 = await page.locator('.pitch-sum').inner_text()
        await long_drag(page, cdp, await center(pd(page, 'Stef')), await center(pd(page, 'Dave')))
        await page.wait_for_timeout(500)
        sum1 = await page.locator('.pitch-sum').inner_text()
        print('  equilibrio:', sum0.split('\n')[0], '->', sum1.split('\n')[0])
        await page.locator('.seg.mtabs button', has_text='Squadre').click()
        await page.wait_for_timeout(600)
        r1 = await rows(page)
        d1 = await duel(page)
        print('Confronto dopo:', r1, d1)
        side = 0 if r0['attacco'][0] != r1['attacco'][0] else 1
        check(r0['attacco'][side] != r1['attacco'][side] and r0['difesa'][side] != r1['difesa'][side],
              f"Stef (difensore) e Dave (attaccante) scambiati: Attacco {r0['attacco'][side]} -> {r1['attacco'][side]}, Difesa {r0['difesa'][side]} -> {r1['difesa'][side]}")
        check(r0['generale'] == r1['generale'] and r0['in porta'] == r1['in porta'] and r0['centrocampo'] == r1['centrocampo'], 'Generale, Centrocampo e In porta restano uguali')
        check(d1[side] < d0[side], f'il valore medio della squadra scende ({d0[side]} -> {d1[side]})')
        other = 1 - side
        check(r0['attacco'][other] == r1['attacco'][other] and d0[other] == d1[other], "l'altra squadra non cambia")
        # si torna come prima, rifacendo lo scambio
        await page.locator('.seg.mtabs button', has_text='Campo').click()
        await page.wait_for_timeout(600)
        await pd(page, 'Stef').scroll_into_view_if_needed()
        await page.evaluate('window.scrollBy(0, 120)')
        await page.wait_for_timeout(200)
        await long_drag(page, cdp, await center(pd(page, 'Stef')), await center(pd(page, 'Dave')))
        await page.wait_for_timeout(500)
        check(await label(page, 'Stef') == ls and await label(page, 'Dave') == ld, 'un altro scambio rimette Stef e Dave al loro posto')
        await page.locator('.seg.mtabs button', has_text='Squadre').click()
        await page.wait_for_timeout(600)
        check(await rows(page) == r0, 'e il Confronto torna come prima')

        # --- 4. Come funziona
        await page.evaluate("() => { const b = [...document.querySelectorAll('button')].find((x) => /Indietro/.test(x.getAttribute('aria-label') || x.textContent)); if (b) b.click(); }")
        await page.wait_for_timeout(500)
        nav = page.get_by_role('button', name='Profilo')
        if await nav.count():
            await nav.first.click()
            await page.wait_for_timeout(600)
        btn = page.get_by_role('button', name='Come funziona')
        if await btn.count():
            await btn.first.click()
            await page.wait_for_timeout(600)
        txt = await page.locator('.sheet').inner_text() if await page.locator('.sheet').count() else ''
        check('In campo l\'area del tuo reparto conta il doppio' in txt and '(2 × Attacco + Centrocampo + Difesa + Generale) / 5' in txt, 'Come funziona spiega il nuovo calcolo')
        check('con gli attaccanti che contano il doppio' in txt, 'Come funziona spiega le righe del Confronto')
        check('In partita il valore dipende anche dal ruolo' in txt, 'Il punteggio rimanda al ruolo')
        await page.screenshot(path=out('valore-come-funziona.png'), full_page=False)

        bad = console_errors(errors)
        check(not bad, 'nessun errore in console' + ('' if not bad else ': ' + ' | '.join(bad[:5])))
        await browser.close()


if __name__ == '__main__':
    run(main)
