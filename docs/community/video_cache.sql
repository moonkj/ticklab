-- 큐레이션 YouTube 영상 서버 캐시
-- Edge Function(youtube-videos)이 YouTube Data API 결과를 여기에 30분 캐시한다.
-- YouTube 가 공개 RSS(feeds/videos.xml)를 차단해 Data API + 서버캐시로 전환(2026-06-03).
-- 앱은 함수만 호출하지만, 안전하게 공개 읽기 허용. 쓰기는 service_role(함수)만.

create table if not exists public.video_cache (
    id          text primary key,
    payload     jsonb       not null default '[]'::jsonb,
    fetched_at  timestamptz not null default now()
);

alter table public.video_cache enable row level security;

-- 공개 읽기 (anon/authenticated 모두)
drop policy if exists video_cache_read on public.video_cache;
create policy video_cache_read on public.video_cache
    for select using (true);

-- 쓰기 정책은 두지 않음 → service_role(Edge Function)만 RLS 우회하여 upsert.
