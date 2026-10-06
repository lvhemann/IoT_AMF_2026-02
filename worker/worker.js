// ================================================================
//  WORKER SEGURO — Estacao Cofre (Cloudflare Workers + D1)
//
//  Configuracao (Settings -> Variables and Secrets):
//    API_KEY            (Secret)   -> Camada 2
//    CHAVE_HMAC         (Secret)   -> Camada 3
//    EXIGIR_ASSINATURA  (Variable) -> "nao" (so API key) ou "sim" (API key + HMAC)
//  Binding do D1 com o nome  DB  (o mesmo da atividade de D1).
// ================================================================

const JANELA_S = 60;                              // requisicao vale por 60 s
const LIMITES  = { temp: [-20, 60], umid: [0, 100] };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // ---- ESCRITA: passa pelas travas ----
    if (url.pathname === "/insert" && request.method === "POST") {
      const corpo = await request.text();         // texto CRU: e' ele que foi assinado
      const barrado = await autenticar(request, env, corpo);
      if (barrado) return barrado;

      let b;
      try { b = JSON.parse(corpo); } catch { return negar(request, env, 400, "JSON invalido"); }

      // validar entrada: nunca confiar no payload, mesmo autenticado
      const sensor = String(b.sensor ?? "");
      const valor  = Number(b.valor);
      if (!Object.hasOwn(LIMITES, sensor)) return negar(request, env, 400, "sensor desconhecido");
      const [min, max] = LIMITES[sensor];
      if (!Number.isFinite(valor) || valor < min || valor > max)
        return negar(request, env, 400, "valor fora da faixa");

      await env.DB.prepare("INSERT INTO leituras (sensor, valor, timestamp) VALUES (?, ?, ?)")
        .bind(sensor, valor, Date.now()).run();
      return new Response(`OK: ${sensor}=${valor}`);
    }

    // ---- LEITURA (aberta, igual as atividades anteriores) ----
    if (url.pathname === "/list") {
      const sensor = url.searchParams.get("sensor") || "temp";
      const { results } = await env.DB.prepare(
        "SELECT valor, timestamp FROM leituras WHERE sensor = ? ORDER BY timestamp DESC LIMIT 50"
      ).bind(sensor).all();
      return Response.json(results);
    }

    if (url.pathname === "/resumo") {
      const { results } = await env.DB.prepare(
        "SELECT sensor, AVG(valor) AS media, MAX(valor) AS maximo, COUNT(*) AS n FROM leituras GROUP BY sensor"
      ).all();
      return Response.json(results);
    }

    // ---- ALARME: tentativas recusadas (so o dono ve: tem IP de gente) ----
    if (url.pathname === "/tentativas") {
      if (!env.API_KEY || !iguais(request.headers.get("X-API-Key") || "", env.API_KEY))
        return new Response("Unauthorized", { status: 401 });
      const { results } = await env.DB.prepare(
        "SELECT motivo, ip, timestamp FROM tentativas ORDER BY timestamp DESC LIMIT 50"
      ).all();
      return Response.json(results);
    }

    return new Response("Rotas: POST /insert | GET /list?sensor=temp | GET /resumo | GET /tentativas", { status: 404 });
  }
};

// ================================================================
//  autenticar(): devolve null se pode passar, ou a Response de recusa.
//  Reaproveite em QUALQUER rota que grava ou comanda algo.
// ================================================================
async function autenticar(request, env, corpo) {
  if (!env.API_KEY) return new Response("Configure o Secret API_KEY no Worker", { status: 500 });

  // Camada 2 — API key: "voce tem a chave?"
  if (!iguais(request.headers.get("X-API-Key") || "", env.API_KEY))
    return negar(request, env, 401, "sem API key ou API key errada");

  if (env.EXIGIR_ASSINATURA !== "sim") return null;   // ainda na camada 2
  if (!env.CHAVE_HMAC) return new Response("Configure o Secret CHAVE_HMAC no Worker", { status: 500 });

  // Camada 3 — assinatura: "esse corpo saiu de quem tem a chave, sem alteracao?"
  const assinatura = (request.headers.get("X-Assinatura") || "").toLowerCase();
  const esperada   = await hmacHex(env.CHAVE_HMAC, corpo);
  if (!iguais(assinatura, esperada))
    return negar(request, env, 401, "assinatura invalida (corpo alterado ou chave errada)");

  // Anti-replay parte 1 — "essa requisicao e' de agora?"
  let ts;
  try { ts = Number(JSON.parse(corpo).ts); } catch { ts = NaN; }
  const agora = Math.floor(Date.now() / 1000);
  if (!Number.isInteger(ts) || Math.abs(agora - ts) > JANELA_S)
    return negar(request, env, 401, `expirada (ts fora da janela de ${JANELA_S} s)`);

  // Anti-replay parte 2 — "essa assinatura ja foi usada?"
  const r = await env.DB.prepare(
    "INSERT OR IGNORE INTO assinaturas_usadas (assinatura, timestamp) VALUES (?, ?)"
  ).bind(assinatura, Date.now()).run();
  if (r.meta.changes === 0) return negar(request, env, 401, "replay (assinatura ja usada)");

  // faxina: assinatura com mais de 5 min ja cairia na janela de tempo
  await env.DB.prepare("DELETE FROM assinaturas_usadas WHERE timestamp < ?")
    .bind(Date.now() - 5 * 60 * 1000).run();
  return null;
}

// HMAC-SHA256 em hexadecimal — mesma conta que o ESP32 faz com mbedtls
async function hmacHex(chave, msg) {
  const enc = new TextEncoder();
  const k = await crypto.subtle.importKey("raw", enc.encode(chave),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", k, enc.encode(msg));
  return [...new Uint8Array(mac)].map(b => b.toString(16).padStart(2, "0")).join("");
}

// Comparacao em tempo constante (nao revela onde a diferenca esta)
function iguais(a, b) {
  if (a.length !== b.length) return false;
  let dif = 0;
  for (let i = 0; i < a.length; i++) dif |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return dif === 0;
}

// Recusa + registra a tentativa (sem guardar segredo nenhum)
async function negar(request, env, status, motivo) {
  try {
    await env.DB.prepare("INSERT INTO tentativas (motivo, ip, timestamp) VALUES (?, ?, ?)")
      .bind(motivo, request.headers.get("CF-Connecting-IP") || "?", Date.now()).run();
  } catch (e) { /* tabela ainda nao criada: segue recusando mesmo assim */ }
  return new Response(`Recusado: ${motivo}`, { status });
}
