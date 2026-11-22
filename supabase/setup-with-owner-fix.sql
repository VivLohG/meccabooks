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

drop policy if exists inv_all on public.invites;
create policy inv_all on public.invites for all to authenticated
  using (public.has_perm('users'))
  with check (public.has_perm('users') and (not is_owner or public.is_owner()));

create or replace function public.docs_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid(); new.created_at := now();
  else
    new.created_by := old.created_by; new.created_at := old.created_at;
  end if;
  new.updated_by := auth.uid(); new.updated_at := now();
  return new;
end $$;
drop trigger if exists docs_stamp on public.docs;
create trigger docs_stamp before insert or update on public.docs
  for each row execute function public.docs_stamp();

create or replace function public.guard_items() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.coll = 'items' and (
       (new.data->'prices') is distinct from (old.data->'prices') or
       (new.data->'pcts')   is distinct from (old.data->'pcts')   or
       (new.data->'cost')   is distinct from (old.data->'cost')   or
       (new.data->'price')  is distinct from (old.data->'price')) then
    if not public.has_perm('editPrices') then
      raise exception 'You do not have the right to change prices or costs';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists guard_items on public.docs;
create trigger guard_items before update on public.docs
  for each row execute function public.guard_items();

create or replace function public.audit_label(d jsonb) returns text
language sql immutable as $$
  select left(coalesce(
    case when d ? 'no' and (d ? 'name' or d ? 'memo') then (d->>'no') || ' · ' || coalesce(d->>'name', d->>'memo') end,
    case when coalesce(d->>'ref','') <> '' and d ? 'memo' then (d->>'ref') || ' · ' || (d->>'memo') end,
    d->>'no', d->>'ref', d->>'name', d->>'memo', d->>'desc', d->>'kw', d->>'code', d->>'date', ''), 120);
$$;

create or replace function public.audit_amount(d jsonb) returns numeric
language plpgsql immutable as $$
declare k text; v numeric;
begin
  if d is null then return null; end if;
  foreach k in array array['total','amount','value','counted'] loop
    if d ? k and jsonb_typeof(d->k) = 'number' then return (d->>k)::numeric; end if;
  end loop;
  if jsonb_typeof(d->'lines') = 'array' then
    select sum(coalesce((l->>'debit')::numeric, 0)) into v from jsonb_array_elements(d->'lines') l
     where jsonb_typeof(l->'debit') = 'number';
    return v;
  end if;
  return null;
end $$;

create or replace function public.docs_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare ch text[];
begin
  if tg_op = 'INSERT' then
    insert into audit(by, action, coll, doc_id, branch, label, amount)
    values (auth.uid(), 'create', new.coll, new.id, new.branch, audit_label(new.data), audit_amount(new.data));
  elsif tg_op = 'UPDATE' then
    select array_agg(k order by k) into ch from (
      select k from jsonb_object_keys(new.data || old.data) k
      where k not in ('_by','_at','_createdBy','_createdAt','id')
        and (new.data->k) is distinct from (old.data->k)) x;
    if ch is null then return new; end if;               -- nothing really changed
    insert into audit(by, action, coll, doc_id, branch, label, amount, changed)
    values (auth.uid(), 'edit', new.coll, new.id, new.branch, audit_label(new.data), audit_amount(new.data), ch[1:8]);
  else
    insert into audit(by, action, coll, doc_id, branch, label, amount)
    values (auth.uid(), 'delete', old.coll, old.id, old.branch, audit_label(old.data), audit_amount(old.data));
    return old;
  end if;
  return new;
end $$;
drop trigger if exists docs_audit on public.docs;
create trigger docs_audit after insert or update or delete on public.docs
  for each row execute function public.docs_audit();

create or replace function public.guard_profiles() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.is_owner is distinct from old.is_owner then raise exception 'The owner flag cannot be changed here'; end if;
  if new.username is distinct from old.username then raise exception 'Usernames cannot be changed'; end if;
  if new.id = auth.uid() and not old.is_owner and
     (new.perms is distinct from old.perms or new.active is distinct from old.active) then
    raise exception 'You cannot change your own access';
  end if;
  return new;
end $$;
drop trigger if exists guard_profiles on public.profiles;
create trigger guard_profiles before update on public.profiles
  for each row execute function public.guard_profiles();

