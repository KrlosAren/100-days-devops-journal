# Día 79 - Jenkins Deployment Job (Freestyle + Poll SCM + sudo NOPASSWD + cp deploy)

## Problema / Desafío

El equipo de desarrollo quiere **deploy automático**: cuando alguien hace push al branch `master` del repo `sarah/web`, Jenkins debe detectarlo, hacer checkout del código, y desplegar el contenido en `/var/www/html` de stapp01 (Apache document root). Sin intervención manual.

Requirements:

1. Login a Jenkins como `admin` / `Adm!n321`
2. Asegurar que httpd corre en stapp01 (puerto 8080)
3. Crear job **`nautilus-app-deployment`** (Freestyle — no Pipeline)
4. Configurar polling del repo `sarah/web` — al detectar push a `master`, disparar el build
5. El job debe:
   - Hacer git checkout del repo
   - Cambiar ownership de `/var/www/html` a `sarah`
   - Copiar **todo el contenido del repo** (no solo `index.html`) a `/var/www/html/`
   - Reiniciar httpd
6. SSH como sarah, editar `index.html` con "Welcome to the xFusionCorp Industries", commit + push a master
7. Validar que el LB (`https://<lab-id>:8091/`) muestra el nuevo contenido tras 1-2 minutos

Stack del lab:

| Componente              | Detalle                                                                |
| ----------------------- | ---------------------------------------------------------------------- |
| **Gitea**               | Repo `sarah/web` con branch `master`                                   |
| **stapp01**             | App Server 1 — Apache en `:8080`, user developer `sarah`               |
| **Jenkins controller** | Donde se crea el job                                                    |
| **stlb01:8091**         | LB (haproxy) — frontea Apache de los app servers                       |

## Conceptos clave

### Poll SCM — polling-based trigger

Hasta el Día 73 los triggers fueron de dos tipos: **manual** (Build Now) o **cron** (Build periodically — corre incondicionalmente al horario). Hoy aparece el tercero: **Poll SCM**.

| Trigger             | Comportamiento                                                                                  |
| ------------------- | ----------------------------------------------------------------------------------------------- |
| **Build periodically** (Día 73) | Corre el job **siempre** en el horario indicado, haya o no cambios               |
| **Poll SCM** (este lab)         | Corre **una query al SCM** en el horario indicado. Solo dispara el job si hay cambios |

Sintaxis: misma del cron clásico.

```
H/2 * * * *      # poll cada ~2 minutos (con H — spread load)
*/1 * * * *      # poll cada 1 minuto (sin spread)
* * * * *        # equivalente a */1 — cada minuto (lo usado en el lab)
```

Internamente, Poll SCM hace:

```
[cron schedule fires]
  ↓
git ls-remote <url>      ← le pregunta al SCM por el SHA del último commit
  ↓
SHA comparado contra el del último build exitoso
  ↓
si difieren → trigger build
si iguales  → log "no changes" y volver al sleep
```

### Poll SCM vs Webhooks — el trade-off real

Poll SCM es la **versión casera** de un webhook. Cómo se compara:

| Aspecto                          | Poll SCM (este lab)                                       | Webhook (producción típica)                              |
| -------------------------------- | --------------------------------------------------------- | -------------------------------------------------------- |
| Quién inicia                     | Jenkins → SCM                                              | SCM → Jenkins                                            |
| Setup en el SCM                  | Ninguno                                                   | Configurar webhook URL en el repo                        |
| Latencia                         | 0 a N minutos (depende del intervalo)                     | <1 segundo                                               |
| Carga                            | Polling constante (sea o no haya cambios)                 | Cero hasta que haya un push                              |
| Requisitos de red                | Jenkins → SCM outbound                                    | SCM → Jenkins inbound (Jenkins reachable desde internet) |
| Funciona detrás de NAT estricto | ✅                                                         | ❌ (a menos que el SCM y Jenkins estén en la misma red)   |

Para este lab Poll SCM es lo correcto (KodeKloud no expone Jenkins inbound). Para producción real con Gitea/GitHub, **webhooks** son la opción estándar.

### `NOPASSWD` en sudoers — qué hace y por qué se necesita

