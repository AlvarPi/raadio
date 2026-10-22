// /count – avalik loendur maandumislehele: ainult lehe avamiste koguarv (päevade tabel on /stats taga).
export async function onRequestGet({ env }) {
  let pageViews = 0;
  try {
    pageViews = (await env.STATS.prepare("SELECT COALESCE(SUM(n), 0) AS n FROM hits WHERE kind = 'page_view'").first())?.n || 0;
  } catch { /* D1 pole seotud või tabelit veel pole */ }
  return Response.json({ page_views: pageViews }, { headers: { "cache-control": "public, max-age=300" } });
}
