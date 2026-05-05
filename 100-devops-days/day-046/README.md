# Día 46 - Desplegar una app PHP + MariaDB con Docker Compose

## Problema / Desafío

El equipo de desarrollo de Nautilus terminó una app PHP que necesita un stack completo: servidor web con PHP + Apache, y base de datos MariaDB. Hay que desplegarla en App Server 1 (`stapp01`) usando un único `docker-compose.yml` en `/opt/devops/`.

**Servicio web:**
- Contenedor: `php_host`, imagen `php:<algún tag con apache>`
- Puerto host `8087` → contenedor `80`
- Bind mount `/var/www/html` (host) → `/var/www/html` (contenedor)

**Servicio db:**
- Contenedor: `mysql_host`, imagen `mariadb:latest`
- Puerto host `3306` → contenedor `3306`
- Bind mount `/var/lib/mysql` (host) → `/var/lib/mysql` (contenedor)
- Variables: `MYSQL_DATABASE=database_host` + un usuario custom con su contraseña

Validación: `curl <host>:8087/` debe devolver el HTML de `index.php`.

## Conceptos clave

### Múltiples servicios en un solo compose

Un compose puede declarar varios servicios bajo la clave `services:`. Cada servicio se vuelve un contenedor independiente, pero todos comparten una **red default** que Compose crea automáticamente. Dentro de esa red, los servicios se ven entre sí usando el **nombre del servicio** como hostname.

```
Red interna (devops_default):
  web → DNS interno → mysql_host:3306   (o "db:3306" usando el nombre del servicio)
```

Aunque en este lab el código PHP no se conecta a la DB, esta es la base sobre la que se construyen stacks reales (web ↔ DB ↔ cache ↔ workers).

### Variables de entorno: prefijos `MYSQL_` vs `MARIADB_`

La imagen oficial de `mariadb` acepta **dos juegos** de nombres para las mismas variables, por compatibilidad histórica con MySQL:

| Nombre legacy (MySQL) | Nombre actual (MariaDB) |
|----------------------|------------------------|
| `MYSQL_ROOT_PASSWORD` | `MARIADB_ROOT_PASSWORD` |
| `MYSQL_DATABASE` | `MARIADB_DATABASE` |
| `MYSQL_USER` | `MARIADB_USER` |
| `MYSQL_PASSWORD` | `MARIADB_PASSWORD` |

Ambos prefijos funcionan. Lo recomendable es elegir uno y mantenerlo — mezclarlos confunde a quien lea el archivo después.

### `MARIADB_USER` requiere `MARIADB_PASSWORD`

Una sutileza importante de la imagen: si declaras `MARIADB_USER` **sin** declarar `MARIADB_PASSWORD`, la creación del usuario se omite o el entrypoint falla con `MARIADB_USER set but MARIADB_PASSWORD not set`. Vienen en par.

```yaml
# ❌ Incompleto: el usuario "admin" no se crea
environment:
  - MARIADB_USER=admin
  - MARIADB_ROOT_PASSWORD=...

# ✅ Correcto: ambos juntos
environment:
  - MARIADB_USER=admin
  - MARIADB_PASSWORD=<contraseña_compleja>
  - MARIADB_ROOT_PASSWORD=...
```

El lab pide explícitamente "un usuario custom con contraseña compleja", así que las dos variables son obligatorias.

### Bind mount de `/var/lib/mysql` y persistencia

Montar `/var/lib/mysql` del host sobre el contenedor hace que los **datafiles** de MariaDB vivan fuera del contenedor. Implicaciones:

- Los datos sobreviven a `docker compose down` (e incluso a borrar la imagen).
- Si la carpeta del host ya tenía datafiles de una corrida previa, MariaDB **no re-inicializa**. Eso significa que cambiar `MYSQL_DATABASE` o `MARIADB_USER` después de la primera corrida no tiene efecto — la base ya existe.
- Para forzar re-inicialización: detener el stack, borrar `/var/lib/mysql/*` en el host, levantar de nuevo.

Esto explica por qué a veces "cambié la variable y nada pasó": el volumen tiene precedencia.

### `php:apache` vs `php:fpm`

La imagen oficial de PHP tiene tres familias de tags:

| Tag | Qué incluye | Cuándo usarla |
|-----|-------------|---------------|
| `php:<v>-apache` | PHP + Apache (mod_php) embebido | Stack todo-en-uno, dev/labs |
| `php:<v>-fpm` | Solo PHP-FPM (escucha en 9000) | Producción con nginx separado |
| `php:<v>-cli` | Solo el CLI de PHP | Scripts/cron, sin servidor web |

