-- MECCA BOOKS database setup — PART 3 of 3 (run parts 1, 2, 3 in order)

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

-- Done. Refresh the Mecca Books app.
