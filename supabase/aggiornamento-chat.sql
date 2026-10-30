-- ============================================================
-- Algor Bomber · aggiornamento "chat come WhatsApp" (30 ottobre 2026)
-- Da incollare nell'SQL Editor di Supabase ed eseguire una volta (Run),
-- dopo aggiornamento-traguardi.sql. Si può rieseguire senza danni.
-- Non sposta e non cancella nessun dato: i messaggi di prima restano com'erano.
--
-- Cosa fa:
--   1. chat private tra due persone (compagni di gruppo o amici): g/d_{uid1}_{uid2}/chat/...
--      le leggono solo le due persone, nemmeno gli amministratori dell'app
--   2. letture: per ogni chat e persona fin dove ha ricevuto e letto (spunte e non letti)
--   3. funzioni per reazioni, modifica (primi 15 minuti), eliminazione per tutti,
--      letture, silenzia (lo sa solo chi silenzia), elenco delle chat con i non letti
--   4. spazio "chat" per foto e vocali: privato, ogni file lo vede solo chi è nella chat
--   5. "sta scrivendo…": canali privati del tempo reale, solo per chi è nella chat
--   6. notifiche sul telefono: telefoni iscritti, chiavi delle notifiche (le crea da sola
--      la funzione "notify") e avviso alla funzione a ogni messaggio nuovo
--   7. eliminando un account spariscono anche le sue letture, i suoi telefoni e le sue preferenze
--   8. per gli amministratori dell'app: quanto spazio usano foto e vocali
--
-- Se un giorno il progetto Supabase cambia, vanno aggiornati l'indirizzo e la chiave
-- pubblica (anon) nella funzione chat_push, al punto 6.
-- ============================================================

