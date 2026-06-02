-- TickLab — 최근 기능들 통합 배포 SQL (전부 idempotent: 이미 적용된 것도 재실행 무해).
-- 전제: schema.sql(기본 테이블) + admin_rls.sql(is_admin·admin_users)이 이미 배포돼 있어야 함.
-- Supabase SQL Editor 에 통째로 붙여넣고 Run.

-- ─────────────────────────────────────────────────────────
-- 1) 댓글 (community_comments) + 댓글 수 트리거
-- ─────────────────────────────────────────────────────────
create table if not exists public.community_comments (
    id          uuid primary key default gen_random_uuid(),
    post_id     uuid not null references public.community_posts(id) on delete cascade,
    uid         uuid not null default auth.uid(),
    author_name text,
    body        text not null,
    status      text not null default 'visible',
    created_at  timestamptz not null default now()
);
create index if not exists idx_comments_post on public.community_comments (post_id, created_at);
alter table public.community_comments enable row level security;
drop policy if exists comments_select on public.community_comments;
create policy comments_select on public.community_comments for select
    using (status = 'visible' or public.is_admin(auth.uid()) or uid = auth.uid());
drop policy if exists comments_insert_own on public.community_comments;
create policy comments_insert_own on public.community_comments for insert with check (uid = auth.uid());
drop policy if exists comments_delete_own_or_admin on public.community_comments;
create policy comments_delete_own_or_admin on public.community_comments for delete
    using (uid = auth.uid() or public.is_admin(auth.uid()));
drop policy if exists comments_admin_update on public.community_comments;
create policy comments_admin_update on public.community_comments for update
    using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

alter table public.community_posts add column if not exists comment_count int not null default 0;
create or replace function public.bump_comment_count() returns trigger
language plpgsql security definer as $$
begin
    if (tg_op = 'INSERT') then
        update public.community_posts set comment_count = comment_count + 1 where id = new.post_id;
    elsif (tg_op = 'DELETE') then
        update public.community_posts set comment_count = greatest(0, comment_count - 1) where id = old.post_id;
    end if;
    return null;
end; $$;
drop trigger if exists trg_comment_count on public.community_comments;
create trigger trg_comment_count after insert or delete on public.community_comments
    for each row execute function public.bump_comment_count();

-- ─────────────────────────────────────────────────────────
-- 2) 좋아요 라이커 공개(인스타 "누가 좋아요") — 이름 비정규화 + 전체 읽기
-- ─────────────────────────────────────────────────────────
alter table public.community_likes add column if not exists author_name text;
drop policy if exists likes_select_all on public.community_likes;
create policy likes_select_all on public.community_likes for select using (true);

-- 2-b) 좋아요 알림용 — 글 작성자가 본인 게시물 좋아요 읽기(전체공개와 OR로 공존).
drop policy if exists likes_select_post_author on public.community_likes;
create policy likes_select_post_author on public.community_likes for select
    using (
        uid = auth.uid()
        or exists (select 1 from public.community_posts p where p.id = post_id and p.author_uid = auth.uid())
    );

-- ─────────────────────────────────────────────────────────
-- 3) 닉네임 중복 방지 — 대소문자 무시 unique
-- ─────────────────────────────────────────────────────────
create unique index if not exists community_profiles_display_name_key
    on public.community_profiles (lower(display_name));

-- ─────────────────────────────────────────────────────────
-- 4) 공지 삭제 정책
-- ─────────────────────────────────────────────────────────
drop policy if exists announcements_admin_delete on public.community_announcements;
create policy announcements_admin_delete on public.community_announcements
    for delete using (public.is_admin(auth.uid()));

-- ─────────────────────────────────────────────────────────
-- 5) 큐레이션 YouTube 채널 (영상 피드)
-- ─────────────────────────────────────────────────────────
create table if not exists public.curated_channels (
    id            uuid primary key default gen_random_uuid(),
    channel_id    text not null,
    title         text not null,
    thumbnail_url text,
    locale        text not null default 'en',
    category      text,
    sort_order    int  not null default 0,
    active        boolean not null default true,
    created_at    timestamptz not null default now(),
    unique (channel_id, locale)
);
create index if not exists idx_curated_active on public.curated_channels (active, locale, sort_order);
alter table public.curated_channels enable row level security;
drop policy if exists curated_channels_select on public.curated_channels;
create policy curated_channels_select on public.curated_channels for select
    using (active = true or public.is_admin(auth.uid()));
drop policy if exists curated_channels_admin_insert on public.curated_channels;
create policy curated_channels_admin_insert on public.curated_channels
    for insert with check (public.is_admin(auth.uid()));
drop policy if exists curated_channels_admin_update on public.curated_channels;
create policy curated_channels_admin_update on public.curated_channels
    for update using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));
