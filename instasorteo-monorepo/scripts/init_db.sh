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