El script del job tiene tres comandos que requieren privilegios root:

```bash
sudo chown -R sarah:sarah /var/www/html
sudo cp -rf ${WORKSPACE}/* /var/www/html/
sudo systemctl restart httpd
```

El user `sarah` necesita poder ejecutar estos sin que el `sudo` pida password (porque el job corre en background, no hay shell interactivo para responder al prompt). La línea agregada a sudoers:

```
sarah ALL=(ALL) NOPASSWD: ALL
```

Decodificación:

| Parte                  | Significado                                                              |
| ---------------------- | ------------------------------------------------------------------------ |
| `sarah`                | User al que aplica la regla                                              |
| `ALL=(ALL)`            | Desde cualquier host, puede actuar como cualquier user                   |
| `NOPASSWD:`            | Sin pedir password                                                       |
| `ALL`                  | Cualquier comando                                                        |

### Hardening del sudoers — alternativas a `NOPASSWD: ALL`

`NOPASSWD: ALL` es **conveniente pero permisivo**: si la cuenta de sarah se compromete, el atacante tiene root sin restricciones. Hay tres alternativas, ordenadas de mejor a peor relación seguridad/simplicidad:

#### Opción A (recomendada) — Eliminar la necesidad de sudo para `cp` + sudoers solo para `systemctl`

La causa raíz de necesitar `NOPASSWD: ALL` es que `/var/www/html` es owned por `root:root`. Si el ownership se cambia **una sola vez** (manualmente, fuera del job), el `cp` deja de necesitar sudo. Solo queda `systemctl restart/reload httpd` que sí requiere root.

**Setup inicial** (una sola vez, como tony admin):

```bash
ssh tony@stapp01
sudo chown -R sarah:sarah /var/www/html
sudo chmod -R 755 /var/www/html

# Sudoers limitado a httpd
sudo tee /etc/sudoers.d/sarah <<'EOF'
sarah ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart httpd, /usr/bin/systemctl reload httpd
EOF
sudo chmod 440 /etc/sudoers.d/sarah
sudo visudo -c   # validar sintaxis
```

**Script del job** (sin sudo en cp ni chown):

```bash
cp -rf ${WORKSPACE}/* /var/www/html/
sudo systemctl reload httpd
```

> Cambiar `restart` por `reload` — Apache acepta el reload sin matar conexiones activas, menos disruptivo.

**Trade-off**: superficie de ataque mínima razonable (sarah solo puede reload Apache con sudo). Simple de mantener.

#### Opción B (engañosa) — Lista de comandos exactos en sudoers

Si por alguna razón no se puede cambiar el ownership, restringir sudoers a los comandos específicos:

```
sarah ALL=(ALL) NOPASSWD: /usr/bin/chown -R sarah\:sarah /var/www/html, \
                          /usr/bin/cp -rf /home/sarah/jenkins_agent/workspace/nautilus-app-deployment/* /var/www/html/, \
                          /usr/bin/systemctl restart httpd, \
                          /usr/bin/systemctl reload httpd
```

**Trampa de sudoers wildcards**: en el archivo de sudoers, `*` **funciona como wildcard** pero **no es shell glob**. Significa "cualquier secuencia de caracteres incluido `/`", lo cual es **demasiado permisivo**:

```bash
# El * en sudoers matchea CUALQUIER path, incluido path traversal:
sudo cp -rf /home/sarah/jenkins_agent/workspace/nautilus-app-deployment/../../../../etc/passwd /var/www/html/
# Esto es autorizado por la regla — bug de seguridad clásico
```

Esta opción **parece más segura** pero el wildcard la vuelve casi tan permisiva como `NOPASSWD: ALL`. **Evitar wildcards en paths de sudoers**.

#### Opción C — Script wrapper con sudo a un solo binario

Crear un script `/usr/local/bin/deploy-webapp.sh` owned por root, y permitir solo ese script:

