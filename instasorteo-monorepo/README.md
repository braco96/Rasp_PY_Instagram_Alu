# Instasorteo Monorepo

Hola 👋 Soy el autor de este proyecto. Aquí empaqueto **frontend (Astro SSR)**, **API Node (mysql2)** y **backend Python** para:
- Mostrar **número de comentarios** y **ganadores** (sin almacenar texto de comentarios).
- Conectarme **directo a MySQL** (sin PHP).
- Ingerir un JSON de Instagram (scraper local) y generar **rankings en PDF**.

## Cómo lo uso yo

1) **Creo la BBDD** local y semillas:
```bash
DB_HOST=localhost DB_NAME=instasorteo DB_USER=root DB_PASS=collado ./scripts/init_db.sh

