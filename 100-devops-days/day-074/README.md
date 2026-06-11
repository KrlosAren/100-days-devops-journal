# Día 74 - Jenkins Database Backup Job (mysqldump + Credentials Manager + cron)

## Problema / Desafío

Hay que automatizar el backup de la DB `kodekloud_db01` que vive en el App Server (`stapp01`). El job debe correr cada 10 minutos, generar un dump con nombre dinámico (`db_YYYY-MM-DD.sql`), y copiarlo al Storage Server (`ststor01`).

Requirements:

1. Login a la UI de Jenkins como `admin` / `Adm!n321`
2. Crear job **`database-backup`** (Freestyle)
3. Configurar:
   - **Backup de `kodekloud_db01`** en `stapp01` (user `kodekloud_roy`, password `asdfgdsd`)
   - **Nombre del dump**: `db_$(date +%F).sql` (ejemplo: `db_2026-06-05.sql`)
   - **Copiar a** `ststor01:/home/natasha/db_backups/`
   - **Trigger cron**: `*/10 * * * *` (cada 10 minutos — usar **exactamente** esta expresión, no `H/10`)
4. El password de la DB debe vivir en el **Credentials Manager**, no hardcoded en el script

Servers involucrados:

| Server         | Rol                                  | Usuario SSH    | Detalle                                          |
| -------------- | ------------------------------------ | -------------- | ------------------------------------------------ |
| `jenkins`      | Server de Jenkins (controller)       | `jenkins`      | Donde corre el job                                |
| `stapp01`      | App Server 1                         | `steve`        | MariaDB 10.5 escuchando en :3306 (LAMP stack)    |
| `ststor01`     | Storage Server                       | `natasha`      | Destino de los backups                            |

DB:

| Atributo          | Valor                  |
| ----------------- | ---------------------- |
| Tipo              | MariaDB 10.5.29        |
| Puerto            | 3306                   |
| Database          | `kodekloud_db01`       |
| Usuario           | `kodekloud_roy`        |
| Password          | `asdfgdsd`             |

## Conceptos clave

### Verificación de la DB antes de scriptear

Antes de armar el job, vale validar a mano que el dump funcione. Esto evita debuggear desde Jenkins lo que se puede debuggear desde un shell:

```bash
# 1. Confirmar que el puerto 3306 está abierto
ssh tony@stapp01 'sudo netstat -tunlp | grep 3306'
# tcp6  0  0  :::3306  :::*  LISTEN  2717/mariadbd

# 2. Login interactivo para validar credenciales
ssh tony@stapp01
mysql -u kodekloud_roy kodekloud_db01 -p
# Enter password: asdfgdsd
# MariaDB [kodekloud_db01]> show databases;

# 3. Dump manual para validar la sintaxis
mysqldump -u kodekloud_roy -p kodekloud_db01 > db_$(date +%F).sql
# Enter password: asdfgdsd
ls
# db_2026-06-05.sql
```

> Que aparezca `mariadbd` (no `mysqld`) en el output de `netstat` confirma que es **MariaDB**, fork open-source de MySQL. Sintaxis de comandos `mysql`/`mysqldump` es **idéntica** entre los dos — vienen incluso del mismo paquete de cliente en RHEL.

### `mysql` vs `mysqldump` — distintos comandos para distintos propósitos

| Comando       | Para qué sirve                                          |
| ------------- | ------------------------------------------------------- |
| **`mysql`**   | Cliente **interactivo** (REPL) — abre prompt para queries |
| **`mysqldump`** | Genera **snapshot SQL** de una DB — output a stdout    |

Bug clásico: usar `mysql` en lugar de `mysqldump` en un script de backup. `mysql` abre la conexión pero no produce dump — espera input interactivo. El script termina sin generar el archivo y `> /tmp/dump.sql` queda vacío.

### Flags de `mysqldump` que importan

```bash
mysqldump -u <user> -p<password> <database> > <output.sql>
#         │      │              │            │
#         │      │              │            └─ Redirección a archivo
#         │      │              └───────────────  Nombre de la DB
#         │      └──────────────────────────────  Password (sin espacio entre -p y el password)
#         └─────────────────────────────────────  Usuario (minúscula)
```