```bash
# Crear el script como tony (admin)
sudo tee /usr/local/bin/deploy-webapp.sh <<'EOF'
#!/bin/bash
set -euo pipefail

WORKSPACE="/home/sarah/jenkins_agent/workspace/nautilus-app-deployment"

# Validación defensiva del path
if [[ ! -d "$WORKSPACE" ]]; then
    echo "ERROR: workspace no existe" >&2
    exit 1
fi

cp -rf "$WORKSPACE"/* /var/www/html/
chown -R sarah:sarah /var/www/html
systemctl reload httpd
EOF
sudo chmod 755 /usr/local/bin/deploy-webapp.sh
sudo chown root:root /usr/local/bin/deploy-webapp.sh

# Sudoers solo para ese script
sudo tee /etc/sudoers.d/sarah <<'EOF'
sarah ALL=(ALL) NOPASSWD: /usr/local/bin/deploy-webapp.sh
EOF
sudo chmod 440 /etc/sudoers.d/sarah
```

**Script del job** queda en una sola línea:

```bash
sudo /usr/local/bin/deploy-webapp.sh
```

**Pros**: sarah solo ejecuta **un script específico** con sudo. El script está **fuera del control de sarah** (owned `root:root`) — no puede modificarlo. Validaciones internas posibles.

**Cons**: requiere mantener el script aparte. Si cambia la lógica de deploy, hay que editar el script en el server, no el job en Jenkins.

#### Comparación final

| Opción                                                       | Seguridad        | Simplicidad        | Recomendación                              |
| ------------------------------------------------------------ | ---------------- | ------------------ | ------------------------------------------ |
| `NOPASSWD: ALL` (la del lab inicial)                         | ❌ Pésima         | ✅ Máxima           | Labs efímeros, demos                        |
| **A** — chown una vez + sudoers solo httpd                   | ✅ Buena          | ✅ Buena            | **Lo más práctico para este lab**           |
| **B** — Lista de comandos con wildcards                      | ⚠️ Falsa sensación de seguridad | ⚠️ Sintaxis traicionera | Evitar — wildcards mal usados              |
| **C** — Script wrapper                                       | ✅ Excelente      | ⚠️ Requiere setup  | Producción real                             |

**Recomendación**: para este lab, la **Opción A** es el sweet spot. Para producción real con stakes más altos, la **Opción C** con un script versionado en git + Ansible para distribuirlo.

#### Detalle anclado — `reload` vs `restart`

Una propiedad útil de `systemctl reload httpd` vs `restart`: `reload` envía `SIGHUP` a Apache, que **re-lee la config sin matar las conexiones activas**. Para un deploy de archivos estáticos, `reload` ni siquiera es estrictamente necesario — Apache lee `index.html` en cada request, no en startup. **El restart/reload solo es necesario cuando cambia la config de Apache** (`httpd.conf`, `.htaccess`, módulos). Para este lab puro de archivos estáticos, omitir el restart es válido y el sitio se actualiza igual. El lab lo pide explícitamente, pero vale como detalle para producción.

### Por qué cambiar el ownership de `/var/www/html`

Antes del primer build, `/var/www/html` puede ser owned por `root:root` (default del paquete httpd). El `cp` del job lo hace con `sudo`, así que el cp en sí no falla — los archivos copiados quedan como `root:root`.

El `sudo chown -R sarah:sarah /var/www/html` antes del cp tiene dos propósitos:

1. **Idempotencia**: si en un build futuro el script cambiara (ej. usar `rsync` sin sudo), los archivos ya están preparados para escritura por sarah
2. **Que el .git/ del workspace no sea owned por root**: si por error se copiara con `cp -rf ${WORKSPACE}/.` (dotglob), el `.git/` quedaría como root y futuras operaciones de git fallarían

> Para este caso específico del lab, el cambio de ownership es **defensivo** — el script funciona aunque no lo haga, pero deja el filesystem en estado consistente.

### `cp -rf ${WORKSPACE}/*` — qué se copia exactamente

El glob `${WORKSPACE}/*` en bash:

| Patrón                | Incluye dotfiles? | Resultado típico                            |
| --------------------- | ----------------- | ------------------------------------------- |
| `${WORKSPACE}/*`      | **No**            | `index.html`, `assets/`, otros archivos non-dot |
| `${WORKSPACE}/.*`     | Solo dotfiles     | `.git/`, `.gitignore`                         |
| `${WORKSPACE}/.` (con punto) | Sí           | Todo, incluido `.git/` — **no es lo que se quiere** |

