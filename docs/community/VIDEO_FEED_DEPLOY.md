# 영상 피드 백엔드 배포 (YouTube Data API + Edge Function)

YouTube 가 공개 RSS(`feeds/videos.xml`)를 차단(2026-06-03)해서, 영상 소스를
**Supabase Edge Function + YouTube Data API v3 + 서버캐시**로 전환했다.

- 앱은 `…/functions/v1/youtube-videos` (Supabase 도메인) 만 호출 — 외부 호출 정책 유지
- YouTube API 키는 **서버 시크릿**으로만 사용 (앱에 미포함)
- `video_cache` 30분 캐시 → 사용자 수와 무관하게 YouTube 호출량 고정(쿼터·비용 보호)
- **비용 0** — Data API 무료 할당량 10,000유닛/일, 실사용 ~480유닛/일

배포는 **대시보드 4단계**(CLI 불필요)면 끝난다.

---

## 1. YouTube Data API 키 발급 (Google Cloud, 무료·카드 불필요)

1. https://console.cloud.google.com → 프로젝트 생성(또는 기존 선택)
2. **API 및 서비스 → 라이브러리** → "YouTube Data API v3" 검색 → **사용 설정**
3. **API 및 서비스 → 사용자 인증 정보 → 사용자 인증 정보 만들기 → API 키**
4. (권장) 생성된 키 → **키 제한** → API 제한 → "YouTube Data API v3" 만 선택
5. 키 문자열 복사 (예: `AIza...`)

> Data API v3 는 무료 할당량(10,000유닛/일) 내에서 과금 없음. 결제 계정 불필요.

## 2. SQL 실행 (Supabase Dashboard → SQL Editor)

`docs/community/video_cache.sql` 내용을 붙여넣고 **Run**.

## 3. Edge Function 배포 (Supabase Dashboard → Edge Functions)

1. **Edge Functions → Deploy a new function** (또는 Create function)
2. 이름: `youtube-videos`
3. `supabase/functions/youtube-videos/index.ts` 내용을 그대로 붙여넣기 → **Deploy**

> CLI 선호 시:
> ```bash
> supabase functions deploy youtube-videos --project-ref tknicqhhgqfviuqczctl
> ```

## 4. 시크릿 설정 (Edge Functions → Secrets / Manage secrets)

- `YOUTUBE_API_KEY` = (1단계에서 복사한 키)

> `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` 는 Supabase 가 자동 주입 — 설정 불필요.
> CLI: `supabase secrets set YOUTUBE_API_KEY=AIza... --project-ref tknicqhhgqfviuqczctl`

---

## 동작 확인

- 앱 → 분석 → 영상 → 아래로 당겨 새로고침 → 등록 채널 최신 영상 표시
- 첫 호출은 라이브 조회(수 초), 이후 30분은 캐시에서 즉시 응답
- 함수 단독 테스트:
  ```bash
  curl -s "https://tknicqhhgqfviuqczctl.supabase.co/functions/v1/youtube-videos" \
    -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <ANON_KEY>" | head -c 400
  ```

## 채널 추가/관리

기존과 동일 — 관리자 모드에서 채널 추가(@핸들·URL·UCxxxx) → `curated_channels` 저장.
함수가 그 채널들을 읽어 영상을 채운다. **채널 추가 흐름은 변경 없음**(채널 페이지 스크랩은
RSS 차단과 무관하게 정상 동작).

## 튜닝

- `index.ts` 의 `TTL_MS`(서버캐시), `PER_CHANNEL`(채널당 개수), `MAX_TOTAL`(총 상한) 조절 가능.
- 채널이 많아 쿼터가 걱정되면 `PER_CHANNEL` 을 줄이거나 `TTL_MS` 를 늘린다.
