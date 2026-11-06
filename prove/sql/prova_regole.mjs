// Prove delle regole delle partite (supabase/aggiornamento-regole.sql) su un Postgres in memoria (PGlite).
// Le funzioni di base sono copiate da quelle in produzione (schema.sql, aggiornamento-gruppi.sql, aggiornamento-chat.sql);
// lo script delle regole è quello vero. Le scritture passano da update_doc come fa l'app, con il ruolo "authenticated".
import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';

const db = new PGlite();
const FAIL = [];
const check = (cond, msg) => { console.log((cond ? 'OK   ' : 'FAIL ') + msg); if (!cond) FAIL.push(msg); };

await db.exec(`
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('email', coalesce(current_setting('test.email', true), '')) $$;
grant usage on schema auth to authenticated;

create table public.docs (path text primary key, col text not null, id text not null, data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(), cpath text, gid text);
grant select, insert, update, delete on public.docs to authenticated;
create table public.app_admins (email text primary key);
grant select on public.app_admins to authenticated;
insert into public.app_admins values ('admin@app.it');

create or replace function public.now_ms() returns bigint
language sql stable as $$ select (extract(epoch from clock_timestamp()) * 1000)::bigint $$;
create or replace function public.ms_of(v jsonb) returns bigint
language sql immutable as $$
  select case
    when jsonb_typeof(v) = 'number' then floor((v #>> '{}')::numeric)::bigint
    when jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^\\d{1,15}$' then (v #>> '{}')::bigint
    else 0
  end;
$$;
create or replace function public.docs_fill_paths() returns trigger
language plpgsql as $$
begin
  new.cpath := left(new.path, length(new.path) - length(new.id) - 1);
  new.gid := case when new.path like 'g/%' then split_part(new.path, '/', 2) end;
  return new;
end $$;
create trigger docs_fill_paths before insert or update on public.docs for each row execute function public.docs_fill_paths();
create or replace function public.is_app_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_admins where email = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
create or replace function public.is_member(p_gid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.docs
    where path = 'members/' || p_gid || '~' || auth.uid()::text and data ->> 'status' = 'active');
$$;
create or replace function public.is_group_admin(p_gid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.docs
    where path = 'members/' || p_gid || '~' || auth.uid()::text
      and data ->> 'status' = 'active' and data ->> 'role' = 'admin');
$$;
create or replace function public.jsonb_deep_merge(a jsonb, b jsonb) returns jsonb
language plpgsql immutable as $$
declare k text; r jsonb;
begin
  if jsonb_typeof(a) = 'object' and jsonb_typeof(b) = 'object' then
    r := a;
    for k in select jsonb_object_keys(b) loop
      r := jsonb_set(r, array[k], case when a ? k then public.jsonb_deep_merge(a -> k, b -> k) else b -> k end, true);
    end loop;
    return r;
  end if;
  return b;
end $$;
create or replace function public.update_doc(p_path text, p_patch jsonb) returns void
language plpgsql security invoker as $$
begin
  update public.docs set data = public.jsonb_deep_merge(data, p_patch), updated_at = now() where path = p_path;
  if not found then raise exception 'documento non trovato' using errcode = 'P0002'; end if;
end $$;
-- come poll_vote: una funzione del database (security definer) che scrive per conto di chi la chiama
create or replace function public.fn_write(p_path text, p_patch jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.docs set data = public.jsonb_deep_merge(data, p_patch) where path = p_path;
end $$;
`);

// lo script vero (due volte: si può rieseguire)
const script = fs.readFileSync(new URL('../../supabase/aggiornamento-regole.sql', import.meta.url), 'utf8');
await db.exec(script);
await db.exec(script);
const res = await db.query(script.slice(script.indexOf("select 'Aggiornamento regole completato'")));
check(res.rows[0] && res.rows[0].regole_attive === 1, 'lo script si esegue (anche due volte) e accende la regola');

// persone e gruppi
const U = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const ORG = U(1), MEM = U(2), MEM2 = U(3), GADM = U(4), AADM = U(5), OUT = U(6), BOOK = U(7);
const now = Date.now();
const DAY = 86400000;
const ymd = (t) => new Date(t).toISOString().slice(0, 10);
const put = (path, data) => db.query('insert into docs (path, col, id, data) values ($1, $2, $3, $4)',
  [path, path.split('/').slice(-2)[0], path.split('/').pop(), JSON.stringify(data)]);
