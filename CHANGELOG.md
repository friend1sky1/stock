# 更新日志（新→旧）

## 2026-11-03 注册查重改走服务端函数 username_taken（第一步，main 部署）

**背景**：`user_profiles` 表策略为 `FOR SELECT USING (true)`（行级不限、无列级控制），导致**未登录也能读全表 username + email**（实测匿名可读，3 条记录）。原查重走 `ilike` 前端查全表，必须开放全表读，属于结构性依赖。

### 改动
- 宝华在 Supabase SQL Editor 建函数 `public.username_taken(p_name text) RETURNS boolean`，`SECURITY DEFINER` + `SET search_path=public`，`lower()` 大小写不敏感匹配，`GRANT EXECUTE TO anon, authenticated`，并 `NOTIFY pgrst, 'reload schema'`
- `index.html`：`isUsernameTaken()` 由 `.from('user_profiles').select().ilike()` 改为 `_supabase.rpc('username_taken', {p_name})`，判据由 `data.length>0` 改为 `data===true`
- 行为不变：大小写不敏感、出错仍 fail-open 返回 false（与原来一致）

### 验证（main）
- 函数实测：`GBH`→true、`gbh`→true（大小写不敏感）、不存在→false，HTTP 200
- 线上 index.html 逐字节 = 本地最终版；`rpc版=1 / 旧ilike=0 / 入口=1`
- headless 加载线上页面：无 JS 错误；authOverlay/authEmail/authSubmitBtn/stockTabBar 元素齐全
- recover.html 200、overview.html 200

### 未做 / 下一步
- **第二步（未执行）**：收紧 `user_profiles` 的 SELECT 策略，去掉 `USING (true)`，改为「仅读自己 + 通过 username_taken 查重」，彻底关闭匿名读全表（含 email）
- 待宝华真人验收：登录一次，确认昵称显示、持仓同步正常


## 2026-11-03 新增独立页面「回本计算器」recover.html（main 部署）

**需求**：宝华自研回本计算器，作为与做T计算器并列的独立功能页，单独开页部署。

### 新增
- **新文件** `recover.html`（39,624 字节，纯前端单文件零依赖，无外部 CDN/字体；原名 t-recover-calc.html，应宝华要求改为 recover.html，旧文件已删）
- 访问地址：`https://t.ai-zhihui.cn/recover.html`
- **入口**：做T计算器（index.html）与持仓总览（overview.html）底部 links 各加一行「📈 回本计算器」，指向 recover.html
- 功能：浮亏计算 / 补仓方案表（0~50000 股，点行套用）/ 补仓后成本与回本价 / 回本所需涨幅进度条 / 还需几个涨停 / 交易费用模型（佣金万3可改+印花税万5+过户费万0.1+最低5元）/ 三源行情（雅虎→腾讯→东财）含 3 秒冷却与网络自检
- 涨跌幅按代码自动判断：68/30→20%，8/4/92→30%，其余10%

### 验证（main）
- `node --check` 内联 JS 语法通过；零外部依赖（favicon 为 data URI）
- 线上 HTTP 200，与本地文件**逐字节一致**（diff 无差异）
- 桌面 1000px / 窄屏 485px 双视口实测：布局无横向溢出，表格在自身容器内横向滚动
- 实盘取价：京东方A 现价 4.40、-1.38%、来源腾讯行情（雅虎主源被 CORS 拦截，自动降级成功）
- 计算口径抽验：500股@27.0032、现价4.4 → 浮亏 11,302；补1000股@4.4 → 总投入 17,902 / 摊薄 11.93 / 回本涨幅 171%，均与手算一致

### 未做
- 未接入登录/云同步（当前纯本地计算，与做T账号体系无关）


## 2026-09-15 - 新增持仓自动取当日开盘价 + 做T价格统一两位小数

**问题**：正T「买入价」默认显示4位小数（如 40.1900）——做T参数沿用成本价（券商成本价4位），载入时未四舍五入。

### 新增
- **新增持仓自动取价**：输入6位代码后（防抖500ms）自动调腾讯财经接口取**当日开盘价**，命中当日缓存则0请求；取不到回落成本价并提示
- **防封IP三件套**：①全局串行队列+最小间隔1200ms ②同日同代码缓存去重（localStorage，只留当天）③失败退避10分钟
- 复用每日批量刷新的结果（当日缓存共享），避免重复请求
- 模态框内新增取价状态提示（获取中/已采用/未取到）

### 修复
- 做T价格参数（tPrice1/tPrice2、n_t_price1/n_t_price2）在「云端读取 / 本地读取 / 载入表单 / 切换模式 / 每日刷新」全链路统一 round2 两位小数
- 新增持仓的做T参数默认值改为跟随**真实开盘价**（原为成本价）
- 成本价精度保持不变（仍4位，快照 fmtMoney4）

