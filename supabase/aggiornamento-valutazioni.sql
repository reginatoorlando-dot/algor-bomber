-- Algor Bomber: valutazioni più efficaci (novembre 2026).
-- Da incollare nell'editor SQL di Supabase dopo gli altri aggiornamenti. Si può eseguire più volte.
-- Non sposta e non cancella dati.
--
-- 1. global_votes: per le stats generali dà tutte le valutazioni di tutti i gruppi, anche quelle date prima
--    (campo h di ogni valutazione), senza dire chi le ha date: l'app fa la media delle ultime 30 per ogni voce.
-- 2. Confronto: tabella cmp_votes e funzioni cmp_vote (un confronto) e cmp_state (gli effetti, senza chi li ha
--    causati; i propri confronti dell'ultimo mese; quanti ne ha fatti ognuno). Chi ha scelto chi resta segreto.
-- 3. rater_stats: quante valutazioni e quanti confronti ha fatto una persona in tutti i gruppi (per i traguardi).
-- 4. Pulizia: eliminando un profilo o un gruppo spariscono anche i suoi confronti.

-- 1. Valutazioni di tutti i gruppi: ogni valutazione con le precedenti della stessa persona (h)
create or replace function public.global_votes() returns table (target text, vote jsonb)
language sql stable security definer set search_path = public as $$
  select e.key as target, e.value as vote
    from public.docs d
   cross join lateral jsonb_each(case when jsonb_typeof(d.data -> 'r') = 'object' then d.data -> 'r' else '{}'::jsonb end) e
   where d.col = 'ratings' and d.gid is not null
     and e.key <> d.id and jsonb_typeof(e.value) = 'object'
     and auth.uid() is not null;
$$;

-- 2. Confronto: chi è più forte su una voce tra due compagni di gruppo.
--    da e db: quanto cambia la voce di a e di b (+2/−2 se si sceglie il più debole, ±1 con "Uguali", 0 se non cambia).
create table if not exists public.cmp_votes (
  id    bigserial primary key,
  gid   text not null,
  voter text not null,
  a     text not null,
  b     text not null,
  voce  text not null,
  da    smallint not null,
  db    smallint not null,
  t     timestamptz not null default now()
);
create index if not exists cmp_votes_gid on public.cmp_votes (gid, t);
create index if not exists cmp_votes_voter on public.cmp_votes (voter, t);
alter table public.cmp_votes enable row level security;
revoke all on public.cmp_votes from anon, authenticated;

-- un confronto: la stessa coppia sulla stessa voce al massimo una volta al mese per persona, 150 al giorno in tutto
create or replace function public.cmp_vote(p_gid text, p_a text, p_b text, p_voce text, p_da int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me text := auth.uid()::text; n int;
begin
  if me is null then raise exception 'Accesso richiesto.' using errcode = '42501'; end if;
  if p_gid is null or not is_member(p_gid) then raise exception 'Non sei in questo gruppo.' using errcode = '42501'; end if;
  if p_a is null or p_b is null or p_a = p_b or me = p_a or me = p_b then
    raise exception 'Confronto non valido.' using errcode = '22023';
  end if;
  if p_voce is null or p_voce not in ('tir', 'dri', 'pat', 'pas', 'vis', 'pce', 'con', 'sci', 'pdi', 'vel', 'res', 'ele', 'cpz', 'rif', 'usc', 'tuf', 'lan') then
    raise exception 'Voce non valida.' using errcode = '22023';
  end if;
  if p_da is null or p_da not in (-2, -1, 0, 1, 2) then raise exception 'Confronto non valido.' using errcode = '22023'; end if;
  if (select count(*) from docs where col = 'members' and id in (p_gid || '~' || p_a, p_gid || '~' || p_b) and data ->> 'status' = 'active') < 2 then
    raise exception 'Uno dei due non è più nel gruppo.' using errcode = '22023';
  end if;
  if exists (select 1 from cmp_votes
              where gid = p_gid and voter = me and voce = p_voce
                and least(a, b) = least(p_a, p_b) and greatest(a, b) = greatest(p_a, p_b)
                and t > now() - interval '30 days') then
    raise exception 'Hai già confrontato questi due su questa voce nell''ultimo mese.' using errcode = '22023';
  end if;
  if (select count(*) from cmp_votes where voter = me and t > now() - interval '1 day') >= 150 then
    raise exception 'Per oggi hai fatto abbastanza confronti: riprendi domani.' using errcode = '22023';
  end if;
  insert into cmp_votes (gid, voter, a, b, voce, da, db) values (p_gid, me, p_a, p_b, p_voce, p_da, -p_da);
  select count(*) into n from cmp_votes where gid = p_gid and voter = me;
  return jsonb_build_object('ok', true, 'n', n);
end $$;
revoke all on function public.cmp_vote(text, text, text, text, int) from public, anon;
grant execute on function public.cmp_vote(text, text, text, text, int) to authenticated;

-- lo stato dei confronti di un gruppo (o, senza gruppo, gli effetti in tutti i gruppi per le stats generali):
--   ev: [giocatore, voce, variazione, quando] senza chi l'ha causata
--   mine: i miei confronti dell'ultimo mese [a, b, voce, quando], per non riproporli
--   n: quanti confronti ha fatto ognuno nel gruppo; ms: quando ha fatto il 50°, il 250° e il 1000° (traguardi)
create or replace function public.cmp_state(p_gid text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me text := auth.uid()::text;
begin
  if me is null then return null; end if;
  if p_gid is null then
    return jsonb_build_object('ev', coalesce((
      select jsonb_agg(jsonb_build_array(x.who, x.voce, x.d, x.ms) order by x.ms)
        from (select a as who, voce, da as d, (extract(epoch from t) * 1000)::bigint as ms from cmp_votes where da <> 0
              union all
              select b, voce, db, (extract(epoch from t) * 1000)::bigint from cmp_votes where db <> 0) x), '[]'::jsonb));
  end if;
  if not (is_member(p_gid) or is_app_admin()) then return null; end if;
  return jsonb_build_object(
    'ev', coalesce((
      select jsonb_agg(jsonb_build_array(x.who, x.voce, x.d, x.ms) order by x.ms)
        from (select a as who, voce, da as d, (extract(epoch from t) * 1000)::bigint as ms from cmp_votes where gid = p_gid and da <> 0
              union all
              select b, voce, db, (extract(epoch from t) * 1000)::bigint from cmp_votes where gid = p_gid and db <> 0) x), '[]'::jsonb),
    'mine', coalesce((
      select jsonb_agg(jsonb_build_array(a, b, voce, (extract(epoch from t) * 1000)::bigint))
        from cmp_votes where gid = p_gid and voter = me and t > now() - interval '30 days'), '[]'::jsonb),
    'n', coalesce((
      select jsonb_object_agg(voter, c) from (select voter, count(*) as c from cmp_votes where gid = p_gid group by voter) z), '{}'::jsonb),
    'ms', coalesce((
      select jsonb_object_agg(voter, ms) from (
        select voter, jsonb_agg(ms order by rn) as ms from (
          select voter, row_number() over (partition by voter order by t, id) as rn, (extract(epoch from t) * 1000)::bigint as ms
            from cmp_votes where gid = p_gid) w
         where rn in (50, 250, 1000) group by voter) z), '{}'::jsonb));
end $$;
revoke all on function public.cmp_state(text) from public, anon;
grant execute on function public.cmp_state(text) to authenticated;

-- 3. Per i traguardi di chi valuta, in tutti i gruppi: quante valutazioni ha dato (e quando la 10ª, la 50ª, la 200ª)
--    e quanti confronti ha fatto (e quando il 50°, il 250°, il 1000°). Solo numeri e date: niente voti.
create or replace function public.rater_stats(p_uid text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare nr int; nsum int; rms jsonb; nc int; cms jsonb;
begin
  if auth.uid() is null or p_uid is null then return null; end if;
  -- le date delle valutazioni date: quelle salvate dall'app (ts) o, nei documenti di prima, quelle delle valutazioni
  with mine as (
    select d.data from docs d where d.col = 'ratings' and d.gid is not null and d.id = p_uid
  ), times as (
    select (x)::bigint as ms from mine,
      jsonb_array_elements_text(case when jsonb_typeof(data -> 'ts') = 'array' then data -> 'ts' else '[]'::jsonb end) x
     where x ~ '^\d{1,15}$'
    union all
    select ms_of(e.value -> 't') from mine
      cross join lateral jsonb_each(case when jsonb_typeof(data -> 'r') = 'object' then data -> 'r' else '{}'::jsonb end) e
     where coalesce(jsonb_typeof(data -> 'ts'), '') <> 'array' and e.key <> p_uid and jsonb_typeof(e.value) = 'object'
    union all
    select ms_of(h -> 't') from mine
      cross join lateral jsonb_each(case when jsonb_typeof(data -> 'r') = 'object' then data -> 'r' else '{}'::jsonb end) e
      cross join lateral jsonb_array_elements(case when jsonb_typeof(e.value -> 'h') = 'array' then e.value -> 'h' else '[]'::jsonb end) h
     where coalesce(jsonb_typeof(data -> 'ts'), '') <> 'array' and e.key <> p_uid
  ), ranked as (
    select ms, row_number() over (order by ms) as rn from times
  )
  select (select count(*) from times),
         (select coalesce(sum(case when jsonb_typeof(data -> 'n') = 'number' then (data ->> 'n')::numeric::int else 0 end), 0) from mine),
         coalesce((select jsonb_agg(ms order by rn) from ranked where rn in (10, 50, 200)), '[]'::jsonb)
    into nr, nsum, rms;
  select count(*) into nc from cmp_votes where voter = p_uid;
  select coalesce(jsonb_agg(ms order by rn), '[]'::jsonb) into cms from (
    select row_number() over (order by t, id) as rn, (extract(epoch from t) * 1000)::bigint as ms from cmp_votes where voter = p_uid
  ) w where rn in (50, 250, 1000);
  return jsonb_build_object('rv', jsonb_build_object('n', greatest(nr, nsum), 'ms', rms),
                            'cv', jsonb_build_object('n', nc, 'ms', cms));
end $$;
revoke all on function public.rater_stats(text) from public, anon;
grant execute on function public.rater_stats(text) to authenticated;

-- 4. Eliminando un profilo o un gruppo spariscono anche i suoi confronti
create or replace function public.cmp_cleanup() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.col = 'players' then
    delete from cmp_votes where voter = old.id or a = old.id or b = old.id;
  elsif old.col = 'groups' then
    delete from cmp_votes where gid = old.id;
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke execute on function public.cmp_cleanup() from public, anon, authenticated;
drop trigger if exists docs_cmp_cleanup on public.docs;
create trigger docs_cmp_cleanup after delete on public.docs
  for each row when (old.col in ('players', 'groups')) execute function public.cmp_cleanup();

-- l'app vede subito le funzioni nuove
notify pgrst, 'reload schema';

select 'Aggiornamento valutazioni completato' as esito;