| Flag                    | Importancia                                                                       |
| ----------------------- | --------------------------------------------------------------------------------- |
| `-u <user>`             | Username — `-u` minúscula (`-U` no existe)                                         |
| `-p<password>`          | Password **sin espacio**. Con espacio: `-p asdfgdsd` → asdfgdsd se interpreta como nombre de DB |
| `-p` (sin valor)        | Pide password interactivamente (no útil en scripts)                                |
| `--password=<password>` | Alternativa explícita, más legible                                                 |
| `MYSQL_PWD=<password>` env var | Más segura — el password no aparece en `ps -ef`                          |
| `-h <host>`             | Si la DB no está en localhost                                                      |
| `--single-transaction`  | Dump consistente para tablas InnoDB sin lockear                                    |
| `--routines`            | Incluir stored procedures y functions                                              |
| `--triggers`            | Incluir triggers                                                                   |

> Para producción real, un dump "completo" típicamente es:
> ```bash
> mysqldump -u <user> -p<pwd> --single-transaction --routines --triggers <db> > dump.sql
> ```

### Por qué `MYSQL_PWD` es preferible a `-p<password>`

Con `-p<password>`:

```bash
$ mysqldump -p<password> mydb > dump.sql
# En otra sesión del mismo server:
$ ps -ef | grep mysqldump
steve  1234  ...  mysqldump -pasdfgdsd mydb     ← password visible
```

Con `MYSQL_PWD`:

```bash
$ MYSQL_PWD=<password> mysqldump mydb > dump.sql
$ ps -ef | grep mysqldump
steve  1234  ...  mysqldump mydb                ← sin password en la línea
```

> Las env vars de un proceso se ven en `/proc/<pid>/environ`, pero requiere ser owner del proceso o root. La line de comando `/proc/<pid>/cmdline` la puede leer **cualquier usuario** del server. Por eso `MYSQL_PWD` es la convención segura.

### Jenkins Credentials Manager — la primera vez en el journal

Hasta ahora todos los secrets (SSH keys, passwords) vivían en filesystem o hardcoded. Hoy aparece el **Credentials Manager** — el "Vault interno" de Jenkins.

Ubicación en la UI: **Manage Jenkins → Credentials → System → Global credentials**.

Tipos de credentials disponibles:

| Tipo                          | Cuándo usar                                                                |
| ----------------------------- | -------------------------------------------------------------------------- |
| **Username with password**    | Pares user/password — bases de datos, registros Docker, APIs               |
| **SSH Username with private key** | SSH keys (alternativa al `/var/lib/jenkins/.ssh/` filesystem)             |
| **Secret text**               | Strings opacos — tokens API, passwords sueltos. **Este lab usa este.**     |
| **Secret file**               | Archivos opacos — kubeconfigs, service account JSON                        |
| **Certificate**               | PKCS#12 / JKS — TLS client certs                                            |

Plugin necesario: **Credentials** (`credentials` plugin, suele venir preinstalado en setup wizard; si no, instalarlo del marketplace — ver screenshot inicial del lab).

### Bindings — cómo el job consume las credentials

Una credential creada en el manager no es accesible directamente desde el shell. Hay que **bindearla** al job:

1. Job config → marcar **"Use secret text(s) or file(s)"** en la sección Build Environment
2. **Add → Secret text**
3. Configurar:
   - **Variable**: nombre de la env var en el shell (ej. `MYSQL_PASSWORD`)
   - **Credentials**: dropdown → seleccionar la credential creada (por su ID)

Cuando el job corre, la variable está disponible en el shell:

```bash
echo "Password length: ${#MYSQL_PASSWORD}"     # Solo la longitud, no el valor
# Jenkins enmascara el valor en logs:
echo "$MYSQL_PASSWORD"
# **** (output enmascarado)
```

> **Garantía operacional**: Jenkins reemplaza el valor del secret por `****` en todos los logs. Incluso con `set -x`, los comandos que usan el secret aparecen ofuscados. Esto justifica el overhead vs hardcodear: **el log es auditable sin filtrar el secret**.

### Diferencia con env vars normales del job

