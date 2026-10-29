-- ============================================================
-- Algor Bomber · aggiornamento "partite" (29 ottobre 2026)
-- Da incollare nell'SQL Editor di Supabase ed eseguire una volta (Run).
-- Si può rieseguire senza danni. Non sposta e non cancella nessun dato.
--
-- Cosa fa:
--   1-2. comune dei gruppi e modifica del gruppo (le stesse funzioni di aggiornamento-zone.sql:
--        se l'avevi già eseguito non cambia niente)
--   3. sondaggio sul giorno: ognuno segna i giorni in cui è libero; appena un giorno arriva
--      al numero per due squadre piene, la partita nasce da sola su quel giorno
--   4. chi ha creato il sondaggio (o un amministratore del gruppo) può chiuderlo scegliendo il giorno
-- ============================================================

-- un posto valido: {name, prov, lat, lng} dentro l'Italia, altrimenti null
create or replace function public.clean_loc(p jsonb) returns jsonb
language plpgsql immutable as $$
declare nm text; pv text; la numeric; lo numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  if coalesce(jsonb_typeof(p -> 'lat'), '') <> 'number' or coalesce(jsonb_typeof(p -> 'lng'), '') <> 'number' then return null; end if;
  nm := btrim(coalesce(p ->> 'name', ''));
  pv := upper(btrim(coalesce(p ->> 'prov', '')));
  la := (p ->> 'lat')::numeric;
  lo := (p ->> 'lng')::numeric;
  if length(nm) < 1 or length(nm) > 60 or length(pv) > 3 then return null; end if;
  if la < 35 or la > 48 or lo < 6 or lo > 19.5 then return null; end if;
  return jsonb_build_object('name', nm, 'prov', pv, 'lat', round(la, 4), 'lng', round(lo, 4));
end $$;

-- 1. creare un gruppo, ora anche con il comune (la versione vecchia a due valori continua a funzionare)
drop function if exists public.create_group(text, text);
create or replace function public.create_group(p_name text, p_city text, p_loc jsonb default null) returns text
language plpgsql security definer set search_path = public as $$
declare
  me text := auth.uid()::text;
  nm text := btrim(coalesce(p_name, ''));
  lc jsonb := public.clean_loc(p_loc);
  ct text := btrim(coalesce(case when lc is not null then lc ->> 'name' else p_city end, ''));
  g text;
begin
  if me is null then raise exception 'Devi accedere per creare un gruppo.' using errcode = '42501'; end if;
  if length(nm) < 2 or length(nm) > 40 then raise exception 'Il nome del gruppo deve avere tra 2 e 40 caratteri.' using errcode = '22023'; end if;
  if length(ct) < 2 or length(ct) > 60 then raise exception 'Scegli la città del gruppo.' using errcode = '22023'; end if;
  if not exists (select 1 from docs where path = 'players/' || me) then
    raise exception 'Crea prima il tuo profilo.' using errcode = '22023';
  end if;
  g := 'g_' || substr(md5(random()::text || clock_timestamp()::text || me), 1, 10);
  insert into docs (path, col, id, data) values ('groups/' || g, 'groups', g,
    jsonb_build_object('name', nm, 'city', ct, 'by', me, 'created', now_ms(), 'n', 1)
      || case when lc is not null then jsonb_build_object('loc', lc) else '{}'::jsonb end);
  insert into docs (path, col, id, data) values ('members/' || g || '~' || me, 'members', g || '~' || me,
    jsonb_build_object('gid', g, 'uid', me, 'role', 'admin', 'status', 'active', 't', now_ms()));
  return g;
end $$;

-- 2. nome e città del gruppo: li cambiano i suoi amministratori (e gli amministratori dell'app)
create or replace function public.update_group(p_gid text, p_name text, p_city text, p_loc jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  nm text := btrim(coalesce(p_name, ''));
  lc jsonb := public.clean_loc(p_loc);
  ct text := btrim(coalesce(case when lc is not null then lc ->> 'name' else p_city end, ''));
begin
  if not (is_group_admin(p_gid) or is_app_admin()) then
    raise exception 'Solo gli amministratori del gruppo possono modificarlo.' using errcode = '42501';
  end if;
  if not exists (select 1 from docs where path = 'groups/' || p_gid) then
    raise exception 'Questo gruppo non esiste più.' using errcode = '22023';
  end if;
  if length(nm) < 2 or length(nm) > 40 then raise exception 'Il nome del gruppo deve avere tra 2 e 40 caratteri.' using errcode = '22023'; end if;
  if length(ct) < 2 or length(ct) > 60 then raise exception 'Scegli la città del gruppo.' using errcode = '22023'; end if;
  update docs set data = (data - 'loc') || jsonb_build_object('name', nm, 'city', ct)
                         || case when lc is not null then jsonb_build_object('loc', lc) else '{}'::jsonb end
   where path = 'groups/' || p_gid;
end $$;

-- oggi, in Italia, come 'AAAA-MM-GG'
create or replace function public.today_it() returns text
language sql stable as $$ select to_char(now() at time zone 'Europe/Rome', 'YYYY-MM-DD') $$;

-- chi ha votato un giorno diventa "ci sono" per la partita, nell'ordine in cui l'ha votato
create or replace function public.poll_rsvp(p_votes jsonb, p_day text) returns jsonb
language sql immutable as $$
  select coalesce(jsonb_object_agg(e.key, jsonb_build_object('s', 'in', 't', e.value -> p_day)), '{}'::jsonb)
    from jsonb_each(case when jsonb_typeof(p_votes) = 'object' then p_votes else '{}'::jsonb end) e
   where jsonb_typeof(e.value) = 'object' and e.value ? p_day;
$$;

-- 3. votare: p_days sono tutti i giorni in cui sei libero (lista vuota = togli il voto)
create or replace function public.poll_vote(p_gid text, p_mid text, p_days jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me text := auth.uid()::text;
  pth text := 'g/' || p_gid || '/matches/' || p_mid;
  today text := public.today_it();
  d jsonb; days jsonb; need int; votes jsonb; old jsonb; mine jsonb := '{}'::jsonb; x text; win text; c int;
begin
  if me is null or not public.is_member(p_gid) then
    raise exception 'Devi essere nel gruppo per votare.' using errcode = '42501';
  end if;
  select data into d from docs where path = pth for update;
  if d is null then raise exception 'Il sondaggio non esiste più.' using errcode = '22023'; end if;
  if coalesce(d ->> 'status', '') <> 'poll' then
    return jsonb_build_object('status', d ->> 'status', 'day', d ->> 'date');
  end if;
  days := case when jsonb_typeof(d -> 'poll' -> 'days') = 'array' then d -> 'poll' -> 'days' else '[]'::jsonb end;
  need := greatest(2, least(40, coalesce((d -> 'poll' ->> 'need')::int, 10)));
  votes := case when jsonb_typeof(d -> 'poll' -> 'votes') = 'object' then d -> 'poll' -> 'votes' else '{}'::jsonb end;
  old := case when jsonb_typeof(votes -> me) = 'object' then votes -> me else '{}'::jsonb end;
  -- solo i giorni del sondaggio non ancora passati; chi li aveva già segnati tiene la sua ora di voto
  if jsonb_typeof(p_days) = 'array' then
    for x in select distinct t.value from jsonb_array_elements_text(p_days) t loop
      if days ? x and x >= today then
        mine := mine || jsonb_build_object(x, coalesce(old -> x, to_jsonb(public.now_ms())));
      end if;
    end loop;
  end if;
  if mine = '{}'::jsonb then votes := votes - me; else votes := votes || jsonb_build_object(me, mine); end if;
  -- il primo giorno, in ordine di data, che arriva al numero per due squadre piene
  for x in select t.value from jsonb_array_elements_text(days) t where t.value >= today order by t.value loop
    select count(*) into c from jsonb_each(votes) e where jsonb_typeof(e.value) = 'object' and e.value ? x;
    if c >= need then win := x; exit; end if;
  end loop;
  if win is null then
    update docs set data = jsonb_set(data, '{poll,votes}', votes) where path = pth;
    return jsonb_build_object('status', 'poll');
  end if;
  update docs set data = jsonb_set(jsonb_set(data, '{poll,votes}', votes), '{poll,closed}',
                           jsonb_build_object('day', win, 't', public.now_ms(), 'how', 'auto'))
                         || jsonb_build_object('status', 'open', 'date', win,
                              'rsvp', coalesce(data -> 'rsvp', '{}'::jsonb) || public.poll_rsvp(votes, win))
   where path = pth;
  return jsonb_build_object('status', 'open', 'day', win);
end $$;

-- 4. chiudere a mano scegliendo il giorno (di solito il più votato)
create or replace function public.poll_close(p_gid text, p_mid text, p_day text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me text := auth.uid()::text;
  pth text := 'g/' || p_gid || '/matches/' || p_mid;
  d jsonb; votes jsonb;
begin
  select data into d from docs where path = pth for update;
  if d is null then raise exception 'Il sondaggio non esiste più.' using errcode = '22023'; end if;
  if not ((coalesce(d ->> 'by', '') = me and public.is_member(p_gid)) or public.is_group_admin(p_gid) or public.is_app_admin()) then
    raise exception 'Il sondaggio lo chiude chi l''ha creato o un amministratore del gruppo.' using errcode = '42501';
  end if;
  if coalesce(d ->> 'status', '') <> 'poll' then raise exception 'Il sondaggio è già chiuso.' using errcode = '22023'; end if;
  if jsonb_typeof(d -> 'poll' -> 'days') <> 'array' or not ((d -> 'poll' -> 'days') ? p_day) then
    raise exception 'Questo giorno non è nel sondaggio.' using errcode = '22023';
  end if;
  if p_day < public.today_it() then raise exception 'Questo giorno è già passato.' using errcode = '22023'; end if;
  votes := case when jsonb_typeof(d -> 'poll' -> 'votes') = 'object' then d -> 'poll' -> 'votes' else '{}'::jsonb end;
  update docs set data = jsonb_set(data, '{poll,closed}', jsonb_build_object('day', p_day, 't', public.now_ms(), 'how', 'manual'))
                         || jsonb_build_object('status', 'open', 'date', p_day,
                              'rsvp', coalesce(data -> 'rsvp', '{}'::jsonb) || public.poll_rsvp(votes, p_day))
   where path = pth;
  return jsonb_build_object('status', 'open', 'day', p_day);
end $$;

-- l'app vede subito le funzioni nuove
notify pgrst, 'reload schema';

select 'Aggiornamento completato' as esito,
       (select count(*) from public.docs where col = 'matches') as partite;