create or replace function public.profiles_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.perms is distinct from old.perms or new.active is distinct from old.active or new.full_name is distinct from old.full_name then
    insert into audit(by, action, coll, doc_id, label, changed)
    values (auth.uid(), 'edit', 'access', new.id::text, new.full_name || ' (' || new.username || ')',
            array_remove(array[
              case when new.perms     is distinct from old.perms     then 'access ticks' end,
              case when new.active    is distinct from old.active    then case when new.active then 'login enabled' else 'login disabled' end end,
              case when new.full_name is distinct from old.full_name then 'name' end], null));
  end if;
  return new;
end $$;
drop trigger if exists profiles_audit on public.profiles;
create trigger profiles_audit after update on public.profiles
  for each row execute function public.profiles_audit();

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare uname text := lower(split_part(new.email, '@', 1)); inv invites;
begin
  select * into inv from invites where username = uname;
  if not found then
    raise exception 'Sign-up is by invitation only (no invite for %)', uname;
  end if;
  insert into profiles(id, username, full_name, is_owner, perms)
  values (new.id, uname, coalesce(nullif(inv.full_name, ''), new.raw_user_meta_data->>'full_name', uname), inv.is_owner, inv.perms);
  insert into audit(by, action, coll, doc_id, label)
  values (coalesce(inv.created_by, new.id), 'create', 'access', new.id::text, coalesce(nullif(inv.full_name,''), uname) || ' (' || uname || ')');
  delete from invites where username = uname;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.next_no(k text) returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if not public.is_member() then raise exception 'Not allowed'; end if;
  insert into counters(key, n) values (k, 1)
  on conflict (key) do update set n = counters.n + 1
  returning n into v;
  return v;
end $$;

create or replace function public.touch() returns void
language sql security definer set search_path = public as $$
  update profiles set last_seen = now() where id = auth.uid();
$$;

create or replace function public.reset_password(target uuid, new_password text) returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if not public.has_perm('users') then raise exception 'Not allowed'; end if;
  if exists(select 1 from profiles where id = target and is_owner) then raise exception 'The owner password cannot be reset here'; end if;
  if length(coalesce(new_password, '')) < 6 then raise exception 'Password must be at least 6 characters'; end if;
  update auth.users set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')), updated_at = now()
   where id = target;
  insert into audit(by, action, coll, doc_id, label, changed)
  select auth.uid(), 'edit', 'access', target::text, full_name || ' (' || username || ')', array['password reset']
    from profiles where id = target;
end $$;

revoke all on function public.reset_password(uuid, text) from public, anon;
grant execute on function public.reset_password(uuid, text) to authenticated;
revoke all on function public.next_no(text) from public, anon;
grant execute on function public.next_no(text) to authenticated;
revoke all on function public.touch() from public, anon;
grant execute on function public.touch() to authenticated;

insert into storage.buckets (id, name, public) values ('invoices', 'invoices', false)
on conflict (id) do nothing;

drop policy if exists inv_files_read   on storage.objects;
drop policy if exists inv_files_insert on storage.objects;
drop policy if exists inv_files_delete on storage.objects;
create policy inv_files_read on storage.objects for select to authenticated
  using (bucket_id = 'invoices' and public.can_branch(split_part(name, '/', 1)) and public.is_member());
create policy inv_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'invoices' and public.can_branch(split_part(name, '/', 1)) and public.is_member());
create policy inv_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'invoices' and public.has_perm('delete') and public.can_branch(split_part(name, '/', 1)));

do $$ begin
  begin alter publication supabase_realtime add table public.docs;     exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.profiles; exception when duplicate_object then null; end;
end $$;

insert into public.invites (username, full_name, is_owner)
values ('vivian', 'Vivian Lohrmann', true)
on conflict (username) do nothing;

alter table public.profiles disable trigger guard_profiles;
insert into public.profiles (id, username, full_name, is_owner, active)
select id, 'vivian', 'Vivian Lohrmann', true, true
from auth.users where email = 'vivian@staff.secmec.co.za'
on conflict (id) do update set is_owner = true, active = true;
alter table public.profiles enable trigger guard_profiles;
update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where email = 'vivian@staff.secmec.co.za';
delete from public.invites where username = 'vivian' and exists (select 1 from public.profiles where username = 'vivian');
