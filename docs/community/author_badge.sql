-- Round 171 (2026-06-02): 닉네임 옆 장착 뱃지 표시.
-- 작성자가 BadgesView 에서 장착한 뱃지 이모지를 게시물과 함께 저장 → 피드에서 닉네임 옆에 노출.
-- (뱃지는 클라 로컬 데이터로 산출되므로, 다른 사용자에게 보이려면 게시 시 이모지를 함께 전송한다.)
--
-- 적용: Supabase SQL Editor 에서 실행. 기존 행은 NULL(미표시).

alter table public.community_posts
    add column if not exists author_badge text;

-- 길이 가드(이모지 1~2자 정도만) — 악용/오남용 방지.
alter table public.community_posts
    drop constraint if exists community_posts_author_badge_len;
alter table public.community_posts
    add constraint community_posts_author_badge_len
    check (author_badge is null or char_length(author_badge) <= 8);
