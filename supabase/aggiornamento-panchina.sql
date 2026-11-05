-- ============================================================
-- Algor Bomber: panchina nel Campo (5 novembre 2026)
-- Da eseguire dopo aggiornamento-notifiche.sql. Non sposta dati e si può rieseguire.
--
-- Nel Campo chi organizza fa entrare uno della lista d'attesa al posto di chi è in campo:
-- i due si scambiano anche il posto in lista (l'app scambia i loro orari di risposta).
-- Chi entra riceveva già la notifica "Si è liberato un posto: giochi tu"; con questo
-- aggiornamento chi passa dai confermati alla lista d'attesa riceve:
--   "Marco ti ha messo in panchina per domani alle 21:00: sei n° 1 in lista d'attesa"
-- (o, se la partita diventa di un formato più piccolo: "Ora si gioca a 5, …: sei in lista d'attesa, n° 2").
-- Novità anche per "posto libero": dopo l'inizio della partita non si manda più (sono correzioni,
-- non c'è più niente da raggiungere). Tutto il resto di match_push è com'era.
-- ============================================================

create or replace function public.match_push()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me text := coalesce(auth.uid()::text, '');
  d jsonb := new.data;
  o jsonb := case when tg_op = 'UPDATE' then old.data end;
  st text := coalesce(new.data ->> 'status', '');
  ost text := coalesce(case when tg_op = 'UPDATE' then old.data ->> 'status' end, '');
  gname text; url text; tag text; fmt text; quando text; campo text; who text;
  oldc text[]; newc text[]; wait text[]; x text; i int;
begin
  if new.gid is null or not exists (select 1 from push_subs limit 1) then return null; end if;
  select coalesce(nullif(data ->> 'name', ''), 'Algor Bomber') into gname from docs where path = 'groups/' || new.gid;
  gname := coalesce(gname, 'Algor Bomber');
  url := './?m=' || new.gid || '.' || new.id;
  tag := 'partita-' || new.id;
  fmt := 'a ' || coalesce(d ->> 'format', '5');
  quando := public.match_when(d);
  campo := coalesce(' · ' || nullif(d ->> 'field', ''), '');
  who := public.pname(me);

  if tg_op = 'INSERT' then
    if st = 'poll' then
      perform public.push_enqueue(array_remove(public.group_members(new.gid), me), gname,
        who || ' propone una partita ' || fmt || ': segna i giorni in cui sei libero', tag, url);
    elsif st not in ('played', 'cancelled') and public.match_start(d) > now() then
      perform public.push_enqueue(array_remove(public.group_members(new.gid), me), gname,
        'Nuova partita ' || fmt || ' ' || quando || campo || '. Ci sei?', tag, url);
    end if;
    return null;
  end if;

  -- il sondaggio ha scelto il giorno: si gioca
  if ost = 'poll' and st = 'open' then
    newc := public.match_confirmed(d);
    perform public.push_enqueue(array_remove(newc, me), gname, 'Si gioca ' || quando || campo || '!', tag, url);
    wait := public.match_waitlist(d);
    for i in 1 .. coalesce(array_length(wait, 1), 0) loop
      if wait[i] <> me then
        perform public.push_enqueue(array[wait[i]], gname, 'Si gioca ' || quando || ': sei in lista d''attesa, n° ' || i, tag, url);
      end if;
    end loop;
    return null;
  end if;
  -- annullata
  if st = 'cancelled' and ost <> 'cancelled' then
    perform public.push_enqueue(array_remove(public.rsvp_in(o), me), gname, 'Partita annullata: ' || quando, tag, url);
    return null;
  end if;
  -- chiusa: si vota l'MVP
  if st = 'played' and ost <> 'played' then
    perform public.push_enqueue(
      array_remove(coalesce((select array_agg(v) from jsonb_array_elements_text(case when jsonb_typeof(d -> 'final' -> 'ids') = 'array' then d -> 'final' -> 'ids' else '[]'::jsonb end) v), '{}'), me),
      gname, 'Vota l''MVP di ' || public.day_it(d ->> 'date') || ': si chiude tra 24 ore', tag, url);
    return null;
  end if;
  if st in ('poll', 'played', 'cancelled') then return null; end if;

  -- cambiati giorno, ora o campo
  if coalesce(o ->> 'date', '') <> coalesce(d ->> 'date', '') or coalesce(o ->> 'time', '') <> coalesce(d ->> 'time', '')
     or coalesce(o ->> 'field', '') <> coalesce(d ->> 'field', '') then
    perform public.push_enqueue(array_remove(public.rsvp_in(d), me), gname, 'Partita cambiata: ' || quando || campo, tag, url);
  end if;
  -- inviti nuovi
  for x in select k from jsonb_object_keys(case when jsonb_typeof(d -> 'invites') = 'object' then d -> 'invites' else '{}'::jsonb end) k
            where not (case when jsonb_typeof(o -> 'invites') = 'object' then o -> 'invites' else '{}'::jsonb end ? k) loop
    if x <> me then
      perform public.push_enqueue(array[x], gname,
        public.pname(coalesce(d -> 'invites' -> x ->> 'by', me)) || ' ti invita a giocare ' || quando || campo || '. Ci sei?', tag, url);
    end if;
  end loop;
  -- da qui in poi solo prima dell'inizio: dopo, chi entra o esce sono correzioni
  if not coalesce(public.match_start(d) > now(), false) then return null; end if;
  -- posto libero: chi aspettava in lista d'attesa ed entra
  oldc := public.match_confirmed(o);
  newc := public.match_confirmed(d);
  wait := public.match_waitlist(o);
  select coalesce(array_agg(y), '{}') into newc from unnest(newc) y where y = any (wait) and not (y = any (oldc));
  if coalesce(array_length(newc, 1), 0) > 0 then
    perform public.push_enqueue(array_remove(newc, me), gname, 'Si è liberato un posto: giochi tu, ' || quando || campo || '!', tag, url);
  end if;
  -- in panchina: chi era tra i confermati ed è finito in lista d'attesa (lo ha fatto uscire chi organizza,
  -- o la partita è diventata di un formato più piccolo); ognuno con il suo numero
  wait := public.match_waitlist(d);
  for i in 1 .. coalesce(array_length(wait, 1), 0) loop
    if wait[i] <> me and wait[i] = any (oldc) then
      perform public.push_enqueue(array[wait[i]], gname,
        case when public.match_cap(o) = public.match_cap(d)
          then who || ' ti ha messo in panchina per ' || quando || ': sei n° ' || i || ' in lista d''attesa'
          else 'Ora si gioca ' || fmt || ', ' || quando || ': sei in lista d''attesa, n° ' || i end,
        tag, url);
    end if;
  end loop;
  return null;
exception when others then
  return null;
end $function$;
