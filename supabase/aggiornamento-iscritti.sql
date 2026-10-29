-- ============================================================
-- Algor Bomber · aggiornamento "iscritti" (29 ottobre 2026)
-- Da incollare nell'SQL Editor di Supabase ed eseguire una volta (Run),
-- dopo aggiornamento-gruppi.sql. Si può rieseguire senza danni.
-- Non sposta e non cancella nessun dato: cambia solo cosa si vede e aggiunge due funzioni.
--
-- Cosa fa:
--   1. tutti gli iscritti all'app vedono i profili di tutti (nome, foto, ruoli, infortunio)
--   2. stats generali: i voti di tutti i gruppi, senza dire chi li ha dati
--   3. l'amministratore di un gruppo aggiunge direttamente un iscritto al gruppo
-- ============================================================

-- 1. Profili visibili a tutti gli iscritti
create or replace function public.can_see_player(p_uid text) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null;
$$;

-- 2. Voti di tutti i gruppi, anonimi: per ogni coppia (chi vota, chi è votato) conta il voto più recente.
--    Le autovalutazioni stanno nei profili; chi ha dato i singoli voti si vede solo dentro il gruppo.
create or replace function public.global_votes() returns table (target text, vote jsonb)
language sql stable security definer set search_path = public as $$
  select x.target, x.vote
    from (
      select distinct on (d.id, e.key) e.key as target, e.value as vote
        from public.docs d
       cross join lateral jsonb_each(case when jsonb_typeof(d.data -> 'r') = 'object' then d.data -> 'r' else '{}'::jsonb end) e
       where d.col = 'ratings' and d.gid is not null
         and e.key <> d.id and jsonb_typeof(e.value) = 'object'
       order by d.id, e.key,
                case when jsonb_typeof(e.value -> 't') = 'number' then (e.value ->> 't')::numeric else 0 end desc
    ) x
   where auth.uid() is not null;
$$;

-- 3. L'amministratore del gruppo (o dell'app) aggiunge un iscritto: entra subito e può uscire quando vuole.
--    Restituisce 'added', oppure 'active' se era già nel gruppo.
create or replace function public.add_member(p_gid text, p_uid text) returns text
language plpgsql security definer set search_path = public as $$
declare p text := 'members/' || p_gid || '~' || p_uid; st text;
begin
  if not (is_group_admin(p_gid) or is_app_admin()) then
    raise exception 'Solo gli amministratori del gruppo possono aggiungere persone.' using errcode = '42501';
  end if;
  if not exists (select 1 from docs where path = 'groups/' || p_gid) then
    raise exception 'Questo gruppo non esiste più.' using errcode = '22023';
  end if;
  if not exists (select 1 from docs where path = 'players/' || p_uid) then
    raise exception 'Questa persona non ha ancora creato il profilo.' using errcode = '22023';
  end if;
  select data ->> 'status' into st from docs where path = p;
  if st = 'active' then return 'active'; end if;
  if st is not null then
    update docs set data = data || jsonb_build_object('status', 'active', 't', now_ms(), 'by', auth.uid()::text) where path = p;
  else
    insert into docs (path, col, id, data) values (p, 'members', p_gid || '~' || p_uid,
      jsonb_build_object('gid', p_gid, 'uid', p_uid, 'role', 'member', 'status', 'active', 't', now_ms(), 'by', auth.uid()::text));
  end if;
  perform refresh_group(p_gid);
  return 'added';
end $$;

-- l'app vede subito le funzioni nuove
notify pgrst, 'reload schema';

select 'Aggiornamento completato' as esito,
       (select count(*) from public.docs where col = 'players') as iscritti_all_app,
       (select count(*) from public.docs where col = 'groups') as gruppi;
