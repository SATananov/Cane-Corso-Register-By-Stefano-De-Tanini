-- 0003_secure_functions.sql

-- 1) trigger_set_timestamp с фиксиран search_path
create or replace function public.trigger_set_timestamp()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  NEW.updated_at := now();
  return NEW;
end;
$$;

-- (по желание – пресъздаваме тригера, ако не съществува)
drop trigger if exists trg_dogs_set_updated on public.dogs;
create trigger trg_dogs_set_updated
before update on public.dogs
for each row
execute function public.trigger_set_timestamp();

-- 2) is_admin() с фиксиран search_path
create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;
