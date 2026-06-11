# Día 73 - Jenkins Scheduled Jobs (cron trigger + scp multi-server)

## Problema / Desafío

El equipo de Nautilus está armando un sistema de logging centralizado, pero mientras tanto necesita recolectar logs de Apache del App Server 2 hacia el Storage Server **cada 3 minutos**. La solución: un job de Jenkins con trigger cron que hace `scp` de los logs.

Requirements:

1. Login a la UI de Jenkins como `admin` / `Adm!n321`
2. Crear job **`copy-logs`** (Freestyle)
3. Configurar **Build periodically** con cron `*/3 * * * *` (cada 3 minutos)
4. El job debe copiar `access_log` y `error_log` de **App Server 2** (`stapp02`) hacia `/usr/src/finance` del **Storage Server** (`ststor01`)
5. Buildear al menos una vez para validar

Servers involucrados:

| Server         | Rol                                       | Usuario        | OS                          | Path relevante               |
| -------------- | ----------------------------------------- | -------------- | --------------------------- | ---------------------------- |
| `jenkins`      | Server de Jenkins (controller)            | `jenkins`      | Ubuntu                      | `/var/lib/jenkins/.ssh/`     |
| `stapp02`      | App Server 2 (Apache con logs)            | `steve`        | RHEL/CentOS Stream 9        | `/var/log/httpd/access_log`, `error_log` |
| `ststor01`     | Storage Server (destino de los logs)      | `natasha`      | RHEL/CentOS Stream 9        | `/usr/src/finance/`          |

## Conceptos clave

### Tipos de triggers en Jenkins

Cuando se marca **Triggers** en la config del job, hay varias opciones:

| Trigger                              | Cuándo dispara                                                              |
| ------------------------------------ | --------------------------------------------------------------------------- |
| **Build periodically**               | Schedule tipo cron — disparos en momentos definidos                          |
| **Build after other projects are built** | Cuando termina otro job (encadena pipelines)                                |
| **Poll SCM**                         | Cron schedule pero solo dispara si el SCM tiene cambios desde el último poll |
| **GitHub hook trigger**              | Webhook de GitHub — push, PR, etc. (requiere plugin GitHub)                  |
| **Trigger builds remotely**          | Token HTTP — `curl -X POST .../build?token=<token>`                          |
| **Generic Webhook Trigger** (plugin) | Webhooks de cualquier sistema (GitLab, Bitbucket, Jira, custom)              |

Para este lab se usa **Build periodically** con expresión cron `*/3 * * * *`.

### Sintaxis de cron en Jenkins

Cinco campos separados por espacios:

```
MINUTE  HOUR  DAY-OF-MONTH  MONTH  DAY-OF-WEEK
*/3       *         *         *         *
```

| Campo         | Rango     | Ejemplos                                                   |
| ------------- | --------- | ---------------------------------------------------------- |
| MINUTE        | 0-59      | `0` (en punto), `*/15` (cada 15 min), `0,30` (en :00 y :30) |
| HOUR          | 0-23      | `0` (medianoche), `*/2` (cada 2 horas), `9-17` (horario laboral) |
| DAY-OF-MONTH  | 1-31      | `1` (primer día), `*/7` (cada 7 días)                       |
| MONTH         | 1-12      | `*` (todos), `1,7` (enero y julio)                          |
| DAY-OF-WEEK   | 0-7       | `0` o `7` (domingo), `1-5` (lunes-viernes)                  |

Ejemplos comunes:

| Expresión              | Cuándo dispara                                          |
| ---------------------- | ------------------------------------------------------- |
| `*/3 * * * *`          | Cada 3 minutos                                          |
| `0 * * * *`            | En punto cada hora                                      |
| `0 0 * * *`            | Medianoche cada día                                     |
| `0 8 * * 1-5`          | 8 AM de lunes a viernes                                 |
| `0 0 1 * *`            | Medianoche del 1er día de cada mes                      |
| `15 22 * * 5`          | 22:15 cada viernes                                      |

### El warning `H` vs `*` — Spread load evenly

Al usar `*/3 * * * *`, Jenkins muestra:

```
⚠️ Spread load evenly by using 'H/3 * * * *' rather than '*/3 * * * *'
```