Para este lab `php:7.2-apache` es lo correcto: trae todo en un solo contenedor que ya sirve `index.php` desde `/var/www/html`.

## Pasos

1. Inspeccionar el `index.php` que ya existe en `/var/www/html`
2. Escribir el servicio `web` y validar de forma aislada
3. Agregar el servicio `db` con sus env vars
4. Levantar el stack con `docker compose up -d`
5. Verificar contenedores con `docker ps` y la app con `curl`

## Comandos / Código

### 1. Contenido de `/var/www/html/index.php`

```bash
cat /var/www/html/index.php
```

```html
<html>
    <head>
        <title>Welcome to xFusionCorp Industries!</title>
    </head>

    <body>
        <?php
            echo "Welcome to xFusionCorp Industries!";
        ?>
    </body>
</html>
```

### 2. Probar el servicio web aisladamente

Una buena práctica para stacks multi-servicio es validar cada pieza por separado antes de combinarlas. Compose inicial solo con `web`:

```yaml
services:
  web:
    container_name: php_host
    image: php:7.2-apache
    ports:
      - "8087:80"
    volumes:
      - "/var/www/html:/var/www/html"
```

```bash
docker compose up -d
curl localhost:8087
```

```html
<html>
    <head>
        <title>Welcome to xFusionCorp Industries!</title>
    </head>
    <body>
        Welcome to xFusionCorp Industries!    </body>
</html>
```

`<?php echo "..." ?>` ya no aparece en la respuesta — Apache lo procesó con `mod_php` y devolvió solo el resultado del `echo`. Eso confirma que el bind mount sirve los archivos del host **y** que PHP está activo.

### 3. Compose final con web + db

```yaml
services:
  web:
    container_name: php_host
    image: php:7.2-apache
    ports:
      - "8087:80"
    volumes:
      - "/var/www/html:/var/www/html"

  db:
    container_name: mysql_host
    image: mariadb:latest
    ports:
      - "3306:3306"
    volumes:
      - "/var/lib/mysql:/var/lib/mysql"
    environment:
      - MYSQL_DATABASE=database_host
      - MARIADB_USER=admin
      - MARIADB_PASSWORD=<secrets_password>
      - MARIADB_ROOT_PASSWORD=<secret_password>
```

### 4. Levantar el stack

```bash
docker compose up -d
```

```
[+] up 17/17
 ✔ Image php:7.2-apache   Pulled                                       12.2s
 ✔ Network devops_default Created                                      0.1s
 ✔ Container php_host     Created                                      0.1s
 ✔ Container mysql_host   Created                                      0.1s
```

### 5. Verificar contenedores

```bash
docker ps
```

```
CONTAINER ID   IMAGE            COMMAND                  CREATED   STATUS         PORTS                                       NAMES
94c9d9ec0588   mariadb:latest   "docker-entrypoint.s…"   2m ago    Up 2 seconds   0.0.0.0:3306->3306/tcp, :::3306->3306/tcp   mysql_host
58b66acf99b1   php:7.2-apache   "docker-php-entrypoi…"   8m ago    Up 2 seconds   0.0.0.0:8087->80/tcp, :::8087->80/tcp       php_host
```

Ambos en `Up`, con el port mapping correcto: `8087→80` para el web y `3306→3306` para la DB.

### 6. Validar la verificación HTTP

```bash
curl localhost:8087
```

Devuelve el HTML procesado de `index.php` — la app está sirviendo correctamente.

## Verificar que la DB se inicializó correctamente

`docker ps` muestra que el contenedor está corriendo, pero eso **no garantiza** que las variables de entorno hayan creado la base de datos y el usuario. Para confirmarlo hay que consultar el estado real de la DB:

```bash
docker exec mysql_host mariadb -u admin -p'<secret_password>' -e "SHOW DATABASES;"
```

Desglose del comando:

- `docker exec mysql_host` — ejecuta dentro del contenedor (sin `-it` porque es one-shot, no necesitamos terminal interactiva)
- `mariadb` — cliente CLI dentro de la imagen
- `-u admin` — usuario
- `-p'<secret_password>'` — contraseña inline (sin espacio entre `-p` y la contraseña; comillas simples para que el shell no expanda los caracteres especiales)
- `-e "SHOW DATABASES;"` — ejecuta el SQL y sale