| Forma                                          | Cuándo el valor queda en logs                              |
| ---------------------------------------------- | ---------------------------------------------------------- |
| **String parameter** (Día 72)                  | Visible en logs (incluso en el `+` del set -x)             |
| **Credential binding (Secret text)**           | **Enmascarado** como `****` en todo log                    |
| **Hardcoded en el script**                     | Visible en logs, en `config.xml`, en git si versionado    |
| **`/var/lib/jenkins/.ssh/<key>` filesystem**   | No aparece en logs pero queda en disco                     |

Para passwords, **siempre Credential binding**.

## Pasos

1. Login como `admin` / `Adm!n321`
2. SSH al server jenkins desde el jump host
3. Distribuir SSH keys del user `jenkins` a `stapp01` y `ststor01`
4. Validar a mano que `mysqldump` funcione contra `kodekloud_db01`
5. Crear el directorio destino en ststor01: `mkdir -p /home/natasha/db_backups`
6. En la UI: Manage Jenkins → Credentials → Add → **Secret text**
   - **Secret**: `asdfgdsd`
   - **ID**: `mysql-roy-password`
   - **Description**: `Password for kodekloud_roy MySQL user`
7. Dashboard → New Item → `database-backup` → Freestyle → OK
8. Configurar:
   - **Build Triggers** → Build periodically → `*/10 * * * *`
   - **Build Environment** → Use secret text(s) or file(s) → Add Secret text:
     - Variable: `MYSQL_PASSWORD`
     - Credentials: `mysql-roy-password`
   - **Build Steps** → Execute shell → script con `mysqldump` + `scp`
9. Save → Build Now → validar log

## Comandos / Código

### Setup de SSH desde el server jenkins

```bash
ssh root@jenkins

# Generar key si no existe (idempotente)
sudo -u jenkins ssh-keygen -t ed25519 -C "jenkins@ci" \
  -f /var/lib/jenkins/.ssh/id_ed25519 -N "" 2>/dev/null || true

# Distribuir a stapp01 y ststor01
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub tony@stapp01
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub natasha@ststor01

# Validar
sudo -u jenkins ssh -o StrictHostKeyChecking=no tony@stapp01 hostname
sudo -u jenkins ssh -o StrictHostKeyChecking=no natasha@ststor01 hostname
```

### Crear el directorio destino en ststor01

```bash
ssh natasha@ststor01 'mkdir -p /home/natasha/db_backups'
```

> Si se omite este paso, el primer `scp` cae en la trampa documentada en el Día 73 (crea un archivo `db_backups` en lugar de un directorio).

### Validación manual de mysqldump (antes del job)

```bash
ssh tony@stapp01
# En la sesión SSH:
mysqldump -u kodekloud_roy -pasdfgdsd kodekloud_db01 > /tmp/db_$(date +%F).sql
ls -la /tmp/db_*.sql
# -rw-r--r-- 1 tony tony 1.2K Jun 5 ... /tmp/db_2026-06-05.sql

# Confirmar que el archivo contiene SQL (no error o vacío)
head -5 /tmp/db_$(date +%F).sql
# -- MariaDB dump 10.19  Distrib 10.5.29-MariaDB
# -- Host: localhost    Database: kodekloud_db01
# ...
```

> **Nota del lab**: el SSH user para `stapp01` es `tony` (no `steve` como en otros labs). Cada server de KodeKloud tiene un user SSH específico — vale validar cuál es antes de armar el script.

### Credential en el Jenkins Credentials Manager

Navegación: **Manage Jenkins → Credentials → System → Global credentials (unrestricted) → Add Credentials**.

| Campo              | Valor                                       |
| ------------------ | ------------------------------------------- |
| Kind               | **Secret text**                             |
| Scope              | Global                                      |
| Secret             | `asdfgdsd`                                  |
| ID                 | `mysql-roy-password`                        |
| Description        | `Password for kodekloud_roy on stapp01`     |

Click **Create**.

### Configuración del job `database-backup`

**1. General**: nombre `database-backup`, Freestyle.

**2. Build Triggers**:

| Campo                | Valor             |
| -------------------- | ----------------- |
| Build periodically   | ✅                 |
| Schedule             | `*/10 * * * *`    |

