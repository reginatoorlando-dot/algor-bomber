// Prove di match_push (aggiornamento-panchina.sql) su un Postgres in memoria (PGlite).
// Le funzioni di supporto sono copiate da quelle in produzione; push_enqueue scrive in push_queue come quella vera.
import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';

const db = new PGlite();
const FAIL = [];
const check = (cond, msg) => { console.log((cond ? 'OK   ' : 'FAIL ') + msg); if (!cond) FAIL.push(msg); };

await db.exec(`
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
create schema net;
create table net_log (id serial, body jsonb);
create function net.http_post(url text, body jsonb, headers jsonb, timeout_milliseconds int) returns bigint language plpgsql as $$ begin insert into net_log(body) values (body); return 1; end $$;
create table docs (path text primary key, col text, id text, data jsonb, updated_at timestamptz, cpath text, gid text);
create table push_subs (endpoint text, uid uuid, p256dh text, auth text, ua text, created_at timestamptz default now(), last_ok timestamptz);
create table push_prefs (uid uuid, matches boolean default true, updated_at timestamptz default now());
create table push_queue (id bigserial, targets text[], title text, body text, tag text, url text, created_at timestamptz default now(), sent_at timestamptz);

create function public.docs_fill_paths() returns trigger language plpgsql as $f$
begin
  new.cpath := left(new.path, length(new.path) - length(new.id) - 1);
  new.gid := case when new.path like 'g/%' then split_part(new.path, '/', 2) end;
  return new;
end $f$;
create function public.ms_of(v jsonb) returns bigint language sql immutable as $f$
  select case
    when jsonb_typeof(v) = 'number' then floor((v #>> '{}')::numeric)::bigint
    when jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^\\d{1,15}$' then (v #>> '{}')::bigint
    else 0
  end;
$f$;
create function public.match_order(d jsonb) returns text[] language sql immutable as $f$
  select coalesce(array_agg(x.id order by x.t, x.id), '{}') from (
    select e.key as id, coalesce(public.ms_of(e.value -> 't'), 0) as t
      from jsonb_each(case when jsonb_typeof(d -> 'rsvp') = 'object' then d -> 'rsvp' else '{}'::jsonb end) e
     where jsonb_typeof(e.value) = 'object' and e.value ->> 's' = 'in'
    union all
    select g.key, coalesce(public.ms_of(g.value -> 't'), 0)
      from jsonb_each(case when jsonb_typeof(d -> 'guests') = 'object' then d -> 'guests' else '{}'::jsonb end) g
     where jsonb_typeof(g.value) = 'object' and coalesce(g.value ->> 'gone', 'false') <> 'true'
  ) x;
$f$;
create function public.match_cap(d jsonb) returns integer language sql immutable as $f$
  select case coalesce(d ->> 'format', '5') when '7' then 14 when '8' then 16 else 10 end;
$f$;
create function public.match_confirmed(d jsonb) returns text[] language sql immutable as $f$
  select (public.match_order(d))[1:public.match_cap(d)];
$f$;
create function public.match_waitlist(d jsonb) returns text[] language sql immutable as $f$
  select coalesce((public.match_order(d))[public.match_cap(d) + 1:], '{}');
$f$;
create function public.rsvp_in(d jsonb) returns text[] language sql immutable as $f$
  select coalesce(array_agg(e.key), '{}')
    from jsonb_each(case when jsonb_typeof(d -> 'rsvp') = 'object' then d -> 'rsvp' else '{}'::jsonb end) e
   where jsonb_typeof(e.value) = 'object' and e.value ->> 's' = 'in';
$f$;
create function public.day_it(p_date text) returns text language sql immutable as $f$
  select case when coalesce(p_date, '') ~ '^\\d{4}-\\d{2}-\\d{2}$' then
    (array['domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato'])[extract(dow from p_date::date)::int + 1]
    || ' ' || extract(day from p_date::date)::int || ' '
    || (array['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'])[extract(month from p_date::date)::int]
  else '' end;
$f$;
create function public.match_when(d jsonb) returns text language sql stable as $f$
  select case when coalesce(d ->> 'date', '') ~ '^\\d{4}-\\d{2}-\\d{2}$' then
    case (d ->> 'date')::date - (now() at time zone 'Europe/Rome')::date
      when 0 then 'oggi' when 1 then 'domani' else public.day_it(d ->> 'date') end
    || case when coalesce(d ->> 'time', '') ~ '^\\d{1,2}:\\d{2}$' then ' alle ' || (d ->> 'time') else '' end
  else 'giorno da definire' end;
$f$;
create function public.match_start(d jsonb) returns timestamptz language sql stable as $f$
  select case when coalesce(d ->> 'date', '') ~ '^\\d{4}-\\d{2}-\\d{2}$' then
    ((d ->> 'date') || ' ' || case when coalesce(d ->> 'time', '') ~ '^\\d{1,2}:\\d{2}$' then d ->> 'time' else '21:00' end)::timestamp
      at time zone 'Europe/Rome'
  end;
$f$;
create function public.pname(p_uid text) returns text language sql stable security definer set search_path to 'public' as $f$
  select coalesce((select coalesce(nullif(data ->> 'nick', ''), nullif(data ->> 'first', '')) from docs where path = 'players/' || p_uid), 'Qualcuno');
$f$;
create function public.group_members(p_gid text) returns text[] language sql stable security definer set search_path to 'public' as $f$
  select coalesce(array_agg(split_part(id, '~', 2)), '{}') from docs
   where col = 'members' and split_part(id, '~', 1) = p_gid and data ->> 'status' = 'active';
$f$;
create function public.push_enqueue(p_targets text[], p_title text, p_body text, p_tag text, p_url text) returns void
language plpgsql security definer set search_path to 'public' as $f$
declare t text[]; v_id bigint;
begin
  select coalesce(array_agg(distinct x), '{}') into t
    from unnest(coalesce(p_targets, '{}')) x
   where x is not null and x <> ''
     and exists (select 1 from push_subs s where s.uid::text = x)
     and not exists (select 1 from push_prefs pf where pf.uid::text = x and not pf.matches);
  if coalesce(array_length(t, 1), 0) = 0 then return; end if;
  insert into push_queue (targets, title, body, tag, url)
  values (t, left(coalesce(p_title, 'Algor Bomber'), 120), left(coalesce(p_body, ''), 240), coalesce(p_tag, 'partita'), coalesce(p_url, './'))
  returning id into v_id;
  perform net.http_post(url := 'https://example.invalid/functions/v1/notify', body := jsonb_build_object('q', v_id), headers := '{}'::jsonb, timeout_milliseconds := 20000);
exception when others then
  return;
end $f$;
create trigger docs_fill_paths before insert or update on public.docs for each row execute function docs_fill_paths();
`);