-- 0. funzioni di base
-- numero (millisecondi) da un valore JSON: 0 se manca o non è un numero
create or replace function public.ms_of(v jsonb) returns bigint
language sql immutable as $$
  select case
    when jsonb_typeof(v) = 'number' then floor((v #>> '{}')::numeric)::bigint
    when jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^\d{1,15}$' then (v #>> '{}')::bigint
    else 0
  end;
$$;

-- 1. i tipi di documento ammessi: in più le letture (reads)
alter table public.docs drop constraint if exists docs_col_ok;
alter table public.docs add constraint docs_col_ok check (col in
  ('players', 'ratings', 'mv', 'mvp', 'matches', 'fields', 'groups', 'members', 'chat', 'help', 'friends', 'reads'));

-- le due persone di una chat privata: d_{uid1}_{uid2}, i due codici in ordine
create or replace function public.chat_users(p_chat text) returns text[]
language sql immutable as $$
  select case when p_chat like 'd\_%'
    then array[split_part(substr(p_chat, 3), '_', 1), split_part(substr(p_chat, 3), '_', 2)]
    else null end;
$$;

-- due persone possono scriversi se sono amiche o stanno in uno stesso gruppo
create or replace function public.dm_allowed(p_a text, p_b text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_a <> p_b
     and exists (select 1 from docs where path = 'players/' || p_a)
     and exists (select 1 from docs where path = 'players/' || p_b)
     and (
       exists (select 1 from docs where path = 'friends/' || public.friend_key(p_a, p_b) and data ->> 'status' = 'active')
       or exists (
         select 1
           from docs a
           join docs b on b.col = 'members' and split_part(b.id, '~', 1) = split_part(a.id, '~', 1)
          where a.col = 'members' and split_part(a.id, '~', 2) = p_a and a.data ->> 'status' = 'active'
            and split_part(b.id, '~', 2) = p_b and b.data ->> 'status' = 'active'));
$$;

-- chi legge una chat: i membri del gruppo (e gli amministratori dell'app);
-- una chat privata solo le due persone
create or replace function public.chat_can_read(p_chat text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when p_chat is null or auth.uid() is null then false
    when p_chat like 'd\_%' then auth.uid()::text = any (public.chat_users(p_chat))
    else public.is_member(p_chat) or public.is_app_admin()
  end;
$$;

-- chi scrive in una chat: i membri del gruppo; in privato le due persone,
-- finché sono amiche o compagne di gruppo
create or replace function public.chat_can_write(p_chat text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare me text := auth.uid()::text; u text[];
begin
  if me is null or p_chat is null then return false; end if;
  if p_chat like 'd\_%' then
    u := public.chat_users(p_chat);
    if u[1] = '' or u[2] = '' or u[1] collate "C" >= u[2] collate "C" or p_chat <> 'd_' || u[1] || '_' || u[2] then return false; end if;
    if me = u[1] then return public.dm_allowed(u[1], u[2]); end if;
    if me = u[2] then return public.dm_allowed(u[2], u[1]); end if;
    return false;
  end if;
  return public.is_member(p_chat);
end $$;

grant execute on function public.ms_of(jsonb) to authenticated;
grant execute on function public.chat_users(text) to authenticated;
/* le usano le regole di accesso: servono a chi ha fatto l'accesso, a nessun altro */
revoke execute on function public.chat_can_read(text) from public, anon;
revoke execute on function public.chat_can_write(text) from public, anon;
grant execute on function public.chat_can_read(text) to authenticated;
grant execute on function public.chat_can_write(text) to authenticated;
/* dice se due persone sono amiche o compagne: la usa solo chat_can_write, non si chiama dall'app */
revoke execute on function public.dm_allowed(text, text) from public, anon, authenticated;

-- 2. regole di accesso (uguali a prima, con in più le chat private e le letture)
drop policy if exists docs_read on public.docs;
create policy docs_read on public.docs for select to authenticated using (
  case
    when gid like 'd\_%' then public.chat_can_read(gid)
    when gid is not null then public.is_member(gid) or public.is_app_admin()
    when col = 'players' then public.can_see_player(id)
    when col = 'members' then split_part(id, '~', 2) = auth.uid()::text
                              or public.is_member(split_part(id, '~', 1)) or public.is_app_admin()
    when col = 'help' then split_part(id, '~', 1) = auth.uid()::text or public.is_app_admin()
    when col = 'friends' then split_part(id, '~', 1) = auth.uid()::text or split_part(id, '~', 2) = auth.uid()::text
    else true
  end);

drop policy if exists docs_insert on public.docs;
create policy docs_insert on public.docs for insert to authenticated with check (
  case
    when gid like 'd\_%' then col = 'chat'
      and split_part(id, '~', 1) = auth.uid()::text and data ->> 'by' = auth.uid()::text
      and public.chat_can_write(gid)
    when gid is not null then public.is_member(gid) and (
         col = 'matches'
      or (col in ('ratings', 'mvp') and id = auth.uid()::text)
      or (col = 'chat' and split_part(id, '~', 1) = auth.uid()::text and data ->> 'by' = auth.uid()::text))
    when col = 'players' then id = auth.uid()::text
    when col = 'fields' then true
    when col = 'help' then split_part(id, '~', 1) = auth.uid()::text and data ->> 'by' = auth.uid()::text
    else false
  end);

-- reazioni, modifiche, eliminazioni e letture passano dalle funzioni qui sotto
drop policy if exists docs_update on public.docs;
create policy docs_update on public.docs for update to authenticated
  using (
    case
      when gid like 'd\_%' then false
      when gid is not null then public.is_app_admin() or (public.is_member(gid) and (
           col = 'matches' or (col in ('ratings', 'mvp') and id = auth.uid()::text)))
      when col = 'players' then id = auth.uid()::text or public.is_app_admin()
      when col = 'fields' then true
      when col = 'help' then public.is_app_admin()
      else false
    end)
  with check (
    case
      when gid like 'd\_%' then false
      when gid is not null then public.is_app_admin() or (public.is_member(gid) and (
           col = 'matches' or (col in ('ratings', 'mvp') and id = auth.uid()::text)))
      when col = 'players' then id = auth.uid()::text or public.is_app_admin()
      when col = 'fields' then true
      when col = 'help' then public.is_app_admin()
      else false
    end);

drop policy if exists docs_delete on public.docs;
create policy docs_delete on public.docs for delete to authenticated using (
  (public.is_app_admin() and coalesce(gid, '') not like 'd\_%')
  or (gid is not null and col = 'chat' and split_part(id, '~', 1) = auth.uid()::text)
  or (gid is null and col = 'players' and id = auth.uid()::text));

-- i messaggi nuovi: ora giusta (niente messaggi "dal futuro"), niente reazioni o modifiche
-- scritte a mano, testo al massimo di 4000 caratteri
create or replace function public.chat_clean() returns trigger
language plpgsql set search_path = public as $$
declare n bigint := public.now_ms(); t bigint := public.ms_of(new.data -> 't');
begin
  /* il gruppo (gid) lo calcola un altro trigger: qui si guarda il percorso */
  if new.path not like 'g/%' or jsonb_typeof(new.data) <> 'object' then return new; end if;
  new.data := new.data - 'rx' - 'del' - 'delBy' - 'edit';
  if t = 0 or t > n + 60000 or t < n - 600000 then
    new.data := jsonb_set(new.data, '{t}', to_jsonb(n));
  end if;
  if char_length(coalesce(new.data ->> 'text', '')) > 4000 then
    new.data := jsonb_set(new.data, '{text}', to_jsonb(left(new.data ->> 'text', 4000)));
  end if;
  return new;
end $$;
drop trigger if exists docs_chat_clean on public.docs;
create trigger docs_chat_clean before insert on public.docs
  for each row when (new.col = 'chat') execute function public.chat_clean();

-- 3. funzioni della chat
-- reazione a un messaggio: un'emoji a testa; vuota per toglierla
create or replace function public.chat_react(p_path text, p_emoji text) returns void
language plpgsql security definer set search_path = public as $$
declare me text := auth.uid()::text; d record; e text := btrim(coalesce(p_emoji, ''));
begin
  if me is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  select gid, col, data into d from docs where path = p_path for update;
  if not found or d.col <> 'chat' or d.gid is null then raise exception 'Il messaggio non c''è più.' using errcode = '22023'; end if;
  if not public.chat_can_write(d.gid) then raise exception 'Non puoi reagire in questa chat.' using errcode = '42501'; end if;
  if d.data ? 'del' then raise exception 'Il messaggio è stato eliminato.' using errcode = '22023'; end if;
  if char_length(e) > 16 then raise exception 'Reazione non valida.' using errcode = '22023'; end if;
  if e = '' then
    update docs set data = data #- array['rx', me], updated_at = now() where path = p_path;
  else
    update docs set data = jsonb_set(data, '{rx}',
        (case when jsonb_typeof(data -> 'rx') = 'object' then data -> 'rx' else '{}'::jsonb end) || jsonb_build_object(me, e)),
      updated_at = now()
     where path = p_path;
  end if;
end $$;

-- modifica del testo di un proprio messaggio, nei primi 15 minuti
create or replace function public.chat_edit(p_path text, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare me text := auth.uid()::text; d record; t text := btrim(coalesce(p_text, '')); n bigint := public.now_ms();
begin
  if me is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  select gid, col, data into d from docs where path = p_path for update;
  if not found or d.col <> 'chat' or d.gid is null then raise exception 'Il messaggio non c''è più.' using errcode = '22023'; end if;
  if d.data ->> 'by' is distinct from me then raise exception 'Puoi modificare solo i tuoi messaggi.' using errcode = '42501'; end if;
  if d.data ? 'del' then raise exception 'Il messaggio è stato eliminato.' using errcode = '22023'; end if;
  if not public.chat_can_write(d.gid) then raise exception 'Non puoi più scrivere in questa chat.' using errcode = '42501'; end if;
  if n - public.ms_of(d.data -> 't') > 16 * 60000 then
    raise exception 'Un messaggio si può modificare solo nei primi 15 minuti.' using errcode = '22023';
  end if;
  if d.data ? 'voice' or d.data ? 'gif' then raise exception 'Questo messaggio non si può modificare.' using errcode = '22023'; end if;
  if t = '' and not (d.data ? 'media') then raise exception 'Il messaggio non può restare vuoto.' using errcode = '22023'; end if;
  update docs set data = jsonb_set(jsonb_set(data, '{text}', to_jsonb(left(t, 4000))), '{edit}', to_jsonb(n)), updated_at = now()
   where path = p_path;
end $$;

-- eliminazione per tutti: un proprio messaggio, oppure (nei gruppi) gli amministratori del gruppo
-- e dell'app. Resta "Messaggio eliminato"; restituisce i file da togliere dallo spazio della chat.
create or replace function public.chat_delete(p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me text := auth.uid()::text; d record; files jsonb := '[]'::jsonb;
begin
  if me is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  select gid, col, data into d from docs where path = p_path for update;
  if not found or d.col <> 'chat' or d.gid is null then raise exception 'Il messaggio non c''è più.' using errcode = '22023'; end if;
  if d.data ? 'del' then return files; end if;
  if not (d.data ->> 'by' = me
          or (d.gid not like 'd\_%' and (public.is_group_admin(d.gid) or public.is_app_admin()))) then
    raise exception 'Puoi eliminare per tutti solo i tuoi messaggi.' using errcode = '42501';
  end if;
  if jsonb_typeof(d.data -> 'media') = 'array' then
    select coalesce(jsonb_agg(x ->> 'p'), '[]'::jsonb) into files
      from jsonb_array_elements(d.data -> 'media') x where x ->> 'p' is not null;
  end if;
  if d.data -> 'voice' ->> 'p' is not null then files := files || jsonb_build_array(d.data -> 'voice' ->> 'p'); end if;
  update docs set data = jsonb_build_object('by', d.data -> 'by', 't', d.data -> 't', 'del', public.now_ms(), 'delBy', me),
                  updated_at = now()
   where path = p_path;
  return files;
end $$;

-- letture: fin dove ognuno ha ricevuto (d) e letto (r) in ogni chat. Non tornano mai indietro.
-- p_marks: [{"c": "g_abc", "r": 1730000000000, "d": 1730000000000}, ...]
create or replace function public.chat_seen(p_marks jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me text := auth.uid()::text; x jsonb; c text; r bigint; dv bigint; n bigint := public.now_ms(); p text;
begin
  if me is null then return; end if;
  for x in select value from jsonb_array_elements(case when jsonb_typeof(p_marks) = 'array' then p_marks else '[]'::jsonb end) loop
    c := x ->> 'c';
    if c is null or c = '' or position('/' in c) > 0 or not public.chat_can_read(c) then continue; end if;
    r := least(public.ms_of(x -> 'r'), n + 60000);
    dv := greatest(least(public.ms_of(x -> 'd'), n + 60000), r);
    if r = 0 and dv = 0 then continue; end if;
    p := 'g/' || c || '/reads/' || me;
    insert into docs (path, col, id, data) values (p, 'reads', me, jsonb_build_object('r', r, 'd', dv, 't', n))
    on conflict (path) do update set
      data = (docs.data - 'mute') || jsonb_build_object(
        'r', greatest(public.ms_of(docs.data -> 'r'), public.ms_of(excluded.data -> 'r')),
        'd', greatest(public.ms_of(docs.data -> 'd'), public.ms_of(excluded.data -> 'd')),
        't', n),
      updated_at = now()
    where public.ms_of(excluded.data -> 'r') > public.ms_of(docs.data -> 'r')
       or public.ms_of(excluded.data -> 'd') > public.ms_of(docs.data -> 'd');
  end loop;
end $$;

-- le chat silenziate: le vede solo chi le ha silenziate (e la funzione delle notifiche)
create table if not exists public.chat_prefs (
  uid  uuid not null references auth.users (id) on delete cascade,
  chat text not null,
  mute boolean not null default false,
  t    timestamptz not null default now(),
  primary key (uid, chat)
);
alter table public.chat_prefs enable row level security;
revoke all on public.chat_prefs from anon, authenticated;

-- silenzia (o riattiva) le notifiche di una chat
create or replace function public.chat_mute(p_chat text, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  if p_chat is null or position('/' in p_chat) > 0 or not public.chat_can_read(p_chat) then
    raise exception 'Questa chat non è tua.' using errcode = '42501';
  end if;
  insert into chat_prefs (uid, chat, mute) values (auth.uid(), p_chat, coalesce(p_on, false))
  on conflict (uid, chat) do update set mute = excluded.mute, t = now();
end $$;

-- le chat di chi chiama: i suoi gruppi e le sue chat private, con l'ultimo messaggio e i non letti
create or replace function public.chat_inbox() returns jsonb
language sql stable security definer set search_path = public as $$
  with me as (select auth.uid()::text as u),
  chats as (
    select split_part(m.id, '~', 1) as chat, public.ms_of(m.data -> 't') as since
      from docs m, me
     where m.col = 'members' and split_part(m.id, '~', 2) = me.u and m.data ->> 'status' = 'active'
    union
    select distinct d.gid, 0::bigint
      from docs d, me
     where d.col = 'chat' and d.gid like 'd\_%' and me.u = any (public.chat_users(d.gid))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'chat', c.chat,
      'last', case when l.data is null then null else jsonb_strip_nulls(jsonb_build_object(
          'id', l.id, 'by', l.data -> 'by', 't', l.data -> 't', 'text', left(l.data ->> 'text', 160),
          'n', case when jsonb_typeof(l.data -> 'media') = 'array' then jsonb_array_length(l.data -> 'media') end,
          'gif', l.data -> 'gif' -> 'k', 'voice', l.data -> 'voice' -> 'd',
          'del', l.data -> 'del')) end,
      'unread', (select count(*) from docs x
                  where x.cpath = 'g/' || c.chat || '/chat'
                    and x.data ->> 'by' is distinct from (select u from me)
                    and not (x.data ? 'del')
                    and public.ms_of(x.data -> 't') > greatest(public.ms_of(r.data -> 'r'), c.since)),
      'r', public.ms_of(r.data -> 'r'),
      'd', public.ms_of(r.data -> 'd'),
      'mute', coalesce(pf.mute, false),
      /* le spunte del mio ultimo messaggio: letto da tutti, arrivato a tutti o solo inviato */
      'lt', case when l.data ->> 'by' = (select u from me) and not (l.data ? 'del') then (
        select case
          when count(*) = 0 then 'sent'
          when bool_and(public.ms_of(rr.data -> 'r') >= public.ms_of(l.data -> 't')) then 'read'
          when bool_and(greatest(public.ms_of(rr.data -> 'd'), public.ms_of(rr.data -> 'r')) >= public.ms_of(l.data -> 't')) then 'delivered'
          else 'sent' end
        from (
          select o.u from unnest(public.chat_users(c.chat)) o(u)
           where c.chat like 'd\_%' and o.u <> (select u from me)
          union all
          select split_part(mm.id, '~', 2) from docs mm
           where c.chat not like 'd\_%' and mm.col = 'members' and split_part(mm.id, '~', 1) = c.chat
             and mm.data ->> 'status' = 'active' and split_part(mm.id, '~', 2) <> (select u from me)
             and public.ms_of(mm.data -> 't') <= public.ms_of(l.data -> 't') + 60000) rec
        left join docs rr on rr.path = 'g/' || c.chat || '/reads/' || rec.u) end)), '[]'::jsonb)
  from chats c
  left join lateral (
    select x.id, x.data from docs x
     where x.cpath = 'g/' || c.chat || '/chat'
     order by public.ms_of(x.data -> 't') desc
     limit 1) l on true
  left join docs r on r.path = 'g/' || c.chat || '/reads/' || (select u from me)
  left join chat_prefs pf on pf.uid::text = (select u from me) and pf.chat = c.chat;
$$;

revoke execute on function public.chat_react(text, text) from public, anon;
revoke execute on function public.chat_edit(text, text) from public, anon;
revoke execute on function public.chat_delete(text) from public, anon;
revoke execute on function public.chat_seen(jsonb) from public, anon;
revoke execute on function public.chat_mute(text, boolean) from public, anon;
revoke execute on function public.chat_inbox() from public, anon;
grant execute on function public.chat_react(text, text) to authenticated;
grant execute on function public.chat_edit(text, text) to authenticated;
grant execute on function public.chat_delete(text) to authenticated;
grant execute on function public.chat_seen(jsonb) to authenticated;
grant execute on function public.chat_mute(text, boolean) to authenticated;
grant execute on function public.chat_inbox() to authenticated;

-- 4. spazio "chat" per foto e vocali: {chat}/{chi lo manda}/{file}
--    privato; al massimo 10 MB a file (le foto l'app le riduce prima, a circa 300 KB)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat', 'chat', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp', 'image/gif',
              'audio/mp4', 'audio/aac', 'audio/x-m4a', 'audio/mpeg', 'audio/webm', 'audio/ogg'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists chat_files_read on storage.objects;
create policy chat_files_read on storage.objects for select to authenticated using (
  bucket_id = 'chat' and public.chat_can_read((storage.foldername(name))[1]));

drop policy if exists chat_files_insert on storage.objects;
create policy chat_files_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'chat'
  and (storage.foldername(name))[2] = auth.uid()::text
  and public.chat_can_write((storage.foldername(name))[1]));

-- toglie i file chi li ha mandati; nei gruppi anche gli amministratori del gruppo e dell'app
drop policy if exists chat_files_delete on storage.objects;
create policy chat_files_delete on storage.objects for delete to authenticated using (
  bucket_id = 'chat' and (
    (storage.foldername(name))[2] = auth.uid()::text
    or ((storage.foldername(name))[1] not like 'd\_%'
        and (public.is_group_admin((storage.foldername(name))[1]) or public.is_app_admin()))));

-- 5. "sta scrivendo…": canali privati chat:{chat}, solo per chi può leggere la chat
drop policy if exists chat_rt_read on realtime.messages;
create policy chat_rt_read on realtime.messages for select to authenticated using (
  realtime.messages.extension in ('broadcast', 'presence')
  and (select realtime.topic()) like 'chat:%'
  and public.chat_can_read(substr((select realtime.topic()), 6)));

drop policy if exists chat_rt_write on realtime.messages;
create policy chat_rt_write on realtime.messages for insert to authenticated with check (
  realtime.messages.extension in ('broadcast', 'presence')
  and (select realtime.topic()) like 'chat:%'
  and public.chat_can_read(substr((select realtime.topic()), 6)));

-- 6. notifiche sul telefono
-- i telefoni iscritti (li legge solo la funzione "notify", con la chiave di servizio)
create table if not exists public.push_subs (
  endpoint   text primary key,
  uid        uuid not null references auth.users (id) on delete cascade,
  p256dh     text not null,
  auth       text not null,
  ua         text,
  created_at timestamptz not null default now(),
  last_ok    timestamptz
);
create index if not exists push_subs_uid_idx on public.push_subs (uid);
alter table public.push_subs enable row level security;
revoke all on public.push_subs from anon, authenticated;

-- messaggi già avvisati: ogni messaggio manda una notifica sola
create table if not exists public.push_sent (path text primary key, t timestamptz not null default now());
alter table public.push_sent enable row level security;
revoke all on public.push_sent from anon, authenticated;

-- le chiavi delle notifiche (VAPID): le crea la funzione "notify" la prima volta.
-- Quella privata non esce mai dal database e dalla funzione.
create table if not exists public.push_keys (
  id         integer primary key default 1 check (id = 1),
  pub        text not null,
  jwk        jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.push_keys enable row level security;
revoke all on public.push_keys from anon, authenticated;

-- la chiave pubblica, per iscrivere il telefono
create or replace function public.push_public_key() returns text
language sql stable security definer set search_path = public as $$
  select pub from push_keys where id = 1;
$$;

create or replace function public.push_register(p_endpoint text, p_p256dh text, p_auth text, p_ua text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Devi accedere.' using errcode = '42501'; end if;
  if coalesce(p_endpoint, '') !~ '^https://' or length(p_endpoint) > 1000
     or coalesce(p_p256dh, '') = '' or coalesce(p_auth, '') = '' or length(p_p256dh) > 200 or length(p_auth) > 100 then
    raise exception 'Iscrizione alle notifiche non valida.' using errcode = '22023';
  end if;
  insert into push_subs (endpoint, uid, p256dh, auth, ua)
  values (p_endpoint, auth.uid(), p_p256dh, p_auth, left(p_ua, 200))
  on conflict (endpoint) do update set uid = excluded.uid, p256dh = excluded.p256dh, auth = excluded.auth,
    ua = excluded.ua, created_at = now();
end $$;

create or replace function public.push_unregister(p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from push_subs where endpoint = p_endpoint and uid = auth.uid();
$$;

-- quanti telefoni di chi chiama ricevono le notifiche
create or replace function public.push_devices() returns integer
language sql stable security definer set search_path = public as $$
  select count(*)::integer from push_subs where uid = auth.uid();
$$;

revoke execute on function public.push_public_key() from public, anon;
revoke execute on function public.push_register(text, text, text, text) from public, anon;
revoke execute on function public.push_unregister(text) from public, anon;
revoke execute on function public.push_devices() from public, anon;
grant execute on function public.push_public_key() to authenticated;
grant execute on function public.push_register(text, text, text, text) to authenticated;
grant execute on function public.push_unregister(text) to authenticated;
grant execute on function public.push_devices() to authenticated;

-- per la funzione "notify": le chiavi (lette o salvate la prima volta)
create or replace function public.push_keys_get() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('pub', pub, 'jwk', jwk) from push_keys where id = 1;
$$;
create or replace function public.push_keys_put(p_pub text, p_jwk jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_pub, '') = '' or jsonb_typeof(p_jwk) <> 'object' then
    raise exception 'chiavi non valide' using errcode = '22023';
  end if;
  insert into push_keys (id, pub, jwk) values (1, p_pub, p_jwk) on conflict (id) do nothing;
  /* se due chiamate arrivano insieme vince la prima: tutte usano quella salvata */
  return (select jsonb_build_object('pub', pub, 'jwk', jwk) from push_keys where id = 1);
end $$;

-- per la funzione "notify": chi avvisare per un messaggio nuovo e cosa scrivere.
-- Una volta sola per messaggio, solo nei primi 10 minuti; chi ha silenziato la chat
-- non riceve niente, a meno che non sia stato menzionato con @.
create or replace function public.push_targets(p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  d record; who text; v_chat text; others text[]; sender text; gname text; prev text; title text; body text; subs jsonb;
begin
  select gid, col, data into d from docs where path = p_path;
  if not found or d.col <> 'chat' or d.gid is null or d.data ? 'del' then return null; end if;
  if public.now_ms() - public.ms_of(d.data -> 't') > 10 * 60000 then return null; end if;
  insert into push_sent (path) values (p_path) on conflict do nothing;
  if not found then return null; end if;
  delete from push_sent where t < now() - interval '3 days';
  who := d.data ->> 'by';
  v_chat := d.gid;
  if v_chat like 'd\_%' then
    others := array_remove(public.chat_users(v_chat), who);
  else
    select coalesce(array_agg(split_part(id, '~', 2)), '{}') into others
      from docs where col = 'members' and split_part(id, '~', 1) = v_chat and data ->> 'status' = 'active'
       and split_part(id, '~', 2) <> who;
    select data ->> 'name' into gname from docs where path = 'groups/' || v_chat;
  end if;
  -- chi ha silenziato la chat (tranne se menzionato)
  select coalesce(array_agg(o), '{}') into others
    from unnest(others) o
   where not exists (select 1 from chat_prefs pf where pf.uid::text = o and pf.chat = v_chat and pf.mute)
      or (jsonb_typeof(d.data -> 'ment') = 'array' and d.data -> 'ment' ? o);
  if coalesce(array_length(others, 1), 0) = 0 then return null; end if;
  select coalesce(nullif(data ->> 'nick', ''), nullif(data ->> 'first', ''), 'Qualcuno') into sender from docs where path = 'players/' || who;
  sender := coalesce(sender, 'Qualcuno');
  prev := nullif(btrim(left(coalesce(d.data ->> 'text', ''), 140)), '');
  if prev is null then
    prev := case
      when jsonb_typeof(d.data -> 'media') = 'array' and jsonb_array_length(d.data -> 'media') > 1 then '📷 ' || jsonb_array_length(d.data -> 'media') || ' foto'
      when jsonb_typeof(d.data -> 'media') = 'array' then '📷 Foto'
      when d.data ? 'voice' then '🎤 Messaggio vocale'
      when d.data -> 'gif' ->> 'k' = 'stk' then 'Sticker'
      when d.data ? 'gif' then 'GIF'
      else 'Nuovo messaggio' end;
  elsif jsonb_typeof(d.data -> 'media') = 'array' then
    prev := '📷 ' || prev;
  end if;
  if v_chat like 'd\_%' then title := sender; body := prev;
  else title := coalesce(gname, 'Gruppo'); body := sender || ': ' || prev; end if;
  select jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)) into subs
    from push_subs s where s.uid::text = any (others);
  if subs is null then return null; end if;
  return jsonb_build_object('title', title, 'body', body, 'tag', 'chat-' || v_chat,
    'url', './?chat=' || v_chat, 't', public.ms_of(d.data -> 't'), 'subs', subs);
end $$;

-- telefoni che non esistono più (il servizio delle notifiche risponde 404 o 410)
create or replace function public.push_gone(p_endpoints text[]) returns void
language sql security definer set search_path = public as $$
  delete from push_subs where endpoint = any (p_endpoints);
$$;
create or replace function public.push_ok(p_endpoints text[]) returns void
language sql security definer set search_path = public as $$
  update push_subs set last_ok = now() where endpoint = any (p_endpoints);
$$;
revoke execute on function public.push_keys_get() from public, anon, authenticated;
revoke execute on function public.push_keys_put(text, jsonb) from public, anon, authenticated;
revoke execute on function public.push_targets(text) from public, anon, authenticated;
revoke execute on function public.push_gone(text[]) from public, anon, authenticated;
revoke execute on function public.push_ok(text[]) from public, anon, authenticated;
grant execute on function public.push_keys_get() to service_role;
grant execute on function public.push_keys_put(text, jsonb) to service_role;
grant execute on function public.push_targets(text) to service_role;
grant execute on function public.push_gone(text[]) to service_role;
grant execute on function public.push_ok(text[]) to service_role;

-- a ogni messaggio nuovo il database avvisa la funzione "notify" (che manda le notifiche).
-- Parte solo se almeno un telefono ha attivato le notifiche; un errore qui non blocca mai il messaggio.
create extension if not exists pg_net;

create or replace function public.chat_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp0aGZ0dnNlaGVhem1vcmN2d25vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyMDc3MDcsImV4cCI6MjEwODc4MzcwN30.32Zq6ydtqrwohlrpHL35RE8-_6AEIT7_nmuDtW4yRSI';
begin
  if new.gid is not null and exists (select 1 from public.push_subs limit 1) then
    perform net.http_post(
      url := 'https://zthftvseheazmorcvwno.supabase.co/functions/v1/notify',
      body := jsonb_build_object('path', new.path),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', k, 'Authorization', 'Bearer ' || k),
      timeout_milliseconds := 20000);
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke execute on function public.chat_push() from public, anon, authenticated;
drop trigger if exists docs_chat_push on public.docs;
create trigger docs_chat_push after insert on public.docs
  for each row when (new.col = 'chat') execute function public.chat_push();

-- 7. eliminando un account spariscono anche le sue letture, i suoi telefoni e le sue preferenze
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
  delete from docs where col = 'reads' and id = p_uid;
  delete from push_subs where uid::text = p_uid;
  delete from chat_prefs where uid::text = p_uid;
  begin
    delete from auth.users where id::text = p_uid;
  exception when others then
    res := 'profilo';
  end;
  foreach g in array gs loop perform refresh_group(g); end loop;
  return res;
end $$;

-- 8. per gli amministratori dell'app: quanti file e quanto spazio usano foto e vocali
create or replace function public.chat_space() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_app_admin() then
    raise exception 'Solo gli amministratori dell''app.' using errcode = '42501';
  end if;
  return (select jsonb_build_object('files', count(*), 'bytes', coalesce(sum(public.ms_of(o.metadata -> 'size')), 0))
            from storage.objects o where o.bucket_id = 'chat');
end $$;
revoke execute on function public.chat_space() from public, anon;
grant execute on function public.chat_space() to authenticated;

-- l'app vede subito le funzioni nuove
notify pgrst, 'reload schema';

select 'Aggiornamento chat completato' as esito,
       (select count(*) from public.docs where col = 'chat') as messaggi,
       (select count(*) from storage.buckets where id = 'chat') as spazio_chat;