### 文件变更
- `index.html`：新增 fetchOpenPriceForCode/lookupOpenPriceForModal/_openCacheGet·Set/_fmt2；saveStock 改 async 并在新增时补查开盘价

---
## 2026-08-18 - 多用户版本上线（Supabase）

**核心升级：从单机版→云端多用户版**

### 新增功能
- **用户认证**：支持邮箱+密码注册/登录，以及魔法链接（Magic Link）免密码登录
- **云端数据同步**：持仓数据存储在 Supabase 云端，换设备/清缓存不丢失
- **多用户隔离**：每个用户独立持仓数据，RLS（Row Level Security）保障数据安全

### 技术实现
- Supabase Auth（邮箱密码+Magic Link）
- Supabase PostgreSQL + RLS policy
- 数据同步策略：本地缓存优先（速度）+ 云端同步（持久化），800ms 防抖
- 新用户自动创建默认持仓（洪都航空/维远股份/京东方A）
- 同步失败自动重试（最多3次）

### 文件变更
- `index.html`：增加登录界面、Supabase 数据同步、用户邮箱显示、退出按钮
- `overview.html`：增加登录界面、从 Supabase 加载持仓数据、退出按钮
- `supabase-init.sql`：数据库初始化 SQL（建表+RLS+索引+触发器）

---

## 2026-08-17 - 持仓总览页面交互升级

overview.html（t.ai-zhihui.cn）：
- **电脑版放大至 120%**：桌面端 scale 由 1.15 调整为 1.20
- **成本/持仓可编辑**：持仓（holdQty）、成本（costPrice）由只读改为可编辑输入框，与现价一致，输入实时联动更新市值/盈亏/盈亏% 及合计行
- **更新时间精确到分**：修复 updateDateLabel 时间比较逻辑，现在正确显示「数据更新：YYYY-MM-DD HH:mm」
- **修复输入 bug**：重写输入处理（parseInput 统一解析），删除数字再输入不再报错、不丢焦点、不跳变；空输入合法置空，非法输入标红提示但不污染原值

## 2026-08-13 09:30 - 持仓数据同步（飞书表格权威数据）

飞书表格 → 网站同步：
- **洪都航空**：现价 26.70→29.14（成本 30.4028、持仓 4000 不变）
- **维远股份**：现价 12.86→12.79（成本 15.5713、持仓 6000 不变）
- **TCL科技**：已从表格删除，从默认持仓中移除
- **京东方A**：成本 7.6288→8.6212，持仓 6400→4000，现价 5.90 不变

新增修复：overview.html 的 localStorage 恢复逻辑由硬编码长度5改为动态 portfolio.length

## 2026-08-11 - 持仓总览页面优化

overview.html（t.ai-zhihui.cn）：
- **成本列**：加粗 + 字号放大（font-weight 700，0.92rem）
- **现价输入修复**：输入时不再整表重绘（原每次输入都调用 renderTable() 重建表格，导致光标跳动卡顿），改为只更新本行市值/盈亏/盈亏% + 合计行，输入丝滑

## 2026-07-23 11:18 - 持仓数据同步

飞书表格 → 网站同步：
- **云铝股份**：已清仓（成本0/持仓0），从默认数据中删除
- **中国石油**：成本 11.2806→11.2688，持仓 1000 不变
- **黄河旋风**：成本 10.5885，持仓 1000 不变

## 2026-08-10 10:10 - 持仓数据同步

做T计算器 + 持仓总览默认持仓更新：
- **洪都航空**：成本 30.4028，持仓 4000，现价 26.70
- **维远股份**：成本 15.5713，持仓 6000，现价 12.86
- **TCL科技**：成本 4.9617，持仓 8000，现价 4.81
- **京东方A**：成本 7.6288，持仓 6400，现价 5.90
（原 云铝/今世缘/中国石油/黄河旋风 已替换）

## 2026-09-11 做T价格统一四舍五入2位小数
- 修复：手动输入的卖出价/买入价(tPrice1)、预期价(tPrice2)、开盘价(openPrice)不再被原地保留多位小数
- 新增 round2()/roundPriceInput() 工具函数，价格失焦(onblur)时四舍五入到2位小数并回写
- calculate() 计算前安全网：tPrice1/tPrice2 统一 round2 再计算，防止未失焦直接点计算带多位小数
- 覆盖：正T的买入价/预期卖出价、倒T的卖出价/预期接回价，逻辑对称一致