> ⚠️ **Sobre el `-p` inline:** Pasar la contraseña directamente en la línea de comando es práctico para labs y troubleshooting puntual, pero **no es seguro en entornos compartidos**:
>
> - **Queda en `~/.bash_history`** (cualquiera con acceso al usuario la ve después con `history`).
> - **Es visible para otros usuarios del host** mientras el proceso corre — `ps aux` muestra los argumentos completos, incluyendo la contraseña.
> - **Aparece en logs de auditoría / SIEM** si el sistema captura comandos ejecutados.
> - **Termina en logs de CI/CD** en plano si el comando corre dentro de un pipeline.
>
> Alternativas más seguras según el contexto:
>
> ```bash
> # 1. -p sin valor: el cliente pide la contraseña interactivamente (no queda en history)
> docker exec -it mysql_host mariadb -u admin -p -e "SHOW DATABASES;"
>
> # 2. Variable MYSQL_PWD inyectada solo al proceso (no aparece en argv)
> docker exec -e MYSQL_PWD='<secret>' mysql_host mariadb -u admin -e "SHOW DATABASES;"
>
> # 3. Archivo de credenciales con permisos 600 (~/.my.cnf dentro del contenedor)
> docker exec mysql_host mariadb --defaults-file=/etc/mysql/admin.cnf -e "SHOW DATABASES;"
> ```
>
> Para producción real: nunca hardcodear contraseñas en compose files — usar [Docker secrets](https://docs.docker.com/engine/swarm/secrets/), Vault, o el secret manager de tu plataforma (AWS Secrets Manager, GCP Secret Manager, K8s Secrets).

**Resultado esperado (estado limpio, primera inicialización):**

```
Database
information_schema
database_host
```

`database_host` aparece junto a `information_schema` (que es interna de MariaDB) → confirmado: la env var `MYSQL_DATABASE` se aplicó y el usuario `admin` puede autenticarse.

### Qué pasa si `/var/lib/mysql` ya tenía datos previos

Si el bind mount del host no estaba vacío al levantar el stack por primera vez, el entrypoint de MariaDB **detecta los datafiles existentes y omite la inicialización completa**. No corre los `CREATE DATABASE`, no crea usuarios, y no aplica ninguna `MARIADB_*` variable.

Síntoma típico:

```bash
docker exec mysql_host mariadb -u admin -p'<secret_password>' -e "SHOW DATABASES;"
# ERROR 1045 (28000): Access denied for user 'admin'@'localhost' (using password: YES)
```

El contenedor está `Up`, `mariadbd` corre como PID 1, pero el usuario `admin` simplemente nunca existió en esta corrida.

**Cómo resolverlo (re-inicializar):**

```bash
# 1. Bajar el stack (mantiene el volumen del host)
docker compose down

# 2. Vaciar el directorio de datafiles del host
rm -rf /var/lib/mysql/*

# 3. Levantar de nuevo — esta vez el entrypoint corre la inicialización
docker compose up -d

# 4. Reverificar
docker exec mysql_host mariadb -u admin -p'<secret_password>' -e "SHOW DATABASES;"
```

> **Por qué importa esta verificación:** Las variables de entorno de imágenes oficiales se leen **solo en la primera corrida**, cuando la carpeta de datos está vacía. Si el bind mount ya tenía datafiles, las nuevas variables se ignoran sin error visible — el contenedor reporta `Up`, los logs no se quejan, pero el usuario y la base nunca se crean. La única forma de detectarlo es consultando el estado real con `docker exec`.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `MARIADB_USER set but MARIADB_PASSWORD not set` en logs del contenedor db | Faltó declarar `MARIADB_PASSWORD` — siempre van en par |
| Cambié una env var pero la DB sigue con la config vieja | El bind mount `/var/lib/mysql` ya tiene datafiles inicializados — borrar el contenido del directorio del host y `docker compose up -d` para re-inicializar |
| `Bind for 0.0.0.0:3306 failed: port is already allocated` | Otro proceso usa 3306 (probablemente un MariaDB del host) — `ss -tlnp \| grep 3306` para identificarlo |
| `curl localhost:8087` devuelve el código `<?php ... ?>` literal en vez del HTML procesado | PHP no se está ejecutando — verificar que la imagen sea `php:<v>-apache` (no solo `php:<v>`, que es el CLI) |
| `mysql_host` se reinicia en loop | Revisar `docker logs mysql_host` — usualmente es una env var inválida o un datafile corrupto en el bind mount |
| YAML inconsistencia de indentación | Compose es estricto con la indentación — usar 2 espacios consistentes, no mezclar con tabs |

## Recursos

- [Imagen oficial de PHP — variantes y tags](https://hub.docker.com/_/php)
- [Imagen oficial de MariaDB — env vars completas](https://hub.docker.com/_/mariadb)
- [Compose file reference: services](https://docs.docker.com/compose/compose-file/05-services/)
- [Por qué `MARIADB_USER` y `MARIADB_PASSWORD` van en par](https://github.com/MariaDB/mariadb-docker/blob/master/docs/content/_index.md#mariadb_user-mariadb_password)
