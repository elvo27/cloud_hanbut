alter table public.game_high_scores
add column if not exists played_at timestamp with time zone not null
default timezone('utc', now());

drop function if exists public.submit_game_high_score(text, text, integer, integer);

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
  normalized_nickname text := btrim(p_nickname);
  normalized_played_at timestamp with time zone := coalesce(
    p_played_at,
    timezone('utc', now())
  );
  result_row public.game_high_scores;
begin
  if normalized_game_name = '' then
    raise exception 'game_name is required' using errcode = '22023';
  end if;

  if normalized_nickname = '' then
    raise exception 'nickname is required' using errcode = '22023';
  end if;

  if p_score is null or p_score < 0 then
    raise exception 'score must be non-negative' using errcode = '22023';
  end if;

  if p_last_stage is not null and p_last_stage < 0 then
    raise exception 'last_stage must be non-negative' using errcode = '22023';
  end if;

  insert into public.game_high_scores as scores (
    game_name,
    nickname,
    score,
    last_stage,
    played_at
  )
  values (
    normalized_game_name,
    normalized_nickname,
    p_score,
    p_last_stage,
    normalized_played_at
  )
  on conflict (game_name, nickname) do update
    set score = excluded.score,
        last_stage = excluded.last_stage,
        played_at = excluded.played_at,
        updated_at = timezone('utc', now())
  where excluded.score > scores.score
     or coalesce(excluded.last_stage, -1) > coalesce(scores.last_stage, -1)
  returning * into result_row;

  if result_row.id is null then
    select *
    into result_row
    from public.game_high_scores
    where game_name = normalized_game_name
      and nickname = normalized_nickname;
  end if;

  return result_row;
end;
$$;

revoke all on function public.submit_game_high_score(text, text, integer, integer, timestamp with time zone) from public;
grant execute on function public.submit_game_high_score(text, text, integer, integer, timestamp with time zone) to anon, authenticated;