> Aunque Jenkins muestra el warning de usar `H/10`, el lab pide **exactamente** `*/10`. No cambiarlo.

**3. Build Environment** → marcar **"Use secret text(s) or file(s)"** → Add → **Secret text**:

| Campo        | Valor                       |
| ------------ | --------------------------- |
| Variable     | `MYSQL_PASSWORD`            |
| Credentials  | `mysql-roy-password`        |

**4. Build Steps** → **Execute shell**:

```bash
# Construir el nombre del archivo con la fecha
name="db_$(date +%F).sql"
echo "Generando dump $name desde stapp01..."

# Crear el directorio destino si no existe (idempotente)
ssh natasha@ststor01 'mkdir -p /home/natasha/db_backups'

# Ejecutar mysqldump en stapp01 usando MYSQL_PWD para evitar exponer el password en ps -ef
# El password viaja como env var inyectada via Credential binding, NO hardcoded
ssh tony@stapp01 "MYSQL_PWD='$MYSQL_PASSWORD' mysqldump -u kodekloud_roy kodekloud_db01" > "/tmp/$name"

echo "Dump generado en /tmp/$name (tamaño: $(stat -c%s /tmp/$name) bytes)"

# Copiar al storage server
echo "Copiando a ststor01:/home/natasha/db_backups/"
scp "/tmp/$name" "natasha@ststor01:/home/natasha/db_backups/$name"

echo "Backup completado."

# Validar
ssh natasha@ststor01 "ls -lhart /home/natasha/db_backups/ | tail -5"
```

**Save**.

### Detalles del script — punto por punto

| Línea / pattern                                                                     | Por qué                                                                                              |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `name="db_$(date +%F).sql"`                                                          | `$(date +%F)` se expande al equivalente de `2026-06-05`. Las comillas dobles permiten la expansión.  |
| `ssh natasha@ststor01 'mkdir -p ...'`                                                | Comillas simples para que la variable `$MYSQL_PASSWORD` **no se expanda** acá (no aplica)            |
| `ssh tony@stapp01 "MYSQL_PWD='$MYSQL_PASSWORD' mysqldump -u kodekloud_roy ..."`     | Comillas dobles externas para que `$MYSQL_PASSWORD` se expanda **localmente** en Jenkins             |
| `MYSQL_PWD='$MYSQL_PASSWORD'`                                                        | Pasa el password como env var a mysqldump en el server remoto. **No aparece en `ps -ef`**            |
| `> "/tmp/$name"`                                                                     | Redirección **del lado de Jenkins** — el stdout del ssh viene al workspace, no a `/tmp/` de stapp01 |

> **Importante sobre la redirección**: el `>` está **fuera** del ssh (después de la comilla de cierre). Eso significa que `ssh tony@stapp01 "mysqldump ..."` ejecuta el dump remotamente, **transmite el SQL como stdout por la conexión SSH**, y Jenkins escribe el archivo en su propio `/tmp/`. Si el `>` estuviera dentro de las comillas, el archivo se crearía en `/tmp/` de stapp01.

### Variante alternativa — dump generado y leído en stapp01

Si se prefiere que el dump quede primero en stapp01 y después se copie:

```bash
name="db_$(date +%F).sql"

# Generar dump remotamente (queda en /tmp/ de stapp01)
ssh tony@stapp01 "MYSQL_PWD='$MYSQL_PASSWORD' mysqldump -u kodekloud_roy kodekloud_db01 > /tmp/$name"

# Copiar de stapp01 a ststor01 directamente
scp "tony@stapp01:/tmp/$name" "natasha@ststor01:/home/natasha/db_backups/$name"

# Limpiar el archivo temporal en stapp01
ssh tony@stapp01 "rm -f /tmp/$name"
```

Pros y contras de cada variante:

| Variante                                | Pros                                                | Contras                                                                  |
| --------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------ |
| **Dump → stdout → archivo en Jenkins**  | No deja archivos temporales en stapp01              | El dump pasa por el filesystem del jenkins (workspace)                   |
| **Dump → archivo en stapp01 → scp**     | Más claro de leer; cada paso es un comando atómico  | Hay que limpiar el archivo temporal o se acumulan                        |
| **`mysqldump` desde Jenkins directo**   | Sin intermediario remoto                            | Requiere abrir 3306 en stapp01 a la red del jenkins (security boundary)  |

