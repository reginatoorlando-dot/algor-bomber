-- ============================================================
-- Algor Bomber · aggiornamento "regole" (6 novembre 2026)
-- Da incollare nell'SQL Editor di Supabase e eseguire una volta (Run).
-- Si può rieseguire senza danni. Non sposta e non cancella dati.
--
-- Le regole delle partite che l'app già rispetta valgono anche nel database:
-- chi scrivesse "a mano" (fuori dall'app, con il proprio accesso) non può fare
-- quello che l'app non lascia fare. Valgono solo per chi scrive con il proprio
-- accesso: le funzioni del database (sondaggio, notifiche, promemoria…) e gli
-- amministratori dell'app non sono toccati. Chi organizza una partita è chi l'ha
-- creata, più gli amministratori del gruppo e dell'app.
--
--   1. chi ha creato la partita resta quello; una partita nuova si crea a nome
--      proprio, aperta o come sondaggio, con dentro al massimo sé stessi;
--   2. colori delle squadre e sondaggio (giorni, voti, annullarlo): chi organizza
--      (i voti passano dalla funzione poll_vote, come oggi);
--   3. iscritti e ospiti: chiunque nel gruppo li segna, come nell'app, ma
--      spostare gli altri da una squadra all'altra lo fa chi organizza;
--      gli orari d'iscrizione sono quelli veri: uno "nel passato" (per passare
--      davanti in lista) diventa l'ora di adesso; un ospite si aggiunge a nome proprio;
--   4. campo prenotato: lo segni a nome tuo; lo toglie chi l'ha segnato o chi organizza;
--   5. cassa: prezzo e quota li scrive chi organizza, chi ha prenotato o chi
--      raccoglie; "pagato" lo segna chi raccoglie (o un amministratore del gruppo);
--   6. risultato, marcatori e chiusura: dopo l'inizio della partita successiva li
--      cambiano solo gli amministratori del gruppo e dell'app;
--   7. inviti a una partita: a nome proprio.
-- Chi prova a fare altro riceve un messaggio in italiano, che l'app mostra così com'è.
-- ============================================================

-- un oggetto JSON, o vuoto se non lo è (le regole non si rompono con dati strani)
create or replace function public.rules_obj(v jsonb) returns jsonb
language sql immutable as $$
  select case when jsonb_typeof(v) = 'object' then v else '{}'::jsonb end;
$$;

