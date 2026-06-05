-- TickLab — 프로필 전체 복원 활성화 (로그인 시 시작연도·좋아하는 브랜드·대표 메이커·소개까지 복원)
-- ===========================================================================
-- 증상: 재설치 후 로그인하면 이름·사진만 돌아오고 컬렉션 시작연도/좋아하는 브랜드/
--       대표 메이커/소개는 안 돌아온다.
-- 원인: 이 필드를 담는 컬럼이 community_profiles 에 없어서 클라이언트가 push 할 때
--       graceful 폴백으로 그 컬럼들을 떼고 보냄(이름/사진/소개만 저장) → 복원할 데이터가 서버에 없음.
-- 조치: 아래를 Supabase 대시보드 → SQL Editor 에 붙여 1회 실행. 모두 멱등(IF NOT EXISTS)이라
--       이미 일부 적용돼 있어도 안전.
-- 실행 후: 로그인 상태에서 프로필을 한 번 저장(편집→완료)하면 전체 필드가 서버에 올라가고,
--          이후 재설치/기기변경 후 로그인하면 전부 복원된다.
-- ===========================================================================

-- 1) 프로필 본체 컬럼 (복원의 주 경로)
alter table public.community_profiles add column if not exists start_year text;
alter table public.community_profiles add column if not exists fav_brands text;
alter table public.community_profiles add column if not exists rep_brand  text;
alter table public.community_profiles add column if not exists is_dealer  boolean not null default false;

-- 2) 게시물 작성자 스냅샷 (보조 복원 경로 — 게시 이력이 있으면 여기서도 보강)
alter table public.community_posts add column if not exists author_bio        text;
alter table public.community_posts add column if not exists author_start_year text;
alter table public.community_posts add column if not exists author_fav_brands text;

-- RLS 는 schema.sql 의 profiles_select / profiles_insert_own / profiles_update_own 로 충분 — 추가 불필요.
