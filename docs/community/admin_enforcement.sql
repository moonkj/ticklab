-- TickLab 운영 본체 — 제재(단계적) + 감사 로그 (Supabase 백엔드 초안)
-- ===========================================================================
-- 선행: admin_rls.sql(admin_users·is_admin·posts_insert 가드), admin_ops.sql 적용.
-- 이 스키마는 "웹 어드민 콘솔"이 사용하는 운영 본체. iOS 앱은 결과(차단/경고)만 받음.
-- 운영 사양서 §4(제재)·§6(감사) + 모더레이션 정책 §4 대응. 측정 데이터(A)는 비대상.
-- ===========================================================================

-- 1) 제재 테이블 — 단계: 1 경고 / 2 콘텐츠처리 / 3 일시정지 / 4 영구차단
create table if not exists public.community_sanctions (
    id          uuid primary key default gen_random_uuid(),
    target_uid  uuid not null,
    level       int  not null check (level between 1 and 4),
    reason      text not null,
    reason_code text,                       -- 정책 사유 코드(거래/욕설/사기 등)
    admin_uid   uuid not null default auth.uid(),
    created_at  timestamptz not null default now(),
    expires_at  timestamptz                 -- 일시정지(3) 만료. 영구차단(4)·경고는 null
);
create index if not exists idx_sanctions_target on public.community_sanctions(target_uid, created_at desc);
alter table public.community_sanctions enable row level security;

-- 본인 제재 조회(통지용) / admin 전체
drop policy if exists sanctions_select on public.community_sanctions;
create policy sanctions_select on public.community_sanctions for select
    using (target_uid = auth.uid() or public.is_admin(auth.uid()));
-- admin 만 부과/수정(이의신청 처리 시 취소)
drop policy if exists sanctions_admin_write on public.community_sanctions;
create policy sanctions_admin_write on public.community_sanctions for all
    using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- 현재 게시 제한(일시정지 미만료 OR 영구차단) 여부
create or replace function public.is_sanctioned(check_uid uuid)
returns boolean language sql security definer stable as $$
    select exists (
        select 1 from public.community_sanctions
        where target_uid = check_uid
          and (level = 4 or (level = 3 and (expires_at is null or expires_at > now())))
    );
$$;

-- 2) 게시 차단 — posts_insert 정책에 제재 검사 추가.
--    ⚠️ admin_rls.sql 의 posts_insert(거래 예약닉네임 가드)를 아래로 "교체" (OR 합성 무력화 방지).
drop policy if exists posts_insert on public.community_posts;
create policy posts_insert on public.community_posts for insert
    with check (
        author_uid = auth.uid()
        and not public.is_sanctioned(auth.uid())          -- 정지/차단 사용자 게시 금지
        and (
            coalesce(author_name, '') not in
                ('TickLab', 'TickLab Team', 'TickLab 운영', '운영', 'Admin')
            or public.is_admin(auth.uid())
        )
    );

-- 3) 감사 로그 — 모든 운영 액션 기록(분쟁·이의신청 증거). 변조 방지 위해 update/delete 미허용.
create table if not exists public.community_moderation_log (
    id         uuid primary key default gen_random_uuid(),
    action     text not null,               -- report_process/hide/delete/warn/sanction/announce
    target_id  uuid,                         -- post_id 또는 user_uid
    reason     text,
    admin_uid  uuid not null default auth.uid(),
    created_at timestamptz not null default now()
);
alter table public.community_moderation_log enable row level security;
drop policy if exists modlog_admin_select on public.community_moderation_log;
create policy modlog_admin_select on public.community_moderation_log for select
    using (public.is_admin(auth.uid()));
drop policy if exists modlog_admin_insert on public.community_moderation_log;
create policy modlog_admin_insert on public.community_moderation_log for insert
    with check (public.is_admin(auth.uid()) and admin_uid = auth.uid());
-- update/delete 정책 없음 → 누구도 수정/삭제 불가(변조 방지).

-- ===========================================================================
-- NOTE
-- - 단계적 제재·이의신청 워크플로·CSAM 외부연동은 웹 어드민 콘솔에서 이 스키마 위에 구현.
-- - iOS 앱: 정지/차단 사용자는 게시 시 서버가 거부(uploadPost 가 에러 표시). 경고는 community_warnings 로 통지.
-- - 측정 데이터(A)는 이 운영 백엔드(B)에 절대 전송/저장 금지 — Hard Rule #8.
-- ===========================================================================
