# Proyecto Rasp_PY_Instagram_Alu

> Sistema de **raspado, análisis y gestión de concursos de Instagram**, desarrollado en **Python** con base de datos **MySQL**.  
> Permite detectar **seguidores nuevos o perdidos**, **comentarios borrados**, **participantes activos**, y generar **rankings automáticos** por fechas.

---

## 📖 Descripción general

El sistema está diseñado para registrar concursos y sus datos asociados, como productos, usuarios, comentarios y seguidores.  
Cada ejecución de **raspado** crea una "fotografía" del estado del concurso en ese momento, almacenando información en tablas con sufijo `_por_fechas`.

### Objetivos principales:
- 📊 Registrar concursos y productos asociados.  
- 🧠 Analizar seguidores y detectar `unfollows`.  
- 💬 Procesar comentarios y marcar `sigue` / `participa`.  
- 🏆 Calcular rankings automáticos de papeletas.  
- 🔄 Generar un **JSON exportable** para integrarse con Java.

---

## 🗄️ Diseño de Base de Datos (MySQL 8)

```sql
CREATE DATABASE IF NOT EXISTS instasorteo
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE instasorteo;

CREATE TABLE concursos (
  id_concurso BIGINT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(200) NOT NULL,
  fecha_concurso DATE NOT NULL,
  creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE usuarios (
  id_usuario BIGINT AUTO_INCREMENT PRIMARY KEY,
  nick VARCHAR(100) NOT NULL UNIQUE,
  fecha_seguimiento DATE NULL,
  unfollows TINYINT(1) NOT NULL DEFAULT 0,
  creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE productos (
  id_producto BIGINT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  descripcion VARCHAR(10000) NOT NULL,
  imagen_blob LONGBLOB NULL,
  imagen_url VARCHAR(255) NULL,
  id_ganador BIGINT NULL,
  FOREIGN KEY (id_ganador) REFERENCES usuarios(id_usuario) ON DELETE SET NULL
);

CREATE TABLE concursos_productos (
  id_concurso BIGINT NOT NULL,
  id_producto BIGINT NOT NULL,
  PRIMARY KEY (id_concurso, id_producto),
  FOREIGN KEY (id_concurso) REFERENCES concursos(id_concurso) ON DELETE CASCADE,
  FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
);

CREATE TABLE raspados (
  id_raspado BIGINT AUTO_INCREMENT PRIMARY KEY,
  fecha DATETIME NOT NULL,
  fuente VARCHAR(100) NULL
);

CREATE TABLE comentarios (
  id_comentario BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_raspado BIGINT NOT NULL,
  id_concurso BIGINT NOT NULL,
  id_usuario BIGINT NOT NULL,
  mensaje TEXT NOT NULL,
  fecha_raspado DATETIME NOT NULL,
  sigue TINYINT(1) DEFAULT 1,
  participa TINYINT(1) DEFAULT 1,
  fecha_comentario DATETIME NULL,
  id_externo VARCHAR(128) NULL,
  UNIQUE KEY uq_ext (id_concurso, id_externo),
  FOREIGN KEY (id_raspado) REFERENCES raspados(id_raspado) ON DELETE CASCADE,
  FOREIGN KEY (id_concurso) REFERENCES concursos(id_concurso) ON DELETE CASCADE,
  FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario) ON DELETE CASCADE
);

CREATE TABLE seguidores_snapshots (
  id_snapshot BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_raspado BIGINT NOT NULL,
  id_usuario BIGINT NOT NULL,
  fecha_raspado DATETIME NOT NULL,
  n_mensajes INT DEFAULT 0,
  fecha DATE NOT NULL,
  FOREIGN KEY (id_raspado) REFERENCES raspados(id_raspado) ON DELETE CASCADE,
  FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario) ON DELETE CASCADE
);

CREATE TABLE ranking_por_fechas (
  id_ranking BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_concurso BIGINT NOT NULL,
  id_usuario BIGINT NOT NULL,
  papeletas INT DEFAULT 0,
  fecha DATE NOT NULL,
  FOREIGN KEY (id_concurso) REFERENCES concursos(id_concurso) ON DELETE CASCADE,
  FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario) ON DELETE CASCADE
);
```

---

## 🧠 Modelos en Python (backend/models.py)

```python
from dataclasses import dataclass, field, asdict
from datetime import datetime, date
from typing import List, Optional, Dict, Any

@dataclass
class Producto:
    nombre: str
    descripcion: str
    imagen_url: Optional[str] = None
    id_ganador: Optional[int] = None

@dataclass
class Usuario:
    nick: str
    fecha_seguimiento: Optional[date] = None
    unfollows: bool = False

@dataclass
class Comentario:
    id_externo: Optional[str]
    mensaje: str
    usuario: str
    fecha_raspado: datetime
    sigue: bool
    participa: bool
    fecha: Optional[datetime] = None

@dataclass
class Seguimiento:
    usuario: str
    fecha_raspado: datetime
    id_raspado: int
    n_mensajes: int
    fecha: date

@dataclass
class RankingItem:
    usuario: str
    papeletas: int
    fecha: date

@dataclass
class Raspado:
    id_raspado: int
    fecha: datetime

@dataclass
class Concurso:
    id_concurso: int
    fecha_concurso: date
    usuarios: List[str] = field(default_factory=list)
    comentarios: List[Comentario] = field(default_factory=list)
    productos: List[Producto] = field(default_factory=list)
```

---

## ⚙️ Flujo de trabajo en Python

### 1️⃣ Raspado de Seguidores

