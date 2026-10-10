-- Slappy Bird leaderboard. Paste this whole file into Supabase: SQL Editor -> New query -> Run.
-- Safe to run again: it only adds what's missing, keeps every score, and replaces the functions.
--
-- One row per player (per device). The table itself is locked: the game can only touch it through
-- the two functions below. A player proves a row is theirs with a random secret their device keeps;
-- only a hash of it is stored here. Names are unique, and the developer's row is flagged.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.players (
  id          uuid primary key,
  secret_hash text not null,
  name        text not null,
  best        int  not null default 0,          -- all-time best
  best_at     timestamptz,
  week        date,                             -- Monday (UTC) of the week week_best belongs to
  week_best   int  not null default 0,
  week_at     timestamptz,
  last_at     timestamptz not null default now(),
  created_at  timestamptz not null default now()
);
alter table public.players add column if not exists dev boolean not null default false;
create index if not exists players_best_idx on public.players (best desc, best_at);
create index if not exists players_week_idx on public.players (week, week_best desc, week_at);

-- No policies = no direct reads or writes through the API; everything goes through the functions.
alter table public.players enable row level security;

-- The developer: the row currently named XDKOKY (the best one, if there are several) gets the flag
-- once. The flag stays with that row even if it's renamed.
update public.players set dev = true
where id = (select id from public.players where name = 'XDKOKY' order by best desc, created_at limit 1)
  and not exists (select 1 from public.players where dev);

-- Unique names: give duplicates (all but the best-scoring one) a number, then enforce it.
with d as (
  select id, name, row_number() over (partition by name order by dev desc, best desc, created_at) as rn
  from public.players
)
update public.players p set name = left(d.name, 12 - length(d.rn::text) - 1) || ' ' || d.rn
from d where p.id = d.id and d.rn > 1;
create unique index if not exists players_name_key on public.players (name);

-- Old versions of the functions (their return types change below).
drop function if exists public.submit_score(uuid, text, text, int);
drop function if exists public.leaderboard(text, uuid);

-- Record a finished run (also used with score 0 to set or change the player's name).
-- Returns the name actually stored: if the requested name is taken (or reserved for the developer)
-- an existing player keeps their old name, and a new player gets the name with a number added.
create function public.submit_score(p_id uuid, p_secret text, p_name text, p_score int)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r    public.players;
  wk   date := date_trunc('week', now() at time zone 'utc')::date;
  nm   text := left(btrim(regexp_replace(regexp_replace(upper(coalesce(p_name, '')), '[^A-Z0-9 ]', '', 'g'), ' +', ' ', 'g')), 12);
  base text;
  i    int := 0;
  ok   boolean;
begin
  if nm = '' then nm := 'PLAYER'; end if;
  if p_score is null or p_score < 0 or p_score > 999 then raise exception 'bad score'; end if;
  if p_secret is null or length(p_secret) < 16 then raise exception 'bad secret'; end if;

  select * into r from public.players where id = p_id for update;
  if found and r.secret_hash <> crypt(p_secret, r.secret_hash) then raise exception 'not your player'; end if;

  -- is the requested name free for this player? (the developer's name and look-alikes are reserved)
  ok := not exists (select 1 from public.players where name = nm and id <> p_id)
        and (coalesce(r.dev, false) or position('XDKOKY' in translate(replace(nm, ' ', ''), '01', 'OI')) = 0);

  if r.id is null then
    if not ok then                                   -- new player: add a number until the name is free
      base := case when position('XDKOKY' in translate(replace(nm, ' ', ''), '01', 'OI')) > 0 then 'PLAYER' else nm end;
      nm := base;
      while exists (select 1 from public.players where name = nm) loop
        i := i + 1; nm := left(base, 12 - length(i::text) - 1) || ' ' || i;
      end loop;
    end if;
    insert into public.players (id, secret_hash, name, best, best_at, week, week_best, week_at)
    values (p_id, crypt(p_secret, gen_salt('bf')), nm, p_score, now(), wk, p_score, now());
    return nm;
  end if;

  if not ok then nm := r.name; end if;               -- taken: keep the current name, still record the score
  if p_score > 0 and now() - r.last_at < interval '2 seconds' then raise exception 'too fast'; end if;

  update public.players set
    name      = nm,
    last_at   = case when p_score > 0 then now() else r.last_at end,
    best      = greatest(r.best, p_score),
    best_at   = case when p_score > r.best then now() else r.best_at end,
    week      = case when p_score > 0 then wk else r.week end,
    week_best = case when p_score = 0 then r.week_best when r.week = wk then greatest(r.week_best, p_score) else p_score end,
    week_at   = case when p_score > 0 and (r.week is distinct from wk or p_score > r.week_best) then now() else r.week_at end
  where id = p_id;
  return nm;
end $$;

-- Top 10 for 'week' (resets Mondays 00:00 UTC) or 'all', plus the asking player's own row.
create function public.leaderboard(p_kind text, p_id uuid default null)
returns table (rank bigint, name text, score int, me boolean, dev boolean)
language sql stable security definer
set search_path = public
as $$
  with b as (
    select id, name, dev,
           case when p_kind = 'week' then week_best else best end as score,
           case when p_kind = 'week' then week_at   else best_at end as at
    from public.players
    where p_kind <> 'week' or week = date_trunc('week', now() at time zone 'utc')::date
  ), r as (
    select id, name, dev, score, rank() over (order by score desc) as rk, row_number() over (order by score desc, at) as rn
    from b where score > 0
  )
  select rk, name, score, coalesce(id = p_id, false), dev from r where rn <= 10 or id = p_id order by rn;
$$;

revoke all on function public.submit_score(uuid, text, text, int) from public;
revoke all on function public.leaderboard(text, uuid) from public;
grant execute on function public.submit_score(uuid, text, text, int) to anon, authenticated;
grant execute on function public.leaderboard(text, uuid) to anon, authenticated;
