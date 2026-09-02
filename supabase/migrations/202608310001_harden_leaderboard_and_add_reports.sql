alter table public.game_high_scores
add column if not exists player_id uuid,
add column if not exists is_hidden boolean not null default false;

create index if not exists game_high_scores_top_stage_idx
on public.game_high_scores (game_name, last_stage desc, score desc, played_at desc)
where is_hidden = false;

create index if not exists game_high_scores_latest_idx
on public.game_high_scores (game_name, played_at desc)
where is_hidden = false;

drop policy if exists "Anyone can read high scores" on public.game_high_scores;
create policy "Anyone can read visible high scores"
on public.game_high_scores
for select
to anon, authenticated
using (is_hidden = false);

create or replace function public.cloud_connect_maximum_score(p_last_stage integer)
returns bigint
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  current_stage integer;
  safe_count integer;
  time_limit integer;
  total bigint := 0;
begin
  if p_last_stage < 0 or p_last_stage > 200 then
    return -1;
  end if;

  for current_stage in 1..p_last_stage loop
    safe_count := least(current_stage + 1, 28);
    time_limit := case
      when current_stage >= 40 then 20
      when current_stage >= 30 then 25
      else least(greatest(8 + safe_count * 3, 8), 30)
    end;
    total := total + current_stage * 100 + time_limit * 5;
  end loop;
  return total;
end;
$$;

create or replace function public.submit_game_high_score(
  p_game_name text,
  p_nickname text,
  p_score integer,
  p_last_stage integer default null,
  p_played_at timestamp with time zone default null
)
returns public.game_high_scores
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_game_name text := btrim(p_game_name);
  normalized_nickname text := regexp_replace(btrim(p_nickname), '\s+', ' ', 'g');
  normalized_stage integer := coalesce(p_last_stage, 0);
  normalized_played_at timestamp with time zone := least(
    coalesce(p_played_at, timezone('utc', now())),
    timezone('utc', now()) + interval '5 minutes'
  );
  result_row public.game_high_scores;
begin
  if normalized_game_name <> 'cloud_connect' then
    raise exception 'unsupported game_name' using errcode = '22023';
  end if;
  if char_length(normalized_nickname) not between 1 and 24
     or normalized_nickname ~ '[[:cntrl:]]'
     or normalized_nickname ~* '(https?://|www\.|[a-z0-9-]+\.(com|net|org|kr|io)(\W|$))'
     or normalized_nickname ~* '(시발|씨발|병신|개새끼|fuck|shit|bitch)' then
    raise exception 'nickname is not allowed' using errcode = '22023';
  end if;
  if normalized_stage not between 1 and 200 then
    raise exception 'last_stage is out of range' using errcode = '22023';
  end if;
  if p_score is null or p_score < 0
     or p_score > public.cloud_connect_maximum_score(normalized_stage) then
    raise exception 'score is out of range' using errcode = '22023';
  end if;

  insert into public.game_high_scores as scores (
    game_name, nickname, score, last_stage, played_at
  ) values (
    normalized_game_name, normalized_nickname, p_score,
    normalized_stage, normalized_played_at
  )
  on conflict (game_name, nickname) do update
    set score = greatest(scores.score, excluded.score),
        last_stage = greatest(coalesce(scores.last_stage, 0), excluded.last_stage),
        played_at = case
          when excluded.score > scores.score
            or excluded.last_stage > coalesce(scores.last_stage, 0)
          then excluded.played_at
          else scores.played_at
        end,
        updated_at = case
          when excluded.score > scores.score
            or excluded.last_stage > coalesce(scores.last_stage, 0)
          then timezone('utc', now())
          else scores.updated_at
        end
  returning * into result_row;

  return result_row;
end;
$$;

create or replace function public.submit_game_high_score(
  p_game_name text,
  p_nickname text,
  p_score integer,
  p_last_stage integer,
  p_played_at timestamp with time zone,
  p_player_id uuid
)
returns public.game_high_scores
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_game_name text := btrim(p_game_name);
  normalized_nickname text := regexp_replace(btrim(p_nickname), '\s+', ' ', 'g');
  normalized_played_at timestamp with time zone := least(
    coalesce(p_played_at, timezone('utc', now())),
    timezone('utc', now()) + interval '5 minutes'
  );
  existing_row public.game_high_scores;
  result_row public.game_high_scores;