## 2026-10-21 白屏根治 + CDN 去依赖（main 推）
- **根因**：`cdn.jsdelivr.net` 在国内被拦截 → `supabase-js` 加载失败 → `_supabase` 为空 → 启动 IIFE 直接 `return` → `.app` 一直 `display:none` → **整页白屏（只有淡黄底色 `#FBF6F0`）**。容错提示写在同样隐藏的 `authOverlay` 里，连提示都看不见。
- **修复三层**：
  1. `supabase.min.js` 本地托管入仓（218KB，v2.118.0），改本地引用，彻底摆脱 CDN
  2. 修白屏：`_supabase` 为空改为**降级可用**（显示主界面 + 顶部红色横幅），不再 `return`
  3. 兜底超时：脚本 8 秒未就绪 → 触发 `__onSbUnavailable()` 走降级
- **文件**：index.html、overview.html、supabase.min.js（新增）
- **验证**：本地降级单测通过（app.display=flex / 横幅出现 / initApp 执行）；线上三文件均 HTTP 200，index 已指向本地库
- **未做**：`clear.html` 无需改（不依赖 supabase-js）

## 2026-10-21 新增「到价提醒」A档（main 推 commit f00c81655a5f）
- **需求**：宝华选择 A 档——只做到价提醒，最小可用
- **功能**：持仓信息卡片内新增一行「🔔 ≥/≤ 价格」；每 30 秒（页面可见时）拉腾讯行情比对；命中即顶部红色横幅 + 三声提示音 + 系统通知；每只股票 tab 显示 🔔 标记；触发后自动关闭，需手动重开
- **存储**：localStorage `tcalc_alerts_v1`，key 为股票代码（无代码用名称），与持仓解耦，改名不丢
- **实测**：本地 + 线上双验证，京东方A 现价 5.05 正确触发，未触发时不会误报，无 JS 错误
- **未做（待议）**：跨设备同步需加 Supabase 列；关掉浏览器后仍提醒需服务器 cron 推飞书

## 2026-10-21 持仓总览补上到价提醒（main 推 commit 1c3f7e065397）
- **需求**：宝华确认「两处都有」——计算器 + 持仓总览都要能设到价提醒
- **实现**：操作列加 🔔（暗=未设 / 亮=监控中 / 闪=已触发）；点开底部弹窗设方向+价格+开关
- **关键设计**：两页共用 `localStorage['tcalc_alerts_v1']`，在计算器设的提醒，总览页直接能看到、能改、能响，反之亦然
- **实测**：本地弹窗/开启/命中/横幅链路全通，无 JS 错误

## 2026-10-22 10:05 登录网络失败可诊断化（main）
- 背景：宝华电脑端登录报「网络连接失败」，但服务端实测正常（域名解析干净、auth 接口 1.2s 返回）
- 改动 index.html：
  1. 登录请求新增 `authCall()` —— 网络类错误自动重试 2 次（各等 2.5s），密码错等业务错误立即返回不重试
  2. 失败后调用 `probeCloudReachable()` 探测云端可达性，区分两种结论：连不上云端 / 云端可达但请求被中断
  3. `friendlyAuthError` 拆分「超时」「网络中断」两类文案，不再一律「网络连接失败」
- 本地实测：断网场景 6s 内给出结论、按钮恢复；密码错场景 1.2s 正确提示、无多余重试
- commit 92a4f86c，线上已验证（size 136024→138969，含 authCall/probeCloudReachable）

## 2026-10-22 10:40 云端请求改走同域中转（搜狗浏览器拦截根治·main）
- 背景：同一台电脑 Edge 能登录、搜狗浏览器报「连不上云端」→ 确认是浏览器拦截第三方域名 supabase.co
- 方案：新增 vercel.json `/sb/:path*` → `idindbktqpjulhvcvcdj.supabase.co/:path*` 重写；前端 SUPABASE_URL 改为 `https://t.ai-zhihui.cn/sb`
- 配套：
  1. 固定 `storageKey: sb-idindbktqpjulhvcvcdj-auth-token`，中转/直连两种模式共用同一登录态（不丢登录）
  2. `ensureSupabaseBase()`：页面加载即探测中转，不可用自动回退直连（只切一次，不回旋）
  3. `probeCloudReachable()`：中转失败再试直连，直连可用则当场切换
- 线上验证：/sb/auth/v1/health=200、/sb/rest/v1=200、POST token 0.44s 返回 invalid_credentials；overview 走 /sb、无 JS 报错
- 回退测试：把中转地址改坏后，4 秒内自动切直连，登录仍正常
- commits: vercel.json 939c25b7 / index.html 1844f4d8 / overview.html fd1278b4
