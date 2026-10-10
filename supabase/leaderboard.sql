-- Slappy Bird leaderboard. Paste this whole file into Supabase: SQL Editor -> New query -> Run.
-- Safe to run again (it only creates what's missing and replaces the functions).
--
-- One row per player (per device). The table itself is locked: the game can only touch it through
-- the two functions below. A player proves a row is theirs with a random secret their device keeps;
-- only a hash of it is stored here.

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
create index if not exists players_best_idx on public.players (best desc, best_at);
create index if not exists players_week_idx on public.players (week, week_best desc, week_at);

-- No policies = no direct reads or writes through the API; everything goes through the functions.
alter table public.players enable row level security;

-- Record a finished run (also used with score 0 to set or change the player's name).
create or replace function public.submit_score(p_id uuid, p_secret text, p_name text, p_score int)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r  public.players;
  wk date := date_trunc('week', now() at time zone 'utc')::date;
  nm text := left(btrim(regexp_replace(upper(coalesce(p_name, '')), '[^A-Z0-9 ]', '', 'g')), 12);
begin
  if nm = '' then nm := 'PLAYER'; end if;
  if p_score is null or p_score < 0 or p_score > 999 then raise exception 'bad score'; end if;
  if p_secret is null or length(p_secret) < 16 then raise exception 'bad secret'; end if;

  select * into r from public.players where id = p_id for update;
  if not found then
    insert into public.players (id, secret_hash, name, best, best_at, week, week_best, week_at)
    values (p_id, crypt(p_secret, gen_salt('bf')), nm, p_score, now(), wk, p_score, now());
    return;
  end if;

  if r.secret_hash <> crypt(p_secret, r.secret_hash) then raise exception 'not your player'; end if;
  if now() - r.last_at < interval '2 seconds' then raise exception 'too fast'; end if;

  update public.players set
    name      = nm,
    last_at   = now(),
    best      = greatest(r.best, p_score),
    best_at   = case when p_score > r.best then now() else r.best_at end,
    week      = wk,
    week_best = case when r.week = wk then greatest(r.week_best, p_score) else p_score end,
    week_at   = case when r.week is distinct from wk or p_score > r.week_best then now() else r.week_at end
  where id = p_id;
end $$;

-- Top 10 for 'week' (resets Mondays 00:00 UTC) or 'all', plus the asking player's own row.
create or replace function public.leaderboard(p_kind text, p_id uuid default null)
returns table (rank bigint, name text, score int, me boolean)
language sql stable security definer
set search_path = public
as $$
  with b as (
    select id, name,
           case when p_kind = 'week' then week_best else best end as score,
           case when p_kind = 'week' then week_at   else best_at end as at
    from public.players
    where p_kind <> 'week' or week = date_trunc('week', now() at time zone 'utc')::date
  ), r as (
    select id, name, score, rank() over (order by score desc) as rk, row_number() over (order by score desc, at) as rn
    from b where score > 0
  )
  select rk, name, score, (id = p_id) from r where rn <= 10 or id = p_id order by rn;
$$;

revoke all on function public.submit_score(uuid, text, text, int) from public;
revoke all on function public.leaderboard(text, uuid) from public;
grant execute on function public.submit_score(uuid, text, text, int) to anon, authenticated;
grant execute on function public.leaderboard(text, uuid) to anon, authenticated;