> `${WORKSPACE}/*` es **lo correcto** para este lab porque excluye automáticamente `.git/`. Si por error se usara con dotglob (`shopt -s dotglob` antes), el `.git/` quedaría en `/var/www/html/` y Apache podría exponer archivos como `.git/config` (security risk).

### El flow completo del lab — del push al cambio visible

```
1. sarah edita /home/sarah/web/index.html
                    ↓
2. git add + git commit + git push origin master
                    ↓
3. (espera hasta 60s)
                    ↓
4. Jenkins Poll SCM corre — git ls-remote detecta nuevo SHA
                    ↓
5. Jenkins dispara build → checkout en /home/sarah/jenkins_agent/workspace/nautilus-app-deployment/
                    ↓
6. Script del job:
   a. sudo chown -R sarah:sarah /var/www/html
   b. sudo cp -rf ${WORKSPACE}/* /var/www/html/   ← copia los archivos del repo
   c. sudo systemctl restart httpd                ← reinicia Apache para asegurar carga limpia
                    ↓
7. Apache sirve el nuevo /var/www/html/index.html
                    ↓
8. LB stlb01:8091 → Apache stapp01:8080 → archivo nuevo
                    ↓
9. curl al LB devuelve "Welcome to the xFusionCorp Industries"
```

## Pasos

1. Login Jenkins como admin
2. SSH a stapp01 como tony (admin)
3. Configurar sudoers para sarah: `NOPASSWD: ALL`
4. Reutilizar el agent `App Server 1` (label `stapp01`) configurado en Día 77-78
   - Si el agent murió, re-arrancarlo como sarah
5. (Si no están instalados) Instalar plugins **Git** y **Pipeline**
6. Verificar que httpd está corriendo en `:8080`
7. Crear job **`nautilus-app-deployment`** (Freestyle)
8. Configurar:
   - **Restrict where this project can be run**: label `stapp01`
   - **Source Code Management**: Git → URL del repo + branch `master`
   - **Build Triggers**: Poll SCM → `* * * * *`
   - **Build Steps**: Execute shell → script con chown + cp + restart
9. Save → Build Now (primera vez para validar)
10. SSH como sarah → editar index.html → push → esperar 60s → validar via LB

## Comandos / Código

### 1. Verificar que httpd está corriendo en stapp01

```bash
ssh tony@stapp01

sudo systemctl status httpd
# active (running) — confirma que está up

sudo systemctl list-units | grep -i http
# httpd.service  loaded active running  The Apache HTTP Server

# Verificar el puerto
cat /etc/httpd/conf/httpd.conf | grep -i listen
# Listen 8080
```

Validar localmente:

```bash
curl localhost:8080
# Welcome to KodeKloud   ← contenido inicial del repo (no del lab)
```

### 2. Configurar sudoers para sarah (como tony, que es admin)

```bash
ssh tony@stapp01

# Crear archivo de sudoers para sarah (no editar /etc/sudoers directo)
echo "sarah ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/sarah
sudo chmod 440 /etc/sudoers.d/sarah

# Validar sintaxis
sudo visudo -c
# /etc/sudoers: parsed OK
# /etc/sudoers.d/sarah: parsed OK
```

Validar que sarah puede usar sudo sin password:

```bash
sudo su - sarah
sudo whoami
# root  ← (sin pedir password)
```

> **Convención importante**: nunca editar `/etc/sudoers` directamente. Siempre crear archivos drop-in en `/etc/sudoers.d/`. Esto evita romper sudoers entero si hay un typo (el archivo principal incluye automáticamente los de `/etc/sudoers.d/`).

### 3. Setup del agent (resumen del Día 77-78)

Si el agent no existe o está offline:

```bash
# Como tony en stapp01
sudo su - sarah

# Si no existe el dir
mkdir -p /home/sarah/jenkins_agent
cd /home/sarah/jenkins_agent

# Descargar y arrancar agent (secret del UI de Jenkins)
curl -sO http://jenkins:8080/jnlpJars/agent.jar
nohup java -jar agent.jar \
  -url http://jenkins:8080/ \
  -secret <SECRET_DEL_UI> \
  -name "App Server 1" \
  -webSocket \
  -workDir "/home/sarah/jenkins_agent" \
  > ~/agent.log 2>&1 &
```

