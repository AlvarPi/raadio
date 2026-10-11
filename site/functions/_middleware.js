// Anonüümne loendur: ainult päevased arvud (ei IP-aadresse, ei muid isikuandmeid).
// D1 binding STATS (Pages → Settings → Bindings). Ilma selleta lihtsalt ei loeta.
const TRACK = {
  "/": "page_view",
  "/install": "install_mac",
  "/install.ps1": "install_win",
  "/version.json": "update_check",
};

export async function onRequest(ctx) {
  const { request, env, next } = ctx;
  const url = new URL(request.url);
  let kind = TRACK[url.pathname];
  if (kind && request.method === "GET" && env.STATS) {
    if (kind.startsWith("install_") && url.searchParams.has("update")) kind += "_update"; // raadio update
    const day = new Date().toISOString().slice(0, 10);
    ctx.waitUntil(
      env.STATS.batch([
        env.STATS.prepare("CREATE TABLE IF NOT EXISTS hits (day TEXT NOT NULL, kind TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, kind))"),
        env.STATS.prepare("INSERT INTO hits (day, kind, n) VALUES (?, ?, 1) ON CONFLICT (day, kind) DO UPDATE SET n = n + 1").bind(day, kind),
      ]).catch(() => {}),
    );
  }
  return next();
}
