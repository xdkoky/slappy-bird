-- Slappy Bird - Copyright (c) 2026 xdkoky. All rights reserved. See LICENSE.
-- ============================================================ friends
-- Friend codes, friend requests (they must be accepted) and a head-to-head race record per pair.
alter table public.players add column if not exists code text;
create unique index if not exists players_code_key on public.players (code);

create table if not exists public.friends (
  a      uuid not null references public.players(id) on delete cascade,   -- the pair, smaller id first
  b      uuid not null references public.players(id) on delete cascade,
  status text not null default 'pending',                                 -- 'pending' or 'ok'
  asked  uuid not null,                                                   -- who sent the request
  wins_a int  not null default 0,
  wins_b int  not null default 0,
  created_at timestamptz not null default now(),
  primary key (a, b),
  check (a < b)
);
alter table public.friends enable row level security;

create or replace function public.auth_player(p_id uuid, p_secret text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.players where id = p_id and secret_hash = crypt(coalesce(p_secret, ''), secret_hash));
$$;

-- this player's friend code (made the first time it's asked for)
create or replace function public.my_code(p_id uuid, p_secret text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare c text; al text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; k int;
begin
  if not public.auth_player(p_id, p_secret) then raise exception 'not your player'; end if;
  select code into c from public.players where id = p_id;
  while c is null loop
    c := ''; for k in 1..5 loop c := c || substr(al, 1 + floor(random() * length(al))::int, 1); end loop;
    if exists (select 1 from public.players where code = c) then c := null;
    else update public.players set code = c where id = p_id; end if;
  end loop;
  return c;
end $$;

-- ask someone (by friend code or exact name). Returns 'sent <id>', 'accepted <id>' (they had asked you),
-- 'already', 'pending', 'self' or 'notfound'.
create or replace function public.friend_request(p_id uuid, p_secret text, p_target text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare t uuid; lo uuid; hi uuid; f public.friends; q text := btrim(regexp_replace(upper(coalesce(p_target, '')), ' +', ' ', 'g'));
begin
  if not public.auth_player(p_id, p_secret) then raise exception 'not your player'; end if;
  select id into t from public.players where code = q;
  if t is null then select id into t from public.players where name = q; end if;
  if t is null then return 'notfound'; end if;
  if t = p_id then return 'self'; end if;
  lo := least(p_id, t); hi := greatest(p_id, t);
  select * into f from public.friends where a = lo and b = hi;
  if not found then insert into public.friends (a, b, asked) values (lo, hi, p_id); return 'sent ' || t; end if;
  if f.status = 'ok' then return 'already'; end if;
  if f.asked <> p_id then update public.friends set status = 'ok' where a = lo and b = hi; return 'accepted ' || t; end if;
  return 'pending';
end $$;

-- accept a request (p_accept), or decline / cancel / unfriend (not p_accept)
create or replace function public.friend_set(p_id uuid, p_secret text, p_other uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.auth_player(p_id, p_secret) then raise exception 'not your player'; end if;
  if p_accept then
    update public.friends set status = 'ok' where a = least(p_id, p_other) and b = greatest(p_id, p_other) and asked = p_other;
  else
    delete from public.friends where a = least(p_id, p_other) and b = greatest(p_id, p_other);
  end if;
end $$;

-- friends and requests: status 'ok', 'in' (they asked you) or 'out' (you asked them)
create or replace function public.friends_list(p_id uuid, p_secret text)
returns table (id uuid, name text, skin text, status text, wins int, losses int)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, p.name, p.skin,
         case when f.status = 'ok' then 'ok' when f.asked = p_id then 'out' else 'in' end,
         case when f.a = p_id then f.wins_a else f.wins_b end,
         case when f.a = p_id then f.wins_b else f.wins_a end
  from public.friends f
  join public.players p on p.id = case when f.a = p_id then f.b else f.a end
  where (f.a = p_id or f.b = p_id) and public.auth_player(p_id, p_secret)
  order by 4, p.name;
$$;

-- the winner of a race between friends records it
create or replace function public.race_won(p_id uuid, p_secret text, p_other uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.auth_player(p_id, p_secret) then raise exception 'not your player'; end if;
  update public.friends set wins_a = wins_a + case when a = p_id then 1 else 0 end,
                            wins_b = wins_b + case when b = p_id then 1 else 0 end
  where a = least(p_id, p_other) and b = greatest(p_id, p_other) and status = 'ok';
end $$;

revoke all on function public.auth_player(uuid, text) from public, anon, authenticated;
revoke all on function public.my_code(uuid, text) from public;
revoke all on function public.friend_request(uuid, text, text) from public;
revoke all on function public.friend_set(uuid, text, uuid, boolean) from public;
revoke all on function public.friends_list(uuid, text) from public;
revoke all on function public.race_won(uuid, text, uuid) from public;
grant execute on function public.my_code(uuid, text) to anon, authenticated;
grant execute on function public.friend_request(uuid, text, text) to anon, authenticated;
grant execute on function public.friend_set(uuid, text, uuid, boolean) to anon, authenticated;
grant execute on function public.friends_list(uuid, text) to anon, authenticated;
grant execute on function public.race_won(uuid, text, uuid) to anon, authenticated;
