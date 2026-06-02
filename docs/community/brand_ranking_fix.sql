-- TickLab 브랜드 리그 — get_brand_ranking RPC 버그 수정
-- ===========================================================================
-- 버그 요약:
--   brand_wear_stats 테이블에는 (device_hash, brand, period_type, period_key, count)
--   가 기간별로 분리 upsert 된다. 그러나 기존 get_brand_ranking 함수는
--   WHERE 절에서 period_type / period_key 필터를 누락한 채 전체 행을 SUM 하여
--   weekly·monthly·yearly 탭이 모두 누적 합계(전기간 total)를 반환했다.
-- 수정:
--   WHERE period_type = p_period_type AND period_key = p_period_key 를 추가.
-- ===========================================================================
-- 적용: Supabase SQL Editor 에 붙여 Run.
-- 멱등: CREATE OR REPLACE 이므로 재실행 무해.
-- ===========================================================================

-- brand_wear_stats 테이블이 아직 없는 환경을 위한 DDL (멱등)
-- (schema.sql에 TODO로만 남아 있어 여기서 정식 정의)
create table if not exists public.brand_wear_stats (
    id          bigserial   primary key,
    device_hash text        not null,
    brand       text        not null,
    period_type text        not null,   -- 'day' | 'week' | 'month' | 'year'
    period_key  text        not null,   -- 예: '2026-W22', '2026-06', '2026', '2026-06-02'
    count       int         not null default 0,
    updated_at  timestamptz not null default now(),
    unique (device_hash, brand, period_type, period_key)
);
create index if not exists idx_brand_wear_stats_lookup
    on public.brand_wear_stats (period_type, period_key, brand);

-- RLS: 쓰기는 본인 device_hash 행만, 읽기는 RPC 경유(직접 SELECT 차단)
alter table public.brand_wear_stats enable row level security;

-- 직접 SELECT 차단 — 집계는 RPC 로만 (랭킹 조작 정보 은닉)
drop policy if exists brand_wear_stats_no_direct_select on public.brand_wear_stats;
-- (정책 없음 = default deny → 직접 SELECT 불가)

-- anon 사용자가 본인 행을 upsert 할 수 있어야 함
drop policy if exists brand_wear_stats_upsert_own on public.brand_wear_stats;
create policy brand_wear_stats_upsert_own on public.brand_wear_stats
    for insert
    with check (true);   -- device_hash 는 서버에서 검증하기 어려우므로 INSERT 허용;
                          -- 개수 상한·brand 화이트리스트는 TODO(schema.sql §6)

drop policy if exists brand_wear_stats_update_own on public.brand_wear_stats;
create policy brand_wear_stats_update_own on public.brand_wear_stats
    for update
    using (true);

-- ────────────────────────────────────────────────────────────────────────────
-- 핵심 수정: get_brand_ranking — 기간 필터 추가
-- ────────────────────────────────────────────────────────────────────────────
-- 파라미터 (Swift 클라이언트가 전송하는 JSON 키와 1:1 일치):
--   p_period_type text  — 'day' | 'week' | 'month' | 'year'
--   p_period_key  text  — periodKey(type:) 결과, 예: '2026-W22'
--   p_limit       int   — 반환 행 수 상한 (클라이언트는 30 전송)
--
-- 반환 컬럼 (Swift AnyCodable 디코더가 "brand" / "total_count" 키를 읽음):
--   brand       text
--   total_count bigint  (JSON 숫자 → Swift Int/Double → Int 변환 허용)
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.get_brand_ranking(
    p_period_type text,
    p_period_key  text,
    p_limit       int default 30
)
returns table (
    brand       text,
    total_count bigint
)
language sql
security definer
stable
as $$
    select
        brand,
        sum(count)::bigint as total_count
    from public.brand_wear_stats
    where period_type = p_period_type
      and period_key  = p_period_key   -- ← 기존 함수에서 누락된 핵심 필터
    group by brand
    having sum(count) > 0
    order by total_count desc
    limit p_limit;
$$;

-- RPC 는 anon key 로 호출 가능해야 함 (Supabase 기본값은 authenticated 만 허용)
grant execute on function public.get_brand_ranking(text, text, int) to anon, authenticated;

-- ===========================================================================
-- 진단 쿼리 — Supabase SQL Editor 에서 직접 실행해 버그·수정 확인
-- ===========================================================================

-- (a) 현재 DB에 저장된 (period_type, period_key) 종류 확인
--     → 버그 환경에서는 다양한 period_key 가 섞여 있어야 함.
--     수정 후에는 각 period_type 아래 오늘/이번주/이번달/올해 key 가 분리돼야 함.
/*
select
    period_type,
    period_key,
    count(distinct device_hash) as devices,
    count(*)                    as rows,
    sum(count)                  as total_wears
from public.brand_wear_stats
group by period_type, period_key
order by period_type, period_key desc;
*/

-- (b) 특정 브랜드(예: Rolex)의 기간별 누적 합산 확인
--     수정 전 get_brand_ranking 은 모든 period_key 를 더해 이 합계와 일치했을 것.
--     수정 후에는 각 period_key 슬롯만 합산하므로 값이 작아짐.
/*
select
    period_type,
    period_key,
    sum(count) as total_count
from public.brand_wear_stats
where brand = 'Rolex'
group by period_type, period_key
order by period_type, period_key desc;
*/

-- (c) 수정된 RPC 샘플 호출 — 이번 주 랭킹 확인
--     p_period_key 값은 Swift periodKey(type:"week") 와 동일한 ISO 주차 형식 사용:
--       yearForWeekOfYear + weekOfYear → '2026-W23'  (실행 시점에 맞게 변경)
/*
select *
from public.get_brand_ranking('week', '2026-W23', 30);
*/