for (const [u, role] of [[ORG, 'member'], [MEM, 'member'], [MEM2, 'member'], [GADM, 'admin'], [AADM, 'member'], [BOOK, 'member']]) {
  await put('members/G1~' + u, { status: 'active', role });
  await put('members/G2~' + u, { status: 'active', role });
}
const base = () => ({
  date: ymd(now + 2 * DAY), time: '21:00', field: 'Campo', format: 7, status: 'open', by: ORG, created: now - DAY,
  teamMode: 'pick', colors: { a: 'bianco', b: 'nero' },
  rsvp: { [ORG]: { s: 'in', t: now - 5000, side: 'a' }, [MEM]: { s: 'in', t: now - 4000, side: 'a' }, [MEM2]: { s: 'in', t: now - 3000, side: 'b' } },
  guests: { g_1: { name: 'Cugino', role: 'CEN', t: now - 2000, by: MEM, side: 'b' } },
  teams: { a: [], b: [], roles: {} },
});
await put('g/G1/matches/M1', base());
// G1: una partita giocata tre giorni fa, e la successiva è già iniziata ieri → risultato bloccato
await put('g/G1/matches/OLD', Object.assign(base(), { date: ymd(now - 3 * DAY), status: 'played', playedAt: now - 3 * DAY, result: { a: 3, b: 2 }, final: { ids: [ORG, MEM] } }));
await put('g/G1/matches/NEXT', Object.assign(base(), { date: ymd(now - DAY) }));
// G2: giocata ieri, la successiva è dopodomani → si può ancora correggere
await put('g/G2/matches/PL', Object.assign(base(), { date: ymd(now - DAY), status: 'played', playedAt: now - DAY, result: { a: 1, b: 1 }, final: { ids: [ORG] } }));
await put('g/G2/matches/FUT', Object.assign(base(), { date: ymd(now + 2 * DAY) }));
await put('g/G1/matches/P1', { status: 'poll', by: ORG, created: now, format: 7, poll: { days: [ymd(now + 3 * DAY)], need: 14, votes: {} }, rsvp: {}, guests: {} });
await put('g/G1/matches/NOCOL', Object.assign(base(), { colors: null }));

// scrive come una persona, passando da update_doc come l'app (o da un insert, come "Nuova partita")
async function as(uid, email, sql, params) {
  await db.exec(`select set_config('test.uid', '${uid || ''}', false), set_config('test.email', '${email || ''}', false); set role authenticated;`);
  try { await db.query(sql, params); return { ok: true }; }
  catch (e) { return { ok: false, msg: e.message, code: e.code }; }
  finally { await db.exec('reset role;'); }
}
const upd = (uid, path, patch, email) => as(uid, email, 'select update_doc($1, $2::jsonb)', [path, JSON.stringify(patch)]);
const ins = (uid, path, data) => as(uid, '', 'insert into docs (path, col, id, data) values ($1, $2, $3, $4::jsonb)', [path, 'matches', path.split('/').pop(), JSON.stringify(data)]);
const get = async (path) => (await db.query('select data from docs where path = $1', [path])).rows[0].data;
const ok = (r, msg) => check(r.ok, msg + (r.ok ? '' : ' — ' + r.msg));
const no = (r, msg, txt) => check(!r.ok && r.code === '42501' && (!txt || r.msg.includes(txt)), msg + (r.ok ? ' — passata!' : ' («' + r.msg + '»)'));
const M1 = 'g/G1/matches/M1';

