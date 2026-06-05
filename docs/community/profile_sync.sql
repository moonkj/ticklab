-- TickLab 커뮤니티 — 프로필 서버 동기화 / 로그인 복원
-- ===========================================================================
-- 목적: 프로필(이름·사진·소개·시작연도·브랜드·딜러)을 community_profiles(uid PK)에
--       전부 동기화해, 재설치/기기변경 후 (Apple) 로그인하면 그대로 복원되게 한다.
-- 배경: 기존엔 프로필이 로컬(UserDefaults) 전용 + 서버엔 display_name 만 올라가
--       앱을 지웠다 깔면 사진·이름이 사라졌다. 아래 컬럼 추가로 전체 복원 가능.
-- 적용: Supabase 대시보드 → SQL Editor 에 붙여 실행.
-- 참고: display_name / avatar_path / bio 는 schema.sql 의 community_profiles 에 이미 존재.
--       이 SQL 미배포 시에도 클라이언트는 graceful 동작(이름·아바타·소개만 복원, 나머지는
--       내 최근 게시물에서 보강). 아래는 '전체 필드 복원' 정확도를 위한 것.
-- ===========================================================================

alter table public.community_profiles add column if not exists start_year text;
alter table public.community_profiles add column if not exists fav_brands text;
alter table public.community_profiles add column if not exists rep_brand  text;
alter table public.community_profiles add column if not exists is_dealer  boolean not null default false;

-- RLS 는 schema.sql 에 이미 정의됨:
--   profiles_select(전체 읽기) · profiles_insert_own / profiles_update_own (uid = auth.uid())
-- 추가 정책 불필요.