### 4. Crear el job `nautilus-app-deployment`

Navegación: **Dashboard → New Item → `nautilus-app-deployment` → Freestyle project → OK**

### 5. Configuración del job

**Restrict where this project can be run**: ✅
- Label Expression: `stapp01`

**Source Code Management** → **Git**:

| Campo              | Valor                                                          |
| ------------------ | -------------------------------------------------------------- |
| Repository URL     | `http://gitea:3000/sarah/web` *(o la URL del proxy del lab)*    |
| Credentials        | (Gitea credentials con user `sarah`)                            |
| Branch to build    | `*/master`                                                      |

**Build Triggers** → **Poll SCM**:
- Schedule: `* * * * *` (cada minuto)

**Build Steps** → **Execute shell**:

```bash
sudo chown -R sarah:sarah /var/www/html
sudo cp -rf ${WORKSPACE}/* /var/www/html/
sudo systemctl restart httpd
```

Click **Save**.

### 6. Primer build manual (validación)

`Job → Build Now`

Log esperado:

```
Started by user admin
Running as SYSTEM
Building remotely on App Server 1 (stapp01) in workspace /home/sarah/jenkins_agent/workspace/nautilus-app-deployment
The recommended git tool is: NONE
No credentials specified
Cloning the remote Git repository
Cloning repository https://3000-port-<lab-id>:3000/sarah/web
 > git init /home/sarah/jenkins_agent/workspace/nautilus-app-deployment # timeout=10
 > git fetch --tags --force --progress -- https://...sarah/web +refs/heads/*:refs/remotes/origin/* # timeout=10
 > git rev-parse refs/remotes/origin/master^{commit} # timeout=10
Checking out Revision 1f2bb805f72f24efb04b5a5bd32e0da2d6f75f5d (refs/remotes/origin/master)
 > git checkout -f 1f2bb805f72f24efb04b5a5bd32e0da2d6f75f5d # timeout=10
Commit message: "Added index.html file"
First time build. Skipping changelog.
[nautilus-app-deployment] $ /bin/sh -xe /tmp/jenkins<id>.sh
+ sudo chown -R sarah:sarah /var/www/html
+ sudo cp -rf /home/sarah/jenkins_agent/workspace/nautilus-app-deployment/index.html /var/www/html/
+ sudo systemctl restart httpd
Finished: SUCCESS
```

Detalles a notar:

| Línea                                                                                              | Significado                                                              |
| -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `Building remotely on App Server 1`                                                                | Corre en el agent stapp01, no en el controller                            |
| `Cloning the remote Git repository`                                                                | Primera vez clona; siguientes builds hacen fetch incremental              |
| `git checkout -f 1f2bb805...`                                                                      | Detached HEAD apuntando al SHA exacto del último commit del master       |
| `+ sudo cp -rf /home/sarah/jenkins_agent/workspace/nautilus-app-deployment/index.html /var/www/html/` | El `*` se expandió a `index.html` porque era el único archivo del repo  |
| `Finished: SUCCESS`                                                                                | Exit code 0 — deploy completado                                          |

### 7. La parte clave del lab — editar como sarah y pushear

```bash
ssh sarah@stapp01
cd /home/sarah/web

# Estado actual del repo
git status
# On branch master
# nothing to commit, working tree clean

cat index.html
# Welcome to KodeKloud

# Actualizar el contenido
cat > index.html <<'EOF'
Welcome to the xFusionCorp Industries
EOF

# Commit
git add index.html
git commit -m "Update welcome message to xFusionCorp Industries"

# Push al remoto
git push origin master
```

Output esperado del push:

```
Counting objects: 3, done.
Delta compression using up to N threads
Compressing objects: 100% (2/2), done.
Writing objects: 100% (3/3), 320 bytes | 320.00 KiB/s, done.
Total 3 (delta 0), reused 0 (delta 0)
To http://gitea:3000/sarah/web.git
   1f2bb80..a5c3d12  master -> master
```

### 8. Esperar y validar el auto-deploy

