// 同域云通道：/cloud/* → Supabase
// 作用：让浏览器只访问自己的域名，避免直连云端在不稳定网络下被拦截
// 运行位置：Cloudflare Pages Functions（免费额度 100,000 次/天）

const UPSTREAM = 'https://idindbktqpjulhvcvcdj.supabase.co';
// 公开键（本来就在网页里，用于调用数据库/登录接口），不是密钥
const ANON_KEY = 'sb_publishable_T6Frrq5pHqJbvSgcm4Df-Q_U1xpMszp';

function jsonOut(obj, status) {
  return new Response(JSON.stringify(obj), {
    status: status || 200,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }
  });
}

// 每 IP 限流（同一实例内尽力而为，配合上游自带的登录限流）
const _rl = new Map();
function tooMany(ip) {
  const now = Date.now();
  const arr = (_rl.get(ip) || []).filter(function (t) { return now - t < 60000; });
  arr.push(now);
  _rl.set(ip, arr);
  if (_rl.size > 500) _rl.clear();
  return arr.length > 10;
}

// 用户名登录：服务端内部完成「用户名 → 邮箱 → 换凭证」，邮箱不出服务器
async function handleUsernameLogin(context) {
  const { request, env } = context;
  if (request.method !== 'POST') return jsonOut({ error: 'method_not_allowed' }, 405);

  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  if (tooMany(ip)) return jsonOut({ error: 'rate_limited' }, 429);

  const token = (env && env.TCALC_LOGIN_TOKEN) ? String(env.TCALC_LOGIN_TOKEN) : '';
  if (!token) return jsonOut({ error: 'server_not_configured' }, 503);

  let body = {};
  try { body = await request.json(); } catch (e) { return jsonOut({ error: 'bad_request' }, 400); }
  const name = String((body && body.name) || '').trim();
  const password = String((body && body.password) || '');
  if (name.length < 2 || name.length > 40 || !password) return jsonOut({ error: 'bad_request' }, 400);

  // 1) 查用户名对应的邮箱：调数据库函数，数据库只认本服务的口令，且只返回邮箱
  let email = null;
  try {
    const lr = await fetch(UPSTREAM + '/rest/v1/rpc/tcalc_login_email', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        apikey: ANON_KEY,
        'x-tcalc-token': token
      },
      body: JSON.stringify({ p_name: name, p_password: password })
    });
    if (lr.status === 404) return jsonOut({ error: 'server_not_configured' }, 503); // 数据库函数还没建
    if (!lr.ok) return jsonOut({ error: 'lookup_failed' }, 502);
    email = await lr.json();
  } catch (e) {
    return jsonOut({ error: 'lookup_failed' }, 502);
  }
  // 数据库函数的返回：邮箱字符串 / 'AMBIGUOUS' / 'NO_USER' / 'BAD_TOKEN' / null
  if (email === 'AMBIGUOUS') return jsonOut({ error: 'duplicate_username' }, 409); // 重名绝不猜，宁可让他用邮箱登
  if (email === 'BAD_TOKEN') return jsonOut({ error: 'server_not_configured' }, 503); // 口令不匹配：部署配置问题，不是用户问题
  if (!email || typeof email !== 'string' || email === 'NO_USER') return jsonOut({ error: 'invalid_credentials' }, 401);

  // 2) 拿邮箱 + 密码去换登录凭证
  let tj = {};
  try {
    const tr = await fetch(UPSTREAM + '/auth/v1/token?grant_type=password', {
      method: 'POST',
      headers: { 'content-type': 'application/json', apikey: ANON_KEY },
      body: JSON.stringify({ email: email, password: password })
    });
    tj = await tr.json().catch(function () { return {}; });
    if (!tr.ok) return jsonOut({ error: 'invalid_credentials' }, 401);
  } catch (e) {
    return jsonOut({ error: 'upstream_unreachable' }, 502);
  }

  return jsonOut({
    access_token: tj.access_token,
    refresh_token: tj.refresh_token,
    expires_in: tj.expires_in,
    expires_at: tj.expires_at,
    token_type: tj.token_type,
    user: { id: tj.user && tj.user.id, email: tj.user && tj.user.email }
  }, 200);
}

export async function onRequest(context) {
  const { request } = context;
  const url = new URL(request.url);

  // 用户名登录专用入口（不走上游透传）
  if (url.pathname === '/cloud/tcalc/login') return handleUsernameLogin(context);

  // /cloud/auth/v1/... → https://<upstream>/auth/v1/...
  const path = url.pathname.replace(/^\/cloud/, '');
  const target = UPSTREAM + path + url.search;

  const headers = new Headers(request.headers);
  // 去掉会干扰上游的请求头
  ['host', 'cf-connecting-ip', 'cf-ipcountry', 'cf-ray',
   'cf-visitor', 'x-forwarded-proto', 'x-real-ip', 'cdn-loop'].forEach(function (h) {
    headers.delete(h);
  });

  const init = {
    method: request.method,
    headers: headers,
    redirect: 'follow'
  };

  if (request.method !== 'GET' && request.method !== 'HEAD') {
    init.body = await request.arrayBuffer();
  }

  try {
    const resp = await fetch(target, init);
    const outHeaders = new Headers(resp.headers);
    outHeaders.set('cache-control', 'no-store');
    return new Response(resp.body, {
      status: resp.status,
      statusText: resp.statusText,
      headers: outHeaders
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: 'upstream_unreachable', detail: String(err) }),
      { status: 502, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } }
    );
  }
}
