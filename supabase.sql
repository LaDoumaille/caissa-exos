-- ============================================================
-- Challenges Caïssa : base Supabase (à coller une seule fois
-- dans SQL Editor > New query > Run)
-- ============================================================

create extension if not exists pgcrypto;

-- Membres du club : juste un prénom, pas de compte, pas de code
create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 40),
  created_at timestamptz not null default now()
);
create unique index if not exists members_name_uniq on public.members (lower(btrim(name)));

-- Exercices
create table if not exists public.exercises (
  id uuid primary key default gen_random_uuid(),
  num int not null unique,
  fen text not null,
  question text not null default '',
  options jsonb not null,             -- [{"san":"g4","uci":"g2g4"}, ...]
  status text not null default 'open' check (status in ('open','revealed')),
  correct int[],                      -- reste vide tant que la correction n'est pas publiée
  video_url text,
  comment text,
  created_at timestamptz not null default now(),
  revealed_at timestamptz
);

-- Solutions cachées jusqu'à la révélation (aucun accès direct)
create table if not exists public.solutions (
  exercise_id uuid primary key references public.exercises(id) on delete cascade,
  correct int[] not null
);

-- Réponses : une seule par membre et par exercice, non modifiable
create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  choice int not null check (choice >= 0),
  created_at timestamptz not null default now(),
  unique (exercise_id, member_id)
);

-- Réglages (clé du lien coach)
create table if not exists public.config (
  key text primary key,
  value text not null
);
insert into public.config(key, value)
values ('coach_key', encode(extensions.gen_random_bytes(9), 'hex'))
on conflict (key) do nothing;

-- ---------- Droits ----------
alter table public.members   enable row level security;
alter table public.exercises enable row level security;
alter table public.solutions enable row level security;
alter table public.answers   enable row level security;
alter table public.config    enable row level security;

revoke all on public.members, public.exercises, public.solutions, public.answers, public.config from anon, authenticated;
grant select, insert on public.members   to anon, authenticated;
grant select         on public.exercises to anon, authenticated;
grant select, insert on public.answers   to anon, authenticated;

drop policy if exists members_read on public.members;
drop policy if exists members_add on public.members;
drop policy if exists exercises_read on public.exercises;
drop policy if exists answers_read on public.answers;
drop policy if exists answers_add on public.answers;

create policy members_read on public.members for select to anon, authenticated using (true);
create policy members_add  on public.members for insert to anon, authenticated with check (true);
create policy exercises_read on public.exercises for select to anon, authenticated using (true);
create policy answers_read on public.answers for select to anon, authenticated using (true);
create policy answers_add  on public.answers for insert to anon, authenticated
  with check (exists (
    select 1 from public.exercises e
    where e.id = exercise_id and e.status = 'open'
      and choice < jsonb_array_length(e.options)
  ));

-- ---------- Fonctions coach (protégées par la clé du lien coach) ----------
create or replace function public._is_coach(p_key text) returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.config where key = 'coach_key' and value = p_key);
$$;
revoke all on function public._is_coach(text) from public, anon, authenticated;

create or replace function public.coach_ok(p_key text) returns boolean
language sql security definer set search_path = public stable as $$
  select public._is_coach(p_key);
$$;

create or replace function public.create_exercise(
  p_key text, p_num int, p_fen text, p_question text, p_options jsonb, p_correct int[]
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_n int;
begin
  if not public._is_coach(p_key) then raise exception 'not_coach'; end if;
  v_n := jsonb_array_length(p_options);
  if v_n < 2 or v_n > 8 then raise exception 'bad_options'; end if;
  if p_correct is null or cardinality(p_correct) = 0 then raise exception 'no_correct'; end if;
  if exists (select 1 from unnest(p_correct) c where c < 0 or c >= v_n) then raise exception 'bad_correct'; end if;
  insert into public.exercises(num, fen, question, options)
  values (coalesce(p_num, (select coalesce(max(num), 0) + 1 from public.exercises)), p_fen, coalesce(p_question, ''), p_options)
  returning id into v_id;
  insert into public.solutions(exercise_id, correct) values (v_id, p_correct);
  return v_id;
end $$;

create or replace function public.coach_solution(p_key text, p_exercise uuid) returns int[]
language plpgsql security definer set search_path = public stable as $$
begin
  if not public._is_coach(p_key) then raise exception 'not_coach'; end if;
  return (select correct from public.solutions where exercise_id = p_exercise);
end $$;

create or replace function public.reveal_exercise(p_key text, p_exercise uuid, p_video_url text, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._is_coach(p_key) then raise exception 'not_coach'; end if;
  update public.exercises e
     set status = 'revealed',
         correct = s.correct,
         video_url = nullif(btrim(coalesce(p_video_url, '')), ''),
         comment = nullif(btrim(coalesce(p_comment, '')), ''),
         revealed_at = coalesce(e.revealed_at, now())
    from public.solutions s
   where e.id = p_exercise and s.exercise_id = e.id;
end $$;

create or replace function public.delete_exercise(p_key text, p_exercise uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._is_coach(p_key) then raise exception 'not_coach'; end if;
  delete from public.exercises where id = p_exercise;
end $$;

create or replace function public.delete_member(p_key text, p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._is_coach(p_key) then raise exception 'not_coach'; end if;
  delete from public.members where id = p_member;
end $$;

grant execute on function public.coach_ok(text) to anon, authenticated;
grant execute on function public.create_exercise(text, int, text, text, jsonb, int[]) to anon, authenticated;
grant execute on function public.coach_solution(text, uuid) to anon, authenticated;
grant execute on function public.reveal_exercise(text, uuid, text, text) to anon, authenticated;
grant execute on function public.delete_exercise(text, uuid) to anon, authenticated;
grant execute on function public.delete_member(text, uuid) to anon, authenticated;

-- ---------- Vidéos de correction ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('videos', 'videos', true, 52428800, array['video/mp4','video/webm','video/quicktime'])
on conflict (id) do nothing;

drop policy if exists videos_upload on storage.objects;
create policy videos_upload on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'videos');

-- Lien coach à copier :
select value as cle_coach from public.config where key = 'coach_key';
