-- MECCA BOOKS database setup — PART 2 of 3 (run parts 1, 2, 3 in order)

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
