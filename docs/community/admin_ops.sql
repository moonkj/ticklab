-- TickLab 운영 대시보드 백엔드 (presence + 신고 조회 + 숨김 처리)
-- ===========================================================================
-- 선행: admin_rls.sql (admin_users, is_admin) 가 먼저 적용되어 있어야 함.
-- 적용: Supabase 대시보드 → SQL Editor 에 붙여 실행.
-- 참고: '전체/오늘 게시물 수'는 기존 posts_select(approved 공개 읽기)로 동작하므로
--       이 SQL 없이도 앱 대시보드에 표시됨. 아래는 '활동 사용자'·'신고'·'숨김'용.
-- ===========================================================================

-- 1) presence — '현재 활동 사용자' 근사치 (앱이 커뮤니티 사용 시 하트비트 UPSERT)
create table if not exists public.community_presence (
    uid        uuid primary key,
    last_seen  timestamptz not null default now()
);
alter table public.community_presence enable row level security;

-- 본인 presence upsert(INSERT/UPDATE) 허용
drop policy if exists presence_insert on public.community_presence;
create policy presence_insert on public.community_presence
    for insert with check (uid = auth.uid());
drop policy if exists presence_update on public.community_presence;
create policy presence_update on public.community_presence
    for update using (uid = auth.uid()) with check (uid = auth.uid());

-- admin 만 전체 presence 조회(활동 사용자 카운트)
drop policy if exists presence_admin_select on public.community_presence;
create policy presence_admin_select on public.community_presence
    for select using (public.is_admin(auth.uid()));

-- 2) 신고 조회 — admin 만 전체 SELECT (일반 사용자는 본인 신고 insert 만, 기존 정책 유지)
drop policy if exists reports_admin_select on public.community_reports;
create policy reports_admin_select on public.community_reports
    for select using (public.is_admin(auth.uid()));

-- 3) 게시물 숨김 — admin 은 모든 글 status UPDATE 가능
--    (기존 posts_update_own = 본인 글만, 과 OR 로 합쳐져 admin 은 전체 가능)
drop policy if exists posts_admin_update on public.community_posts;
create policy posts_admin_update on public.community_posts
    for update using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- (선택) 오래된 presence 정리 — 5분 지난 행 삭제하는 스케줄 잡을 두면 테이블 가벼움.
-- delete from public.community_presence where last_seen < now() - interval '10 minutes';
