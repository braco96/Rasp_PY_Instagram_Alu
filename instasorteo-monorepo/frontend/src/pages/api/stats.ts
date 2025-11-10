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
