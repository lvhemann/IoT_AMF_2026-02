-- Rode no console do seu banco D1 (Cloudflare -> D1 -> seu banco -> Console).
-- "IF NOT EXISTS": se a tabela ja existe (da atividade de D1), nada acontece.

CREATE TABLE IF NOT EXISTS leituras (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  sensor    TEXT    NOT NULL,
  valor     REAL    NOT NULL,
  timestamp INTEGER NOT NULL
);

-- Toda requisicao recusada fica registrada aqui (o "alarme" do sistema)
CREATE TABLE IF NOT EXISTS tentativas (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  motivo    TEXT    NOT NULL,
  ip        TEXT,
  timestamp INTEGER NOT NULL
);

-- Assinaturas ja aceitas: se a mesma chegar de novo, e' replay
CREATE TABLE IF NOT EXISTS assinaturas_usadas (
  assinatura TEXT    PRIMARY KEY,
  timestamp  INTEGER NOT NULL
);
