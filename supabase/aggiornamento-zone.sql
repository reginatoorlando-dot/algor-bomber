-- ============================================================
-- Algor Bomber · aggiornamento "zone" (29 ottobre 2026)
-- Da eseguire una volta, dopo aggiornamento-iscritti.sql. Si può rieseguire senza danni.
-- Non sposta e non cancella nessun dato.
--
-- Cosa fa:
--   1. i gruppi possono avere il comune scelto dall'elenco, con le coordinate
--      (servono per cercare i gruppi per distanza; la posizione delle persone non viene mai chiesta)
--   2. gli amministratori del gruppo possono cambiarne nome e città
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

-- l'app vede subito le funzioni nuove
notify pgrst, 'reload schema';

select 'Aggiornamento completato' as esito,
       (select count(*) from public.docs where col = 'groups') as gruppi;
