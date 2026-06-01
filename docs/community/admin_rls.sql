-- TickLab 운영 관리자 — Supabase 보안 강제 (RLS)
-- ===========================================================================
-- 목적: 클라이언트가 author_name="TickLab" 로 게시하는 것을 "실제 관리자 uid" 로만 제한.
-- 배경: 앱의 운영 ID 토글(ticklab.admin.actingAsTickLab)은 클라이언트 편의/표시용이며
--       탈옥 기기에서 위조 가능하다. 따라서 'TickLab' 같은 예약 닉네임 사용은 반드시
--       서버 RLS 로 강제해야 한다 (운영 사양서 §5 신뢰안전·§6 감사 결론).
-- 적용: Supabase 대시보드 → SQL Editor 에 붙여 실행.
-- ===========================================================================

-- 1) 관리자 계정 테이블 -------------------------------------------------------
create table if not exists public.admin_users (
    uid        uuid primary key,
    name       text not null default 'TickLab',
    role       text not null default 'admin',     -- 'admin' | 'moderator'
    created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;

-- 본인 admin 여부만 확인 가능(전체 목록 노출 금지).
drop policy if exists admin_users_self_select on public.admin_users;
create policy admin_users_self_select on public.admin_users
    for select using (uid = auth.uid());

-- 2) admin 판별 함수 ---------------------------------------------------------
create or replace function public.is_admin(check_uid uuid)
returns boolean
language sql
security definer
stable
as $$
    select exists (select 1 from public.admin_users where uid = check_uid);
$$;

-- 3) 예약 닉네임 게시 제한 ----------------------------------------------------
--    community_posts INSERT 시: author_name 이 예약어면 admin uid 만 허용.
--    (일반 사용자는 예약어 외 자유 닉네임 사용 가능)
drop policy if exists community_posts_insert_guard on public.community_posts;
create policy community_posts_insert_guard on public.community_posts
    for insert
    with check (
        author_uid = auth.uid()
        and (
            coalesce(author_name, '') not in
                ('TickLab', 'TickLab Team', 'TickLab 운영', '운영', 'Admin')
            or public.is_admin(auth.uid())
        )
    );

-- 4) (선택) 관리자 하루 1장 제한 면제 ----------------------------------------
--    기존 daily_post_limit 트리거 함수 맨 앞에 아래를 추가하면 관리자는 공지 다회 게시 가능:
--      if public.is_admin(new.author_uid) then return new; end if;

-- 5) 운영자 등록 ------------------------------------------------------------
--    앱에서 Apple 로그인 후 본인 auth uid 를 확인하여 등록:
--      insert into public.admin_users (uid, name) values ('<your-auth-uid>', 'TickLab')
--      on conflict (uid) do nothing;

-- ===========================================================================
-- NOTE: 이 SQL 은 "TickLab 게시" 위조 방지의 최소 요건이다. 신고 큐·제재·감사 로그 등
--       나머지 운영 기능은 운영 사양서 결론대로 별도 백엔드/웹 어드민 콘솔에서 처리한다
--       (측정 데이터(A 영역)는 운영 백엔드(B)로 절대 전송 금지 — Hard Rule #8 불변).
-- ===========================================================================