### Log esperado del Console Output

```
Started by user admin
Running as SYSTEM
Building in workspace /var/lib/jenkins/workspace/database-backup
[database-backup] $ /bin/sh -xe /tmp/jenkins<id>.sh
+ name=db_2026-06-05.sql
+ date +%F
+ echo Generando dump db_2026-06-05.sql desde stapp01...
Generando dump db_2026-06-05.sql desde stapp01...
+ ssh natasha@ststor01 mkdir -p /home/natasha/db_backups
+ ssh tony@stapp01 MYSQL_PWD='****' mysqldump -u kodekloud_roy kodekloud_db01
+ echo Dump generado en /tmp/db_2026-06-05.sql (tamaño: 1234 bytes)
Dump generado en /tmp/db_2026-06-05.sql (tamaño: 1234 bytes)
+ echo Copiando a ststor01:/home/natasha/db_backups/
Copiando a ststor01:/home/natasha/db_backups/
+ scp /tmp/db_2026-06-05.sql natasha@ststor01:/home/natasha/db_backups/db_2026-06-05.sql
+ echo Backup completado.
Backup completado.
+ ssh natasha@ststor01 ls -lhart /home/natasha/db_backups/ | tail -5
-rw-r--r-- 1 natasha natasha 1.3K Jun  5 09:30 db_2026-06-05.sql
Finished: SUCCESS
```

> Observación clave: la línea `+ ssh tony@stapp01 MYSQL_PWD='****' mysqldump ...` muestra el password **enmascarado**. Jenkins detecta automáticamente que el valor de `$MYSQL_PASSWORD` viene de una credential y lo reemplaza por `****` en el log, incluso en el output de `set -x`.

## Versión que pasó el lab (con sus issues anclados)

El script que finalmente pasó la validación fue:

```bash
name=db_$(date +%F).sql
echo "Creando dump con nombre $name..."
ssh tony@stapp01 mysqldump -u kodekloud_roy -p'asdfgdsd' kodekloud_db01 > /tmp/db_$(date +%F).sql
echo "Dump finalizado..."
echo "Copiando en server storage..."
scp tony@stapp01:/tmp/$name natasha@ststor01:/home/natasha/db_backups/
echo "Finalizada la copia..."
echo "Validamos existencia..."
ssh natasha@ststor01 "ls -lhart /home/natasha/db_backups"
```

Log final:

```
+ ssh tony@stapp01 mysqldump -u kodekloud_roy -pasdfgdsd kodekloud_db01
...
+ scp tony@stapp01:/tmp/db_2026-06-05.sql natasha@ststor01:/home/natasha/db_backups/
...
-rw-r--r-- 1 natasha natasha 1.3K Jun  5 14:08 db_2026-06-05.sql
Finished: SUCCESS
```

El lab validó porque el archivo apareció en `ststor01:/home/natasha/db_backups/`. Pero hay dos issues operacionales que vale documentar:

### Issue 1 — El password queda expuesto en el log

```
+ ssh tony@stapp01 mysqldump -u kodekloud_roy -pasdfgdsd kodekloud_db01
```

Como `asdfgdsd` está **hardcoded en el script** (no inyectado vía Credentials Manager), Jenkins no lo reconoce como secret y **no lo enmascara**. Cualquier user con `Job: Read` sobre este job puede leer el password en `<job>/<build#>/console`, y el archivo `/var/lib/jenkins/jobs/database-backup/builds/<N>/log` lo conserva en disco.

**Fix**: pasar al Credentials Manager (Secret text) + Credential binding como env var, según la sección "Configuración del job" arriba. Jenkins entonces enmascara automáticamente el valor en logs:

```
+ ssh tony@stapp01 MYSQL_PWD='****' mysqldump -u kodekloud_roy kodekloud_db01
```

### Issue 2 — Misterio de paths que "funciona por accidente"

