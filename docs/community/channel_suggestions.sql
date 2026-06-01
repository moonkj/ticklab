-- TickLab 영상 채널 제안 — 사용자가 추천 YouTube 채널 주소를 운영자에게 제출.
-- 배포 순서: admin_rls.sql(is_admin) 먼저 → 이 파일.
-- 사용자(익명 세션 포함)는 본인 제안 INSERT만, 운영자만 조회/삭제.

create table if not exists public.channel_suggestions (
    id         uuid primary key default gen_random_uuid(),
    uid        uuid not null default auth.uid(),
    url        text not null,
    note       text,
    created_at timestamptz not null default now()
);
create index if not exists idx_suggestions_created
    on public.channel_suggestions (created_at desc);

alter table public.channel_suggestions enable row level security;

-- 제출: 본인 uid 로만 INSERT.
drop policy if exists suggestions_insert_own on public.channel_suggestions;
create policy suggestions_insert_own on public.channel_suggestions
    for insert with check (uid = auth.uid());

-- 조회/삭제: 운영자만.
drop policy if exists suggestions_admin_select on public.channel_suggestions;
create policy suggestions_admin_select on public.channel_suggestions
    for select using (public.is_admin(auth.uid()));
drop policy if exists suggestions_admin_delete on public.channel_suggestions;
create policy suggestions_admin_delete on public.channel_suggestions
    for delete using (public.is_admin(auth.uid()));
