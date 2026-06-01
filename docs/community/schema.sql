-- TickLab Community — Supabase/Postgres 스키마 + RLS (SSOT)
-- 2026-05-31. 익명 사진 피드 + 좋아요. Anonymous Auth(auth.uid()) 기준.
-- 적용: Supabase SQL Editor 에서 실행. Anonymous Sign-in 먼저 활성화할 것.

-- ────────────────────────────────────────────────────────────
-- 1. Tables
-- ────────────────────────────────────────────────────────────

create table if not exists public.community_posts (
    id            uuid primary key default gen_random_uuid(),
    author_uid    uuid not null default auth.uid(),
    image_path    text not null,                 -- Storage 'community' 버킷 경로
    brand         text,                          -- 선택: 브랜드 태그 (랭킹 연계)
    caption       text,                          -- 선택: 짧은 한 줄 멘트(≤60자, 온디바이스 텍스트 검열 통과분)
    like_count    int  not null default 0,
    report_count  int  not null default 0,
    status        text not null default 'approved'  -- approved | hidden | blocked
                       check (status in ('approved','hidden','blocked')),
    created_at    timestamptz not null default now()
);
create index if not exists idx_posts_feed
    on public.community_posts (status, created_at desc);
create index if not exists idx_posts_author
    on public.community_posts (author_uid, created_at desc);

create table if not exists public.community_likes (
    post_id  uuid not null references public.community_posts(id) on delete cascade,
    uid      uuid not null default auth.uid(),
    created_at timestamptz not null default now(),
    primary key (post_id, uid)                   -- 멱등: 1인 1좋아요
);

create table if not exists public.community_reports (
    id         uuid primary key default gen_random_uuid(),
    post_id    uuid not null references public.community_posts(id) on delete cascade,
    uid        uuid not null default auth.uid(),
    reason     text,
    created_at timestamptz not null default now(),
    unique (post_id, uid)                        -- 1인 1신고
);

-- 차단: 내가 차단한 작성자 (클라가 피드에서 필터)
create table if not exists public.community_blocks (
    uid          uuid not null default auth.uid(),  -- 차단 주체
    blocked_uid  uuid not null,                     -- 차단 대상
    created_at   timestamptz not null default now(),
    primary key (uid, blocked_uid)
);

-- ────────────────────────────────────────────────────────────
-- 2. 카운터 트리거 (like_count / report_count) + 신고 자동 숨김
-- ────────────────────────────────────────────────────────────

create or replace function public.bump_like_count() returns trigger as $$
begin
    if (tg_op = 'INSERT') then
        update public.community_posts set like_count = like_count + 1 where id = new.post_id;
    elsif (tg_op = 'DELETE') then
        update public.community_posts set like_count = greatest(0, like_count - 1) where id = old.post_id;
    end if;
    return null;
end; $$ language plpgsql security definer;

drop trigger if exists trg_like_count on public.community_likes;
create trigger trg_like_count
    after insert or delete on public.community_likes
    for each row execute function public.bump_like_count();

-- 신고 N회 누적 시 자동 hidden (솔로 운영 — 인력 개입 전 1차 방어)
create or replace function public.bump_report_count() returns trigger as $$
declare threshold constant int := 3;
begin
    update public.community_posts
       set report_count = report_count + 1,
           status = case when report_count + 1 >= threshold then 'hidden' else status end
     where id = new.post_id;
    return null;
end; $$ language plpgsql security definer;

drop trigger if exists trg_report_count on public.community_reports;
create trigger trg_report_count
    after insert on public.community_reports
    for each row execute function public.bump_report_count();

-- ────────────────────────────────────────────────────────────
-- 3. 하루 1장 제한 (서버 강제)
-- ────────────────────────────────────────────────────────────

create or replace function public.enforce_daily_post_limit() returns trigger as $$
begin
    if exists (
        select 1 from public.community_posts
         where author_uid = new.author_uid
           and created_at >= date_trunc('day', now())
    ) then
        raise exception 'daily_post_limit' using errcode = 'P0001';
    end if;
    return new;
end; $$ language plpgsql security definer;

drop trigger if exists trg_daily_limit on public.community_posts;
create trigger trg_daily_limit
    before insert on public.community_posts
    for each row execute function public.enforce_daily_post_limit();

-- 테스트 중 무제한 업로드가 필요하면 트리거만 임시 비활성:
--   drop trigger if exists trg_daily_limit on public.community_posts;
-- 정식 오픈 전 위 create 문을 다시 실행해 복구할 것.

-- ────────────────────────────────────────────────────────────
-- 3b. (이미 배포된 DB용) 증분 마이그레이션 — caption 컬럼 추가
--     처음 schema 를 적용하는 경우 위 create table 에 이미 포함되어 불필요.
-- ────────────────────────────────────────────────────────────
alter table public.community_posts add column if not exists caption text;

-- ────────────────────────────────────────────────────────────
-- 4. RLS — 익명 Auth(auth.uid()) 기준
-- ────────────────────────────────────────────────────────────