-- inizio di una partita, ora italiana (senza ora: le 21, come nell'app); null se il giorno non è valido
create or replace function public.rules_match_start(d jsonb) returns timestamptz
language plpgsql stable as $$
begin
  if coalesce(d ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return ((d ->> 'date') || ' ' || case when coalesce(d ->> 'time', '') ~ '^\d{1,2}:\d{2}$' then d ->> 'time' else '21:00' end)::timestamp
         at time zone 'Europe/Rome';
exception when others then
  return null;
end $$;

-- la partita successiva del gruppo è già iniziata? (come nell'app: non contano annullate e sondaggi)
create or replace function public.rules_next_started(p_cpath text, p_id text, d jsonb) returns boolean
language plpgsql stable set search_path = public as $$
declare t0 timestamptz := public.rules_match_start(d); nx timestamptz;
begin
  if t0 is null then return false; end if;
  select min(y.s) into nx from (
    select public.rules_match_start(x.data) as s from public.docs x
     where x.cpath = p_cpath and x.col = 'matches' and x.id <> p_id
       and coalesce(x.data ->> 'status', '') not in ('cancelled', 'poll')
  ) y where y.s > t0;
  return nx is not null and now() >= nx;
end $$;

-- orari d'iscrizione veri: quelli cambiati (o nuovi) fuori da [10 minuti fa, tra 1 minuto] diventano adesso
create or replace function public.rules_fix_times(p_old jsonb, p_new jsonb, p_now bigint) returns jsonb
language plpgsql immutable as $$
declare a jsonb := public.rules_obj(p_old); b jsonb := public.rules_obj(p_new); k text; t bigint;
begin
  for k in select jsonb_object_keys(b) loop
    if jsonb_typeof(b -> k) = 'object' and (b -> k) ? 't' and (a #> array[k, 't']) is distinct from (b #> array[k, 't']) then
      t := public.ms_of(b #> array[k, 't']);
      if t < p_now - 600000 or t > p_now + 60000 then
        b := jsonb_set(b, array[k, 't'], to_jsonb(p_now));
      end if;
    end if;
  end loop;
  return b;
end $$;

create or replace function public.match_rules() returns trigger
language plpgsql set search_path = public as $$
-- niente "security definer": così si riconosce chi scrive con il proprio accesso (current_user = authenticated)
declare
  me text := auth.uid()::text;
  n jsonb := new.data;
  o jsonb;
  gadm boolean;
  org boolean;
  nowms bigint := public.now_ms();
  a jsonb; b jsonb; k text;
  bk0 text; bk1 text; coll text;
begin
  if current_user <> 'authenticated' or me is null then return new; end if;
  if jsonb_typeof(n) is distinct from 'object' then
    raise exception 'Partita non valida.' using errcode = '22023';
  end if;
  if public.is_app_admin() then return new; end if;
  gadm := new.gid is not null and public.is_group_admin(new.gid);

  -- 1. partita nuova: a nome proprio, aperta o sondaggio, con dentro al massimo sé stessi
  if tg_op = 'INSERT' then
    if coalesce(n ->> 'by', '') <> me then
      raise exception 'Una partita nuova la crei a nome tuo.' using errcode = '42501';
    end if;
    if coalesce(n ->> 'status', 'open') not in ('open', 'poll') or n ? 'result' or n ? 'final' or n ? 'playedAt' then
      raise exception 'Una partita nuova è aperta (o un sondaggio): il risultato si scrive dopo averla giocata.' using errcode = '42501';
    end if;
    if exists (select 1 from jsonb_object_keys(public.rules_obj(n -> 'rsvp')) x where x <> me) then
      raise exception 'In una partita nuova ci sei al massimo tu: gli altri si aggiungono dopo.' using errcode = '42501';
    end if;
    if exists (select 1 from jsonb_each(public.rules_obj(n -> 'guests')) g where coalesce(g.value ->> 'by', '') <> me)
       or exists (select 1 from jsonb_each(public.rules_obj(n -> 'invites')) i where coalesce(i.value ->> 'by', '') <> me) then
      raise exception 'Ospiti e inviti si aggiungono a nome tuo.' using errcode = '42501';
    end if;
    if public.rules_obj(n #> '{poll,votes}') <> '{}'::jsonb or n #> '{poll,closed}' is not null then
      raise exception 'Un sondaggio nuovo parte senza voti: si vota toccando i giorni.' using errcode = '42501';
    end if;
    if nullif(n #>> '{booked,by}', '') is not null and n #>> '{booked,by}' <> me then
      raise exception 'Il campo prenotato lo segni a nome tuo.' using errcode = '42501';
    end if;
    if n ? 'rsvp' then n := jsonb_set(n, '{rsvp}', public.rules_fix_times('{}'::jsonb, n -> 'rsvp', nowms)); end if;
    if n ? 'guests' then n := jsonb_set(n, '{guests}', public.rules_fix_times('{}'::jsonb, n -> 'guests', nowms)); end if;
    new.data := n;
    return new;
  end if;

  o := old.data;
  org := coalesce(o ->> 'by', '') = me or gadm;

  -- 1. chi ha creato la partita resta quello
  if (o -> 'by') is distinct from (n -> 'by') or (o -> 'created') is distinct from (n -> 'created') then
    raise exception 'Chi ha creato la partita non si cambia.' using errcode = '42501';
  end if;

  -- 6. risultato, marcatori e chiusura dopo l'inizio della partita successiva: solo gli amministratori
  if not gadm and coalesce(o ->> 'status', '') = 'played'
     and ((o -> 'result') is distinct from (n -> 'result') or (o -> 'final') is distinct from (n -> 'final')
          or (o -> 'status') is distinct from (n -> 'status') or (o -> 'playedAt') is distinct from (n -> 'playedAt'))
     and public.rules_next_started(old.cpath, old.id, o) then
    raise exception 'La partita successiva è già iniziata: risultato e marcatori li correggono solo gli amministratori.' using errcode = '42501';
  end if;

  -- 4. campo prenotato: a nome proprio; lo toglie o lo cambia chi l'ha segnato o chi organizza
  if (o -> 'booked') is distinct from (n -> 'booked') and not org then
    bk0 := nullif(o #>> '{booked,by}', '');
    bk1 := nullif(n #>> '{booked,by}', '');
    if bk0 is not null and bk0 <> me then
      raise exception 'Il campo prenotato lo cambia chi l''ha segnato o chi organizza la partita.' using errcode = '42501';
    end if;
    if bk1 is not null and bk1 <> me then
      raise exception 'Il campo prenotato lo segni a nome tuo.' using errcode = '42501';
    end if;
  end if;

  -- 5. cassa: chi raccoglie è quello scritto nella cassa, se no chi ha prenotato, se no chi ha creato la partita
  if (o -> 'cassa') is distinct from (n -> 'cassa') then
    coll := coalesce(nullif(o #>> '{cassa,by}', ''), nullif(o #>> '{booked,by}', ''), nullif(o ->> 'by', ''));
    if (o #> '{cassa,paid}') is distinct from (n #> '{cassa,paid}') and not (gadm or coll = me) then
      raise exception 'Chi ha pagato lo segna chi raccoglie i soldi.' using errcode = '42501';
    end if;
    if (public.rules_obj(o -> 'cassa') - 'paid') is distinct from (public.rules_obj(n -> 'cassa') - 'paid')
       and not (org or coll = me or nullif(o #>> '{booked,by}', '') = me) then
      raise exception 'Prezzo e quota li scrive chi organizza, chi ha prenotato il campo o chi raccoglie.' using errcode = '42501';
    end if;
  end if;

  if not org then
    -- 2. colori (si possono solo mettere quelli di partenza a una partita che non li ha) e sondaggio
    if (o -> 'colors') is distinct from (n -> 'colors')
       and not (coalesce(jsonb_typeof(o -> 'colors'), 'null') = 'null' and n -> 'colors' = '{"a": "bianco", "b": "nero"}'::jsonb) then
      raise exception 'I colori delle squadre li cambia chi organizza la partita.' using errcode = '42501';
    end if;
    if (o -> 'poll') is distinct from (n -> 'poll')
       or ((o -> 'status') is distinct from (n -> 'status') and 'poll' in (coalesce(o ->> 'status', ''), coalesce(n ->> 'status', ''))) then
      raise exception 'Il sondaggio lo gestisce chi l''ha creato: per votare tocca i giorni in cui sei libero.' using errcode = '42501';
    end if;

    -- 3. iscritti: la squadra degli altri la cambia chi organizza
    a := public.rules_obj(o -> 'rsvp'); b := public.rules_obj(n -> 'rsvp');
    for k in select jsonb_object_keys(a) union select jsonb_object_keys(b) loop
      if k <> me and (a -> k) is distinct from (b -> k)
         and coalesce(a #>> array[k, 'side'], '') is distinct from coalesce(b #>> array[k, 'side'], '') then
        raise exception 'Spostare gli altri da una squadra all''altra lo fa chi organizza la partita.' using errcode = '42501';
      end if;
    end loop;
    if n ? 'rsvp' then n := jsonb_set(n, '{rsvp}', public.rules_fix_times(o -> 'rsvp', n -> 'rsvp', nowms)); end if;

    -- 3. ospiti: si aggiungono a nome proprio; restano di chi li ha portati; la squadra la cambia chi organizza
    a := public.rules_obj(o -> 'guests'); b := public.rules_obj(n -> 'guests');
    for k in select jsonb_object_keys(a) union select jsonb_object_keys(b) loop
      if (a -> k) is distinct from (b -> k) then
        if a ? k then
          if (a #> array[k, 'by']) is distinct from (b #> array[k, 'by']) then
            raise exception 'Un ospite resta di chi l''ha portato.' using errcode = '42501';
          end if;
          if coalesce(a #>> array[k, 'side'], '') is distinct from coalesce(b #>> array[k, 'side'], '') then
            raise exception 'Spostare gli altri da una squadra all''altra lo fa chi organizza la partita.' using errcode = '42501';
          end if;
        elsif coalesce(b #>> array[k, 'by'], '') <> me then
          raise exception 'Un ospite lo aggiungi a nome tuo.' using errcode = '42501';
        end if;
      end if;
    end loop;
    if n ? 'guests' then n := jsonb_set(n, '{guests}', public.rules_fix_times(o -> 'guests', n -> 'guests', nowms)); end if;

    -- 7. inviti: a nome proprio
    a := public.rules_obj(o -> 'invites'); b := public.rules_obj(n -> 'invites');
    for k in select jsonb_object_keys(a) union select jsonb_object_keys(b) loop
      if (a -> k) is distinct from (b -> k) and coalesce(b #>> array[k, 'by'], '') <> me then
        raise exception 'Un invito lo mandi a nome tuo.' using errcode = '42501';
      end if;
    end loop;
  end if;

  new.data := n;
  return new;
end $$;

grant execute on function public.rules_obj(jsonb), public.rules_match_start(jsonb),
  public.rules_next_started(text, text, jsonb), public.rules_fix_times(jsonb, jsonb, bigint) to authenticated;

drop trigger if exists docs_match_rules on public.docs;
create trigger docs_match_rules before insert or update on public.docs
  for each row when (new.col = 'matches') execute function public.match_rules();

select 'Aggiornamento regole completato' as esito,
       (select count(*) from pg_trigger where tgname = 'docs_match_rules') as regole_attive,
       (select count(*) from public.docs where col = 'matches') as partite;