El símbolo **`H`** es una extensión de Jenkins al cron tradicional. Funciona como un **hash determinístico** del nombre del job mapeado dentro del rango:

| Expresión                | Comportamiento                                                                  |
| ------------------------ | ------------------------------------------------------------------------------- |
| `*/3 * * * *`            | Dispara en :00, :03, :06, :09, ... — **todos los jobs al mismo segundo**       |
| `H/3 * * * *`            | Dispara cada 3 min pero con offset basado en `hash(job-name)`                  |
| `H * * * *`              | Una vez por hora, minuto basado en hash (no fijo en :00)                       |
| `H H * * *`              | Una vez al día, hora y minuto basados en hash                                  |

Para un Jenkins con muchos jobs, `H` evita **picos sincronizados** que sobrecargan el master. Para un solo job es irrelevante.

### Pre-vista del próximo run

Cuando se guarda el cron, Jenkins muestra:

```
Would last have run at Wednesday, June 3, 2026, 4:39:00 PM Greenwich Mean Time;
would next run at Wednesday, June 3, 2026, 4:42:00 PM Greenwich Mean Time.
```

Útil para validar visualmente que la expresión cron tiene sentido antes de dejarla activa. La zona horaria es **GMT por default** — para cambiarla, agregar `TZ=America/Buenos_Aires` (u otra) en la primera línea del cron.

### El comando `scp` con dos remotos — qué pasa internamente

```bash
scp steve@stapp02:/var/log/httpd/error_log natasha@ststor01:/usr/src/finance
```

A primera vista parece "stapp02 envía el archivo directamente a ststor01". **No es así**. El `scp` local (en el server jenkins) hace de **intermediario**:

```
Server jenkins (corre el scp)
    │
    ├── 1. SSH a stapp02 (con la key del user jenkins)
    │   ├── Abre el archivo /var/log/httpd/error_log
    │   └── Lee el contenido a un buffer local en jenkins
    │
    └── 2. SSH a ststor01 (con la misma key del user jenkins)
        ├── Crea el archivo /usr/src/finance/error_log
        └── Escribe el buffer
```

Por eso el lab requiere **SSH a los dos servers**, no solo al origen. Sin acceso a ststor01, el segundo paso falla con `Permission denied`.

### `scp -3` — la flag que importa

En OpenSSH **8.7+** (incluyendo Ubuntu 22.04+ y CentOS Stream 9), `scp` usa esta modalidad **por default**. En versiones más viejas, había que pasar `-3` explícitamente:

```bash
scp -3 steve@stapp02:/path natasha@ststor01:/dest
```

Sin `-3` en versiones viejas, scp intentaba que **stapp02 hiciera SSH directo a ststor01** — lo cual requería keys entre los dos remotos, no solo desde el cliente.

### Apache log paths por distro

| Distro              | Path del access log                | Path del error log               |
| ------------------- | ---------------------------------- | -------------------------------- |
| **RHEL/CentOS/Rocky** (este lab) | `/var/log/httpd/access_log`        | `/var/log/httpd/error_log`       |
| **Debian/Ubuntu**   | `/var/log/apache2/access.log`      | `/var/log/apache2/error.log`     |
| **Alpine**          | `/var/log/apache2/access.log`      | `/var/log/apache2/error.log`     |

Diferencias a anclar:

- RHEL usa `httpd` como nombre del servicio y del directorio, Debian usa `apache2`
- RHEL **no agrega `.log`** al nombre del archivo, Debian sí
- El bug del lab (`access_log.log`) fue por mezclar las dos convenciones

## Pasos

1. Login como `admin` / `Adm!n321`
2. SSH al server `jenkins` desde el jump host
3. Distribuir la SSH key del user `jenkins` a **ambos** servers:
   ```bash
   sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub steve@stapp02
   sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub natasha@ststor01
   ```
4. Validar conectividad como user jenkins:
   ```bash
   sudo -u jenkins ssh steve@stapp02 hostname
   sudo -u jenkins ssh natasha@ststor01 hostname
   ```
5. En la UI: Dashboard → New Item → `copy-logs` → Freestyle → OK
6. En la config:
   - **Build Triggers** → marcar "Build periodically" → schedule `*/3 * * * *`
   - **Build Steps** → Add build step → Execute shell → comando con scp
