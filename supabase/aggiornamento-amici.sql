-- ============================================================
-- Algor Bomber · aggiornamento "amici" (29 ottobre 2026)
-- Da incollare nell'SQL Editor di Supabase ed eseguire una volta (Run),
-- dopo aggiornamento-partite.sql. Si può rieseguire senza danni.
-- Non sposta e non cancella nessun dato.
--
-- Cosa fa:
--   1. nuovo tipo di documento: amicizie (friends/{uid1}~{uid2}, i due codici in ordine)
--   2. un'amicizia la vedono solo le due persone coinvolte
--   3. funzioni per chiedere, accettare o rifiutare e togliere un'amicizia
--   4. eliminando un account spariscono anche le sue amicizie
-- (L'affinità tra giocatori la calcola l'app dalle partite giocate: non serve niente qui.)
-- ============================================================

-- 1. i tipi di documento ammessi
alter table public.docs drop constraint if exists docs_col_ok;
alter table public.docs add constraint docs_col_ok check (col in
  ('players', 'ratings', 'mv', 'mvp', 'matches', 'fields', 'groups', 'members', 'chat', 'help', 'friends'));

-- 2. chi può leggere cosa (uguale a prima, con in più le amicizie)
drop policy if exists docs_read on public.docs;
create policy docs_read on public.docs for select to authenticated using (
  case
    when gid is not null then public.is_member(gid) or public.is_app_admin()
    when col = 'players' then public.can_see_player(id)
    when col = 'members' then split_part(id, '~', 2) = auth.uid()::text
                              or public.is_member(split_part(id, '~', 1)) or public.is_app_admin()
    when col = 'help' then split_part(id, '~', 1) = auth.uid()::text or public.is_app_admin()
    when col = 'friends' then split_part(id, '~', 1) = auth.uid()::text or split_part(id, '~', 2) = auth.uid()::text
    else true
  end);

-- 3. amicizie: si scrivono solo con queste funzioni
-- il codice della coppia: i due id in ordine, separati da ~
create or replace function public.friend_key(a text, b text) returns text
language sql immutable as $$ select least(a, b) || '~' || greatest(a, b) $$;

-- chiedere l'amicizia (se l'altro l'aveva già chiesta a te, diventate amici subito).
-- Restituisce 'pending', 'active' o 'self'.
create or replace function public.friend_request(p_uid text) returns text
language plpgsql security definer set search_path = public as $$
declare me text := auth.uid()::text; k text; d jsonb;
begin
  if me is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  if p_uid = me then return 'self'; end if;
  if not exists (select 1 from docs where path = 'players/' || me) then
    raise exception 'Crea prima il tuo profilo.' using errcode = '22023';
  end if;
  if not exists (select 1 from docs where path = 'players/' || p_uid) then
    raise exception 'Questa persona non è più iscritta.' using errcode = '22023';
  end if;
  k := public.friend_key(me, p_uid);
  select data into d from docs where path = 'friends/' || k for update;
  if d is not null then
    if d ->> 'status' = 'pending' and d ->> 'by' = p_uid then
      update docs set data = data || jsonb_build_object('status', 'active', 'at', public.now_ms()) where path = 'friends/' || k;
      return 'active';
    end if;
    return d ->> 'status';
  end if;
  insert into docs (path, col, id, data) values ('friends/' || k, 'friends', k,
    jsonb_build_object('a', split_part(k, '~', 1), 'b', split_part(k, '~', 2), 'by', me, 'status', 'pending', 't', public.now_ms()));
  return 'pending';
end $$;

-- rispondere a una richiesta ricevuta
create or replace function public.friend_respond(p_uid text, p_accept boolean) returns text
language plpgsql security definer set search_path = public as $$
declare me text := auth.uid()::text; k text; d jsonb;
begin
  if me is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  k := public.friend_key(me, p_uid);
  select data into d from docs where path = 'friends/' || k for update;
  if d is null or d ->> 'status' <> 'pending' or d ->> 'by' <> p_uid then
    raise exception 'La richiesta non c''è più.' using errcode = '22023';
  end if;
  if p_accept then
    update docs set data = data || jsonb_build_object('status', 'active', 'at', public.now_ms()) where path = 'friends/' || k;
    return 'active';
  end if;
  delete from docs where path = 'friends/' || k;
  return 'removed';
end $$;

-- togliere un'amicizia o ritirare una richiesta mandata (lo può fare ciascuno dei due)
create or replace function public.friend_remove(p_uid text) returns text
language plpgsql security definer set search_path = public as $$
declare me text := auth.uid()::text;
begin
  if me is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  delete from docs where path = 'friends/' || public.friend_key(me, p_uid);
  return 'removed';
end $$;

-- 4. eliminare un account (come prima, in più toglie le sue amicizie)
create or replace function public.delete_account(p_uid text) returns text
language plpgsql security definer set search_path = public as $$
declare gs text[]; g text; em text; res text := 'ok';
begin
  if not is_app_admin() then
    raise exception 'Solo gli amministratori dell''app possono eliminare un account.' using errcode = '42501';
  end if;
  if p_uid = auth.uid()::text then
    raise exception 'Non puoi eliminare il tuo account da qui.' using errcode = '22023';
  end if;
  select lower(email) into em from auth.users where id::text = p_uid;
  if em is not null and exists (select 1 from app_admins where email = em) then
    raise exception 'Non puoi eliminare un amministratore dell''app.' using errcode = '22023';
  end if;
  select coalesce(array_agg(split_part(id, '~', 1)), '{}') into gs
    from docs where col = 'members' and split_part(id, '~', 2) = p_uid;
  delete from docs where path = 'players/' || p_uid;
  delete from docs where col = 'members' and split_part(id, '~', 2) = p_uid;
  delete from docs where col in ('ratings', 'mvp', 'mv') and id = p_uid;
  update docs set data = jsonb_set(data, '{r}', (data -> 'r') - p_uid)
   where col = 'ratings' and jsonb_typeof(data -> 'r') = 'object' and (data -> 'r') ? p_uid;
  delete from docs where col = 'help' and split_part(id, '~', 1) = p_uid;
  delete from docs where col = 'friends' and (split_part(id, '~', 1) = p_uid or split_part(id, '~', 2) = p_uid);
  begin
    delete from auth.users where id::text = p_uid;
  exception when others then
    res := 'profilo';
  end;
  foreach g in array gs loop perform refresh_group(g); end loop;
  return res;
end $$;

-- l'app vede subito le funzioni nuove
notify pgrst, 'reload schema';

select 'Aggiornamento completato' as esito,
       (select count(*) from public.docs where col = 'players') as iscritti;
