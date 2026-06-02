-- TickLab 인앱 피드백 — 사용자가 설정>피드백에서 보낸 의견(버그/제안/일반)을 운영자에게 수집.
-- 배포 순서: admin_rls.sql(is_admin) 먼저 → 이 파일.
-- 사용자(익명 세션 포함)는 본인 피드백 INSERT만, 운영자만 조회/삭제.
-- (Round 175) 기존 mailto 대신 Supabase 로 수집 → 운영 대시보드(AdminOpsView)에서 확인.

create table if not exists public.app_feedback (
    id          uuid primary key default gen_random_uuid(),
    uid         uuid not null default auth.uid(),
    type        text not null default 'general',   -- 'bug' | 'suggestion' | 'general'
    message     text not null,
    app_version text,
    created_at  timestamptz not null default now()
);
create index if not exists idx_app_feedback_created
    on public.app_feedback (created_at desc);

alter table public.app_feedback enable row level security;

-- 제출: 본인 uid 로만 INSERT.
drop policy if exists app_feedback_insert_own on public.app_feedback;
create policy app_feedback_insert_own on public.app_feedback
    for insert with check (uid = auth.uid());

-- 조회/삭제: 운영자만.
drop policy if exists app_feedback_admin_select on public.app_feedback;
create policy app_feedback_admin_select on public.app_feedback
    for select using (public.is_admin(auth.uid()));
drop policy if exists app_feedback_admin_delete on public.app_feedback;
create policy app_feedback_admin_delete on public.app_feedback
    for delete using (public.is_admin(auth.uid()));