```python
import mysql.connector
from datetime import datetime, date

def actualizar_seguidores(followers_nicks):
    db = mysql.connector.connect(
        host="localhost", user="root", password="collado", database="instasorteo", autocommit=True)
    cur = db.cursor()
    cur.execute("INSERT INTO raspados(fecha) VALUES (%s)", (datetime.utcnow(),))
    id_raspado = cur.lastrowid

    for nick in followers_nicks:
        cur.execute("INSERT IGNORE INTO usuarios(nick) VALUES (%s)", (nick,))
        cur.execute("""
            INSERT IGNORE INTO seguidores_snapshots(id_raspado, id_usuario, fecha_raspado, fecha)
            SELECT %s, id_usuario, %s, %s FROM usuarios WHERE nick=%s
        """, (id_raspado, datetime.utcnow(), date.today(), nick))

    cur.execute("""
      UPDATE usuarios u
      LEFT JOIN (
        SELECT s.id_usuario FROM seguidores_snapshots s WHERE s.id_raspado=%s
      ) AS actual ON actual.id_usuario=u.id_usuario
      SET u.unfollows = CASE WHEN actual.id_usuario IS NULL THEN 1 ELSE 0 END
    """, (id_raspado,))

    db.close()
    print(f"✅ Raspado de seguidores insertado (id={id_raspado})")
```

### 2️⃣ Raspado de Comentarios

```python
import mysql.connector
from datetime import datetime

def actualizar_comentarios(id_concurso, comentarios):
    db = mysql.connector.connect(
        host="localhost", user="root", password="collado", database="instasorteo", autocommit=True)
    cur = db.cursor()
    cur.execute("INSERT INTO raspados(fecha) VALUES (%s)", (datetime.utcnow(),))
    id_raspado = cur.lastrowid

    for c in comentarios:
        cur.execute("INSERT IGNORE INTO usuarios(nick) VALUES (%s)", (c["usuario"],))
        cur.execute("""
          INSERT INTO comentarios(
            id_raspado, id_concurso, id_usuario, mensaje, fecha_raspado, sigue, participa, id_externo
          )
          SELECT %s, %s, id_usuario, %s, %s, 1, %s, %s FROM usuarios WHERE nick=%s
          ON DUPLICATE KEY UPDATE mensaje=VALUES(mensaje), sigue=1, participa=VALUES(participa)
        """, (id_raspado, id_concurso, c["mensaje"], datetime.utcnow(),
              c.get("participa", True), c.get("id_externo"), c["usuario"]))

    db.close()
    print(f"✅ Raspado de comentarios insertado (id={id_raspado})")
```

### 3️⃣ Cálculo de Ranking

```python
import mysql.connector
from datetime import date

def recalcular_ranking(id_concurso):
    db = mysql.connector.connect(
        host="localhost", user="root", password="collado", database="instasorteo", autocommit=True)
    cur = db.cursor()
    cur.execute("""
      SELECT id_usuario, COUNT(*) AS papeletas
      FROM comentarios
      WHERE id_concurso=%s AND participa=1 AND sigue=1
      GROUP BY id_usuario
    """, (id_concurso,))
    for uid, papeletas in cur.fetchall():
        cur.execute("""
          INSERT INTO ranking_por_fechas(id_concurso, id_usuario, papeletas, fecha)
          VALUES (%s,%s,%s,%s)
          ON DUPLICATE KEY UPDATE papeletas=VALUES(papeletas)
        """, (id_concurso, uid, papeletas, date.today()))
    db.close()
    print("🏆 Ranking actualizado correctamente")
```

---

## 📦 Intercambio de Datos (Python → JSON)

```json
{
  "raspado": { "id_raspado": 42, "fecha": "2025-11-10T12:00:00Z" },
  "concurso": { "id_concurso": 1, "fecha_concurso": "2025-12-07" },
  "seguidores": [
    { "usuario": "ana", "fecha_raspado": "2025-11-10T12:00:00Z", "id_raspado": 42, "n_mensajes": 0, "fecha": "2025-11-10" }
  ],
  "comentarios": [
    {
      "id_externo": "ig_cmt_123",
      "mensaje": "¡Participo!",
      "usuario": "ana",
      "fecha_raspado": "2025-11-10T12:00:00Z",
      "sigue": true,
      "participa": true
    }
  ],
  "ranking": [
    { "usuario": "ana", "papeletas": 1, "fecha": "2025-11-10" }
  ],
  "productos": [
    { "nombre": "Rimmel London", "descripcion": "Calendario de Adviento Rimmel", "imagen_url": null, "id_ganador": null }
  ]
}
```

---

## 🐋 Docker (nota técnica)

> Aunque el proyecto está escrito en **Python**, el contenedor puede ser **lanzado desde Java** si el sistema se amplía.

### backend/Dockerfile

```dockerfile
FROM python:3.11-slim
WORKDIR /app
RUN pip install mysql-connector-python
COPY backend/ /app/backend/
CMD ["python", "backend/ingest_followers.py"]
```

### docker-compose.yml

```yaml
version: "3.9"
services:
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: collado
      MYSQL_DATABASE: instasorteo
    ports:
      - "3306:3306"

  backend:
    build:
      context: .
      dockerfile: backend/Dockerfile
    environment:
      DB_HOST: db
      DB_USER: root
      DB_PASS: collado
      DB_NAME: instasorteo
    depends_on:
      - db
```

---

📅 **Última actualización:** 10 de noviembre de 2025  
✉️ **Autor:** [luisitobravete](mailto:luisitobravete@gmail.com)
