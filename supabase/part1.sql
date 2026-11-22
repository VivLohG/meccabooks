-- MECCA BOOKS database setup — PART 1 of 3 (run parts 1, 2, 3 in order)

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  username   text unique not null,
  full_name  text not null default '',
  is_owner   boolean not null default false,
  active     boolean not null default true,
  perms      jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  last_seen  timestamptz
);

create table if not exists public.invites (
  username   text primary key,
  full_name  text not null default '',
  perms      jsonb not null default '{}'::jsonb,
  is_owner   boolean not null default false,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.docs (
  coll       text not null,
  id         text not null,
  branch     text,
  data       jsonb not null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  primary key (coll, id)
);
create index if not exists docs_coll_idx   on public.docs(coll);
create index if not exists docs_branch_idx on public.docs(branch);

create table if not exists public.audit (
  id      bigserial primary key,
  at      timestamptz not null default now(),
  by      uuid,
  action  text not null,          -- create / edit / delete
  coll    text not null,
  doc_id  text,
  branch  text,
  label   text,
  amount  numeric,
  changed text[]
);
create index if not exists audit_at_idx on public.audit(at desc);

create table if not exists public.counters (
  key text primary key,
  n   bigint not null default 0
);

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id = auth.uid() and active);
$$;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_owner from profiles where id = auth.uid() and active), false);
$$;

create or replace function public.has_perm(k text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_owner or coalesce((perms->>k)::boolean, false)
                   from profiles where id = auth.uid() and active), false);
$$;

create or replace function public.can_branch(b text) returns boolean
language sql stable as $$
  select b is null or public.has_perm('br_' || b);
$$;

create or replace function public.coll_write_ok(c text, is_insert boolean) returns boolean
language sql stable as $$
  select case c
    when 'accounts' then public.has_perm('accounts')
    when 'settings' then public.has_perm('setup')
    when 'items'    then (not is_insert) or public.has_perm('inventory') or public.has_perm('editPrices')
    else true end;
$$;

alter table public.profiles enable row level security;
alter table public.invites  enable row level security;
alter table public.docs     enable row level security;
alter table public.audit    enable row level security;
alter table public.counters enable row level security;

drop policy if exists docs_read   on public.docs;
drop policy if exists docs_insert on public.docs;
drop policy if exists docs_update on public.docs;
drop policy if exists docs_delete on public.docs;
create policy docs_read   on public.docs for select to authenticated
  using (public.is_member() and public.can_branch(branch));
create policy docs_insert on public.docs for insert to authenticated
  with check (public.is_member() and public.can_branch(branch) and public.coll_write_ok(coll, true));
create policy docs_update on public.docs for update to authenticated
  using (public.is_member() and public.can_branch(branch))
  with check (public.is_member() and public.can_branch(branch) and public.coll_write_ok(coll, false));
create policy docs_delete on public.docs for delete to authenticated
  using (public.has_perm('delete') and public.can_branch(branch));

drop policy if exists audit_read on public.audit;
create policy audit_read on public.audit for select to authenticated
  using (public.has_perm('audit'));

drop policy if exists prof_read   on public.profiles;
drop policy if exists prof_update on public.profiles;
create policy prof_read   on public.profiles for select to authenticated
  using (public.is_member() or id = auth.uid());
create policy prof_update on public.profiles for update to authenticated
  using (public.has_perm('users') and not is_owner)
  with check (public.has_perm('users'));