// --- iscritti
ok(await upd(MEM, M1, { rsvp: { [MEM]: { s: 'out', t: Date.now() } } }), 'ognuno cambia la sua presenza');
let d = await get(M1);
const before = d.rsvp[MEM].t;
ok(await upd(MEM, M1, { rsvp: { [MEM]: { s: 'in', t: 1000 } } }), 'iscriversi con un orario finto si può, ma…');
d = await get(M1);
check(d.rsvp[MEM].t >= before && Math.abs(d.rsvp[MEM].t - Date.now()) < 5000, '…l\'orario diventa quello di adesso (niente sorpassi in lista)');
ok(await upd(MEM, M1, { rsvp: { [MEM2]: { s: 'maybe', t: Date.now() } } }), 'come nell\'app, chiunque nel gruppo segna la presenza di un altro');
ok(await upd(MEM, M1, { rsvp: { [OUT]: { s: 'in', t: Date.now() } } }), 'e aggiunge chi ha confermato a voce');
no(await upd(MEM, M1, { rsvp: { [MEM2]: { side: 'a' } } }), 'spostare un altro di squadra no', 'chi organizza');
ok(await upd(MEM, M1, { rsvp: { [MEM]: { side: 'b' } } }), 'la propria squadra sì');
ok(await upd(MEM, M1, { rsvp: { [MEM]: { side: 'b' }, [MEM2]: { side: 'b' } } }), 'riscrivere la squadra uguale degli altri (il Campo lo fa) va bene');
d = await get(M1);
const tA = d.rsvp[ORG].t, tB = d.rsvp[OUT].t;
ok(await upd(ORG, M1, { rsvp: { [ORG]: { t: tB }, [OUT]: { t: tA, side: 'a' } } }), 'chi organizza fa entrare dalla panchina (scambio di orari e squadra)');
d = await get(M1);
check(d.rsvp[ORG].t === tB && d.rsvp[OUT].t === tA, 'e gli orari scambiati restano quelli');
ok(await upd(GADM, M1, { rsvp: { [MEM2]: { side: 'a' } } }), 'un amministratore del gruppo sposta gli altri di squadra');

// --- ospiti
ok(await upd(MEM2, M1, { guests: { g_2: { name: 'Amico', role: 'ATT', t: 5, by: MEM2, side: 'a' } } }), 'un ospite si aggiunge a nome proprio');
d = await get(M1);
check(Math.abs(d.guests.g_2.t - Date.now()) < 5000, 'con l\'orario di adesso');
no(await upd(MEM2, M1, { guests: { g_3: { name: 'Finto', t: Date.now(), by: MEM } } }), 'a nome di un altro no', 'a nome tuo');
ok(await upd(MEM2, M1, { guests: { g_1: { gone: true } } }), 'come nell\'app, chiunque toglie un ospite');
no(await upd(MEM2, M1, { guests: { g_2: { side: 'b' } } }), 'la squadra di un ospite la cambia chi organizza', 'chi organizza');
no(await upd(MEM, M1, { guests: { g_2: { by: MEM } } }), 'un ospite resta di chi l\'ha portato');
ok(await upd(ORG, M1, { guests: { g_2: { side: 'b' } } }), 'chi organizza cambia la squadra di un ospite');

// --- colori, creatore, sondaggio
no(await upd(MEM, M1, { colors: { a: 'rosso', b: 'blu' } }), 'i colori li cambia chi organizza', 'colori');
ok(await upd(ORG, M1, { colors: { a: 'rosso', b: 'blu' } }), 'chi ha creato la partita cambia i colori');
ok(await upd(GADM, M1, { colors: { a: 'verde', b: 'nero' } }), 'anche un amministratore del gruppo');
ok(await upd(MEM, 'g/G1/matches/NOCOL', { date: ymd(now + 4 * DAY), colors: { a: 'bianco', b: 'nero' } }), 'modificando una partita senza colori si mettono quelli di partenza (come fa l\'app)');
no(await upd(MEM, M1, { by: MEM }), 'nessuno si fa creatore di una partita', 'creato');
no(await upd(ORG, M1, { by: MEM }), 'nemmeno chi l\'ha creata la passa a un altro');
ok(await upd(AADM, M1, { by: MEM }, 'admin@app.it'), 'un amministratore dell\'app sì');
await upd(AADM, M1, { by: ORG }, 'admin@app.it');
ok(await upd(MEM, M1, { date: ymd(now + 3 * DAY), time: '20:30', field: 'Altro campo', note: 'ciao' }), 'come nell\'app, chiunque cambia giorno, ora e campo');
ok(await upd(MEM, M1, { teams: { a: [ORG], b: [MEM2], roles: {}, t: Date.now(), by: MEM } }), 'e sistema le squadre nel Campo');
no(await upd(MEM, 'g/G1/matches/P1', { poll: { votes: { [MEM]: { x: 1 } } } }), 'i voti del sondaggio non si scrivono a mano', 'sondaggio');
no(await upd(MEM, 'g/G1/matches/P1', { status: 'cancelled' }), 'il sondaggio lo annulla chi l\'ha creato');
ok(await as(MEM, '', 'select fn_write($1, $2::jsonb)', ['g/G1/matches/P1', JSON.stringify({ poll: { votes: { [MEM]: { d: 1 } } } })]), 'le funzioni del database (come poll_vote) non sono toccate');
ok(await upd(ORG, 'g/G1/matches/P1', { status: 'cancelled' }), 'chi l\'ha creato annulla il sondaggio');
ok(await upd(MEM, M1, { status: 'cancelled' }), 'come nell\'app, chiunque annulla una partita');
ok(await upd(MEM, M1, { status: 'open' }), 'e la riapre');

