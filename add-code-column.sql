-- 给 stocks 表新增 code 列（存储股票代码，如 sh600316）
-- 在 Supabase Dashboard → SQL Editor 中执行
ALTER TABLE stocks ADD COLUMN IF NOT EXISTS code TEXT DEFAULT '';

-- 为现有持仓股票设置代码（如已有同名持仓会自动更新其 code）
UPDATE stocks SET code = 'sh600316' WHERE name = '洪都航空' AND (code IS NULL OR code = '');
UPDATE stocks SET code = 'sh600955' WHERE name = '维远股份' AND (code IS NULL OR code = '');
UPDATE stocks SET code = 'sz000725' WHERE name = '京东方A' AND (code IS NULL OR code = '');
