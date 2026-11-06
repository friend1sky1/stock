// 同域云通道：/cloud/* → Supabase
// 作用：让浏览器只访问自己的域名，避免直连云端在不稳定网络下被拦截
// 运行位置：Cloudflare Pages Functions（免费额度 100,000 次/天）

const UPSTREAM = 'https://idindbktqpjulhvcvcdj.supabase.co';

export async function onRequest(context) {
  const { request } = context;
  const url = new URL(request.url);

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
