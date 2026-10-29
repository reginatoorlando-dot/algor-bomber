-- ============================================================
-- Algor Bomber · aggiornamento "gruppi" (29 ottobre 2026)
-- Da incollare nell'SQL Editor di Supabase e eseguire una volta (Run).
-- Si può rieseguire senza danni.
--
-- Cosa fa:
--   0. salva una copia completa dei dati in backup.docs_20261029
--   1. amministratori dell'app (Orlando e Luca)
--   2. ogni documento sa a quale gruppo appartiene
--   3-4. regole di accesso: chat, partite, statistiche visibili solo ai membri del gruppo
--   5. funzioni per creare gruppi, chiedere di entrare, accettare, togliere membri
--   6. eliminazioni riservate agli amministratori (account, gruppi, partite)
--   7. i dati di oggi diventano il primo gruppo: "Algor Bomber", La Spezia
-- ============================================================

-- 0. Copia di sicurezza, fuori dalla parte del database visibile all'app
create schema if not exists backup;
do $$
begin
  if to_regclass('backup.docs_20261029') is null then
    execute 'create table backup.docs_20261029 as table public.docs';
  end if;
end $$;

-- 1. Amministratori dell'app
create table if not exists public.app_admins (email text primary key);
alter table public.app_admins enable row level security;
drop policy if exists app_admins_read on public.app_admins;
create policy app_admins_read on public.app_admins for select to authenticated using (true);
insert into public.app_admins (email)
  values ('reginatoorlando@gmail.com'), ('lgmtortorelli@gmail.com')
  on conflict do nothing;

create or replace function public.is_app_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_admins where email = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

create or replace function public.now_ms() returns bigint
language sql stable as $$ select (extract(epoch from clock_timestamp()) * 1000)::bigint $$;

-- 2. Cartella (cpath) e gruppo (gid) di ogni documento, calcolati dal percorso.
--    Esempi: players/abc -> cpath "players";  g/g_x/matches/m1 -> cpath "g/g_x/matches", gid "g_x"
alter table public.docs add column if not exists cpath text;
alter table public.docs add column if not exists gid text;

create or replace function public.docs_fill_paths() returns trigger
language plpgsql as $$
begin
  new.cpath := left(new.path, length(new.path) - length(new.id) - 1);
  new.gid := case when new.path like 'g/%' then split_part(new.path, '/', 2) end;
  return new;
end $$;
drop trigger if exists docs_fill_paths on public.docs;
create trigger docs_fill_paths before insert or update on public.docs
  for each row execute function public.docs_fill_paths();

update public.docs set cpath = col where cpath is null;
alter table public.docs alter column cpath set not null;
create index if not exists docs_cpath_idx on public.docs (cpath);
create index if not exists docs_gid_idx on public.docs (gid);

alter table public.docs drop constraint if exists docs_path_ok;
alter table public.docs add constraint docs_path_ok check (
  position('/' in id) = 0
  and path = cpath || '/' || id
  and (cpath = col or (gid is not null and cpath = 'g/' || gid || '/' || col)));
alter table public.docs drop constraint if exists docs_col_ok;
alter table public.docs add constraint docs_col_ok check (col in
  ('players', 'ratings', 'mv', 'mvp', 'matches', 'fields', 'groups', 'members', 'chat', 'help'));

-- 3. Funzioni usate dalle regole
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

