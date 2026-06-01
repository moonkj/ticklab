-- TickLab 커뮤니티 댓글 — 사진 게시물 댓글. UGC(욕설·거래 금지는 작성 시점 클라 필터).
-- 배포 순서: schema.sql(community_posts) + admin_rls.sql(is_admin) 먼저 → 이 파일.

create table if not exists public.community_comments (
    id          uuid primary key default gen_random_uuid(),
    post_id     uuid not null references public.community_posts(id) on delete cascade,
    uid         uuid not null default auth.uid(),
    author_name text,
    body        text not null,
    status      text not null default 'visible',   -- 'visible' | 'hidden'(운영자 숨김)
    created_at  timestamptz not null default now()
);
create index if not exists idx_comments_post on public.community_comments (post_id, created_at);
alter table public.community_comments enable row level security;

-- 읽기: visible 전체(+ 운영자/본인은 숨김도). 작성: 본인. 삭제: 본인 또는 운영자. 숨김(update): 운영자.
drop policy if exists comments_select on public.community_comments;
create policy comments_select on public.community_comments for select
    using (status = 'visible' or public.is_admin(auth.uid()) or uid = auth.uid());
drop policy if exists comments_insert_own on public.community_comments;
create policy comments_insert_own on public.community_comments for insert
    with check (uid = auth.uid());
drop policy if exists comments_delete_own_or_admin on public.community_comments;
create policy comments_delete_own_or_admin on public.community_comments for delete
    using (uid = auth.uid() or public.is_admin(auth.uid()));
drop policy if exists comments_admin_update on public.community_comments;
create policy comments_admin_update on public.community_comments for update
    using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- 댓글 수 비정규화(카드 표시) — 트리거로 자동 증감.
alter table public.community_posts add column if not exists comment_count int not null default 0;
create or replace function public.bump_comment_count() returns trigger
language plpgsql security definer as $$
begin
    if (tg_op = 'INSERT') then
        update public.community_posts set comment_count = comment_count + 1 where id = new.post_id;
    elsif (tg_op = 'DELETE') then
        update public.community_posts set comment_count = greatest(0, comment_count - 1) where id = old.post_id;
    end if;
    return null;
end; $$;
drop trigger if exists trg_comment_count on public.community_comments;
create trigger trg_comment_count after insert or delete on public.community_comments
    for each row execute function public.bump_comment_count();