Después del push:

1. **Esperar hasta 60 segundos** — Poll SCM corre cada minuto
2. En la UI de Jenkins: el job debería tener un build nuevo automáticamente
   - "Started by an SCM change" en el log (en vez de "Started by user admin")

```bash
# Mientras se espera, conviene monitorear:
ssh tony@stapp01
sudo journalctl -u jenkins -f
# (en otro shell)

# O directamente curl al LB
watch -n 2 curl -s https://8091-port-<lab-id>:8091/
```

Cuando el build automático termine, el output del curl debe cambiar a reflejar el commit nuevo. Resultado real del lab tras el push:

```bash
curl localhost:8080
# Welcome to KodeKloud - autodeploy

curl https://8091-port-<lab-id>:8091/
# Welcome to KodeKloud - autodeploy
```

> Los dos endpoints devuelven el mismo contenido — confirmación de que el LB rutea correctamente al Apache local y el deploy se aplicó.

> **Importante para validación del lab**: el contenido pedido por el lab es **exactamente** `Welcome to the xFusionCorp Industries`. Si el validador chequea string match exacto, hay que asegurar que el `index.html` tenga literalmente esa línea (no "Welcome to KodeKloud - autodeploy" u otros). Para asegurar:
>
> ```bash
> ssh sarah@stapp01
> cd /home/sarah/web
> cat > index.html <<'EOF'
> Welcome to the xFusionCorp Industries
> EOF
> git add index.html
> git commit -m "Set exact welcome message for lab validation"
> git push origin master
> # Esperar 60s
> curl localhost:8080
> # Welcome to the xFusionCorp Industries
> ```

### Log del build auto-disparado

```
Started by an SCM change
Building remotely on App Server 1 (stapp01) in workspace /home/sarah/jenkins_agent/workspace/nautilus-app-deployment
 > git fetch --tags --force --progress -- https://.../sarah/web +refs/heads/*:refs/remotes/origin/* # timeout=10
 > git rev-parse refs/remotes/origin/master^{commit} # timeout=10
Checking out Revision a5c3d12... (refs/remotes/origin/master)
 > git checkout -f a5c3d12... # timeout=10
Commit message: "Update welcome message to xFusionCorp Industries"
[nautilus-app-deployment] $ /bin/sh -xe /tmp/jenkins<id>.sh
+ sudo chown -R sarah:sarah /var/www/html
+ sudo cp -rf /home/sarah/jenkins_agent/workspace/nautilus-app-deployment/index.html /var/www/html/
+ sudo systemctl restart httpd
Finished: SUCCESS
```

Diferencias respecto al primer build manual:

| Línea                              | Manual (primer build)                  | Auto-disparado (después del push)         |
| ---------------------------------- | -------------------------------------- | ----------------------------------------- |
| `Started by`                       | `user admin`                           | `an SCM change`                           |
| Git operation                      | `Cloning` + `git init`                 | `git fetch --tags` (incremental)          |
| Commit message                     | `"Added index.html file"`              | `"Update welcome message to xFusionCorp Industries"` |
| Changelog                          | `First time build. Skipping changelog.` | Lista los commits desde el último build  |

## Sobre la pregunta `:8080` vs `:8091`

| Endpoint                                            | Qué es                                                                |
| --------------------------------------------------- | --------------------------------------------------------------------- |
| `curl localhost:8080` desde stapp01                | Apache **local** en stapp01 sirviendo `/var/www/html`                 |
| `https://8091-port-<lab-id>:8091/` (botón App)     | LB externo (haproxy en stlb01:8091) que rutea al `:8080` de stapp01   |

Los dos deberían devolver **el mismo contenido**. Si difieren, hay un problema de routing en el LB. El "botón App" usa el LB :8091 por convención del lab.

> Si el lab dice "verify on port 8080" pero el botón App va a :8091 — no es contradicción. El :8080 es el origen real (Apache); el :8091 es el frontend que se le presenta al usuario externo. El contenido es el mismo, solo que el :8091 pasa por más capas.

## Patrón "deploy via cp + restart" vs alternativas

El script del lab es el patrón más simple:

