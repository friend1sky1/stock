-- 做T计算器 多用户版 数据库初始化
-- 在 Supabase Dashboard → SQL Editor 中执行

-- 1. 创建 stocks 表
CREATE TABLE IF NOT EXISTS stocks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  cost_price NUMERIC(12,4) DEFAULT 0,
  hold_qty INTEGER DEFAULT 0,
  open_price NUMERIC(12,4) DEFAULT 0,
  t_price1 NUMERIC(12,4) DEFAULT 0,
  t_qty INTEGER DEFAULT 1000,
  t_price2 NUMERIC(12,4) DEFAULT 0,
  mode TEXT DEFAULT 'reverse',
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 启用 RLS（Row Level Security）
ALTER TABLE stocks ENABLE ROW LEVEL SECURITY;

-- 3. 用户只能访问自己的数据
CREATE POLICY "Users can CRUD their own stocks" ON stocks
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 4. 创建索引
CREATE INDEX IF NOT EXISTS idx_stocks_user_id ON stocks(user_id);

-- 5. 更新时间触发器
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stocks_updated_at
  BEFORE UPDATE ON stocks
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
