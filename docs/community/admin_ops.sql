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

-- 2-1) 게시물 열람 — admin 은 모든 글(숨김/차단 포함) SELECT 가능 (신고 게시물 본문 확인용)
drop policy if exists posts_admin_select on public.community_posts;
create policy posts_admin_select on public.community_posts
    for select using (public.is_admin(auth.uid()));

-- 3) 게시물 숨김 — admin 은 모든 글 status UPDATE 가능
--    (기존 posts_update_own = 본인 글만, 과 OR 로 합쳐져 admin 은 전체 가능)
drop policy if exists posts_admin_update on public.community_posts;
create policy posts_admin_update on public.community_posts
    for update using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- 4) 게시물 삭제 — admin 은 모든 글 DELETE 가능 (운영 모더레이션)
drop policy if exists posts_admin_delete on public.community_posts;
create policy posts_admin_delete on public.community_posts
    for delete using (public.is_admin(auth.uid()));

-- 5) 공지 — 노출 기간 동안 하단 시트로 표시. admin 작성/수정.
create table if not exists public.community_announcements (
    id         uuid primary key default gen_random_uuid(),
    body       text not null,
    starts_at  timestamptz not null default now(),
    ends_at    timestamptz not null default (now() + interval '7 days'),
    active     boolean not null default true,
    created_at timestamptz not null default now()
);
alter table public.community_announcements enable row level security;
-- 모든 사용자: 활성 + 기간 내 공지 읽기 / admin: 전체
drop policy if exists announcements_select on public.community_announcements;
create policy announcements_select on public.community_announcements for select
    using ((active = true and now() between starts_at and ends_at) or public.is_admin(auth.uid()));
drop policy if exists announcements_admin_insert on public.community_announcements;
create policy announcements_admin_insert on public.community_announcements
    for insert with check (public.is_admin(auth.uid()));
drop policy if exists announcements_admin_update on public.community_announcements;
create policy announcements_admin_update on public.community_announcements
    for update using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- 6) 경고 — admin → 특정 사용자. 본인만 읽기.
create table if not exists public.community_warnings (
    id         uuid primary key default gen_random_uuid(),
    target_uid uuid not null,
    message    text not null,
    seen       boolean not null default false,
    created_at timestamptz not null default now()
);
alter table public.community_warnings enable row level security;
drop policy if exists warnings_select_own on public.community_warnings;
create policy warnings_select_own on public.community_warnings for select
    using (target_uid = auth.uid() or public.is_admin(auth.uid()));
drop policy if exists warnings_admin_insert on public.community_warnings;
create policy warnings_admin_insert on public.community_warnings
    for insert with check (public.is_admin(auth.uid()));
drop policy if exists warnings_update_own on public.community_warnings;
create policy warnings_update_own on public.community_warnings
    for update using (target_uid = auth.uid()) with check (target_uid = auth.uid());

-- (선택) 오래된 presence 정리 — 5분 지난 행 삭제하는 스케줄 잡을 두면 테이블 가벼움.
-- delete from public.community_presence where last_seen < now() - interval '10 minutes';
