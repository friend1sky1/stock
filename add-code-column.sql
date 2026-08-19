-- 给 stocks 表新增 code 列（存储股票代码，如 sh600316）
ALTER TABLE stocks ADD COLUMN IF NOT EXISTS code TEXT DEFAULT '';

-- 为现有股票设置代码
UPDATE stocks SET code = 'sh600316' WHERE name = '洪都航空';
UPDATE stocks SET code = 'sz002461' WHERE name = '维远股份';
UPDATE stocks SET code = 'sz000725' WHERE name = '京东方A';