```bash
ssh tony@stapp01 mysqldump ... kodekloud_db01 > /tmp/db_$(date +%F).sql
                                                ↑
                              redirección del lado de Jenkins (escribe en jenkins:/tmp/)

scp tony@stapp01:/tmp/db_2026-06-05.sql natasha@ststor01:...
                ↑
        busca en stapp01:/tmp/ (no en jenkins:/tmp/)
```

Las dos partes apuntan a **paths en servers distintos**:

- El `>` del `ssh ... > /tmp/...` escribe en el server jenkins porque la redirección está **fuera** del comando remoto
- El `scp tony@stapp01:/tmp/...` busca en stapp01, no en jenkins

¿Por qué funcionó? Probablemente porque alguna iteración previa del script tenía la redirección **dentro** del ssh:

```bash
# Versión previa (que dejó el archivo en stapp01)
ssh tony@stapp01 "mysqldump ... kodekloud_db01 > /tmp/db_$(date +%F).sql"
```

Esa versión escribió el archivo en stapp01:/tmp/, y aunque la versión actual del script ya no lo hace, el archivo quedó ahí del run anterior. El scp lo encontró y copió.

**Fix**: alinear los dos lados:

```bash
# Opción A: dump en jenkins → scp local-a-remoto
ssh tony@stapp01 "MYSQL_PWD='$MYSQL_PASSWORD' mysqldump -u kodekloud_roy kodekloud_db01" > "/tmp/$name"
scp "/tmp/$name" "natasha@ststor01:/home/natasha/db_backups/$name"

# Opción B: dump en stapp01 → scp remoto-a-remoto
ssh tony@stapp01 "MYSQL_PWD='$MYSQL_PASSWORD' mysqldump -u kodekloud_roy kodekloud_db01 > /tmp/$name"
scp "tony@stapp01:/tmp/$name" "natasha@ststor01:/home/natasha/db_backups/$name"
ssh tony@stapp01 "rm -f /tmp/$name"   # limpiar el temporal
```

> **Lección operacional**: un job verde no garantiza que el script sea correcto. La validación del lab solo chequea que el archivo aparezca en el destino — no chequea reproducibilidad ni seguridad. Para producción real, vale auditar el log de cada build con criterios extra (passwords no aparecen, paths son dinámicos, idempotencia).

## Bugs comunes en este lab

| Bug                                                          | Síntoma                                                          | Fix                                                                |
| ------------------------------------------------------------ | ---------------------------------------------------------------- | ------------------------------------------------------------------ |
| `mysql` en lugar de `mysqldump`                              | El comando abre el cliente interactivo, archivo de salida vacío  | Cambiar a `mysqldump`                                              |
| `-U` mayúscula en lugar de `-u`                              | `unknown option: -U`                                             | Usar `-u` minúscula                                                |
| `-p asdfgdsd` con espacio entre `-p` y el password           | El password se interpreta como nombre de DB                       | `-pasdfgdsd` sin espacio, o `MYSQL_PWD` env var                    |
| Password hardcodeado en el script                            | Aparece en el log, en `config.xml`, en cualquier audit           | Mover al Credentials Manager y bindear como `MYSQL_PASSWORD`       |
| Comillas dobles dentro de `sh -c "..."`                      | El parser cierra la comilla externa al ver la primera interna   | Usar comillas simples para `sh -c` o no envolver con `sh -c`       |
| Path destino `/home/tmp/$name` cuando el archivo está en `/tmp/$name` | `scp: No such file or directory`                              | Corregir el path source del scp                                    |
| `/home/natasha/db_backups` no existe en ststor01             | scp con barra final falla; sin barra crea archivo (trampa Día 73) | `mkdir -p` previo, terminar destino con `/`                        |
| Cron `*/10` cambiado a `H/10` por el warning de Jenkins      | El lab marca incorrecto                                          | **El lab pide exactamente `*/10`**; ignorar el warning             |
| Job pasa pero el archivo del dump tiene 0 bytes              | `mysqldump` falló silenciosamente; output redirigido sin error visible | Verificar con `wc -c <archivo>`; revisar permisos del user en la DB |

## Anatomía del filesystem después de N builds

