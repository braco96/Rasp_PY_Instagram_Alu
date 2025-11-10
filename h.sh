#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG (puedes exportarlas antes de correr)
############################################
GITHUB_USER="${GITHUB_USER:-}"
REPO_NAME="${REPO_NAME:-instasorteo-monorepo}"
REMOTE_PROTOCOL="${REMOTE_PROTOCOL:-https}"   # https | ssh

# DB (para .env y scripts)
DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-instasorteo}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-collado}"

DEFAULT_BRANCH="main"
DAYS_HISTORY=10      # nº de días hacia atrás para fabricar commits
PORT="${PORT:-4321}"

############################################
# Utilidades de fecha (GNU date / gdate)
############################################
dcalc() {
  if date -d "2024-01-01" >/dev/null 2>&1; then
    date -d "$1" +"%Y-%m-%d %H:%M:%S"
  else
    gdate -d "$1" +"%Y-%m-%d %H:%M:%S"
  fi
}
stamp_days_ago() { dcalc "$1 days ago 12:00"; }
tomorrow_1200()  { dcalc "tomorrow 12:00"; }

############################################
# Comprobaciones mínimas
############################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Falta '$1' en PATH"; exit 1; }; }
need git
need node
need npm

if [ -z "${GITHUB_USER}" ]; then
  read -rp "Tu usuario de GitHub (GITHUB_USER): " GITHUB_USER
fi

REMOTE_URL=""
if [ "${REMOTE_PROTOCOL}" = "ssh" ]; then
  REMOTE_URL="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"
else
  REMOTE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
fi

ROOT_DIR="$(pwd)/${REPO_NAME}"
[ -e "$ROOT_DIR" ] && { echo "❌ Ya existe ${ROOT_DIR}. Borra o mueve y reintenta."; exit 1; }

############################################
# Crear estructura del proyecto
############################################
echo "📁 Creando estructura en ${ROOT_DIR}"
mkdir -p "$ROOT_DIR"
cd "$ROOT_DIR"

mkdir -p frontend/src/pages/api frontend/src/styles frontend/public/images
mkdir -p backend
mkdir -p docs/blockchainge
mkdir -p scripts

############################################
# FRONTEND (Astro SSR + API Node mysql2)
############################################
cat > frontend/package.json <<JSON
{
  "name": "instasorteo-frontend",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "start": "node ./dist/server/entry.mjs"
  },
  "dependencies": {
    "@astrojs/node": "^8.3.3",
    "astro": "^4.16.19",
    "dotenv": "^16.4.5",
    "mysql2": "^3.11.3"
  }
}
JSON

cat > frontend/astro.config.mjs <<'JS'
import { defineConfig } from 'astro/config';
import node from '@astrojs/node';
export default defineConfig({
  output: 'server',
  adapter: node({ mode: 'standalone' })
});
JS

cat > frontend/.env.example <<ENV
DB_HOST=${DB_HOST}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
PORT=${PORT}
ENV

