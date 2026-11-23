-- Mecca Books: Company Documents (run once in the Supabase SQL editor; safe to run again)
-- Rights: companyDocs = see & open them, companyDocsEdit = upload / change. Owner has both.

create or replace function public.coll_read_ok(c text) returns boolean
language sql stable as $$
  select case c when 'companydocs' then public.has_perm('companyDocs') else true end;
$$;

create or replace function public.coll_write_ok(c text, is_insert boolean) returns boolean
language sql stable as $$
  select case c
    when 'accounts' then public.has_perm('accounts')
    when 'settings' then public.has_perm('setup')
    when 'items'    then (not is_insert) or public.has_perm('inventory') or public.has_perm('editPrices')
    when 'companydocs' then public.has_perm('companyDocsEdit')
    else true end;
$$;

drop policy if exists docs_read   on public.docs;
drop policy if exists docs_update on public.docs;
drop policy if exists docs_delete on public.docs;
create policy docs_read   on public.docs for select to authenticated
  using (public.is_member() and public.can_branch(branch) and public.coll_read_ok(coll));
create policy docs_update on public.docs for update to authenticated
  using (public.is_member() and public.can_branch(branch) and public.coll_read_ok(coll))
  with check (public.is_member() and public.can_branch(branch) and public.coll_write_ok(coll, false));
create policy docs_delete on public.docs for delete to authenticated
  using (public.has_perm('delete') and public.can_branch(branch)
         and (coll <> 'companydocs' or public.has_perm('companyDocsEdit')));

-- private file area: <ALL|RB|VV>/<document id>/<file>, 20 MB per file
insert into storage.buckets (id, name, public, file_size_limit) values ('company-docs', 'company-docs', false, 20971520)
on conflict (id) do update set public = false, file_size_limit = 20971520;

drop policy if exists cdoc_files_read   on storage.objects;
drop policy if exists cdoc_files_insert on storage.objects;
drop policy if exists cdoc_files_delete on storage.objects;
create policy cdoc_files_read on storage.objects for select to authenticated
  using (bucket_id = 'company-docs' and public.is_member() and public.has_perm('companyDocs')
         and (split_part(name, '/', 1) = 'ALL' or public.can_branch(split_part(name, '/', 1))));
create policy cdoc_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'company-docs' and public.is_member() and public.has_perm('companyDocsEdit')
         and (split_part(name, '/', 1) = 'ALL' or public.can_branch(split_part(name, '/', 1))));
create policy cdoc_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'company-docs' and public.has_perm('companyDocsEdit') and public.has_perm('delete')
         and (split_part(name, '/', 1) = 'ALL' or public.can_branch(split_part(name, '/', 1))));

select 'company documents ready' as result;
