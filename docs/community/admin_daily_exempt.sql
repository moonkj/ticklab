-- 관리자(TickLab) 하루 1장 제한 면제
-- enforce_daily_post_limit 트리거 함수 맨 앞에 is_admin 면제를 추가한다.
-- admin_users / is_admin 은 이미 있으면 무해(idempotent) — 안전하게 같이 포함.
-- 적용: Supabase SQL Editor 에서 실행. (트리거 trg_daily_limit 는 함수명으로 참조 → 재생성 불필요)

-- (안전) 관리자 식별 인프라
create table if not exists public.admin_users (
    uid        uuid primary key,
    name       text not null default 'TickLab',
    role       text not null default 'admin',
    created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
drop policy if exists admin_users_self_select on public.admin_users;
create policy admin_users_self_select on public.admin_users
    for select using (uid = auth.uid());

create or replace function public.is_admin(check_uid uuid)
returns boolean language sql security definer stable as $$
    select exists (select 1 from public.admin_users where uid = check_uid);
$$;

-- 하루 1장 트리거 — 관리자는 면제(다회 게시 허용), 일반 사용자는 1장 유지
create or replace function public.enforce_daily_post_limit() returns trigger as $$
begin
    if public.is_admin(new.author_uid) then
        return new;   -- 관리자: 하루 여러 장 허용
    end if;
    if exists (
        select 1 from public.community_posts
         where author_uid = new.author_uid
           and created_at >= date_trunc('day', now())
    ) then
        raise exception 'daily_post_limit' using errcode = 'P0001';
    end if;
    return new;
end; $$ language plpgsql security definer;
