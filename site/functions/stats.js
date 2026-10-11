// /stats?k=<STATS_TOKEN> – privaatne ülevaade; /stats?format=json – sama JSON-ina.
// STATS_PUBLIC=1 → kogusummad (mitte päevade tabel) on nähtavad ka ilma võtmeta.
const LABEL = {
  install_mac: "Paigaldused – macOS",
  install_win: "Paigaldused – Windows",
  install_mac_update: "Uuendused – macOS",
  install_win_update: "Uuendused – Windows",
  update_check: "Uuenduste kontrollid",
  page_view: "Lehe avamised",
};

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const k = url.searchParams.get("k") || "";
  const authed = env.STATS_TOKEN && k.length === env.STATS_TOKEN.length &&
    crypto.subtle.timingSafeEqual(new TextEncoder().encode(k), new TextEncoder().encode(env.STATS_TOKEN));
  const isPublic = env.STATS_PUBLIC === "1";
  if (!authed && !isPublic) return new Response("not found", { status: 404 });
  if (!env.STATS) return new Response("STATS (D1) pole seotud", { status: 503 });

  let rows = [];
  try {
    rows = (await env.STATS.prepare("SELECT day, kind, n FROM hits WHERE day >= date('now', '-60 days') ORDER BY day DESC").all()).results || [];
  } catch { /* tabel tekib esimese loendusega */ }
  const allTime = {};
  try {
    for (const r of (await env.STATS.prepare("SELECT kind, SUM(n) AS n FROM hits GROUP BY kind").all()).results || []) allTime[r.kind] = r.n;
  } catch {}
  const installs = (allTime.install_mac || 0) + (allTime.install_win || 0);
  const today = new Date().toISOString().slice(0, 10);
  const yesterday = new Date(Date.now() - 86400e3).toISOString().slice(0, 10);
  const checks = (d) => rows.filter((r) => r.day === d && r.kind === "update_check").reduce((a, r) => a + r.n, 0);
  // iga paigaldus kontrollib ~2× ööpäevas (+ igal käivitusel) → jämedalt pool
  const activeEstimate = Math.round(checks(yesterday) / 2);

  const summary = { installs, installs_mac: allTime.install_mac || 0, installs_win: allTime.install_win || 0,
    updates: (allTime.install_mac_update || 0) + (allTime.install_win_update || 0), active_estimate: activeEstimate,
    page_views: allTime.page_view || 0 };
  if (!authed || url.searchParams.get("format") === "json") {
    return Response.json(authed ? { summary, days: rows } : { installs, active_estimate: activeEstimate },
      { headers: { "cache-control": "no-store", "access-control-allow-origin": "*" } });
  }

  const days = [...new Set(rows.map((r) => r.day))];
  const kinds = Object.keys(LABEL);
  const cell = (d, kd) => rows.find((r) => r.day === d && r.kind === kd)?.n || "";
  const esc = (s) => String(s).replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" }[c]));
  const html = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Statistika · Raadiosalvesti</title>
<style>body{font:15px/1.5 -apple-system,system-ui,sans-serif;margin:24px auto;max-width:900px;padding:0 16px;color:#17181b;background:#f6f6f4}
.k{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:16px 0 24px}
.k div{background:#fff;border:1px solid #e3e3df;border-radius:12px;padding:12px}.k b{display:block;font-size:26px}
table{border-collapse:collapse;width:100%;background:#fff;border-radius:12px;overflow:hidden;font-variant-numeric:tabular-nums}
th,td{padding:7px 10px;border-bottom:1px solid #eee;text-align:right}th:first-child,td:first-child{text-align:left}th{font-size:12px;color:#62656d}
small{color:#62656d}</style>
<h1>Raadiosalvesti – statistika</h1>
<div class="k"><div><b>${installs}</b>paigaldust kokku<br><small>Mac ${summary.installs_mac} · Windows ${summary.installs_win}</small></div>
<div><b>≈ ${activeEstimate}</b>aktiivset paigaldust<br><small>eilsete uuenduskontrollide põhjal</small></div>
<div><b>${summary.updates}</b>uuendust</div><div><b>${summary.page_views}</b>lehe avamist</div></div>
<table><tr><th>Päev</th>${kinds.map((kd) => `<th>${esc(LABEL[kd])}</th>`).join("")}</tr>
${days.map((d) => `<tr><td>${d}${d === today ? " (täna)" : ""}</td>${kinds.map((kd) => `<td>${cell(d, kd)}</td>`).join("")}</tr>`).join("") || `<tr><td colspan="${kinds.length + 1}">Andmeid veel pole.</td></tr>`}
</table><p><small>Loendatakse ainult päringute arvu päevas – IP-aadresse ega muid isikuandmeid ei salvestata. Paigaldused sisaldavad ka korduskäivitusi. Lehe avamistes võib olla roboteid.</small></p>`;
  return new Response(html, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex" } });
}