begin
  if p_player_id is null then
    raise exception 'player_id is required' using errcode = '22023';
  end if;
  if normalized_game_name <> 'cloud_connect' then
    raise exception 'unsupported game_name' using errcode = '22023';
  end if;
  if char_length(normalized_nickname) not between 1 and 24
     or normalized_nickname ~ '[[:cntrl:]]'
     or normalized_nickname ~* '(https?://|www\.|[a-z0-9-]+\.(com|net|org|kr|io)(\W|$))'
     or normalized_nickname ~* '(시발|씨발|병신|개새끼|fuck|shit|bitch)' then
    raise exception 'nickname is not allowed' using errcode = '22023';
  end if;
  if p_last_stage is null or p_last_stage not between 1 and 200 then
    raise exception 'last_stage is out of range' using errcode = '22023';
  end if;
  if p_score is null or p_score < 0
     or p_score > public.cloud_connect_maximum_score(p_last_stage) then
    raise exception 'score is out of range' using errcode = '22023';
  end if;

  select * into existing_row
  from public.game_high_scores
  where game_name = normalized_game_name and nickname = normalized_nickname
  for update;

  if existing_row.id is not null
     and existing_row.player_id is not null
     and existing_row.player_id <> p_player_id then
    raise exception 'nickname is already in use' using errcode = '23505';
  end if;

  insert into public.game_high_scores as scores (
    game_name, nickname, score, last_stage, played_at, player_id
  ) values (
    normalized_game_name, normalized_nickname, p_score, p_last_stage,
    normalized_played_at, p_player_id
  )
  on conflict (game_name, nickname) do update
    set score = greatest(scores.score, excluded.score),
        last_stage = greatest(coalesce(scores.last_stage, 0), excluded.last_stage),
        played_at = case
          when excluded.score > scores.score
            or excluded.last_stage > coalesce(scores.last_stage, 0)
          then excluded.played_at
          else scores.played_at
        end,
        player_id = coalesce(scores.player_id, excluded.player_id),
        updated_at = case
          when excluded.score > scores.score
            or excluded.last_stage > coalesce(scores.last_stage, 0)
          then timezone('utc', now())
          else scores.updated_at
        end
  returning * into result_row;

  return result_row;
end;
$$;

create table if not exists public.game_high_score_reports (
  id bigint generated by default as identity primary key,
  score_id bigint not null references public.game_high_scores(id) on delete cascade,
  reporter_id uuid not null,
  reason text not null,
  created_at timestamp with time zone not null default timezone('utc', now()),
  constraint game_high_score_reports_unique unique (score_id, reporter_id),
  constraint game_high_score_reports_reason check (reason in ('inappropriate_nickname'))
);

alter table public.game_high_score_reports enable row level security;
revoke all on public.game_high_score_reports from anon, authenticated;

create or replace function public.report_game_high_score(
  p_score_id bigint,
  p_reporter_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_reporter_id is null or p_reason <> 'inappropriate_nickname' then
    raise exception 'invalid report' using errcode = '22023';
  end if;

  insert into public.game_high_score_reports (score_id, reporter_id, reason)
  values (p_score_id, p_reporter_id, p_reason)
  on conflict (score_id, reporter_id) do nothing;

end;
$$;

revoke all on function public.cloud_connect_maximum_score(integer) from public;
revoke all on function public.submit_game_high_score(text, text, integer, integer, timestamp with time zone) from public;
revoke all on function public.submit_game_high_score(text, text, integer, integer, timestamp with time zone, uuid) from public;
revoke all on function public.report_game_high_score(bigint, uuid, text) from public;
grant execute on function public.submit_game_high_score(text, text, integer, integer, timestamp with time zone) to anon, authenticated;
grant execute on function public.submit_game_high_score(text, text, integer, integer, timestamp with time zone, uuid) to anon, authenticated;
grant execute on function public.report_game_high_score(bigint, uuid, text) to anon, authenticated;