```bash
sudo cp -rf ${WORKSPACE}/* /var/www/html/
sudo systemctl restart httpd
```

Trade-offs vs otras estrategias:

| Estrategia                                  | Pros                                              | Cons                                                                |
| ------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------- |
| **`cp -rf` + restart** (este lab)            | Simple, sin dependencias extra                    | Restart de httpd = downtime (~100ms); cp no borra archivos eliminados |
| **`rsync -av --delete`**                    | Sincroniza exactamente: agrega, modifica, borra   | Restart sigue siendo necesario (a menos que httpd sea suficientemente reactivo) |
| **`git pull` directo en /var/www/html** (Día 77) | Sin workspace intermedio                          | El `.git/` queda en el document root (security risk)                |
| **Symlink swap** (blue/green)               | Zero downtime — `ln -sfn /var/releases/v2 /var/www/html` | Más complejo de setup; requiere lógica de versiones                  |
| **Container deploy** (Docker)               | Aislamiento completo, versionable                  | Requiere Docker runtime; cambio arquitectural mayor                 |

Para este lab, `cp -rf + restart` es lo correcto. Para producción real con tráfico, **rsync con --delete** sería el siguiente paso, y para algo serio, **blue/green con symlinks o containers**.

### Mejora opcional — `rsync` en lugar de `cp` para deploy más limpio

```bash
sudo chown -R sarah:sarah /var/www/html
sudo rsync -av --delete --exclude='.git' ${WORKSPACE}/ /var/www/html/
sudo systemctl reload httpd     # reload en lugar de restart — menos disruption
```

Diferencias:

- `rsync -av` preserva atributos + verbose
- `--delete` elimina archivos en destino que no están en source (deploy "espejo")
- `--exclude='.git'` defensivo, aunque el `*` del cp ya lo excluía
- `reload` en lugar de `restart` — Apache acepta el nuevo config sin matar conexiones activas

## Anatomía del filesystem durante el ciclo

```
# En stapp01

/home/sarah/web/                        ← Working copy local de sarah (donde edita)
├── .git/
├── index.html
└── (otros archivos)

/home/sarah/jenkins_agent/workspace/nautilus-app-deployment/   ← Workspace del job
├── .git/                                ← Clone hecho por el job (separado del de sarah)
├── index.html
└── (otros archivos)

/var/www/html/                          ← Document root de Apache (servido)
├── index.html                          ← Copia hecha por el cp del job
└── (otros archivos del repo)
```

Cada uno de los tres directorios es **independiente**:

| Directorio                              | Quién lo mantiene                                                          |
| --------------------------------------- | -------------------------------------------------------------------------- |
| `/home/sarah/web/`                      | sarah a mano — donde edita, commitea y pushea                              |
| `/home/sarah/jenkins_agent/workspace/...` | Jenkins via Git plugin — clone/fetch automático en cada build              |
| `/var/www/html/`                        | El script del job vía `cp` — copia desde el workspace                       |

## Conexión con días anteriores

- **Día 73 (Scheduled Jobs)**: cron `*/3 * * * *` para disparar incondicionalmente. Hoy aparece la variante condicional: **Poll SCM** con la misma sintaxis pero comportamiento distinto.
- **Día 77 (Deploy Pipeline)**: hacía `git pull` directo en `/var/www/html`. Hoy es más robusto — checkout en workspace + cp al destino (`.git/` queda fuera del document root).
- **Día 78 (Conditional Pipeline)**: parámetros para múltiples branches. Hoy no — el job solo escucha al master.
- **Día 71 (Package Installation)**: introdujo `sudo -u jenkins` para el agent. Hoy el agent ya corre como sarah (de Día 77), y se agrega `NOPASSWD` para que el job pueda hacer `sudo` sin prompt.
- **Día 18 (LAMP Stack)**: el Apache que escucha en `:8080` y sirve `/var/www/html` viene de aquel setup. Hoy se construye encima con un pipeline de deploy.
- **Día 22-25 (Git workflow)**: el `git add + commit + push` que hace sarah es el flow del Día 25. La diferencia: el push ahora **dispara un robot** (Jenkins) en lugar de ser solo un acto de versionado.

