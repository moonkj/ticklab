-- Round 171 (2026-06-02): 커뮤니티 글-전용 게시 지원.
-- 기존 community_posts.image_path 는 NOT NULL 이라 사진 없이 글만 올릴 수 없었음.
-- → image_path nullable 로 완화 + "사진 또는 캡션 중 하나는 반드시" CHECK 로 빈 게시 차단.
--
-- 적용: Supabase SQL Editor 에서 실행. RLS/insert 정책·하루1장 트리거는 변경 없음
-- (글-전용도 행 1건이라 기존 daily-limit 트리거가 동일하게 카운트).

-- 1) image_path NOT NULL 해제 (글-전용이면 NULL).
alter table public.community_posts
    alter column image_path drop not null;

-- 2) 빈 게시 방지 — 사진 경로 또는 비어있지 않은 캡션 중 하나는 반드시 존재.
alter table public.community_posts
    drop constraint if exists community_posts_content_present;
alter table public.community_posts
    add constraint community_posts_content_present
    check (
        image_path is not null
        or (caption is not null and length(btrim(caption)) > 0)
    );
