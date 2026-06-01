-- TickLab 좋아요 라이커 공개(인스타 스타일 "누가 좋아요 했나") — 이름 비정규화 + 전체 읽기.
-- 배포 순서: schema.sql(community_likes) 먼저 → 이 파일.
-- 주의: 좋아요를 전체 공개로 전환(기존 본인만 읽기). 익명 닉네임이므로 표시명만 노출.

alter table public.community_likes add column if not exists author_name text;

-- 전체 읽기(라이커 목록 표시용). INSERT/DELETE 는 기존 likes_rw(uid=auth.uid())가 계속 강제.
drop policy if exists likes_select_all on public.community_likes;
create policy likes_select_all on public.community_likes for select using (true);