```
# En jenkins
/var/lib/jenkins/credentials.xml             ← Credenciales encriptadas (al disco)
/var/lib/jenkins/secrets/                    ← Master keys de encriptación
/var/lib/jenkins/workspace/database-backup/  ← Workspace (vacío entre builds, no se guarda nada acá)
/var/lib/jenkins/jobs/database-backup/
├── config.xml                               ← Definición del job (incluye binding al credentialId)
└── builds/
    ├── 1/, 2/, 3/, ...                      ← Uno cada 10 min después del primer build

# En stapp01 (si se usa la variante con archivo intermedio)
/tmp/db_2026-06-05.sql                       ← Archivo temporal (limpiar en el script)

# En ststor01
/home/natasha/db_backups/
├── db_2026-06-05.sql                        ← Backup del día
├── db_2026-06-04.sql                        ← Del día anterior (si el job corrió)
└── ...
```

> Importante sobre el `credentials.xml`: el password está cifrado con la master key del Jenkins. **No es base64** (no se puede decodificar trivialmente como un Secret de K8s). La key vive en `/var/lib/jenkins/secrets/master.key` — backup de eso + `credentials.xml` permite restaurar el secret en otro Jenkins.

## Mejora opcional: rotación / retención de backups

El job actual genera un archivo nuevo cada 10 minutos, **sin rotación**. Después de 24 horas hay 144 archivos, después de un mes ~4300. En producción real conviene agregar:

```bash
# Retener solo los últimos 30 dumps
ssh natasha@ststor01 'ls -t /home/natasha/db_backups/db_*.sql | tail -n +31 | xargs -r rm -f'
```

O con `find`:

```bash
# Eliminar dumps más viejos de 7 días
ssh natasha@ststor01 "find /home/natasha/db_backups/ -name 'db_*.sql' -mtime +7 -delete"
```

Otra opción: comprimir el dump para reducir el storage:

```bash
ssh tony@stapp01 "MYSQL_PWD='$MYSQL_PASSWORD' mysqldump -u kodekloud_roy kodekloud_db01 | gzip" > "/tmp/$name.gz"
```

> Estas optimizaciones no están pedidas por el lab — son notas para producción real.

## Conexión con días anteriores

- **Día 18 (LAMP Stack)**: el MariaDB que corre en stapp01 es el mismo paquete configurado en aquel día. La integración con Apache + PHP que se vio ahí es lo que hace que `stapp01` sea un "app server" real.
- **Día 9 (Troubleshooting MariaDB)**: primera aparición de MariaDB. Los comandos `mysql -u ... -p` y la estructura de databases son los mismos.
- **Día 17 (PostgreSQL)**: comparación implícita — Postgres tiene `pg_dump`, MariaDB tiene `mysqldump`. La semántica es equivalente, las flags difieren.
- **Día 71 / 73**: el `sudo -u jenkins ssh-copy-id` se aplica de nuevo a stapp01 y ststor01.
- **Día 72 (Parameterized Builds)**: hoy **no se usan parámetros** porque el job es auto-disparado por cron. La fecha se calcula en runtime con `$(date +%F)`, no se pasa como parámetro.
- **Día 73 (Scheduled Jobs)**: misma estructura cron + scp. La novedad es la **inyección de credenciales** vía Credentials Manager — el patrón anterior tenía passwords hardcoded o en SSH keys del filesystem.
- **Día 62 / 66 (Secrets en K8s)**: el modelo conceptual es paralelo. Los Secrets de K8s viven en etcd y se inyectan al Pod como env var via `secretKeyRef`. Las credentials de Jenkins viven en `credentials.xml` cifrado y se inyectan al job como env var via Credential binding. La sintaxis difiere pero la idea es idéntica.

