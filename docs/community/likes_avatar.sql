-- 좋아요 누른 사람 목록에 아바타(대표사진) 표시용 컬럼.
-- community_likes 에 author_avatar_path 추가 — 게시물(community_posts.author_avatar_path)과 동일 의미.
-- 클라이언트는 좋아요 직후 best-effort PATCH 로 본인 아바타 경로를 기록한다(컬럼 없으면 조용히 무시 → 좋아요는 안 깨짐).
-- 기존 좋아요엔 소급 적용 안 됨(새 좋아요부터 사진 표시).

ALTER TABLE community_likes ADD COLUMN IF NOT EXISTS author_avatar_path text;