-- un profilo lo vede chi è nello stesso gruppo (anche chi ha appena chiesto di entrare)
create or replace function public.can_see_player(p_uid text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_uid = auth.uid()::text or public.is_app_admin() or exists (
    select 1
      from public.docs a
      join public.docs b on b.col = 'members' and split_part(b.id, '~', 1) = split_part(a.id, '~', 1)
     where a.col = 'members'
       and split_part(a.id, '~', 2) = auth.uid()::text
       and a.data ->> 'status' = 'active'
       and split_part(b.id, '~', 2) = p_uid);
$$;

-- 4. Regole di accesso
drop policy if exists docs_read on public.docs;
drop policy if exists docs_insert on public.docs;
drop policy if exists docs_update on public.docs;
drop policy if exists docs_delete on public.docs;
drop policy if exists docs_admin_players on public.docs;

create policy docs_read on public.docs for select to authenticated using (
  case
    when gid is not null then public.is_member(gid) or public.is_app_admin()
    when col = 'players' then public.can_see_player(id)
    when col = 'members' then split_part(id, '~', 2) = auth.uid()::text
                              or public.is_member(split_part(id, '~', 1)) or public.is_app_admin()
    when col = 'help' then split_part(id, '~', 1) = auth.uid()::text or public.is_app_admin()
    else true
  end);

create policy docs_insert on public.docs for insert to authenticated with check (
  case
    when gid is not null then public.is_member(gid) and (
         col = 'matches'
      or (col in ('ratings', 'mvp') and id = auth.uid()::text)
      or (col = 'chat' and split_part(id, '~', 1) = auth.uid()::text and data ->> 'by' = auth.uid()::text))
    when col = 'players' then id = auth.uid()::text
    when col = 'fields' then true
    when col = 'help' then split_part(id, '~', 1) = auth.uid()::text and data ->> 'by' = auth.uid()::text
    else false
  end);

create policy docs_update on public.docs for update to authenticated
  using (
    case
      when gid is not null then public.is_app_admin() or (public.is_member(gid) and (
           col = 'matches' or (col in ('ratings', 'mvp') and id = auth.uid()::text)))
      when col = 'players' then id = auth.uid()::text or public.is_app_admin()
      when col = 'fields' then true
      when col = 'help' then public.is_app_admin()
      else false
    end)
  with check (
    case
      when gid is not null then public.is_app_admin() or (public.is_member(gid) and (
           col = 'matches' or (col in ('ratings', 'mvp') and id = auth.uid()::text)))
      when col = 'players' then id = auth.uid()::text or public.is_app_admin()
      when col = 'fields' then true
      when col = 'help' then public.is_app_admin()
      else false
    end);

create policy docs_delete on public.docs for delete to authenticated using (
  public.is_app_admin()
  or (gid is not null and col = 'chat' and split_part(id, '~', 1) = auth.uid()::text)
  or (gid is null and col = 'players' and id = auth.uid()::text));

-- 5. Gruppi: creazione, richieste, membri
create or replace function public.refresh_group(p_gid text) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  -- se non resta nessun amministratore, lo diventa il membro iscritto da più tempo
  if not exists (select 1 from docs where col = 'members' and split_part(id, '~', 1) = p_gid
                  and data ->> 'status' = 'active' and data ->> 'role' = 'admin') then
    update docs set data = data || jsonb_build_object('role', 'admin')
     where path = (select path from docs
                    where col = 'members' and split_part(id, '~', 1) = p_gid and data ->> 'status' = 'active'
                    order by (data ->> 't')::bigint nulls last, path limit 1);
  end if;
  select count(*) into n from docs
   where col = 'members' and split_part(id, '~', 1) = p_gid and data ->> 'status' = 'active';
  update docs set data = data || jsonb_build_object('n', n) where path = 'groups/' || p_gid;
end $$;
revoke execute on function public.refresh_group(text) from public, anon, authenticated;

create or replace function public.create_group(p_name text, p_city text) returns text
language plpgsql security definer set search_path = public as $$
declare
  me text := auth.uid()::text;
  nm text := btrim(coalesce(p_name, ''));
  ct text := btrim(coalesce(p_city, ''));
  g text;
begin
  if me is null then raise exception 'Devi accedere per creare un gruppo.' using errcode = '42501'; end if;
  if length(nm) < 2 or length(nm) > 40 then raise exception 'Il nome del gruppo deve avere tra 2 e 40 caratteri.' using errcode = '22023'; end if;
  if length(ct) < 2 or length(ct) > 40 then raise exception 'La città deve avere tra 2 e 40 caratteri.' using errcode = '22023'; end if;
  if not exists (select 1 from docs where path = 'players/' || me) then
    raise exception 'Crea prima il tuo profilo.' using errcode = '22023';
  end if;
  g := 'g_' || substr(md5(random()::text || clock_timestamp()::text || me), 1, 10);
  insert into docs (path, col, id, data) values ('groups/' || g, 'groups', g,
    jsonb_build_object('name', nm, 'city', ct, 'by', me, 'created', now_ms(), 'n', 1));
  insert into docs (path, col, id, data) values ('members/' || g || '~' || me, 'members', g || '~' || me,
    jsonb_build_object('gid', g, 'uid', me, 'role', 'admin', 'status', 'active', 't', now_ms()));
  return g;
end $$;

create or replace function public.request_join(p_gid text) returns text
language plpgsql security definer set search_path = public as $$
declare me text := auth.uid()::text; st text;
begin
  if me is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  if not exists (select 1 from docs where path = 'groups/' || p_gid) then
    raise exception 'Questo gruppo non esiste più.' using errcode = '22023';
  end if;
  if not exists (select 1 from docs where path = 'players/' || me) then
    raise exception 'Crea prima il tuo profilo.' using errcode = '22023';
  end if;
  select data ->> 'status' into st from docs where path = 'members/' || p_gid || '~' || me;
  if st is not null then return st; end if;
  insert into docs (path, col, id, data) values ('members/' || p_gid || '~' || me, 'members', p_gid || '~' || me,
    jsonb_build_object('gid', p_gid, 'uid', me, 'role', 'member', 'status', 'pending', 't', now_ms()));
  return 'pending';
end $$;

create or replace function public.decide_request(p_gid text, p_uid text, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare p text := 'members/' || p_gid || '~' || p_uid;
begin
  if not (is_group_admin(p_gid) or is_app_admin()) then
    raise exception 'Solo gli amministratori del gruppo possono decidere sulle richieste.' using errcode = '42501';
  end if;
  if not exists (select 1 from docs where path = p and data ->> 'status' = 'pending') then
    raise exception 'La richiesta non c''è più.' using errcode = '22023';
  end if;
  if p_accept then
    update docs set data = data || jsonb_build_object('status', 'active', 't', now_ms()) where path = p;
  else
    delete from docs where path = p;
  end if;
  perform refresh_group(p_gid);
end $$;

create or replace function public.remove_member(p_gid text, p_uid text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_uid = auth.uid()::text then
    raise exception 'Per uscire dal gruppo usa "Esci dal gruppo".' using errcode = '22023';
  end if;
  if not (is_group_admin(p_gid) or is_app_admin()) then
    raise exception 'Solo gli amministratori del gruppo possono togliere un membro.' using errcode = '42501';
  end if;
  delete from docs where path = 'members/' || p_gid || '~' || p_uid;
  perform refresh_group(p_gid);
end $$;

create or replace function public.set_member_role(p_gid text, p_uid text, p_role text) returns void
language plpgsql security definer set search_path = public as $$
declare p text := 'members/' || p_gid || '~' || p_uid; admins int;
begin
  if p_role not in ('admin', 'member') then raise exception 'Ruolo non valido.' using errcode = '22023'; end if;
  if not (is_group_admin(p_gid) or is_app_admin()) then
    raise exception 'Solo gli amministratori del gruppo possono cambiare i ruoli.' using errcode = '42501';
  end if;
  if not exists (select 1 from docs where path = p and data ->> 'status' = 'active') then
    raise exception 'Questa persona non è nel gruppo.' using errcode = '22023';
  end if;
  select count(*) into admins from docs where col = 'members' and split_part(id, '~', 1) = p_gid
     and data ->> 'status' = 'active' and data ->> 'role' = 'admin';
  if p_role = 'member' and admins <= 1 and exists (select 1 from docs where path = p and data ->> 'role' = 'admin') then
    raise exception 'Il gruppo deve avere almeno un amministratore: nominane prima un altro.' using errcode = '22023';
  end if;
  update docs set data = data || jsonb_build_object('role', p_role) where path = p;
end $$;

create or replace function public.leave_group(p_gid text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  delete from docs where path = 'members/' || p_gid || '~' || auth.uid()::text;
  perform refresh_group(p_gid);
end $$;

-- 6. Eliminazioni: solo gli amministratori dell'app
--    (le partite si eliminano direttamente: la regola docs_delete lo permette solo a loro)
create or replace function public.delete_group(p_gid text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_app_admin() then
    raise exception 'Solo gli amministratori dell''app possono eliminare un gruppo.' using errcode = '42501';
  end if;
  delete from docs where gid = p_gid;
  delete from docs where col = 'members' and split_part(id, '~', 1) = p_gid;
  delete from docs where path = 'groups/' || p_gid;
end $$;

-- restituisce 'ok', oppure 'profilo' se il profilo è stato cancellato ma l'accesso no
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
  begin
    delete from auth.users where id::text = p_uid;
  exception when others then
    res := 'profilo';
  end;
  foreach g in array gs loop perform refresh_group(g); end loop;
  return res;
end $$;

-- 7. I dati di oggi diventano il primo gruppo: "Algor Bomber", La Spezia
do $$
declare g constant text := 'g_algorbomber'; own text;
begin
  select id::text into own from auth.users where lower(email) = 'reginatoorlando@gmail.com' limit 1;
  if not exists (select 1 from public.docs where path = 'groups/' || g) then
    insert into public.docs (path, col, id, data) values ('groups/' || g, 'groups', g,
      jsonb_build_object('name', 'Algor Bomber', 'city', 'La Spezia', 'by', own, 'created', public.now_ms(), 'n', 0));
  end if;
  -- tutti gli iscritti di oggi entrano nel gruppo
  insert into public.docs (path, col, id, data)
  select 'members/' || g || '~' || p.id, 'members', g || '~' || p.id,
         jsonb_build_object('gid', g, 'uid', p.id, 'role', 'member', 'status', 'active', 't', public.now_ms())
    from public.docs p
   where p.col = 'players' and p.gid is null
  on conflict (path) do nothing;
  -- Orlando è l'amministratore del gruppo
  if own is not null then
    insert into public.docs (path, col, id, data)
    values ('members/' || g || '~' || own, 'members', g || '~' || own,
            jsonb_build_object('gid', g, 'uid', own, 'role', 'admin', 'status', 'active', 't', public.now_ms() - 1000))
    on conflict (path) do update set data = public.docs.data || jsonb_build_object('role', 'admin', 'status', 'active');
  end if;
  -- partite, valutazioni e voti MVP passano dentro il gruppo
  insert into public.docs (path, col, id, data, updated_at)
  select 'g/' || g || '/' || d.col || '/' || d.id, d.col, d.id, d.data, d.updated_at
    from public.docs d
   where d.gid is null and d.col in ('matches', 'ratings', 'mvp')
  on conflict (path) do nothing;
  delete from public.docs where gid is null and col in ('matches', 'ratings', 'mvp');
  perform public.refresh_group(g);
end $$;

select 'Aggiornamento completato' as esito,
       (select count(*) from backup.docs_20261029) as documenti_salvati_nella_copia,
       (select data ->> 'n' from public.docs where path = 'groups/g_algorbomber') as membri_del_primo_gruppo;