7. Save
8. Build Now (manualmente, para no esperar el cron)
9. Verificar el Console Output → `Finished: SUCCESS`
10. Validar en el storage server que los archivos están copiados

## Comandos / Código

### Setup de SSH desde el server jenkins

```bash
# Conectarse al server jenkins (no al jump host)
ssh root@jenkins

# Distribuir la SSH key del user jenkins a stapp02
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub steve@stapp02
# (pide password de steve una vez)

# Distribuir la misma key a ststor01
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub natasha@ststor01
# (pide password de natasha una vez)
```

> Si la SSH key del user jenkins no existe todavía (lab nuevo), generarla primero:
>
> ```bash
> sudo -u jenkins ssh-keygen -t ed25519 -C "jenkins@ci" \
>   -f /var/lib/jenkins/.ssh/id_ed25519 -N ""
> ```

Validación:

```bash
sudo -u jenkins ssh -o StrictHostKeyChecking=no steve@stapp02 hostname
# stapp02.stratos.xfusioncorp.com

sudo -u jenkins ssh -o StrictHostKeyChecking=no natasha@ststor01 hostname
# ststor01.stratos.xfusioncorp.com
```

### Configuración del job (UI)

**1. General**: nombre `copy-logs`, tipo Freestyle.

**2. Build Triggers** → marcar **"Build periodically"**

Schedule:

```
*/3 * * * *
```

> Mensaje esperado de Jenkins después de guardar:
>
> ```
> ⚠️ Spread load evenly by using 'H/3 * * * *' rather than '*/3 * * * *'
> Would last have run at <fecha>; would next run at <fecha+3min>.
> ```

**3. Build Steps** → **Execute shell**:

```bash
echo "Inicio proceso de copiado de logs..."

echo "Copiando /var/log/httpd/error_log en /usr/src/finance"
scp steve@stapp02:/var/log/httpd/error_log natasha@ststor01:/usr/src/finance

echo "Copiando /var/log/httpd/access_log en /usr/src/finance"
scp steve@stapp02:/var/log/httpd/access_log natasha@ststor01:/usr/src/finance
```

**4. Save**.

### Disparar build manual (para no esperar 3 min)

Navegación: `Job copy-logs → Build Now`.

### Log esperado del Console Output

```
Started by user admin
Running as SYSTEM
Building in workspace /var/lib/jenkins/workspace/copy-logs
[copy-logs] $ /bin/sh -xe /tmp/jenkins15938332175594278538.sh
+ echo Inicio proceso de copiado de logs...
Inicio proceso de copiado de logs...
+ echo Copiando /var/log/httpd/error_log  en /usr/src/finance
Copiando /var/log/httpd/error_log  en /usr/src/finance
+ scp steve@stapp02:/var/log/httpd/error_log natasha@ststor01:/usr/src/finance
+ echo Copiando /var/log/httpd/access_log  en /usr/src/finance
Copiando /var/log/httpd/access_log  en /usr/src/finance
+ scp steve@stapp02:/var/log/httpd/access_log natasha@ststor01:/usr/src/finance
Finished: SUCCESS
```

### Build disparado por el timer (después del manual)

Cuando el cron dispara automáticamente, el log empieza con:

```
Started by timer
Running as SYSTEM
...
```

> `Started by timer` (en lugar de `Started by user admin`) es la huella visible del trigger automático.

### Verificación en el storage server

```bash
ssh natasha@ststor01 ls -la /usr/src/finance/
```

Output esperado:

```
total ...
-rw-r--r-- 1 natasha natasha   ... error_log
-rw-r--r-- 1 natasha natasha   ... access_log
```

## Autopsia de los bugs encontrados

### Bug 1 — Falta SSH a ststor01

Los primeros builds del lab solo tenían SSH configurado a `stapp02`. El `scp` falló con:

```
Permission denied (publickey).
scp: Connection closed
Build step 'Execute shell' marked build as failure
Finished: FAILURE
```

**Causa**: `scp` con dos remotos necesita SSH a **ambos**.

**Fix**: agregar `ssh-copy-id natasha@ststor01`.