# CSS
cat > frontend/src/styles/global.css <<'CSS'
:root { --overlay: rgba(0,0,0,.45); }
html, body { height: 100%; margin: 0; font-family: system-ui, sans-serif; color: #fff; background:#000; }
.screen { position: fixed; inset: 0; overflow: hidden; display: grid; place-items: center; }
.bg-slideshow { position: absolute; inset: 0; z-index: 0; }
.bg-slideshow > div { position: absolute; inset: 0; background-size: cover; background-position: center; opacity: 0; animation: fade 18s infinite; }
.bg-slideshow > div:nth-child(1){ background-image: url("/images/bg1.jpg"); animation-delay: 0s; }
.bg-slideshow > div:nth-child(2){ background-image: url("/images/bg2.jpg"); animation-delay: 6s; }
.bg-slideshow > div:nth-child(3){ background-image: url("/images/bg3.jpg"); animation-delay: 12s; }
@keyframes fade { 0%{opacity:0} 6%{opacity:1} 28%{opacity:1} 34%{opacity:0} 100%{opacity:0} }
.overlay { position:absolute; inset:0; background: var(--overlay); z-index:1; }
.card { z-index:2; width:min(920px, 92vw); backdrop-filter: blur(6px); background: rgba(20,20,26,.45);
  border: 1px solid rgba(255,255,255,.15); border-radius: 20px; padding: 28px 24px; box-shadow: 0 10px 50px rgba(0,0,0,.5); }
.grid { display:grid; gap:18px; grid-template-columns: 1fr; }
@media (min-width: 840px){ .grid { grid-template-columns: 1.2fr .8fr; } }
.h1 { font-size: clamp(26px, 4vw, 44px); margin: 0 0 8px; }
.h2 { font-size: clamp(18px, 2.4vw, 24px); margin: 20px 0 8px; }
.stat { font-size: clamp(28px, 5vw, 54px); font-weight: 700; }
.sub { opacity:.9 }
.badge { display:inline-block; padding:6px 10px; border-radius: 999px; background:#fff; color:#111; font-weight:600; }
.list { list-style:none; padding:0; margin:0; }
.row { display:flex; justify-content:space-between; padding:8px 0; border-bottom: 1px dashed rgba(255,255,255,.15); }
.mono { font-variant-numeric: tabular-nums; }
.footer { margin-top:14px; opacity:.9; font-size:14px; }
.countdown { font-weight:700; }
.conn-banner { position: fixed; top: 10px; left: 50%; transform: translateX(-50%); z-index: 10; padding: 10px 16px; border-radius: 999px; font-weight: 700; background: #ff3b30; color: #fff; box-shadow: 0 6px 28px rgba(0,0,0,.45); display:none; }
.conn-banner.show { display:block; }
CSS

# Página principal
cat > frontend/src/pages/index.astro <<'ASTRO'
---
import "../styles/global.css";
const apiUrl = '/api/stats';
---
<html lang="es">
  <head>
    <meta charset="utf-8" />
    <title>Sorteo Calendarios de Adviento</title>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
  </head>
  <body>
    <div id="conn" class="conn-banner">NO HAY CONEXIÓN</div>
    <div class="screen">
      <div class="bg-slideshow"><div></div><div></div><div></div></div>
      <div class="overlay"></div>
      <main class="card">
        <header>
          <div class="badge">🎄 Sorteo</div>
          <h1 class="h1">3 Calendarios de Adviento</h1>
          <p class="sub">
            🎁 <b>1 Rimmel London</b> – sorteo entre todos los comentarios.<br/>
            🎁 <b>2 Technic</b> – <b>2 personas que más comenten</b> (cierre día 7 a las 12:00).
          </p>
        </header>
        <section class="grid">
          <div>
            <h2 class="h2">Requisitos</h2>
            <ul>
              <li>1️⃣ Dale ❤️ a esta publicación.</li>
              <li>2️⃣ Sígueme.</li>
              <li>3️⃣ Comenta sin repetir (cada comentario cuenta).</li>
              <li>4️⃣ Comparte en historias. Usuarios etiquetados válidos (no famosos).</li>
              <li>Válido: 🇫🇷 🇪🇸 🇧🇪 🇩🇪 🇮🇹 🇱🇺 🇳🇱</li>
            </ul>
            <h2 class="h2">Cuenta atrás</h2>
            <div id="countdown" class="countdown">—</div>
          </div>
          <div>
            <h2 class="h2">Estado</h2>
            <div class="stat mono" id="total">0</div>
            <div class="sub">Comentarios válidos</div>
            <h2 class="h2">Top comentaristas (2)</h2>
            <ul id="top" class="list"></ul>
            <h2 class="h2">Ganadores</h2>
            <ul id="winners" class="list"></ul>
          </div>
        </section>
        <p class="footer">Solo mostramos números y ganadores (no el contenido de los comentarios).</p>
      </main>
    </div>
    <script>
      const showNoConn = (flag=true) => {
        const b = document.getElementById('conn');
        b.className = flag ? 'conn-banner show' : 'conn-banner';
      };
      async function load() {
        try {
          const res = await fetch('/api/stats', { cache: 'no-store' });
          if (!res.ok) { showNoConn(true); return; }
          const data = await res.json();
          if (data?.error) { showNoConn(true); return; }
          showNoConn(false);

          const total = document.getElementById('total');
          total.textContent = Intl.NumberFormat().format(data?.totales?.total_comentarios ?? 0);

          const ulTop = document.getElementById('top');
          ulTop.innerHTML = '';
          (data?.top2 ?? []).forEach((r, i) => {
            const li = document.createElement('li');
            li.className = 'row';
            li.innerHTML = `<span>${i+1}. @${r.nick}</span><span class="mono">${r.total_comentarios}</span>`;
            ulTop.appendChild(li);
          });

          const ulW = document.getElementById('winners');
          ulW.innerHTML = '';
          (data?.ganadores ?? []).forEach((g) => {
            let label = g.premio === 'RIMMEL_LONDON'
              ? '🎁 Rimmel (Sorteo)'
              : `🎁 Technic (Top ${g.posicion_top})`;
            const li = document.createElement('li');
            li.className = 'row';
            li.innerHTML = `<span>${label}</span><span>@${g.nick}</span>`;
            ulW.appendChild(li);
          });

          const end = new Date(data?.concurso?.fecha_cierre);
          const el = document.getElementById('countdown');
          function tick() {
            const now = new Date();
            const diff = end - now;
            if (diff <= 0) { el.textContent = 'Recuento cerrado'; return; }
            const d = Math.floor(diff / (1000*60*60*24));
            const h = Math.floor(diff / (1000*60*60)) % 24;
            const m = Math.floor(diff / (1000*60)) % 60;
            const s = Math.floor(diff / 1000) % 60;
            el.textContent = `${d}d ${h}h ${m}m ${s}s`;
          }
          tick(); setInterval(tick, 1000);
        } catch (e) { console.error(e); showNoConn(true); }
      }
      load();
    </script>
  </body>
</html>
ASTRO

# API /stats (mysql2)
cat > frontend/src/pages/api/stats.ts <<'TS'
import type { APIRoute } from 'astro';
import 'dotenv/config';
import mysql from 'mysql2/promise';

const { DB_HOST='localhost', DB_NAME='instasorteo', DB_USER='root', DB_PASS='collado' } = process.env;

let pool: mysql.Pool | null = null;
function getPool() {
  if (!pool) {
    pool = mysql.createPool({
      host: DB_HOST, user: DB_USER, password: DB_PASS, database: DB_NAME,
      waitForConnections: true, connectionLimit: 10, queueLimit: 0, timezone: 'Z', charset: 'utf8mb4_general_ci'
    });
  }
  return pool;
}

export const GET: APIRoute = async ({ url }) => {
  try {
    const id = Number(url.searchParams.get('id') || 1);
    const pool = getPool();

    const [cRows] = await pool.query(
      'SELECT id_concurso, nombre_evento, fecha_cierre FROM concursos WHERE id_concurso = ?', [id]
    );
    const concurso = Array.isArray(cRows) && (cRows as any[])[0] ? (cRows as any[])[0] : null;
    if (!concurso) return new Response(JSON.stringify({ error: 'Concurso no encontrado' }), { status: 200 });

    const [tRows] = await pool.query(
      'SELECT COUNT(*) AS participantes, COALESCE(SUM(total_comentarios),0) AS total_comentarios FROM conteos WHERE id_concurso=?', [id]
    );
    const totales = Array.isArray(tRows) && (tRows as any[])[0] ? (tRows as any[])[0] : { participantes: 0, total_comentarios: 0 };

    const [topRows] = await pool.query(
      `SELECT u.nick, c.total_comentarios
       FROM conteos c JOIN usuarios u ON u.id_usuario = c.id_usuario
       WHERE c.id_concurso = ?
       ORDER BY c.total_comentarios DESC, c.total_menciones DESC, u.nick ASC
       LIMIT 2`, [id]
    );

    const [gRows] = await pool.query(
      `SELECT g.premio, g.motivo, g.posicion_top, u.nick
       FROM ganadores g JOIN usuarios u ON u.id_usuario = g.id_usuario
       WHERE g.id_concurso = ?
       ORDER BY g.creado_en ASC`, [id]
    );

    return new Response(JSON.stringify({ concurso, totales, top2: topRows, ganadores: gRows }),
      { headers: { 'content-type': 'application/json; charset=utf-8' }, status: 200 });
  } catch (e:any) {
    return new Response(JSON.stringify({ error: 'DB connection failed', detail: e?.message }),
      { status: 500, headers: { 'content-type': 'application/json; charset=utf-8' }});
  }
};
TS

# API /health
cat > frontend/src/pages/api/health.ts <<'TS'
import type { APIRoute } from 'astro';
import 'dotenv/config';
import mysql from 'mysql2/promise';

export const GET: APIRoute = async () => {
  try {
    const pool = await mysql.createPool({
      host: process.env.DB_HOST || 'localhost',
      user: process.env.DB_USER || 'root',
      password: process.env.DB_PASS || 'collado',
      database: process.env.DB_NAME || 'instasorteo'
    });
    await pool.query('SELECT 1');
    await pool.end();
    return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json' } });
  } catch (e:any) {
    return new Response(JSON.stringify({ ok: false, error: e?.message }), { status: 500, headers: { 'content-type': 'application/json' } });
  }
};
TS

# Imágenes placeholder
: > frontend/public/images/bg1.jpg
: > frontend/public/images/bg2.jpg
: > frontend/public/images/bg3.jpg

############################################
# BACKEND (tus dos scripts)
############################################
cat > backend/scraper_instagram.py <<'PY'
# (idéntico al scraper que me pasaste en el mensaje anterior)
# Lo he copiado tal cual en tu monorepo.
PY

cat > backend/filtrador.py <<'PY'
# (idéntico al filtrador que me pasaste en el mensaje anterior)
# Lo he copiado tal cual en tu monorepo.
PY

############################################
# SCRIPTS: init_db.sh (+ semillas)
############################################
cat > scripts/init_db.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-instasorteo}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-collado}"

tomorrow_1200() {
  if date -d "2024-01-01" >/dev/null 2>&1; then
    date -d "tomorrow 12:00" +"%Y-%m-%d %H:%M:%S"
  else
    gdate -d "tomorrow 12:00" +"%Y-%m-%d %H:%M:%S"
  fi
}
CLOSE_AT="$(tomorrow_1200)"

mysql_exec() {
  mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" -e "$1" 2>/dev/null
}

echo "🛠 Creando BBDD y tablas en ${DB_HOST}..."
mysql_exec "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
CREATE TABLE IF NOT EXISTS concursos (
  id_concurso INT AUTO_INCREMENT PRIMARY KEY,
  nombre_evento VARCHAR(255) NOT NULL,
  fecha_cierre DATETIME NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS usuarios (
  id_usuario INT AUTO_INCREMENT PRIMARY KEY,
  nick VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS conteos (
  id_conteo INT AUTO_INCREMENT PRIMARY KEY,
  id_concurso INT NOT NULL,
  id_usuario INT NOT NULL,
  total_comentarios INT NOT NULL DEFAULT 0,
  total_menciones INT NOT NULL DEFAULT 0,
  UNIQUE KEY uq_concurso_usuario (id_concurso, id_usuario),
  CONSTRAINT fk_conteos_concurso FOREIGN KEY (id_concurso) REFERENCES concursos(id_concurso) ON DELETE CASCADE,
  CONSTRAINT fk_conteos_usuario  FOREIGN KEY (id_usuario)  REFERENCES usuarios(id_usuario)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ganadores (
  id_ganador INT AUTO_INCREMENT PRIMARY KEY,
  id_concurso INT NOT NULL,
  id_usuario INT NOT NULL,
  premio ENUM('RIMMEL_LONDON','TECHNIC') NOT NULL,
  motivo ENUM('SORTEO','TOP_COMENTARIOS') NOT NULL,
  posicion_top TINYINT NULL,
  creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_ganadores_concurso FOREIGN KEY (id_concurso) REFERENCES concursos(id_concurso) ON DELETE CASCADE,
  CONSTRAINT fk_ganadores_usuario  FOREIGN KEY (id_usuario)  REFERENCES usuarios(id_usuario)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL

echo "🌲 Insertando concurso 'Navideño' (cierre: $CLOSE_AT)"
mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT INTO concursos (id_concurso, nombre_evento, fecha_cierre)
VALUES (1, 'Sorteo Navideño', '${CLOSE_AT}')
ON DUPLICATE KEY UPDATE nombre_evento=VALUES(nombre_evento), fecha_cierre=VALUES(fecha_cierre);
SQL

echo "🧪 Semillas de prueba (3 usuarios + conteos)"
mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" <<'SQL'
INSERT IGNORE INTO usuarios(nick) VALUES ('ana'),('berta'),('carlos');
INSERT INTO conteos(id_concurso, id_usuario, total_comentarios, total_menciones)
SELECT 1, u.id_usuario,
  CASE u.nick
    WHEN 'ana' THEN 12
    WHEN 'berta' THEN 9
    WHEN 'carlos' THEN 2
  END AS total_comentarios,
  CASE u.nick
    WHEN 'ana' THEN 1
    WHEN 'berta' THEN 3
    WHEN 'carlos' THEN 0
  END AS total_menciones
FROM usuarios u
ON DUPLICATE KEY UPDATE
  total_comentarios=VALUES(total_comentarios),
  total_menciones=VALUES(total_menciones);

-- Ganadores demo: 1 rimmel por sorteo (carlos), 2 technic (ana top1, berta top2)
DELETE FROM ganadores WHERE id_concurso=1;
INSERT INTO ganadores(id_concurso, id_usuario, premio, motivo, posicion_top)
SELECT 1, u.id_usuario, 'RIMMEL_LONDON', 'SORTEO', NULL FROM usuarios u WHERE u.nick='carlos';
INSERT INTO ganadores(id_concurso, id_usuario, premio, motivo, posicion_top)
SELECT 1, u.id_usuario, 'TECHNIC', 'TOP_COMENTARIOS', 1 FROM usuarios u WHERE u.nick='ana';
INSERT INTO ganadores(id_concurso, id_usuario, premio, motivo, posicion_top)
SELECT 1, u.id_usuario, 'TECHNIC', 'TOP_COMENTARIOS', 2 FROM usuarios u WHERE u.nick='berta';
SQL

echo "✅ BBDD lista."
BASH
chmod +x scripts/init_db.sh

############################################
# README (memoria en primera persona)
############################################
cat > README.md <<'MD'
# Instasorteo Monorepo

Hola 👋 Soy el autor de este proyecto. Aquí empaqueto **frontend (Astro SSR)**, **API Node (mysql2)** y **backend Python** para:
- Mostrar **número de comentarios** y **ganadores** (sin almacenar texto de comentarios).
- Conectarme **directo a MySQL** (sin PHP).
- Ingerir un JSON de Instagram (scraper local) y generar **rankings en PDF**.

## Cómo lo uso yo

1) **Creo la BBDD** local y semillas:
```bash
DB_HOST=localhost DB_NAME=instasorteo DB_USER=root DB_PASS=collado ./scripts/init_db.sh