## Reflexión: Poll SCM vs Webhooks y el modelo pull vs push de CI/CD

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- Poll SCM (pull model) vs Webhook (push model): ¿cuál se siente más natural? Trade-off entre latencia y simplicidad de setup.
- El patrón `cp -rf + restart` para deploy: ¿simple y robusto, o anticuado? Las alternativas (rsync, symlink swap, containers) — ¿cuál usarías en producción?
- `NOPASSWD: ALL` vs lista restringida en sudoers: ¿conveniente o riesgo aceptado? ¿Caso de uso real donde lo restringirías?
- Tres copias del repo (sarah/web, workspace del agent, /var/www/html): ¿overhead aceptable o anti-pattern? Comparar con un push directo via git hook (Día 34).
- El comportamiento de `${WORKSPACE}/*` excluyendo dotfiles por default: ¿propiedad útil o accidente afortunado?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `curl localhost:8080` devuelve `Connection refused`                     | httpd no está corriendo                                                                              | `sudo systemctl start httpd && sudo systemctl enable httpd`                                       |
| `sudo: a password is required` en el log del job                        | sudoers no tiene `NOPASSWD` para sarah                                                               | `echo "sarah ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/sarah && sudo chmod 440 ...`     |
| El job no se dispara aunque se haya pusheado                            | (a) Poll SCM no detecta cambios — verificar el schedule; (b) Git plugin no puede acceder al repo     | "Polling Log" en el job muestra el último resultado del poll. Verificar credentials Git           |
| Auto-build dispara pero `cp` falla con `cp: cannot create regular file '/var/www/html/...': Permission denied` | El `chown` no se ejecutó antes o falló                                                               | Verificar la primera línea del script. Validar manualmente: `sudo ls -la /var/www/html`           |
| El LB muestra el contenido viejo aunque el job pasó                      | Caché del browser o del proxy de KodeKloud                                                            | Hard refresh (Cmd+Shift+R) o `curl` directo desde el server                                       |
| `git checkout -f` falla con conflictos                                  | El workspace tiene cambios locales no commiteados                                                    | Workspace de Jenkins es scratch — borrarlo: `Job → Workspace → Wipe Out Current Workspace`        |
| Push autenticado falla con `401 Unauthorized` desde sarah                | Las credenciales en el `git remote -v` no son válidas                                                | Verificar: `git remote -v` — el URL debe incluir `sarah:Sarah_pass123@gitea:3000/...`             |
| Build manual funciona pero el auto-build no                              | Poll SCM no está bien configurado (schedule vacío o syntax error)                                    | Manage Jenkins → System Log y filtrar por el nombre del job                                       |
| El `cp -rf ${WORKSPACE}/*` solo copia un archivo                         | El repo tiene un único archivo (`index.html`) — no es bug del script                                  | Agregar más archivos al repo, commit + push, verificar que el siguiente build copia todos          |
| Apache devuelve 403 después del cp                                       | Los archivos copiados tienen permisos incorrectos                                                    | `sudo chmod -R 755 /var/www/html` después del cp                                                  |
| El job está disparando dos veces por cada push                           | Poll SCM + webhook configurados a la vez                                                             | Elegir uno: o Poll SCM o webhook, no los dos                                                      |
| El restart de httpd corta conexiones activas                             | `systemctl restart` es disruptivo                                                                    | Usar `systemctl reload` en su lugar — Apache acepta el reload sin matar requests en curso         |

## Recursos

- [Poll SCM (oficial)](https://www.jenkins.io/doc/book/pipeline/syntax/#triggers)
- [Git Plugin — polling vs hooks](https://plugins.jenkins.io/git/)
- [Gitea Webhooks (alternativa a Poll SCM)](https://docs.gitea.io/en-us/webhooks/)
- [sudo NOPASSWD best practices](https://wiki.archlinux.org/title/Sudo#Disable_password_prompt_timeout)
- [rsync vs cp for deploy](https://download.samba.org/pub/rsync/rsync.1)
- [Apache reload vs restart](https://httpd.apache.org/docs/2.4/stopping.html)
- [`/etc/sudoers.d/` best practices](https://manpages.ubuntu.com/manpages/jammy/en/man5/sudoers.5.html)
