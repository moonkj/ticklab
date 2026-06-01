# TickLab 운영 관리자 (Operations Admin)

> 라이브 커뮤니티 운영 시스템 — 운영 ID·대시보드·신고·공지·경고·제재·감사.
> 콘텐츠 정책 레이어는 [`MODERATION_POLICY.md`](MODERATION_POLICY.md), 커뮤니티 SSOT는 [`PLAN.md`](PLAN.md).

## 0. 핵심 전제 — 데이터 경계 (불변)
| | (A) 측정 엔진 | (B) 커뮤니티/운영 |
|---|---|---|
| 내용 | rate·beat error·amplitude·raw 오디오 | 글·신고·건의·통계·공지·경고·제재 |
| 위치 | **100% 온디바이스** | 별도 백엔드(Supabase) |
| 운영자 접근 | ❌ 불가 | ✅ 커뮤니티만 |

- 측정 데이터(A)는 운영 백엔드(B)로 **절대 전송/저장 금지** — CLAUDE.md Hard Rule #8 불변.
- 운영자도 사용자의 측정 데이터는 못 본다. 모더레이션·제재는 B 영역에만 작동.

## 1. 운영 ID (신원 전환)
- 관리자 패널(설정 버전 10탭 → PIN, DEBUG 게이트) → "운영 ID" 세그먼트: **사용자 / 관리자(TickLab)**.
- 플래그: `@AppStorage("ticklab.admin.actingAsTickLab")`.
- ON 시: 커뮤니티 게시 작성자명 = `"TickLab"` + 아바타 = 앱 아이콘(`AppIconProvider`), 앱 상단 **"관리자" 플로팅 배지**(신고 건수 종 아이콘 포함).
- **위조 방지(필수)**: 클라 플래그는 위조 가능 → 서버 RLS(`admin_users` + `is_admin`)로 `'TickLab'` 닉네임을 admin uid 로만 제한. → `admin_rls.sql`.

## 2. 운영 대시보드 (AdminOpsView, 앱 내)
관리자 패널 → "운영 대시보드".
- **통계 그리드**: 현재 활동 사용자(presence 근사) · 오늘/전체 게시물 · 신고 건수.
- **신고된 게시물**: 글 단위 집계(사유·횟수) → 탭하면 **상세**(원본 이미지·캡션·작성자) → **숨김 / 삭제 / 작성자 경고**.
- **공지**: 새 공지 작성·기존 공지 목록 수정(내용 + 노출 기간 + 활성).
- presence 하트비트는 커뮤니티 사용 시 자동(`community_presence`).

## 3. 공지 (Announcements)
- 관리자: 내용 + **노출 기간(시작/종료)** + 활성 토글. 작성·**수정** 가능(`AdminAnnouncementSheet`).
- 사용자: 활성 + 기간 내 공지를 **하단 시트**로 표시(`AnnouncementBottomSheet`). **"오늘 하루 보지 않기"** 체크 + 닫기 → 공지 id별 당일 suppress(UserDefaults).
- 백엔드: `community_announcements`(`admin_ops.sql`).

## 4. 경고 (Warnings)
- 관리자: 신고 게시물 상세 → 작성자에게 경고 메시지 발송.
- 사용자: 커뮤니티 진입 시 미확인 경고 alert → 확인 시 seen 처리.
- 백엔드: `community_warnings`(본인만 조회).

## 5. 신고 큐 + 모더레이션
- 사용자 신고(사유: 부적절·스팸·욕설·저작권·**거래·사기**·기타) → `community_reports` → 글 단위 집계.
- 신고 누적 3건 → 자동 숨김(`schema.sql` 트리거).
- 관리자 액션: 숨김(`status='hidden'`) / 삭제(DELETE) — RLS 보호.
- 신고해도 **글은 계속 표시**(차단·자동숨김으로 가림). 자동 필터(거래/욕설)는 작성 시점([`MODERATION_POLICY.md`](MODERATION_POLICY.md)).

## 6. 제재 (Enforcement) — 단계적
- 단계: **1 경고 → 2 콘텐츠 처리(soft) → 3 일시정지 → 4 영구차단**. 중대위반은 단계 생략 즉시 차단.
- 정지(3, 미만료)/차단(4) 사용자는 **게시 서버 거부**(`is_sanctioned` + `posts_insert`).
- 모든 제재에 사유 통지 + **이의신청** 경로(권리 제한 — 법적 안전).
- 백엔드: `community_sanctions`(`admin_enforcement.sql`). **부과·이의신청 UI는 웹 어드민 콘솔**(앱 미구현).

## 7. 감사 로그 (Audit)
- 모든 운영 액션(신고처리·숨김·삭제·경고·제재·공지) 기록 → `community_moderation_log`. **변조 불가**(update/delete 정책 없음).
- 분쟁·이의신청 증거 + 자기 보호. 1인 운영이라도 처음부터.

## 8. 구성 — 앱 / 백엔드 / 웹 콘솔
| 영역 | 위치 |
|---|---|
| 운영 ID·대시보드·신고 상세·공지 작성·경고·통계 | **iOS 앱**(관리자 패널, DEBUG/운영자) |
| 테이블·RLS·트리거·is_admin·is_sanctioned | **Supabase**(`admin_rls.sql`·`admin_ops.sql`·`admin_enforcement.sql`) |
| 제재 부과·이의신청·감사 조회·세그먼트·CSAM 연동 | **별도 웹 어드민 콘솔**(미구현, 팀검토 권장) |
| 가이드라인·약관(거래 면책)·연령 17+·SLA·이의신청 절차 | **문서/법무**(출시 전 필수) |

## 9. SQL 배포 순서 (Supabase)
1. `admin_rls.sql` — `admin_users`·`is_admin`·`posts_insert` 가드 + 운영자 본인 uid 등록.
2. `admin_ops.sql` — presence·신고 조회/숨김/삭제·공지·경고 테이블/RLS.
3. `admin_enforcement.sql` — 제재·감사·정지 게시차단(웹콘솔 구축 시).

## 10. 미구현/후속 (P1~P2)
- 웹 어드민 콘솔(제재 부과·이의신청·감사 조회·통계 세그먼트).
- 실시간 동시접속(현재는 presence 활동 근사 — Realtime 연동 시 정확).
- CSAM 해시 매칭(PhotoDNA 등 외부 서비스), ML 독성 분류(P2, 검수 큐 우선순위용).
- 스팸 rate-limiting(백엔드), 알림/리텐션(옵트인).
