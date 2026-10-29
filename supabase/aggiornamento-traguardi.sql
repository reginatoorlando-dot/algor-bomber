-- Algor Bomber: traguardi di chiunque, dal suo profilo.
-- Da incollare nell'editor SQL di Supabase dopo gli altri aggiornamenti. Si può eseguire più volte.
-- Non modifica né cancella nessun dato: aggiunge solo una funzione di lettura.
--
-- player_career(persona) restituisce, solo per quella persona e in tutti i suoi gruppi, le partite giocate:
-- giorno e ora, com'è finita per la sua squadra, gol subiti, i suoi gol, assist e autogol, se era in porta,
-- i voti MVP presi da lei e il massimo preso nella partita (per sapere se ha vinto il voto), quanti hanno votato.
-- In più: i punti di affinità migliori con un compagno dello stesso gruppo e i giorni delle partite che ha organizzato.
-- Non dice chi sono i compagni, né quali sono i gruppi, né chi ha votato chi.

create or replace function public.player_career(p_uid text) returns jsonb
language sql stable security definer set search_path = public as $$
  with pm as (
    -- le partite giocate in cui c'era
    select d.gid, d.id as mid, d.data as m,
           case when jsonb_typeof(d.data -> 'final' -> 'a') = 'array' and (d.data -> 'final' -> 'a') ? p_uid then 'a'
                when jsonb_typeof(d.data -> 'final' -> 'b') = 'array' and (d.data -> 'final' -> 'b') ? p_uid then 'b' end as side
      from docs d
     where d.col = 'matches' and d.gid is not null
       and d.data ->> 'status' = 'played'
       and jsonb_typeof(d.data -> 'final') = 'object'
       and jsonb_typeof(d.data -> 'final' -> 'ids') = 'array'
       and (d.data -> 'final' -> 'ids') ? p_uid
  ),
  res as (
    select pm.*,
           (coalesce(jsonb_typeof(m -> 'result' -> 'a'), '') = 'number' and coalesce(jsonb_typeof(m -> 'result' -> 'b'), '') = 'number') as hasres,
           case when jsonb_typeof(m -> 'result' -> 'a') = 'number' then (m -> 'result' ->> 'a')::numeric end as ra,
           case when jsonb_typeof(m -> 'result' -> 'b') = 'number' then (m -> 'result' ->> 'b')::numeric end as rb,
           case when jsonb_typeof(m -> 'result' -> 'ev' -> p_uid) = 'object' then m -> 'result' -> 'ev' -> p_uid else '{}'::jsonb end as ev
      from pm
  ),
  votes as (
    -- voti MVP validi delle sue partite: chi vota e chi è votato erano in campo, nessuno vota se stesso
    select r.gid, r.mid, v.data -> 'v' ->> r.mid as target
      from res r
      join docs v on v.col in ('mvp', 'mv') and v.gid = r.gid
     where (r.m -> 'final' -> 'ids') ? v.id
       and jsonb_typeof(v.data -> 'v' -> r.mid) = 'string'
       and (r.m -> 'final' -> 'ids') ? (v.data -> 'v' ->> r.mid)
       and (v.data -> 'v' ->> r.mid) <> v.id
  ),
  vc as (select gid, mid, target, count(*) as n from votes group by gid, mid, target),
  mvp as (
    select r.gid, r.mid,
           coalesce((select sum(n) from vc where vc.gid = r.gid and vc.mid = r.mid and vc.target = p_uid), 0) as my,
           coalesce((select max(n) from vc where vc.gid = r.gid and vc.mid = r.mid), 0) as mx,
           coalesce((select sum(n) from vc where vc.gid = r.gid and vc.mid = r.mid), 0) as nv
      from res r
  ),
  mates as (
    -- compagni nella sua stessa squadra, nelle partite con risultato (gli ospiti non contano)
    select r.gid, t.mate,
           case when (r.side = 'a' and r.ra > r.rb) or (r.side = 'b' and r.rb > r.ra) then 1.0
                when r.ra = r.rb then 0.5 else 0 end as pts
      from res r
      cross join lateral jsonb_array_elements_text(r.m -> 'final' -> r.side) as t(mate)
     where r.hasres and r.side is not null and t.mate <> p_uid
       and not (jsonb_typeof(r.m -> 'final' -> 'gn') = 'object' and (r.m -> 'final' -> 'gn') ? t.mate)
       and not (jsonb_typeof(r.m -> 'guests') = 'object' and (r.m -> 'guests') ? t.mate)
  ),
  aff as (select coalesce(max(p), 0) as best from (select gid, mate, sum(pts) as p from mates group by gid, mate) x),
  org as (
    select coalesce(jsonb_agg(d.data ->> 'date' order by coalesce(d.data ->> 'date', ''), coalesce(d.data ->> 'time', '21:00')), '[]'::jsonb) as days
      from docs d
     where d.col = 'matches' and d.gid is not null and d.data ->> 'status' = 'played' and d.data ->> 'by' = p_uid
  )
  select case when auth.uid() is null then null else jsonb_build_object(
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'd', r.m ->> 'date',
        't', r.m ->> 'time',
        'out', case when not r.hasres or r.side is null then null
                    when (r.side = 'a' and r.ra > r.rb) or (r.side = 'b' and r.rb > r.ra) then 'w'
                    when r.ra = r.rb then 'd' else 'l' end,
        'conc', case when r.hasres and r.side is not null then (case when r.side = 'a' then r.rb else r.ra end) end,
        'g', case when jsonb_typeof(r.ev -> 'g') = 'number' then (r.ev ->> 'g')::numeric else 0 end,
        'a', case when jsonb_typeof(r.ev -> 'a') = 'number' then (r.ev ->> 'a')::numeric else 0 end,
        'og', case when jsonb_typeof(r.ev -> 'og') = 'number' then (r.ev ->> 'og')::numeric else 0 end,
        'gk', coalesce(r.m -> 'final' -> 'roles' ->> p_uid = 'POR', false),
        'my', x.my, 'mx', x.mx, 'nv', x.nv,
        'ne', jsonb_array_length(r.m -> 'final' -> 'ids'),
        'pa', case when jsonb_typeof(r.m -> 'playedAt') = 'number' then (r.m ->> 'playedAt')::numeric else 0 end
      ))
        from res r join mvp x on x.gid = r.gid and x.mid = r.mid), '[]'::jsonb),
    'aff', (select best from aff),
    'org', (select days from org)
  ) end;
$$;

revoke all on function public.player_career(text) from public, anon;
grant execute on function public.player_career(text) to authenticated;

select 'Aggiornamento traguardi completato' as esito;
