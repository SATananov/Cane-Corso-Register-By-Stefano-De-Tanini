-- CaneCorsoDB – initial, idempotent migration

-- 0) Extensions
create extension if not exists "pgcrypto";

-- 1) Helpers
-- 1.1 updated_at trigger function (idempotent)
create or replace function public.trigger_set_timestamp()
returns trigger
language plpgsql
as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$;

-- 1.2 Admin check helper (idempotent)
create or replace function public.is_admin(uid uuid)
returns boolean
language sql
stable
as $$
  select exists(
    select 1 from public.profiles p
    where p.id = uid and p.role = 'admin'
  );
$$;

-- 2) Schema

-- 2.1 profiles (linked to auth.users)
create table if not exists public.profiles(
  id           uuid primary key
               references auth.users(id) on delete cascade,
  email        text not null,
  display_name text,
  username     text unique,
  role         text not null default 'user',
  avatar_url   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create unique index if not exists profiles_username_key on public.profiles(username);

-- 2.2 dogs
create table if not exists public.dogs(
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references public.profiles(id) on delete cascade,
  name               text not null,
  sex                text check (sex in ('male','female')),
  date_of_birth      date,
  color              text,
  microchip_number   text,
  pedigree_number    text,
  status             text not null default 'pending',  -- pending | approved | rejected
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- keep trigger idempotent
drop trigger if exists trg_dogs_set_updated on public.dogs;
create trigger trg_dogs_set_updated
before update on public.dogs
for each row execute function public.trigger_set_timestamp();

-- 2.3 photos
create table if not exists public.photos(
  id          uuid primary key default gen_random_uuid(),
  dog_id      uuid not null references public.dogs(id) on delete cascade,
  url         text not null,
  created_at  timestamptz not null default now()
);

-- 3) RLS
alter table public.profiles enable row level security;
alter table public.dogs     enable row level security;
alter table public.photos   enable row level security;

-- 3.1 profiles policies (create only if missing)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles select own or admin'
  ) then
    create policy "profiles select own or admin"
      on public.profiles
      for select
      to authenticated
      using ( id = auth.uid() or public.is_admin(auth.uid()) );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles insert self'
  ) then
    create policy "profiles insert self"
      on public.profiles
      for insert
      to authenticated
      with check ( id = auth.uid() );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles update self'
  ) then
    create policy "profiles update self"
      on public.profiles
      for update
      to authenticated
      using ( id = auth.uid() )
      with check ( id = auth.uid() );
  end if;
end $$;

-- 3.2 dogs policies
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='dogs' and policyname='dogs read approved or own or admin'
  ) then
    create policy "dogs read approved or own or admin"
      on public.dogs
      for select
      to anon, authenticated
      using ( status = 'approved'
              or owner_id = auth.uid()
              or public.is_admin(auth.uid()) );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='dogs' and policyname='dogs insert owner'
  ) then
    create policy "dogs insert owner"
      on public.dogs
      for insert
      to authenticated
      with check ( owner_id = auth.uid() );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='dogs' and policyname='dogs update own or admin'
  ) then
    create policy "dogs update own or admin"
      on public.dogs
      for update
      to authenticated
      using ( owner_id = auth.uid() or public.is_admin(auth.uid()) )
      with check ( owner_id = auth.uid() or public.is_admin(auth.uid()) );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='dogs' and policyname='dogs delete own or admin'
  ) then
    create policy "dogs delete own or admin"
      on public.dogs
      for delete
      to authenticated
      using ( owner_id = auth.uid() or public.is_admin(auth.uid()) );
  end if;
end $$;

-- 3.3 photos policies (respect dog visibility)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='photos' and policyname='photos read by dog visibility'
  ) then
    create policy "photos read by dog visibility"
      on public.photos
      for select
      to anon, authenticated
      using (
        exists (
          select 1 from public.dogs d
          where d.id = photos.dog_id
            and ( d.status = 'approved'
                  or d.owner_id = auth.uid()
                  or public.is_admin(auth.uid()) )
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='photos' and policyname='photos write owner or admin'
  ) then
    create policy "photos write owner or admin"
      on public.photos
      for all
      to authenticated
      using (
        exists (
          select 1 from public.dogs d
          where d.id = photos.dog_id
            and ( d.owner_id = auth.uid()
                  or public.is_admin(auth.uid()) )
        )
      )
      with check (
        exists (
          select 1 from public.dogs d
          where d.id = photos.dog_id
            and ( d.owner_id = auth.uid()
                  or public.is_admin(auth.uid()) )
        )
      );
  end if;
end $$;