// la funzione nuova, dallo script vero
await db.exec(fs.readFileSync(new URL('../../supabase/aggiornamento-panchina.sql', import.meta.url), 'utf8'));
await db.exec(`create trigger docs_match_push after insert or update on public.docs for each row when (new.col = 'matches') execute function match_push();`);

// persone: uuid finti ma validi
const U = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const ORG = U(1);
const people = Array.from({ length: 18 }, (_, i) => U(i + 1));
const nick = (u) => 'P' + parseInt(u.slice(-12), 10);
for (const u of people) {
  await db.query(`insert into docs (path, col, id, data) values ($1, 'players', $2, $3)`, ['players/' + u, u, { nick: u === ORG ? 'Orla' : nick(u) }]);
  await db.query(`insert into docs (path, col, id, data) values ($1, 'members', $2, '{"status":"active"}')`, ['members/G1~' + u, 'G1~' + u]);
  await db.query(`insert into push_subs (endpoint, uid) values ($1, $2)`, ['https://push/' + u, u]);
}
await db.query(`insert into docs (path, col, id, data) values ('groups/G1', 'groups', 'G1', '{"name":"Algor Bomber"}')`);

const ymd = async (days) => (await db.query(`select to_char((now() at time zone 'Europe/Rome')::date + $1::int, 'YYYY-MM-DD') as d`, [days])).rows[0].d;
const asUser = async (u) => db.query(`select set_config('test.uid', $1, false)`, [u || '']);
const queue = async () => (await db.query(`select targets, body from push_queue order by id`)).rows;
const clearQ = async () => db.exec('delete from push_queue');
const tomorrow = await ymd(1), yesterday = await ymd(-1);

