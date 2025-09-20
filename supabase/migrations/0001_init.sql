-- Cane Corso Registry – initial schema + RLS
-- Compatible with Supabase (Postgres)

-- 0) Extensions
create extension if not exists "pgcrypto"; -- for gen_random_uuid()

-- 1) Helper: updated_at trigger function (fixed search_path)
drop function if exists public.trigger_set_timestamp();
create or replace function public.trigger_set_timestamp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 2) PROFILES (links 1:1 to auth.users.id)
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  email        text unique,
  display_name text,
  username     text unique,
  role         text not null default 'user' check (role in ('user','admin')),
  avatar_url   text,
  created_at   timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- RLS: profiles
do $$
begin
  create policy "profiles select self"
    on public.profiles for select to authenticated
    using (auth.uid() = id);
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy "profiles insert self"
    on public.profiles for insert to authenticated
    with check (auth.uid() = id);
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy "profiles update self"
    on public.profiles for update to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id);
exception when duplicate_object then null;
end $$;

-- 3) DOGS (Cane Corso records)
create table if not exists public.dogs (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references auth.users(id) on delete cascade,
  name             text not null,
  sex              text not null check (sex in ('male','female')),
  date_of_birth    date not null,
  color            text,
  microchip_number text,
  pedigree_number  text,
  spayed_neutered  boolean default false,
  sire_name        text,
  dam_name         text,
  breeder_name     text,
  notes            text,
  status           text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists dogs_owner_idx  on public.dogs(owner_id);
create index if not exists dogs_status_idx on public.dogs(status);

drop trigger if exists trg_dogs_set_updated on public.dogs;
create trigger trg_dogs_set_updated
before update on public.dogs
for each row execute function public.trigger_set_timestamp();

alter table public.dogs enable row level security;

-- 4) DOG_PHOTOS (simple URL storage; storage bucket policies are separate)
create table if not exists public.dog_photos (
  id         uuid primary key default gen_random_uuid(),
  dog_id     uuid not null references public.dogs(id) on delete cascade,
  url        text not null,
  created_at timestamptz not null default now()
);
create index if not exists dog_photos_dog_idx on public.dog_photos(dog_id);

alter table public.dog_photos enable row level security;

-- 5) Helper: is_admin()
drop function if exists public.is_admin();
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- 6) RLS for DOGS
do $$
begin
  create policy "dogs read approved or own or admin"
    on public.dogs for select to anon, authenticated
    using (
      status = 'approved'
      or owner_id = auth.uid()
      or public.is_admin()
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy "dogs insert owner"
    on public.dogs for insert to authenticated
    with check (owner_id = auth.uid());
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy "dogs update owner"
    on public.dogs for update to authenticated
    using (owner_id = auth.uid())
    with check (owner_id = auth.uid());
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy "dogs delete owner"
    on public.dogs for delete to authenticated
    using (owner_id = auth.uid());
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy "dogs admin update"
    on public.dogs for update to authenticated
    using (public.is_admin()) with check (true);
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy "dogs admin delete"
    on public.dogs for delete to authenticated
    using (public.is_admin());
exception when duplicate_object then null;
end $$;

-- 7) RLS for DOG_PHOTOS
do $$
begin
  create policy "dog_photos read public/own/admin"
    on public.dog_photos for select to anon, authenticated
    using (
      exists (
        select 1 from public.dogs d
        where d.id = dog_id
          and (d.status = 'approved' or d.owner_id = auth.uid() or public.is_admin())
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy "dog_photos insert owner"
    on public.dog_photos for insert to authenticated
    with check (
      exists (
        select 1 from public.dogs d
        where d.id = dog_id and d.owner_id = auth.uid()
      )
    );
exception when duplicate_object then null;
end $$;

do $$
begin
  create policy "dog_photos delete owner or admin"
    on public.dog_photos for delete to authenticated
    using (
      exists (
        select 1 from public.dogs d
        where d.id = dog_id and (d.owner_id = auth.uid() or public.is_admin())
      )
    );
exception when duplicate_object then null;
end $$;

-- Optional comments
comment on table public.dogs is 'Cane Corso dogs – pending/approved/rejected; owner-based RLS.';
comment on table public.dog_photos is 'Photos linked to dogs (RLS follows dog rules).';
