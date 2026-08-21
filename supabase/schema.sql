-- 레버패밀리 ERP — Supabase 스키마
-- SQL Editor에서 전체 실행하세요. (idempotent: 이미 존재하는 테이블/정책은 재생성만 됩니다. 데이터는 삭제되지 않습니다)

create extension if not exists pgcrypto;

-- ========== 법인 ==========
create table if not exists entities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  role text not null default 'broker', -- broker | manufacturer
  biz_number text,
  ceo_name text,
  biz_type text,
  contact text,
  email text,
  biz_address text,
  commission_rate numeric,
  created_at timestamptz not null default now()
);

-- ========== 공급처 ==========
create table if not exists suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_internal boolean not null default false,
  linked_entity_id uuid references entities(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ========== 품목 ==========
create table if not exists items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  unit text,
  category text not null default '일반품목', -- 일반품목 | 소스류
  supplier_id uuid references suppliers(id) on delete set null,
  cost_price numeric,
  created_at timestamptz not null default now()
);

-- ========== 가격 변동 이력 ==========
create table if not exists price_history (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references items(id) on delete cascade,
  entity_id uuid not null references entities(id) on delete cascade,
  purchase_price numeric,
  sale_price numeric,
  commission_rate numeric,
  effective_date date not null,
  note text,
  created_at timestamptz not null default now()
);

-- ========== 스펙 변경 이력 ==========
create table if not exists spec_history (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references items(id) on delete cascade,
  change_date date not null,
  description text not null,
  changed_by text,
  created_at timestamptz not null default now()
);

-- ========== 파트너 브랜드 ==========
create table if not exists partner_brands (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  monthly_fee numeric not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ========== 파트너 청구/수금 내역 ==========
create table if not exists partner_payments (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null references partner_brands(id) on delete cascade,
  billing_month text not null, -- 'YYYY-MM'
  amount numeric not null,
  status text not null default 'pending', -- pending | completed
  paid_date date,
  note text,
  created_at timestamptz not null default now()
);

-- ========== 법인 계정 (사이트 로그인 정보) ==========
create table if not exists entity_accounts (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references entities(id) on delete cascade,
  site_name text not null,
  login_id text not null,
  login_pw text,
  memo text,
  created_at timestamptz not null default now()
);

-- ========== 직원 ==========
create table if not exists employees (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references entities(id) on delete cascade,
  name text not null,
  position text,
  status text not null default 'active', -- active | resigned
  phone text,
  email text,
  birth_date date,
  hire_date date,
  annual_leave_total numeric not null default 0,
  salary numeric,
  memo text,
  created_at timestamptz not null default now()
);

-- ========== 연차 사용 내역 ==========
create table if not exists leave_logs (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  leave_type text not null default '연차', -- 연차 | 반차 | 병가 | 경조사 | 기타
  days numeric not null,
  start_date date not null,
  end_date date not null,
  note text,
  created_at timestamptz not null default now()
);

-- ========== 법인카드 ==========
create table if not exists corporate_cards (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references entities(id) on delete cascade,
  card_name text not null,
  card_company text,
  card_number text,
  card_number_last4 text,
  expiry_date text,
  cvc text,
  holder_employee_id uuid references employees(id) on delete set null,
  status text not null default 'in_use', -- in_use | returned
  issued_date date,
  memo text,
  created_at timestamptz not null default now()
);

-- ========== 물류업체 ==========
create table if not exists logistics_providers (
  id uuid primary key default gen_random_uuid(),
  company_name text not null,
  contact_name text,
  phone text,
  email text,
  region text,
  service_desc text,
  memo text,
  created_at timestamptz not null default now()
);

-- ========== 계좌 ==========
create table if not exists bank_accounts (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references entities(id) on delete cascade,
  bank_name text not null,
  account_name text not null,
  account_number text not null,
  account_password text,
  status text not null default 'active', -- active | inactive
  memo text,
  created_at timestamptz not null default now()
);

-- ========== 공동구매 ==========
create table if not exists group_buys (
  id uuid primary key default gen_random_uuid(),
  item_name text not null,
  vendor_contact text,
  purchase_price numeric not null,
  sale_price numeric not null,
  status text not null default '진행중', -- 진행중 | 완료
  created_at timestamptz not null default now()
);

-- ========== 고정비 ==========
create table if not exists fixed_expenses (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references entities(id) on delete cascade,
  expense_name text not null default '주차비',
  amount numeric not null,
  due_day integer not null default 1, -- 매월 납부일 (1~31)
  account_number text,
  status text not null default 'pending', -- pending | paid
  memo text,
  created_at timestamptz not null default now()
);

-- 기존에 due_date(특정 날짜)로 만들어졌던 버전을 due_day(매월 며칠, 반복)로 전환 + 계좌번호 컬럼 추가
do $$
begin
  if exists (select 1 from information_schema.columns where table_name='fixed_expenses' and column_name='due_date') then
    alter table fixed_expenses add column if not exists due_day integer;
    alter table fixed_expenses add column if not exists account_number text;
    update fixed_expenses set due_day = extract(day from due_date)::int where due_day is null and due_date is not null;
    update fixed_expenses set due_day = 1 where due_day is null;
    alter table fixed_expenses alter column due_day set default 1;
    alter table fixed_expenses alter column due_day set not null;
    alter table fixed_expenses drop column due_date;
  end if;
end $$;

-- ========== RLS: 전체 공개 조회 + 로그인 사용자만 등록/수정/삭제 ==========
do $$
declare
  t text;
begin
  foreach t in array array[
    'entities','suppliers','items','price_history','spec_history',
    'partner_brands','partner_payments','entity_accounts','employees',
    'leave_logs','corporate_cards','logistics_providers','bank_accounts',
    'group_buys','fixed_expenses'
  ]
  loop
    execute format('alter table %I enable row level security', t);

    execute format('drop policy if exists %I on %I', t||'_select_public', t);
    execute format('create policy %I on %I for select using (true)', t||'_select_public', t);

    execute format('drop policy if exists %I on %I', t||'_insert_auth', t);
    execute format('create policy %I on %I for insert to authenticated with check (true)', t||'_insert_auth', t);

    execute format('drop policy if exists %I on %I', t||'_update_auth', t);
    execute format('create policy %I on %I for update to authenticated using (true) with check (true)', t||'_update_auth', t);

    execute format('drop policy if exists %I on %I', t||'_delete_auth', t);
    execute format('create policy %I on %I for delete to authenticated using (true)', t||'_delete_auth', t);
  end loop;
end $$;
