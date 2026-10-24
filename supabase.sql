-- ZERO TO BILLION : comptes joueurs, classement entre potes et sauvegarde dans le cloud
-- À coller dans Supabase > SQL Editor > New query, puis "Run". Le script peut être relancé sans risque.

-- 1. Fiche publique du joueur (ce que voit le classement)
create table if not exists public.ztb_players (
  id          uuid primary key references auth.users(id) on delete cascade,
  pseudo      text not null check (char_length(pseudo) between 2 and 16),
  team        text check (team is null or team ~ '^[A-Z0-9-]{3,16}$'),
  level       integer not null default 1 check (level between 1 and 10000),
  best        double precision not null default 0 check (best >= 0 and best < 1e30),
  shares      integer not null default 0 check (shares >= 0),
  updated_at  timestamptz not null default now()
);
create unique index if not exists ztb_players_pseudo_unique on public.ztb_players (lower(pseudo));
create index if not exists ztb_players_best_idx on public.ztb_players (best desc);
create index if not exists ztb_players_team_idx on public.ztb_players (team, best desc);

-- 2. Sauvegarde privée de la partie (visible uniquement par son propriétaire)
create table if not exists public.ztb_saves (
  id          uuid primary key references auth.users(id) on delete cascade,
  data        jsonb not null check (octet_length(data::text) < 50000),
  all_time    double precision not null default 0,
  updated_at  timestamptz not null default now()
);

-- 3. Sécurité : chacun lit le classement, mais ne modifie que sa propre fiche et sa propre sauvegarde
alter table public.ztb_players enable row level security;
alter table public.ztb_saves   enable row level security;

drop policy if exists "classement lisible par tous" on public.ztb_players;
create policy "classement lisible par tous" on public.ztb_players
  for select using (true);

drop policy if exists "joueur crée sa fiche" on public.ztb_players;
create policy "joueur crée sa fiche" on public.ztb_players
  for insert to authenticated with check ((select auth.uid()) = id);

drop policy if exists "joueur modifie sa fiche" on public.ztb_players;
create policy "joueur modifie sa fiche" on public.ztb_players
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "sauvegarde privée" on public.ztb_saves;
create policy "sauvegarde privée" on public.ztb_saves
  for all to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

grant select on public.ztb_players to anon, authenticated;
grant insert, update on public.ztb_players to authenticated;
grant select, insert, update on public.ztb_saves to authenticated;

-- 4. Le meilleur score et le niveau ne peuvent jamais baisser (même après « Recommencer »)
create or replace function public.ztb_players_keep_best() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.best       := greatest(coalesce(old.best, 0), new.best);
  new.level      := greatest(coalesce(old.level, 1), new.level);
  new.shares     := greatest(coalesce(old.shares, 0), new.shares);
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists ztb_players_keep_best on public.ztb_players;
create trigger ztb_players_keep_best before update on public.ztb_players
  for each row execute function public.ztb_players_keep_best();