// partita a 5 di domani: 12 iscritti (10 confermati + 2 in lista d'attesa), in ordine di risposta
const rsvpOf = (ids, base) => Object.fromEntries(ids.map((u, k) => [u, { s: 'in', t: base + k * 1000 }]));
const ids12 = people.slice(0, 12);
const mk = async (path, data) => { await asUser(ORG); await db.query(`insert into docs (path, col, id, data) values ($1, 'matches', $2, $3)`, [path, path.split('/').pop(), data]); };
const upd = async (path, patch, who) => {
  await asUser(who);
  await db.query(`update docs set data = data || $2::jsonb where path = $1`, [path, patch]);
};
const get = async (path) => (await db.query(`select data from docs where path = $1`, [path])).rows[0].data;

// --- 0. partita nuova: arriva "Nuova partita" a tutti tranne chi la crea
await clearQ();
await mk('g/G1/matches/M1', { status: 'open', format: 5, date: tomorrow, time: '21:00', field: 'Campo Biggi', rsvp: rsvpOf(ids12, 1000000), teams: { a: [], b: [] } });
let q = await queue();
check(q.length === 1 && q[0].targets.length === 17 && !q[0].targets.includes(ORG) && q[0].body.startsWith('Nuova partita a 5 domani alle 21:00'), 'partita nuova: notifica a tutti tranne chi la crea (' + (q[0] && q[0].body) + ')');

// --- 1. panchina: W (11°, primo in lista d'attesa) entra al posto di P3; si scambiano gli orari
await clearQ();
let d = await get('g/G1/matches/M1');
const W = ids12[10], P = ids12[2];
let rs = Object.assign({}, d.rsvp, { [W]: { s: 'in', t: d.rsvp[P].t }, [P]: { s: 'in', t: d.rsvp[W].t } });
await upd('g/G1/matches/M1', { rsvp: rs }, ORG);
q = await queue();
console.log('   ', q.map((x) => x.targets.map(nick).join(',') + ': ' + x.body).join('\n     '));
check(q.some((x) => x.targets.length === 1 && x.targets[0] === W && x.body === 'Si è liberato un posto: giochi tu, domani alle 21:00 · Campo Biggi!'), 'chi entra: "Si è liberato un posto: giochi tu"');
check(q.some((x) => x.targets.length === 1 && x.targets[0] === P && x.body === "Orla ti ha messo in panchina per domani alle 21:00: sei n° 1 in lista d'attesa"), 'chi esce: "Orla ti ha messo in panchina per domani alle 21:00: sei n° 1 in lista d\'attesa"');
check(q.length === 2, 'solo quelle due notifiche');

// --- 2. con il secondo della lista: chi esce prende il n° 2
await clearQ();
d = await get('g/G1/matches/M1');
const W2 = ids12[11], P5 = ids12[4];
rs = Object.assign({}, d.rsvp, { [W2]: { s: 'in', t: d.rsvp[P5].t }, [P5]: { s: 'in', t: d.rsvp[W2].t } });
await upd('g/G1/matches/M1', { rsvp: rs }, ORG);
q = await queue();
check(q.some((x) => x.targets[0] === P5 && x.body.endsWith("sei n° 2 in lista d'attesa")), 'chi esce al posto del secondo in lista è n° 2');
check(q.length === 2 && !q.some((x) => x.targets[0] === P), 'chi era già in panchina non riceve niente di nuovo');

// --- 3. chi organizza manda in panchina sé stesso: a lui niente, a chi entra sì
await clearQ();
d = await get('g/G1/matches/M1');
const first = (await db.query(`select public.match_waitlist(data) as w from docs where path = 'g/G1/matches/M1'`)).rows[0].w[0];
rs = Object.assign({}, d.rsvp, { [first]: { s: 'in', t: d.rsvp[ORG].t }, [ORG]: { s: 'in', t: d.rsvp[first].t } });
await upd('g/G1/matches/M1', { rsvp: rs }, ORG);
q = await queue();
check(q.length === 1 && q[0].targets[0] === first && q[0].body.startsWith('Si è liberato un posto'), 'chi organizza va in panchina da solo: notifica solo a chi entra');

// --- 4. cambiano solo le squadre: niente notifiche
await clearQ();
await upd('g/G1/matches/M1', { teams: { a: ids12.slice(0, 5), b: ids12.slice(5, 10), manual: true } }, ORG);
check((await queue()).length === 0, 'cambiare solo le squadre non manda notifiche');