// --- campo prenotato e cassa
ok(await upd(BOOK, M1, { booked: { by: BOOK, t: Date.now() } }), 'il campo prenotato lo segni a nome tuo');
no(await upd(MEM, M1, { booked: null }), 'toglierlo lo fa chi l\'ha segnato', 'prenotato');
no(await upd(MEM, M1, { booked: { by: MEM2, t: 1 } }), 'né lo passa a un altro');
no(await upd(MEM, M1, { cassa: { price: 70, quota: null, by: MEM, t: Date.now() } }), 'prezzo e quota non li scrive chiunque', 'Prezzo');
ok(await upd(BOOK, M1, { cassa: { price: 70, quota: null, by: BOOK, t: Date.now() } }), 'chi ha prenotato scrive il prezzo');
ok(await upd(ORG, M1, { cassa: { price: 72, t: Date.now() } }), 'anche chi ha creato la partita');
no(await upd(MEM, M1, { cassa: { paid: { [MEM]: { t: Date.now(), by: MEM } } } }), 'nessuno si segna «pagato» da solo', 'raccoglie');
no(await upd(ORG, M1, { cassa: { paid: { [MEM]: { t: Date.now(), by: ORG } } } }), 'come nell\'app, se raccoglie un altro il creatore non segna i pagamenti');
ok(await upd(BOOK, M1, { cassa: { paid: { [MEM]: { t: Date.now(), by: BOOK } } } }), 'chi raccoglie segna chi ha pagato');
ok(await upd(GADM, M1, { cassa: { paid: { [MEM2]: { t: Date.now(), by: GADM } } } }), 'anche un amministratore del gruppo');
ok(await upd(BOOK, M1, { booked: null }), 'chi l\'ha segnato toglie il campo prenotato');
ok(await upd(MEM, M1, { booked: { by: MEM, t: Date.now() } }), 'e un altro lo segna a nome suo');
ok(await upd(ORG, M1, { booked: null }), 'chi organizza lo toglie');
no(await upd(MEM, M1, { booked: { by: MEM2, t: Date.now() } }), 'e nessuno lo segna a nome di un altro', 'a nome tuo');

// --- inviti
ok(await upd(MEM, M1, { invites: { [OUT]: { by: MEM, t: Date.now() } } }), 'un invito si manda a nome proprio');
no(await upd(MEM, M1, { invites: { [MEM2]: { by: ORG, t: Date.now() } } }), 'a nome di un altro no', 'invito');

