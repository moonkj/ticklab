-- 프로필(UserPostsView)에 컬렉터 정보 표시용 — 게시물에 작성자 프로필 스냅샷을 비정규화.
-- author_rep_brand(대표 메이커)는 이미 존재. 아래 3개 추가: 소개·컬렉션 시작연도·좋아하는 브랜드.
-- 클라이언트는 게시 INSERT 에 포함하며, 컬럼 미배포 시 PGRST204 → 해당 컬럼만 빼고 1회 재시도(게시 안 깨짐).
-- 욕설 필터 통과분만 업로드(소개·브랜드).

ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS author_bio text;
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS author_start_year text;
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS author_fav_brands text;
