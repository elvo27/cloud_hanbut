alter function public.cloud_connect_maximum_score(integer)
set search_path = '';

create policy "No direct report table access"
on public.game_high_score_reports
for all
to public
using (false)
with check (false);

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

revoke all on function public.report_game_high_score(bigint, uuid, text) from public;
grant execute on function public.report_game_high_score(bigint, uuid, text) to anon;
revoke execute on function public.report_game_high_score(bigint, uuid, text) from authenticated;
revoke execute on function public.submit_game_high_score(text, text, integer, integer, timestamp with time zone) from authenticated;
revoke execute on function public.submit_game_high_score(text, text, integer, integer, timestamp with time zone, uuid) from authenticated;
