-- TickLab 큐레이션 YouTube 채널 (영상 피드) — 운영자 관리, 전 사용자 공통, 언어별.
-- 배포 순서: admin_rls.sql(is_admin·admin_users) 먼저 → 이 파일.
-- 재생/수집은 앱이 채널 RSS(https://www.youtube.com/feeds/videos.xml?channel_id=...)를 직접 읽음(클라이언트).
--   → 별도 videos 캐시 테이블·서버 폴링 없음(MVP). 채널 목록만 서버에 둔다.

create table if not exists public.curated_channels (
    id            uuid primary key default gen_random_uuid(),
    channel_id    text not null,                  -- YouTube 채널 ID(UCxxxx) — RSS 키
    title         text not null,                  -- 표시 채널명
    thumbnail_url text,
    locale        text not null default 'en',     -- 언어 코드(base): 'ko','en','ja','zh-Hans','zh-Hant','es','hi','fr'
    category      text,                            -- 'review'/'news'/'repair' 등(선택, 필터용)
    sort_order    int  not null default 0,
    active        boolean not null default true,
    created_at    timestamptz not null default now(),
    unique (channel_id, locale)                    -- 같은 채널을 여러 언어에 노출 가능
);
create index if not exists idx_curated_active
    on public.curated_channels (active, locale, sort_order);

alter table public.curated_channels enable row level security;

-- 공개 읽기: 활성 채널은 모두 / 운영자는 전체(관리 목록용, 비활성 포함).
drop policy if exists curated_channels_select on public.curated_channels;
create policy curated_channels_select on public.curated_channels for select
    using (active = true or public.is_admin(auth.uid()));

-- 운영자만 추가/수정/삭제.
drop policy if exists curated_channels_admin_insert on public.curated_channels;
create policy curated_channels_admin_insert on public.curated_channels
    for insert with check (public.is_admin(auth.uid()));
drop policy if exists curated_channels_admin_update on public.curated_channels;
create policy curated_channels_admin_update on public.curated_channels
    for update using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));
drop policy if exists curated_channels_admin_delete on public.curated_channels;
create policy curated_channels_admin_delete on public.curated_channels
    for delete using (public.is_admin(auth.uid()));