// --- risultato dopo l'inizio della partita successiva
no(await upd(MEM, 'g/G1/matches/OLD', { result: { a: 9, b: 0 } }), 'iniziata la partita dopo, il risultato non lo cambia chiunque', 'amministratori');
no(await upd(ORG, 'g/G1/matches/OLD', { final: { ids: [ORG] } }), 'neanche chi l\'ha creata (come nell\'app)');
no(await upd(MEM, 'g/G1/matches/OLD', { status: 'open' }), 'e non si riapre');
ok(await upd(GADM, 'g/G1/matches/OLD', { result: { a: 3, b: 3 } }), 'lo corregge un amministratore del gruppo');
ok(await upd(AADM, 'g/G1/matches/OLD', { status: 'open' }, 'admin@app.it'), 'o dell\'app');
await upd(AADM, 'g/G1/matches/OLD', { status: 'played' }, 'admin@app.it');
ok(await upd(BOOK, 'g/G1/matches/OLD', { booked: { by: BOOK, t: Date.now() } }), 'dopo restano possibili le cose della cassa');
ok(await upd(BOOK, 'g/G1/matches/OLD', { cassa: { paid: { [MEM]: { t: Date.now(), by: BOOK } } } }), 'come segnare i pagamenti');
ok(await upd(MEM, 'g/G2/matches/PL', { result: { a: 2, b: 1 }, final: { ids: [ORG, MEM] } }), 'prima della partita dopo, chiunque corregge il risultato');
ok(await upd(MEM, 'g/G2/matches/PL', { status: 'open' }), 'e la riapre');
ok(await upd(MEM, 'g/G2/matches/PL', { status: 'played', playedAt: Date.now(), final: { ids: [MEM] } }), 'e la chiude di nuovo');

// --- partite nuove
const fresh = (by, extra) => Object.assign({ date: ymd(now + 5 * DAY), time: '21:00', field: 'X', format: 5, status: 'open', by, created: Date.now(),
  teamMode: 'auto', colors: { a: 'bianco', b: 'nero' }, rsvp: { [by]: { s: 'in', t: 7 } }, guests: {}, teams: { a: [], b: [], roles: {} } }, extra || {});
ok(await ins(MEM, 'g/G1/matches/N1', fresh(MEM)), 'chiunque nel gruppo crea una partita, a nome suo');
d = await get('g/G1/matches/N1');
check(Math.abs(d.rsvp[MEM].t - Date.now()) < 5000, 'con l\'orario d\'iscrizione di adesso');
no(await ins(MEM, 'g/G1/matches/N2', fresh(MEM2)), 'a nome di un altro no', 'a nome tuo');
no(await ins(MEM, 'g/G1/matches/N3', fresh(MEM, { rsvp: { [MEM]: { s: 'in', t: Date.now() }, [MEM2]: { s: 'in', t: 1 } } })), 'con dentro altri no');
no(await ins(MEM, 'g/G1/matches/N4', fresh(MEM, { status: 'played', result: { a: 10, b: 0 } })), 'già giocata con il risultato no');
no(await ins(MEM, 'g/G1/matches/N5', fresh(MEM, { status: 'poll', poll: { days: [ymd(now + 6 * DAY)], need: 10, votes: { [MEM2]: { x: 1 } } } })), 'un sondaggio con voti già dentro no');
ok(await ins(MEM, 'g/G1/matches/N6', fresh(MEM, { status: 'poll', rsvp: {}, poll: { days: [ymd(now + 6 * DAY)], need: 10, votes: {} } })), 'un sondaggio nuovo sì');

// --- dati strani e chi non è toccato
ok(await upd(MEM, M1, { rsvp: { [MEM]: 'strano' } }), 'dati strani non rompono le regole');
no(await upd(MEM, M1, { rsvp: 'niente' }), 'cancellare tutti gli iscritti con le loro squadre: un rifiuto pulito, non un errore');
ok(await upd(ORG, M1, { rsvp: 'niente', guests: 42 }), 'chi organizza può anche questo (come prima), senza errori');
await db.exec("update docs set data = jsonb_set(data, '{rsvp}', '{}'::jsonb) where path = 'g/G1/matches/M1'");
ok(await as(null, '', "update docs set data = jsonb_set(data, '{by}', '\"x\"') where path = 'g/G1/matches/NEXT'"), 'senza accesso (servizio, funzioni pianificate) le regole non valgono');
const chatIns = await as(MEM, '', "insert into docs (path, col, id, data) values ('g/G1/chat/x', 'chat', 'x', '{\"by\": \"qualcuno\"}')");
ok(chatIns, 'gli altri documenti (per esempio la chat) non passano da queste regole');

console.log('\nFALLITE:', FAIL.length);
FAIL.forEach((f) => console.log(' -', f));
process.exit(FAIL.length ? 1 : 0);
