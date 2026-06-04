-- 스트림C (2026-06-04): 브랜드 태그 부활.
-- community_posts.brand 컬럼은 schema.sql 에 이미 존재(text, nullable). 그러나 클라
-- uploadPost(brand:) 가 늘 nil 을 보내 사용 안 됐음 → 작성기에서 내 컬렉션 브랜드
-- 화이트리스트 칩으로 채워 보내도록 클라 수정. 이 파일은 서버측 보조(인덱스·검증) 메모.
--
-- 배포 순서: schema.sql(community_posts) 먼저 → 이 파일. 배포는 개발자.
-- 클라는 이 파일 미배포 시에도 정상 동작(brand 필터는 기존 컬럼 기반).

-- 1) 브랜드 필터 조회 가속 — 카드 브랜드 칩 탭 시 ?brand=eq.<brand> 모아보기.
create index if not exists idx_posts_brand
    on public.community_posts (brand, created_at desc)
    where brand is not null;

-- 2) (선택·권장) 거래유도 방지 가드 — brand 는 짧은 메타여야 함(시세·모델명·연락처 차단).
--    화이트리스트는 클라(내 컬렉션 브랜드)에서 1차 강제하지만, 서버 길이 상한으로 2차 방어.
alter table public.community_posts
    drop constraint if exists community_posts_brand_len;
alter table public.community_posts
    add constraint community_posts_brand_len
    check (brand is null or length(btrim(brand)) <= 40);

-- 참고: 측정 데이터(rate/amplitude/serial/구매가)는 brand 와 무관 — 전송 절대 금지 원칙 유지.
--   brand 는 브랜드명 1개(메타 수준)만 허용. 별도 구조적 측정 필드 추가 없음.
