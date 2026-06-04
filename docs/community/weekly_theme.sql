-- 스트림C (2026-06-04): 위클리 테마 챌린지.
-- 운영(TickLab)이 주간 테마를 내리고 피드 상단 배너 + 작성 시 "이번 주 테마로 게시" 토글.
-- 기존 community_announcements 를 kind='theme' 로 확장(별도 테이블 없이 재사용).
--
-- 배포 순서: admin_ops.sql(community_announcements 생성) + admin_rls.sql(is_admin) 먼저 → 이 파일.
-- 클라는 신규 컬럼 미배포 시에도 graceful degrade(테마 배너 미표시·게시 정상). 배포는 개발자.

-- 1) 공지 테이블에 kind / theme_title 컬럼 추가.
--    kind: 'notice'(기본 일반 공지) | 'theme'(위클리 테마). 기존 행은 'notice'.
alter table public.community_announcements
    add column if not exists kind text not null default 'notice';
alter table public.community_announcements
    add column if not exists theme_title text;

-- 2) 게시물에 theme_id — 어떤 위클리 테마로 게시됐는지 귀속(선택). NULL = 테마 미참여.
--    on delete set null: 테마(공지) 삭제돼도 게시물은 보존.
alter table public.community_posts
    add column if not exists theme_id uuid
    references public.community_announcements(id) on delete set null;
create index if not exists idx_posts_theme on public.community_posts (theme_id);

-- 3) 활성 테마 1건 조회는 기존 announcements_select RLS 로 충분
--    (active = true and now() between starts_at and ends_at). 추가 정책 불필요.
--    클라: fetchActiveTheme() → kind=eq.theme&active=eq.true&기간 필터.

-- 4) (선택) theme 행은 body NOT NULL 이므로 운영자 발행 시 theme_title 과 별개로 body 도 채워야 함.
--    클라 postWeeklyTheme() 는 body 비면 title 로 채워 보냄(스키마 호환).

-- 참고: 위조 방지(임의 사용자가 kind='theme' 공지 작성) 는 기존 announcements_admin_insert
--   (with check is_admin(auth.uid())) RLS 로 이미 차단됨 — 추가 작업 없음.
