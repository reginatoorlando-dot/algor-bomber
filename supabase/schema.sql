-- Algor Bomber: schema del database (Supabase).
-- Da incollare nell'editor SQL di Supabase e eseguire una volta sola.
-- Tutta l'app salva "documenti" in una sola tabella, come l'originale.

create table if not exists public.docs (
  path       text primary key,
  col        text not null,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint docs_path_ok check (path = col || '/' || id),
  constraint docs_col_ok  check (col in ('players', 'ratings', 'mv', 'matches', 'fields')),
  constraint docs_size_ok check (pg_column_size(data) < 262144)
);
create index if not exists docs_col_idx on public.docs (col);
alter table public.docs replica identity full;
alter table public.docs enable row level security;

-- Leggono tutti gli iscritti (i voti non sono anonimi).
drop policy if exists docs_read on public.docs;
create policy docs_read on public.docs for select to authenticated using (true);

-- Partite e campi: li può modificare ogni iscritto.
-- Profili, valutazioni e voti: ognuno scrive solo il proprio (id = id dell'account).
drop policy if exists docs_insert on public.docs;
create policy docs_insert on public.docs for insert to authenticated
  with check (col in ('matches', 'fields') or id = auth.uid()::text);

drop policy if exists docs_update on public.docs;
create policy docs_update on public.docs for update to authenticated
  using      (col in ('matches', 'fields') or id = auth.uid()::text)
  with check (col in ('matches', 'fields') or id = auth.uid()::text);

drop policy if exists docs_delete on public.docs;
create policy docs_delete on public.docs for delete to authenticated
  using (id = auth.uid()::text and col in ('players', 'ratings', 'mv'));

-- Unione "in profondità" di due oggetti JSON (gli array vengono sostituiti).
create or replace function public.jsonb_deep_merge(a jsonb, b jsonb) returns jsonb
language plpgsql immutable as $$
declare k text; r jsonb;
begin
  if jsonb_typeof(a) = 'object' and jsonb_typeof(b) = 'object' then
    r := a;
    for k in select jsonb_object_keys(b) loop
      r := jsonb_set(r, array[k], case when a ? k then public.jsonb_deep_merge(a -> k, b -> k) else b -> k end, true);
    end loop;
    return r;
  end if;
  return b;
end $$;

-- Aggiornamento atomico di un documento che esiste già.
create or replace function public.update_doc(p_path text, p_patch jsonb) returns void
language plpgsql security invoker as $$
begin
  update public.docs
     set data = public.jsonb_deep_merge(data, p_patch), updated_at = now()
   where path = p_path;
  if not found then
    raise exception 'documento non trovato' using errcode = 'P0002';
  end if;
end $$;
grant execute on function public.update_doc(text, jsonb) to authenticated;

-- Aggiornamenti in tempo reale.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'docs') then
    alter publication supabase_realtime add table public.docs;
  end if;
end $$;