### Bug 2 — Typo en el path del access_log

El primer intento del script tenía:

```bash
scp steve@stapp02:/var/log/httpd/access_log.log natasha@ststor01:/usr/src/finance
```

Log del build:

```
+ scp steve@stapp02:/var/log/httpd/access_log.log natasha@ststor01:/usr/src/finance
scp: /var/log/httpd/access_log.log: No such file or directory
Build step 'Execute shell' marked build as failure
Finished: FAILURE
```

**Causa**: confusión con la convención Apache de Debian/Ubuntu (`access.log`) vs RHEL/CentOS (`access_log` sin extensión).

**Fix**: cambiar `access_log.log` → `access_log` en el script.

### Bug 3 — `dest open: No such file or directory` al especificar filename en destino

Después del fix del Bug 2, al intentar refinar el script para nombrar el archivo destino explícitamente:

```bash
scp steve@stapp02:/var/log/httpd/error_log natasha@ststor01:/usr/src/finance/error_log
```

El build falló con:

```
+ scp steve@stapp02:/var/log/httpd/error_log natasha@ststor01:/usr/src/finance/error_log
scp: dest open "/usr/src/finance/error_log": No such file or directory
Build step 'Execute shell' marked build as failure
```

**Causa**: contraintuitivo pero crítico — `/usr/src/finance` **no existía como directorio** en `ststor01`. Cuando el primer build (con destino `:/usr/src/finance` sin barra final) corrió, `scp` aplicó esta regla:

| Caso de destino                                  | Comportamiento de scp                                            |
| ------------------------------------------------ | ---------------------------------------------------------------- |
| `/usr/src/finance/` **existe como directorio**   | Crea `/usr/src/finance/<basename-origen>` (lo esperado)          |
| `/usr/src/finance` **no existe**                 | Trata `finance` como **nombre de archivo**, lo crea en `/usr/src/` |
| `/usr/src/finance` **existe como archivo**       | **Sobrescribe** ese archivo con el contenido del origen          |

El primer build "pasó" con `Finished: SUCCESS` pero el resultado real fue:

```
/usr/src/finance   ← archivo regular (no directorio), con el contenido del último scp
```

Como los dos scp del primer script apuntaban al mismo destino, el archivo `finance` quedó con el contenido del segundo (`access_log`). El `error_log` se "perdió" — fue sobrescrito silenciosamente.

Al cambiar el destino a `:/usr/src/finance/error_log`, `scp` **exige** que `/usr/src/finance/` exista como directorio. No existe (es un archivo huérfano del build anterior), entonces falla.

**Fix**:

```bash
# Limpiar el archivo huérfano
ssh natasha@ststor01 'sudo rm -f /usr/src/finance'

# Crear el directorio (idempotente)
ssh natasha@ststor01 'sudo mkdir -p /usr/src/finance && sudo chown natasha:natasha /usr/src/finance'
```

Después de esto, los dos scp funcionan correctamente.

### Versión robusta del script (idempotente)

Para que el job no dependa del estado previo del filesystem y funcione siempre, conviene agregar el `mkdir -p` al inicio:

```bash
echo "Inicio proceso de copiado de logs..."

# Asegurar que el directorio destino existe (idempotente)
ssh natasha@ststor01 'sudo mkdir -p /usr/src/finance && sudo chown natasha:natasha /usr/src/finance'

echo "Copiando /var/log/httpd/error_log en /usr/src/finance"
scp steve@stapp02:/var/log/httpd/error_log natasha@ststor01:/usr/src/finance/error_log

echo "Copiando /var/log/httpd/access_log en /usr/src/finance"
scp steve@stapp02:/var/log/httpd/access_log natasha@ststor01:/usr/src/finance/access_log
```

> **Buena práctica anclada**: en `scp` (y en `cp`/`mv` también), siempre **terminar el destino con `/`** cuando se quiere asegurar que se trata como directorio. `scp src dest:/usr/src/finance/` falla limpio si el directorio no existe, en vez de crear un archivo silenciosamente. Es más predecible y debuggeable.

## Anatomía del filesystem