drop policy if exists curated_channels_admin_delete on public.curated_channels;
create policy curated_channels_admin_delete on public.curated_channels
    for delete using (public.is_admin(auth.uid()));

-- ─────────────────────────────────────────────────────────
-- 6) 채널 제안 (사용자 → 운영자)
-- ─────────────────────────────────────────────────────────
create table if not exists public.channel_suggestions (
    id         uuid primary key default gen_random_uuid(),
    uid        uuid not null default auth.uid(),
    url        text not null,
    note       text,
    created_at timestamptz not null default now()
);
create index if not exists idx_suggestions_created on public.channel_suggestions (created_at desc);
alter table public.channel_suggestions enable row level security;
drop policy if exists suggestions_insert_own on public.channel_suggestions;
create policy suggestions_insert_own on public.channel_suggestions for insert with check (uid = auth.uid());
drop policy if exists suggestions_admin_select on public.channel_suggestions;
create policy suggestions_admin_select on public.channel_suggestions for select using (public.is_admin(auth.uid()));
drop policy if exists suggestions_admin_delete on public.channel_suggestions;
create policy suggestions_admin_delete on public.channel_suggestions for delete using (public.is_admin(auth.uid()));

-- ─────────────────────────────────────────────────────────
-- 7) 글-전용 게시 (Round 171) — image_path nullable + 빈 게시 방지 CHECK
--    ※ 미배포 시 사진 없는 글 게시가 NOT NULL 위반으로 전부 실패하므로 필수.
-- ─────────────────────────────────────────────────────────
alter table public.community_posts alter column image_path drop not null;
alter table public.community_posts drop constraint if exists community_posts_content_present;
alter table public.community_posts add constraint community_posts_content_present
    check (
        image_path is not null
        or (caption is not null and length(btrim(caption)) > 0)
    );

-- ─────────────────────────────────────────────────────────
-- 8) 닉네임 옆 장착 뱃지 (Round 171) — author_badge 컬럼
--    ※ 미배포 시 uploadPost 의 author_badge 필드가 PostgREST 400 유발 가능.
-- ─────────────────────────────────────────────────────────
alter table public.community_posts add column if not exists author_badge text;
alter table public.community_posts drop constraint if exists community_posts_author_badge_len;
alter table public.community_posts add constraint community_posts_author_badge_len
    check (author_badge is null or char_length(author_badge) <= 8);

-- ─────────────────────────────────────────────────────────
-- 9) 아바타 하단 대표 시계 메이커 (Round 174) — author_rep_brand 컬럼
--    프로필 '좋아하는 브랜드' 1순위를 게시 시 비정규화 저장. 피드 아바타 하단 칩.
--    ※ 미배포 시 uploadPost 의 author_rep_brand 필드가 PostgREST 400 유발 → 게시 전체 실패.
--      이 빌드 설치 전에 반드시 먼저 실행할 것.
-- ─────────────────────────────────────────────────────────
alter table public.community_posts add column if not exists author_rep_brand text;
alter table public.community_posts drop constraint if exists community_posts_author_rep_brand_len;
alter table public.community_posts add constraint community_posts_author_rep_brand_len
    check (author_rep_brand is null or char_length(author_rep_brand) <= 40);

-- ─────────────────────────────────────────────────────────
-- 10) 인앱 피드백 (Round 175) — app_feedback 테이블 (mailto 대체)
--     사용자 설정>피드백 → Supabase 수집 → 운영 대시보드(AdminOpsView)에서 확인.
--     ※ admin_rls.sql(is_admin) 먼저 배포돼 있어야 운영자 조회 가능.
--       미배포 시 submitFeedback 이 실패(전송 실패 alert)하지만 게시 등 다른 기능엔 영향 없음.
--     전체 정의·인덱스·RLS 는 docs/community/app_feedback.sql.
-- ─────────────────────────────────────────────────────────
create table if not exists public.app_feedback (
    id          uuid primary key default gen_random_uuid(),
    uid         uuid not null default auth.uid(),
    type        text not null default 'general',
    message     text not null,
    app_version text,
    created_at  timestamptz not null default now()
);
create index if not exists idx_app_feedback_created on public.app_feedback (created_at desc);
alter table public.app_feedback enable row level security;
drop policy if exists app_feedback_insert_own on public.app_feedback;
create policy app_feedback_insert_own on public.app_feedback
    for insert with check (uid = auth.uid());
drop policy if exists app_feedback_admin_select on public.app_feedback;
create policy app_feedback_admin_select on public.app_feedback
    for select using (public.is_admin(auth.uid()));
drop policy if exists app_feedback_admin_delete on public.app_feedback;
create policy app_feedback_admin_delete on public.app_feedback
    for delete using (public.is_admin(auth.uid()));
