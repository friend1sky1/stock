-- ============================================================
-- OpenClaw 数据库安全建表模板（2026-11-03 立）
-- 用途：新建任何带用户数据的表，一律照此起草，禁止从 USING(true) 起步
-- 背景：做T计算器 user_profiles 曾因 USING(true) 导致未登录可读全表邮箱
-- 详见 MEMORY.md §数据库安全基建、TOOLS.md 经验30
-- ============================================================

-- ── 第一步：建表（示例字段，按需替换） ──────────────────────
CREATE TABLE IF NOT EXISTS 表名 (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- 业务字段...
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 第二步：开启行级安全（必须！不开启 = 全表可读） ────────
ALTER TABLE 表名 ENABLE ROW LEVEL SECURITY;

-- ── 第三步：默认只允许「读自己那一行」 ────────────────────
-- 关键点：TO authenticated —— 未登录连查一行的资格都没有
CREATE POLICY "own row read" ON 表名
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- ── 第四步：只允许写自己的行 ──────────────────────────────
CREATE POLICY "own row insert" ON 表名
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "own row update" ON 表名
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "own row delete" ON 表名
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- ── 第五步：更新时间触发器（可选但推荐） ─────────────────
CREATE OR REPLACE FUNCTION 表名_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER 表名_updated_at
  BEFORE UPDATE ON 表名
  FOR EACH ROW EXECUTE FUNCTION 表名_updated_at();

-- ── 第六步：刷新 PostgREST 接口缓存 ──────────────────────
NOTIFY pgrst, 'reload schema';


-- ============================================================
-- 跨用户查询怎么办？（例如：注册时判断用户名是否已被占用）
-- ❌ 绝对不要因此放开表权限
-- ✅ 改为建 SECURITY DEFINER 函数，只暴露「是/否」一个布尔结果
-- ============================================================
--
-- CREATE OR REPLACE FUNCTION public.username_taken(p_name text)
-- RETURNS boolean
-- LANGUAGE sql
-- SECURITY DEFINER
-- SET search_path = public
-- AS $$
--   SELECT EXISTS (
--     SELECT 1 FROM public.表名
--     WHERE lower(username) = lower(trim(p_name))
--   );
-- $$;
--
-- GRANT EXECUTE ON FUNCTION public.username_taken(text) TO anon, authenticated;
-- NOTIFY pgrst, 'reload schema';


-- ============================================================
-- 自检清单（改完必须实测，不看 SQL 是否 Success）
-- ============================================================
-- 1. 匿名密钥 GET /rest/v1/表名?select=id&limit=5  → 必须返回 []（不是 200+数据）
-- 2. 匿名密钥读敏感列（email 等）              → 必须返回 []
-- 3. 需要的服务端函数                          → 必须正常返回 true/false
-- 4. 登录用户：读自己、写自己                  → 必须正常
-- 5. 无痕窗口打开站点、不登录                  → 看不到任何本该登录才有的东西


-- ============================================================
-- 回滚模板（改错了 30 秒恢复原状，执行前先存好）
-- ============================================================
-- DROP POLICY IF EXISTS "own row read"   ON 表名;
-- DROP POLICY IF EXISTS "own row insert" ON 表名;
-- DROP POLICY IF EXISTS "own row update" ON 表名;
-- DROP POLICY IF EXISTS "own row delete" ON 表名;
-- CREATE POLICY "临时全开" ON 表名 FOR SELECT USING (true);   -- ⚠️ 仅应急，恢复后立刻重锁
-- NOTIFY pgrst, 'reload schema';