```
# En el server jenkins
/var/lib/jenkins/.ssh/
├── id_ed25519              (clave privada, chmod 600)
├── id_ed25519.pub          (clave pública)
└── known_hosts             (host keys de stapp02, ststor01)

# En stapp02
~steve/.ssh/authorized_keys (contiene la pubkey de jenkins@ci)

# En ststor01
~natasha/.ssh/authorized_keys (contiene la pubkey de jenkins@ci)
/usr/src/finance/
├── access_log              (copiado por el job)
└── error_log               (copiado por el job)

# En el server jenkins, después de N builds
/var/lib/jenkins/jobs/copy-logs/builds/
├── 1/  (manual o falla)
├── 2/
├── 3/  (success — primer build correcto)
├── 4/  (success — timer)
├── 5/  (success — timer)
└── ... (uno cada 3 minutos)
```

## Alternativas a `scp` (referencia)

| Comando                       | Pros                                                                  | Cons                                                                  |
| ----------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------------- |
| **scp** (este lab)            | Simple, viene con OpenSSH                                              | Cada llamada abre/cierra una conexión SSH (lento si son muchos archivos) |
| **rsync** (`rsync -avz`)      | Solo copia los bytes que cambiaron (incremental)                       | Sintaxis menos intuitiva para multi-host                              |
| **`ssh + tar + ssh`**         | Eficiente para muchos archivos pequeños                                | Más verboso, no idiomático                                            |
| **`ansible` (`copy` module)** | Idempotente, audita los cambios, usa SSH también                       | Requiere instalar Ansible                                             |

Para este caso (2 archivos chicos cada 3 min) `scp` es lo correcto. Si los logs fueran de 1GB+ o si se quisiera copiar incrementalmente, `rsync -avz --partial --append-verify` sería mejor.

### Versión con rsync (para referencia)

```bash
rsync -avz steve@stapp02:/var/log/httpd/error_log /tmp/error_log
rsync -avz /tmp/error_log natasha@ststor01:/usr/src/finance/
rsync -avz steve@stapp02:/var/log/httpd/access_log /tmp/access_log
rsync -avz /tmp/access_log natasha@ststor01:/usr/src/finance/
```

> rsync no soporta dos remotos en una sola llamada como sí lo hace `scp -3`. Hay que hacer un viaje a un buffer local y otro al destino.

## Conexión con días anteriores

- **Día 6 (Cron Job con Cronie)**: introdujo la sintaxis cron del SO. Hoy aparece la **versión Jenkins del cron** — misma sintaxis pero ejecutada por Jenkins, no por crond. La extensión `H` es específica de Jenkins.
- **Día 19/20 (Apache + PHP-FPM)**: los logs de Apache que el lab de hoy copia son los mismos de aquel setup. El path `/var/log/httpd/access_log` es la convención RHEL.
- **Día 71 (Jenkins SSH setup)**: el `sudo -u jenkins ssh-copy-id` que se aplicó al stapp02 hoy es **idéntico** al del Día 71 con ststor01. Hoy se aplicó a **dos servers** porque el flujo lo requiere.
- **Día 72 (Parameterized Builds)**: el job de hoy **no tiene parámetros** porque es completamente automático (cron-driven, sin input). Es el otro extremo del espectro de jobs Jenkins.
- **Día 7 (SSH sin password)**: la base conceptual de todo el lab. Hoy se aplica el patrón pero distribuyéndolo a 2 servers desde el user de un servicio.

