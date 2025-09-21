-- 0002_profiles_autocreate.sql
-- Автоматично създаване на ред в public.profiles при нов auth.user

create or replace function public.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name, username, role)
  values (
    new.id,
    new.email,
    split_part(new.email,'@',1),          -- display_name
    split_part(new.email,'@',1),          -- username
    'user'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_auth_user_created();
