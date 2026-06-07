-- TickLab 접속 누계 — 앱 포그라운드(접속)마다 1행 INSERT, admin 만 집계 SELECT.
-- ===========================================================================
-- 선행: admin_rls.sql (admin_users, is_admin) 가 먼저 적용되어 있어야 함.
-- 적용: Supabase 대시보드 → SQL Editor 에 붙여 실행.
-- 미적용 시 앱 대시보드의 '접속 누계' 4개 타일은 0 으로 표시(graceful).
-- ===========================================================================

create table if not exists public.community_access_log (
    id         bigint generated always as identity primary key,
    uid        uuid not null default auth.uid(),
    created_at timestamptz not null default now()
);
alter table public.community_access_log enable row level security;
create index if not exists idx_access_created on public.community_access_log (created_at desc);

-- 인증된(익명 포함) 사용자는 본인 접속 기록만 INSERT
drop policy if exists access_insert on public.community_access_log;
create policy access_insert on public.community_access_log
    for insert with check (uid = auth.uid());

-- admin 만 전체 집계 SELECT (오늘/주/월/총 카운트)
drop policy if exists access_admin_select on public.community_access_log;
create policy access_admin_select on public.community_access_log
    for select using (public.is_admin(auth.uid()));

-- (선택) 오래된 로그 정리 예시 — 필요 시 주기적으로 실행:
-- delete from public.community_access_log where created_at < now() - interval '365 days';
