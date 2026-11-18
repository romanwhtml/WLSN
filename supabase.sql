-- Run this once in the Supabase SQL Editor for the WLSN broadcast pages.

create table if not exists public.media_library (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  media_type text not null check (media_type in ('audio', 'video', 'image')),
  storage_path text not null unique,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.media_library drop constraint if exists media_library_media_type_check;
alter table public.media_library add constraint media_library_media_type_check
  check (media_type in ('audio', 'video', 'image'));

create table if not exists public.cue_buttons (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  media_id uuid not null references public.media_library(id) on delete cascade,
  position bigint not null default 0,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.station_state (
  id boolean primary key default true check (id),
  current_media_id uuid references public.media_library(id) on delete set null,
  is_playing boolean not null default false,
  play_token uuid,
  updated_at timestamptz not null default now()
);

insert into public.station_state (id)
values (true)
on conflict (id) do nothing;

alter table public.media_library enable row level security;
alter table public.cue_buttons enable row level security;
alter table public.station_state enable row level security;

drop policy if exists "Public can read media library" on public.media_library;
create policy "Public can read media library" on public.media_library
  for select using (true);
drop policy if exists "Studio can add media" on public.media_library;
create policy "Studio can add media" on public.media_library
  for insert to authenticated with check (auth.uid() = created_by);

drop policy if exists "Studio can read cue buttons" on public.cue_buttons;
create policy "Studio can read cue buttons" on public.cue_buttons
  for select to authenticated using (auth.uid() = created_by);
drop policy if exists "Studio can add cue buttons" on public.cue_buttons;
create policy "Studio can add cue buttons" on public.cue_buttons
  for insert to authenticated with check (auth.uid() = created_by);
drop policy if exists "Studio can rename cue buttons" on public.cue_buttons;
create policy "Studio can rename cue buttons" on public.cue_buttons
  for update to authenticated using (auth.uid() = created_by) with check (auth.uid() = created_by);
drop policy if exists "Studio can delete cue buttons" on public.cue_buttons;
create policy "Studio can delete cue buttons" on public.cue_buttons
  for delete to authenticated using (auth.uid() = created_by);

drop policy if exists "Public can read station state" on public.station_state;
create policy "Public can read station state" on public.station_state
  for select using (true);
drop policy if exists "Studio can start broadcasts" on public.station_state;
create policy "Studio can start broadcasts" on public.station_state
  for insert to authenticated with check (auth.uid() is not null);
drop policy if exists "Studio can update broadcasts" on public.station_state;
create policy "Studio can update broadcasts" on public.station_state
  for update to authenticated using (auth.uid() is not null) with check (auth.uid() is not null);

insert into storage.buckets (id, name, public)
values ('broadcast-media', 'broadcast-media', true)
on conflict (id) do update set public = true;

drop policy if exists "Public can play broadcast media" on storage.objects;
create policy "Public can play broadcast media" on storage.objects
  for select using (bucket_id = 'broadcast-media');
drop policy if exists "Studio can upload broadcast media" on storage.objects;
create policy "Studio can upload broadcast media" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'broadcast-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'station_state'
  ) then
    alter publication supabase_realtime add table public.station_state;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'media_library'
  ) then
    alter publication supabase_realtime add table public.media_library;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cue_buttons'
  ) then
    alter publication supabase_realtime add table public.cue_buttons;
  end if;
end
$$;