// --- 5. un confermato si ritira da solo: il primo della lista entra, nessuno va in panchina
await clearQ();
d = await get('g/G1/matches/M1');
const conf = (await db.query(`select public.match_confirmed(data) as c, public.match_waitlist(data) as w from docs where path = 'g/G1/matches/M1'`)).rows[0];
const leaver = conf.c[6];
rs = Object.assign({}, d.rsvp, { [leaver]: { s: 'out', t: 9999999 } });
await upd('g/G1/matches/M1', { rsvp: rs }, leaver);
q = await queue();
check(q.length === 1 && q[0].targets[0] === conf.w[0] && q[0].body.startsWith('Si è liberato un posto'), 'chi si ritira libera il posto al primo della lista (come prima)');

// --- 6. chi ha spento le notifiche delle partite non le riceve
await clearQ();
d = await get('g/G1/matches/M1');
const c2 = (await db.query(`select public.match_confirmed(data) as c, public.match_waitlist(data) as w from docs where path = 'g/G1/matches/M1'`)).rows[0];
const quiet = c2.c[1];
await db.query(`insert into push_prefs (uid, matches) values ($1, false)`, [quiet]);
rs = Object.assign({}, d.rsvp, { [c2.w[0]]: { s: 'in', t: d.rsvp[quiet].t }, [quiet]: { s: 'in', t: d.rsvp[c2.w[0]].t } });
await upd('g/G1/matches/M1', { rsvp: rs }, ORG);
q = await queue();
check(q.length === 1 && q[0].targets[0] === c2.w[0], 'chi ha spento le notifiche delle partite non riceve la panchina');

// --- 7. da 7 a 5: i 4 che restano fuori sono avvisati con il loro numero
await clearQ();
const ids14 = people.slice(0, 14);
await mk('g/G1/matches/M2', { status: 'open', format: 7, date: tomorrow, time: '20:30', field: '', rsvp: rsvpOf(ids14, 2000000) });
await clearQ();
await upd('g/G1/matches/M2', { format: 5 }, ORG);
q = await queue();
console.log('   ', q.map((x) => x.targets.map(nick).join(',') + ': ' + x.body).join('\n     '));
check(q.length === 4 && q.every((x, k) => x.body === `Ora si gioca a 5, domani alle 20:30: sei in lista d'attesa, n° ${k + 1}`), 'da 7 a 5: in 4 ricevono "Ora si gioca a 5…" con il loro numero');

// --- 8. partita già iniziata (ieri, da chiudere): niente notifiche per entrate e uscite
await clearQ();
await mk('g/G1/matches/M3', { status: 'open', format: 5, date: yesterday, time: '21:00', field: 'Campo Biggi', rsvp: rsvpOf(ids12, 3000000) });
await clearQ();
d = await get('g/G1/matches/M3');
rs = Object.assign({}, d.rsvp, { [W]: { s: 'in', t: d.rsvp[P].t }, [P]: { s: 'in', t: d.rsvp[W].t } });
await upd('g/G1/matches/M3', { rsvp: rs }, ORG);
check((await queue()).length === 0, 'partita già iniziata: le correzioni non mandano notifiche');

// --- 9. il resto è come prima: cambio d'ora, annullata, chiusa
await clearQ();
await upd('g/G1/matches/M1', { time: '22:00' }, ORG);
q = await queue();
check(q.length === 1 && q[0].body === 'Partita cambiata: domani alle 22:00 · Campo Biggi' && !q[0].targets.includes(ORG), 'cambio d\'ora: "Partita cambiata" come prima');
await clearQ();
await upd('g/G1/matches/M2', { status: 'cancelled' }, ORG);
q = await queue();
check(q.length === 1 && q[0].body === 'Partita annullata: domani alle 20:30', 'annullata: come prima');
await clearQ();
await upd('g/G1/matches/M1', { status: 'played', final: { ids: ids12.slice(0, 10) } }, ORG);
q = await queue();
check(q.length === 1 && q[0].body.startsWith("Vota l'MVP di"), 'chiusa: voto MVP come prima');

console.log('\nFALLITE:', FAIL.length);
FAIL.forEach((f) => console.log(' -', f));
process.exit(FAIL.length ? 1 : 0);
