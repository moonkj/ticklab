// 큐레이션 YouTube 영상 — curated_channels 를 YouTube Data API v3 로 조회해 최신 영상 반환.
// 앱은 이 함수(Supabase 도메인)만 호출하고, YouTube API 키는 서버 시크릿(YOUTUBE_API_KEY)으로만 사용한다.
// 비용/쿼터 보호: video_cache 테이블에 30분 캐시 → 사용자 수와 무관하게 YouTube 호출량 고정.
//
// 배포:
//   supabase functions deploy youtube-videos
//   supabase secrets set YOUTUBE_API_KEY=<google-cloud-api-key>
// (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 는 Supabase 가 자동 주입 — 따로 설정 불필요)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const YT_KEY = Deno.env.get("YOUTUBE_API_KEY") ?? "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const TTL_MS = 30 * 60 * 1000;     // 서버 캐시 30분
const PER_CHANNEL = 8;             // 채널당 최신 N개
const MAX_TOTAL = 80;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const sb = createClient(SB_URL, SERVICE);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

  // 1) 캐시 신선하면 그대로 반환 (YouTube 호출 안 함)
  const { data: cache } = await sb.from("video_cache").select("payload,fetched_at").eq("id", "global").maybeSingle();
  if (cache?.fetched_at && Date.now() - new Date(cache.fetched_at).getTime() < TTL_MS) {
    return json(cache.payload ?? []);
  }
  if (!YT_KEY) return json(cache?.payload ?? []);   // 키 미설정 — 빈/이전 캐시

  // 2) 활성 채널
  const { data: channels } = await sb
    .from("curated_channels")
    .select("channel_id,title,locale")
    .eq("active", true)
    .order("sort_order", { ascending: true });

  const out: Array<Record<string, unknown>> = [];
  for (const ch of channels ?? []) {
    const cid = String(ch.channel_id ?? "");
    if (!cid) continue;
    // UCxxxx → UUxxxx (업로드 재생목록) — channels.list 호출 없이 1콜로 최신 업로드 조회.
    const uploads = cid.startsWith("UC") ? "UU" + cid.slice(2) : cid;
    const url =
      `https://www.googleapis.com/youtube/v3/playlistItems?part=snippet` +
      `&maxResults=${PER_CHANNEL}&playlistId=${uploads}&key=${YT_KEY}`;
    const r = await fetch(url);
    if (!r.ok) continue;                 // 채널 1개 실패해도 나머지 진행
    const data = await r.json();
    for (const it of data.items ?? []) {
      const sn = it.snippet;
      const vid = sn?.resourceId?.videoId;
      const title = sn?.title ?? "";
      if (!vid || title === "Private video" || title === "Deleted video") continue;
      out.push({
        id: vid,
        title,
        channel_title: sn.videoOwnerChannelTitle ?? sn.channelTitle ?? ch.title,
        published_at: sn.publishedAt,
        locale: ch.locale,
      });
    }
  }
  out.sort((a, b) => (String(a.published_at) < String(b.published_at) ? 1 : -1));
  const payload = out.slice(0, MAX_TOTAL);

  // 3) 결과 있으면 캐시 갱신, 비면 이전 캐시 유지(일시적 API 실패 방어)
  if (payload.length > 0) {
    await sb.from("video_cache").upsert({ id: "global", payload, fetched_at: new Date().toISOString() });
    return json(payload);
  }
  return json(cache?.payload ?? []);
});