## Reflexión: cron jobs en Jenkins vs cron del sistema

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- Cron en Jenkins vs cron del sistema (`crontab`): ¿cuándo conviene uno sobre el otro? El cron del SO es más simple pero no tiene UI ni historial visible. El de Jenkins agrega overhead pero da logs centralizados, retry visible, alertas si falla.
- El warning de Jenkins sobre `H/3` vs `*/3`: ¿algo que conocías o nuevo? ¿En tu trabajo previo viste casos de spike sincronizado al usar `*/N`?
- El `scp` con dos remotos como intermediario: ¿anticipabas ese comportamiento o esperabas que stapp02 hablara directo con ststor01?
- La diferencia de paths Apache RHEL vs Debian (`/var/log/httpd/access_log` sin `.log` vs `/var/log/apache2/access.log` con `.log`): ¿es algo internalizado o de los detalles que siempre toman por sorpresa?
- En producción, para "centralised logging management" como el que el lab menciona, la solución más común es **agents que pushean a un sistema central** (Filebeat → Elasticsearch, Vector → Loki, Fluentd → Splunk). El enfoque scp+cron de hoy es la "versión casera" — útil para entender el problema, no para escalar. ¿Cómo se compara con experiencias previas en log shipping?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `Permission denied (publickey)` al hacer scp                            | Falta SSH a uno de los dos servers (stapp02 o ststor01)                                              | `ssh-copy-id` a **ambos** desde el user jenkins                                                  |
| `scp: /path: No such file or directory`                                 | Typo en el path del archivo origen                                                                   | Verificar el path real en el server origen: `ssh steve@stapp02 ls -la /var/log/httpd/`           |
| El cron no dispara en el horario esperado                                | Zona horaria del Jenkins ≠ zona local del operador                                                   | Jenkins muestra "next run" en GMT por default. Para usar otra TZ, agregar `TZ=America/Buenos_Aires` al inicio del schedule |
| Warning persistente sobre `H/3` aunque la expresión esté correcta       | Comportamiento normal — Jenkins recomienda pero no obliga                                            | Cambiar `*/3` a `H/3` si hay muchos jobs cron en el mismo Jenkins                                |
| El build manual funciona pero el cron no dispara                        | El cron se calcula desde "creación del job", puede tardar hasta N minutos en el primer trigger      | Esperar el ciclo completo del cron. Verificar con `kubectl describe...` no aplica acá; mirar `/var/log/jenkins/jenkins.log` |
| `Started by timer` ausente en builds nuevos                              | El job fue disparado manualmente o por otro trigger, no por el cron                                  | Mirar la columna "Started by" en la lista de builds para distinguir manual vs automático          |
| `scp` lento o tira timeout                                               | Conexión SSH lenta, o el archivo es muy grande                                                       | Considerar `rsync --partial` para resumir; aumentar el timeout del scp con `-o ConnectTimeout=30` |
| Archivos copiados pero con permisos incorrectos en ststor01             | `scp` preserva los permisos del archivo origen, no aplica un umask del destino                       | Agregar `-p` (preserva) o post-procesar con `chmod` desde el script del job                       |
| `scp: dest open "/path/file": No such file or directory`                | El **directorio padre del destino no existe**, o existe como archivo (no directorio)                 | `ssh dest 'sudo mkdir -p /path && sudo chown user:group /path'` antes del scp                     |
| `scp src dest:/path` sin barra final crea un archivo en lugar de copiar al directorio | Si `/path` no existe, scp lo trata como nombre de archivo (no directorio)                            | Siempre terminar el destino con `/` cuando se espera un directorio: `dest:/path/`                 |
| `Host key verification failed` la primera vez                            | known_hosts del user jenkins no tiene la host key del server destino                                 | Conectarse una vez con `sudo -u jenkins ssh -o StrictHostKeyChecking=no <user>@<server>`         |
| El job dispara pero el log muestra `Build step 'Execute shell' marked build as failure` sin más info | Algún comando del script salió con exit code != 0 (set -e abortó)                                    | Leer todo el log buscando el último comando + el primer mensaje de error                          |
| Logs del Apache no actualizados después del scp                         | Los archivos se copian, pero la app stapp02 sigue logueando — el snapshot es del momento del scp     | Esperar al próximo ciclo del cron, o disparar manualmente para tener un snapshot fresco           |

## Recursos

- [Build Triggers (oficial)](https://www.jenkins.io/doc/book/pipeline/syntax/#triggers)
- [Cron syntax in Jenkins (oficial)](https://www.jenkins.io/doc/book/pipeline/syntax/#cron-syntax)
- [The `H` symbol explained](https://www.jenkins.io/blog/2018/09/05/jenkins-cron-tutorial/)
- [`scp` man page](https://man.openbsd.org/scp) — la flag `-3` y la modalidad moderna
- [OpenSSH 8.7 release notes (scp default change)](https://www.openssh.com/txt/release-8.7)
- [Apache log files in RHEL vs Debian](https://httpd.apache.org/docs/2.4/logs.html)