alter table public.community_posts   enable row level security;
alter table public.community_likes   enable row level security;
alter table public.community_reports enable row level security;
alter table public.community_blocks  enable row level security;

-- posts: 누구나 approved 만 읽기 / 본인 글은 항상 읽기 / 인증유저만 본인 글 INSERT / 본인 글만 UPDATE·DELETE
drop policy if exists posts_select on public.community_posts;
create policy posts_select on public.community_posts for select
    using (status = 'approved' or author_uid = auth.uid());

drop policy if exists posts_insert on public.community_posts;
create policy posts_insert on public.community_posts for insert
    with check (author_uid = auth.uid());

drop policy if exists posts_update_own on public.community_posts;
create policy posts_update_own on public.community_posts for update
    using (author_uid = auth.uid());

drop policy if exists posts_delete_own on public.community_posts;
create policy posts_delete_own on public.community_posts for delete
    using (author_uid = auth.uid());

-- likes: 본인 것만 insert/delete, 읽기는 본인 것(좋아요 여부 확인용)
drop policy if exists likes_rw on public.community_likes;
create policy likes_rw on public.community_likes for all
    using (uid = auth.uid()) with check (uid = auth.uid());

-- reports: 본인 신고만 insert
drop policy if exists reports_insert on public.community_reports;
create policy reports_insert on public.community_reports for insert
    with check (uid = auth.uid());

-- blocks: 본인 차단 목록만
drop policy if exists blocks_rw on public.community_blocks;
create policy blocks_rw on public.community_blocks for all
    using (uid = auth.uid()) with check (uid = auth.uid());

-- ────────────────────────────────────────────────────────────
-- 5. Storage 버킷 'community' — 콘솔에서 생성 후 정책
--    public read(approved 사진), 본인 폴더만 write.
--    경로 규약: community/{auth.uid()}/{uuid}.jpg
-- ────────────────────────────────────────────────────────────
-- (Storage 정책은 콘솔 Storage > Policies 에서:)
-- SELECT: bucket_id = 'community'                              (공개 읽기)
-- INSERT: bucket_id = 'community' and (storage.foldername(name))[1] = auth.uid()::text

-- ────────────────────────────────────────────────────────────
-- 6. TODO(별도): 기존 brand_wear_stats RLS 강화
--    현재 anon 키로 임의 device_hash write 가능 → 랭킹 조작 구멍.
--    write 시 count 상한·brand 화이트리스트 검증, 직접 SELECT 차단(RPC만).
-- ────────────────────────────────────────────────────────────

-- ════════════════════════════════════════════════════════════
-- 7. 신원 전환 — 공개 프로필 + Apple 로그인 + 팔로우/스크랩 (V2)
--    Apple provider 는 콘솔 Authentication > Providers > Apple 에서 활성화.
--    아래 전체를 SQL Editor 에서 한 번 실행.
-- ════════════════════════════════════════════════════════════

-- 7.0 (이미 배포된 버킷) 공개 읽기 — 사진/아바타가 public URL 로 표시되게.
update storage.buckets set public = true where id = 'community';

-- 7.1 프로필 (auth.uid() 1:1, 공개)
create table if not exists public.community_profiles (
    uid          uuid primary key default auth.uid(),
    display_name text not null default 'Collector',
    avatar_path  text,
    bio          text,
    created_at   timestamptz not null default now()
);
alter table public.community_profiles enable row level security;
drop policy if exists profiles_select on public.community_profiles;
create policy profiles_select on public.community_profiles for select using (true);
drop policy if exists profiles_insert_own on public.community_profiles;
create policy profiles_insert_own on public.community_profiles for insert with check (uid = auth.uid());
drop policy if exists profiles_update_own on public.community_profiles;
create policy profiles_update_own on public.community_profiles for update using (uid = auth.uid());

-- 7.2 게시물 작성자 표시명 비정규화(피드 1쿼리 렌더). 이름 변경은 신규 글부터 반영.
alter table public.community_posts add column if not exists author_name text;
alter table public.community_posts add column if not exists author_avatar_path text;

-- 7.3 팔로우
create table if not exists public.community_follows (
    follower_uid uuid not null default auth.uid(),
    followed_uid uuid not null,
    created_at   timestamptz not null default now(),
    primary key (follower_uid, followed_uid),
    check (follower_uid <> followed_uid)
);
alter table public.community_follows enable row level security;
drop policy if exists follows_select on public.community_follows;
create policy follows_select on public.community_follows for select using (true);
drop policy if exists follows_rw on public.community_follows;
create policy follows_rw on public.community_follows for all
    using (follower_uid = auth.uid()) with check (follower_uid = auth.uid());

-- 7.4 스크랩/저장(북마크)
create table if not exists public.community_bookmarks (
    uid        uuid not null default auth.uid(),
    post_id    uuid not null references public.community_posts(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (uid, post_id)
);
alter table public.community_bookmarks enable row level security;
drop policy if exists bookmarks_rw on public.community_bookmarks;
create policy bookmarks_rw on public.community_bookmarks for all
    using (uid = auth.uid()) with check (uid = auth.uid());
