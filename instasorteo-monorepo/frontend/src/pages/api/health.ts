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