## Reflexión: el rol del Credentials Manager en CI/CD

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- El paso de "password hardcoded" a "credential binding": ¿es algo que conocías de antes o nuevo? ¿En qué herramientas previas (Ansible Vault, sops, secrets de GitHub Actions, AWS Secrets Manager) lo manejabas?
- El detalle `MYSQL_PWD` vs `-p<password>` para evitar exposición en `ps -ef`: ¿lo conocías? Hay un patrón general acá — "no usar argv para secrets". ¿Lo aplicarías a otras herramientas (curl con `--data` vs `--data-binary @file`, etc.)?
- El warning de Jenkins sobre `H/10` vs `*/10` y el lab pidiendo exactamente `*/10`: ¿caso donde "obedecer al lab" es subóptimo, o queda claro por qué pueden pedirlo (consistencia en docs, simplicidad pedagógica)?
- Comparación con K8s Secrets (Día 62/66): ambos modelos cifran los secrets at rest y los inyectan como env vars. ¿El de Jenkins se siente "más maduro" por ser mainstream desde hace décadas, o más arcaico?
- El bug clásico de `mysql` vs `mysqldump` y de `-U` vs `-u`: ¿se identifica al primer error o suele tomar dos o tres iteraciones? ¿Qué técnica funciona para internalizar las flags exactas de herramientas que se usan poco?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `mysqldump: unknown option '-U'`                                        | Flag con mayúscula                                                                                   | Usar `-u` minúscula                                                                               |
| `mysqldump: Got error: 1049: Unknown database 'asdfgdsd'`               | `-p asdfgdsd` con espacio interpreta el password como database                                       | `-pasdfgdsd` sin espacio, o `MYSQL_PWD` env var                                                   |
| Archivo `/tmp/db_*.sql` tiene 0 bytes                                   | `mysql` (cliente interactivo) en lugar de `mysqldump`; o `mysqldump` falló y la redirección creó archivo vacío | Verificar el comando exacto; `mysqldump` retorna SQL en stdout, `mysql` espera input             |
| Password aparece en logs                                                | Se hardcodeó en el script en lugar de usar Credential binding                                        | Mover al Credentials Manager y bindear como env var                                               |
| Credential binding configurado pero `$MYSQL_PASSWORD` vacío en el shell | El ID de la credential en el binding no coincide con el ID real                                      | Verificar en Manage Jenkins → Credentials que el ID sea exactamente `mysql-roy-password`         |
| `scp: dest open: No such file or directory`                             | `/home/natasha/db_backups/` no existe en ststor01                                                    | `ssh natasha@ststor01 mkdir -p /home/natasha/db_backups` antes del scp                            |
| Job pasa pero el archivo no aparece en ststor01                         | El path source del scp es incorrecto (ej. `/home/tmp/` en lugar de `/tmp/`)                          | Verificar el path con `ssh tony@stapp01 ls -la /tmp/db_*.sql`                                    |
| El cron no respeta `*/10`                                                | Jenkins lo reemplazó por `H/10` automáticamente al guardar                                           | Verificar el textarea del Schedule después de Save — debería decir literalmente `*/10 * * * *`   |
| `Access denied for user 'kodekloud_roy'@'localhost'`                    | Password incorrecto en la credential, o el user no tiene grants para hacer dump                      | `mysql -u kodekloud_roy -p<pwd>` manual para verificar; `SHOW GRANTS FOR 'kodekloud_roy'@'%'`     |
| `Got packet bigger than 'max_allowed_packet' bytes`                     | Una tabla individual excede el buffer default                                                        | Agregar `--max_allowed_packet=512M` al `mysqldump`                                                |
| El dump generado tiene caracteres raros / encoding                      | Mismatch de charset entre el server y la herramienta cliente                                         | Agregar `--default-character-set=utf8mb4`                                                         |
| Build pasa la primera vez pero falla las siguientes con timeout         | Conexiones SSH huérfanas se acumulan en el server                                                    | Configurar `ServerAliveInterval` en `~jenkins/.ssh/config` para keepalive                         |

## Recursos

- [Jenkins Credentials (oficial)](https://www.jenkins.io/doc/book/using/using-credentials/)
- [Credentials Binding plugin](https://plugins.jenkins.io/credentials-binding/)
- [`mysqldump` reference (MariaDB)](https://mariadb.com/kb/en/mysqldump/)
- [End-of-life of `-p<password>` recommendation (security)](https://dev.mysql.com/doc/refman/8.0/en/password-security-user.html)
- [`MYSQL_PWD` environment variable](https://dev.mysql.com/doc/refman/8.0/en/environment-variables.html)
- [Best practices for DB backups](https://mariadb.com/kb/en/backup-and-restore-overview/)
