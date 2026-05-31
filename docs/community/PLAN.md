# TickLab Community — 구현 설계 (Phase 2)

> 2026-05-31 착수. 4직군 팀 토론 + 개발자 승인 반영. 측정 전용 앱 아님 — 생활기록 플랫폼의 커뮤니티 축.

## 1. 컨셉 (확정)

- **익명 사진 피드 + 좋아요.** 닉네임/실명 비노출. 하루 **1장** 게시.
- 화면 표시는 익명이지만, 검열·차단·소유권을 위해 **내부 안정 ID**(Supabase Anonymous Auth)는 보유.
- **게이팅(콜드스타트 후 ON):** 무료 = 최근 ~10장 풀 노출 + 인기글 부분 흐림 + "Pro로 전체 보기". 본인 글·하루 1장 업로드·좋아요는 영속 무료.
- **검열:** 온디바이스 사전필터(SensitiveContentAnalysis) + 신고기반 자동 숨김. 외부 vision API 미사용.

## 2. 단계 (콜드스타트 → 수익화)

1. **C1 (현재):** 결정 기록·스키마·피처플래그·코어(모델·검열). 백엔드 OFF.
2. **C2:** 클라 서비스(Anon Auth·업로드·피드·좋아요·신고/차단) + 피드/작성 UI(PhotoCropView 재사용) + EULA 게이트. 게이팅 OFF.
3. **C3 (밀도 확보 후):** 페이월 게이팅 ON — 최근 N장 + 인기글 부분 흐림 + `PurchaseRouter.Intent.community`.
4. **C4:** 신고 자동숨김 튜닝·원격 N 조정·시딩(레퍼럴 연계).

## 3. 데이터 모델 — `schema.sql` 참조

- `community_posts(id, author_uid, image_path, brand, like_count, report_count, status, created_at)`
- `community_likes(post_id, uid)` PK(post_id, uid) — 멱등
- `community_reports(id, post_id, uid, reason, created_at)` unique(post_id, uid)
- Storage 버킷 `community` (사진). 클라에서 4:3 크롭 + 장변 1280 리사이즈 후 업로드(egress 절감).
- `status`: `pending`→`approved`(기본 자동 통과) / `hidden`(report_count ≥ N 자동) / `blocked`.
- 하루 1장: `community_posts` INSERT 트리거 또는 RLS에서 `created_at::date` 당일 본인 글 존재 시 거부.

## 4. 게이팅 규칙 (C3)

| 대상 | 무료 | Pro |
|---|---|---|
| 최근 ~10장 (원격 N) | 풀 노출 | 풀 노출 |
| 그 이후 인기글(좋아요 임계↑) | 부분 흐림 + CTA | 풀 노출 |
| 본인 글 / 하루 1장 업로드 / 좋아요 | 무료 | 무료 |

- 흐림: blur radius ~18, dim 0.35, 실루엣·좋아요 수는 비침(사회적 증거). **가짜 카운트·클릭베이트 금지.**
- 페이월: **스크롤 도달·CTA 탭 시에만**(진입 즉시 금지). 24h 노출 1회 cap.
- N은 하드코딩 금지 — 원격/FeatureFlags 조정.

## 5. 검열 (기기 + 신고)

- **사전(클라):** 업로드 직전 `CommunityModerationService.isSensitive(image)` (SensitiveContentAnalysis). true면 게시 차단 + 안내. 기능 `.disabled`면 통과시키고 신고기반에 위임.
- **사후(서버):** `report_count ≥ THRESHOLD` → `status='hidden'` 자동(트리거). 피드 쿼리는 `status='approved'`만.
- EXIF strip 필수(`EXIFStripper`). 측정/시리얼/구매가 전송 금지.

## 6. App Store UGC 필수 (Guideline 1.2 — 없으면 리젝)

- [ ] **신고(report)** — 모든 게시물 1탭
- [ ] **차단(block)** — 작성자 안 보이게(내부 안정 ID 기준)
- [ ] **콘텐츠 필터** — 온디바이스 사전필터(위)
- [ ] **zero-tolerance EULA** — 가입/첫 게시 흐름에 명시 동의
- [ ] **24h 내 조치 + 신고자 통보** 프로세스
- [ ] **연락처** 노출(앱 내 또는 메타데이터)
- [ ] 연령 등급 **17+**(또는 최소 12+)
- [ ] 타인 식별정보 업로드 금지 동의

## 7. 개발자(배포) 체크리스트 — 백엔드

> 클라이언트는 코드로 준비되나, 아래는 Supabase 콘솔/CLI에서 직접:

1. Supabase **Anonymous Sign-in 활성화** (Auth settings).
2. `schema.sql` 실행 (테이블·RLS·트리거).
3. Storage 버킷 `community` 생성 + RLS(본인 업로드만, 공개 읽기는 approved).
4. (기존) brand_wear_stats **RLS 강화**도 같이 — 현재 anon 키로 임의 write 가능(랭킹 조작 구멍).
5. App Store Connect: 연령 17+, EULA(zero-tolerance) 등록, 개인정보 처리방침 갱신.
6. `Secrets.swift` 의 Supabase URL/anonKey 재사용 (신규 키 불필요).

## 8. 미해결·후속 결정

- 차단 영속성: 익명 Auth는 재설치 시 uid 리셋 → 차단 우회 가능. 강한 차단이 필요하면 Sign in with Apple 연결(linkIdentity)로 승격(C4+).
- 결제 티어: 서버·검열 비용 지속 → 구독 정합. 일회성/평생은 측정 Pro에 묶고 커뮤니티는 보너스 검토.
- 매매·진품감정·댓글·팔로우: 범위 제외(법적·운영 리스크). 팔로우는 "지속 가명 프로필" 도입 시에만.
