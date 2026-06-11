# Día 80 - Jenkins Chained Builds (upstream → downstream con "trigger only if stable")

## Problema / Desafío

El equipo DevOps quiere automatizar **dos pasos secuenciales** del deploy:

1. Hacer pull del repo `web` en `/var/www/html` de stapp01 (deploy)
2. **Si y solo si el deploy fue exitoso**, reiniciar Apache (restart)

La solución pedida: dos jobs separados encadenados — un **upstream** que hace el pull y un **downstream** que reinicia el servicio, disparado solo si el primero quedó verde.

Requirements:

1. Login a Jenkins como `admin` / `Adm!n321`
2. Crear job **`devops-app-deployment`** — Freestyle, hace `git pull origin master` en `/var/www/html`
3. Crear job **`manage-services`** — Freestyle, ejecuta `sudo systemctl restart httpd`
4. Configurar `devops-app-deployment` como **upstream** de `manage-services` con condición **"trigger only if build is stable"**
5. Validar que un build del upstream dispara automáticamente el downstream
6. El LB (`http://stlb01:8091`) debe servir el contenido del repo

Stack del lab:

| Componente              | Detalle                                                    |
| ----------------------- | ---------------------------------------------------------- |
| **Gitea**               | Repo `sarah/web` con branch `master`                        |
| **stapp01**             | App Server 1 — Apache en `:8080`, `/var/www/html` = working tree del repo |
| **Jenkins controller** | Donde se crean los 2 jobs encadenados                       |
| **stlb01:8091**         | LB (haproxy) — frontea Apache                               |

## Conceptos clave

### Chained Builds — el patrón fundamental

Un **build encadenado** es una secuencia de dos o más jobs Jenkins donde el output de uno dispara al siguiente. La terminología:

| Rol            | Significado                                                                        |
| -------------- | ---------------------------------------------------------------------------------- |
| **Upstream**   | Job que dispara a otro. En el lab: `devops-app-deployment`                          |
| **Downstream** | Job que es disparado por otro. En el lab: `manage-services`                         |

Visualización en la UI:

```
[devops-app-deployment]  ────►  [manage-services]
   upstream                       downstream
   "deploy"                       "restart httpd"
   Status: SUCCESS                Trigger: "only if upstream is stable"
```

### Cómo se configura — "Build other projects"

En el job upstream, sección **Post-build Actions**:

1. Click **"Add post-build action"** → **"Build other projects"**
2. Llenar:
   - **Projects to build**: `manage-services` (nombre exacto del downstream)
   - Elegir una de las **tres opciones de trigger**:
     - **Trigger only if build is stable** ← lo que pide el lab
     - **Trigger even if the build is unstable**
     - **Trigger even if the build fails**

### Build Status en Jenkins — qué significa "stable"

Jenkins marca cada build con uno de cinco estados:

| Status        | Color      | Significado                                                                |
| ------------- | ---------- | -------------------------------------------------------------------------- |
| **SUCCESS**   | 🟢 Verde   | Todos los pasos terminaron con exit 0, sin warnings de post-actions       |
| **UNSTABLE**  | 🟡 Amarillo | Pasos exitosos pero un post-action marcó warnings (típico: tests flaky)  |
| **FAILURE**   | 🔴 Rojo    | Algún paso terminó con exit ≠ 0                                            |
| **ABORTED**   | ⚪ Gris    | Build cancelado manualmente o por timeout                                  |
| **NOT_BUILT** | ⚪ Gris    | El job no se ejecutó (ej. dependencia upstream falló)                      |

Las tres opciones del trigger downstream:

| Opción del trigger                          | Statuses upstream que disparan downstream | Cuándo usar                          |
| ------------------------------------------- | ----------------------------------------- | ------------------------------------ |
| **Only if build is stable** (el lab)        | Solo SUCCESS                              | Deploy → restart (queremos garantía) |
| **Even if the build is unstable**           | SUCCESS o UNSTABLE                        | Tests flaky aceptables               |
| **Even if the build fails**                 | Cualquier resultado, incluido FAILURE     | Notification / rollback jobs         |

> Para deploy → restart Apache, "Only if stable" es lo correcto. Si el deploy tuvo UNSTABLE (warnings), reiniciar Apache podría dejar el sitio sirviendo contenido inconsistente.

### Chained Builds vs Pipeline — la diferencia conceptual

Estos dos patrones resuelven el mismo problema con paradigmas distintos:

| Aspecto                       | Chained Freestyle (este lab)                      | Pipeline (Día 77-78)                                 |
| ----------------------------- | ------------------------------------------------- | ---------------------------------------------------- |
| Número de jobs                | **N jobs separados** encadenados                  | **Un solo job** con N stages                          |
| Configuración de la secuencia | Post-build Actions de cada job                    | Bloques `stages { stage('A') { } stage('B') { } }`  |
| Visualización del flow        | Diagrama upstream/downstream                       | Pipeline visualization con stages                    |
| Compartir workspace           | **No** — cada job tiene su propio workspace        | Sí — el workspace persiste entre stages             |
| Condicionales entre etapas    | "Trigger only if stable" (binario)                | `when { expression { ... } }` (cualquier condición)  |
| Errores y retry               | Solo a nivel de job entero                         | Granular por stage con `retry(3) { ... }`            |
| Versionable en git            | Difícil (XML separado por job)                    | Trivial (Jenkinsfile único en el repo)               |

> **Tendencia industria**: Pipeline para nuevos workflows. Chained builds existen para compatibilidad con setups viejos o para mantener jobs muy independientes (ej. notification jobs que pueden ser triggered por muchos upstreams distintos).

### Pipeline equivalente del lab (referencia)

Si se hiciera el mismo workflow con Pipeline:

```groovy
pipeline {
    agent { label 'stapp01' }
    stages {
        stage('Deploy') {
            steps {
                sh '''
                    sudo git config --global --add safe.directory /var/www/html
                    sudo git -C /var/www/html pull origin master
                '''
            }
        }
        stage('Restart httpd') {
            when {
                expression { currentBuild.currentResult == 'SUCCESS' }
            }
            steps {
                sh 'sudo systemctl restart httpd'
            }
        }
    }
}
```

Ventajas Pipeline vs chained:
- Un solo job, un solo `config.xml`
- El workspace persiste entre stages (no relevante acá, pero útil en general)
- Versionable como Jenkinsfile en el repo

Para este lab, el requerimiento es **explícitamente Freestyle chained** — la solución Pipeline es solo referencia.

### El error `detected dubious ownership` — fix preventivo

Cuando el job hace `sudo git pull` en `/var/www/html`, puede aparecer:

```
fatal: detected dubious ownership in repository at '/var/www/html'
To add an exception for this directory, call:
        git config --global --add safe.directory /var/www/html
```

Causa: Git **2.35.2+** introdujo una protección (CVE-2022-24765) que aborta cuando el directorio `.git/` es owned por **user X** pero el comando `git` corre como **user Y**. Caso típico:

- `/var/www/html/.git/` es owned por `root:root` (porque el clone original fue con sudo)
- El job ejecuta `sudo git pull` que efectivamente corre como root → matchea, **sin error**

Pero también puede aparecer al revés:

- `/var/www/html/.git/` es owned por `sarah:sarah`
- El job corre como tony y hace `sudo git pull` (efectivamente como root) → mismatch, **error**

Fix preventivo, ejecutar **una vez** al inicio del script del job:

```bash
sudo git config --global --add safe.directory /var/www/html
```

Esto agrega `/var/www/html` a la lista de directorios confiables del `.gitconfig` global de root. Solo necesario una vez por server.

### Por qué los dos jobs deben correr en el agent `stapp01`

Una lección del Día 79: si el job no se restringe al agent específico, Jenkins puede schedulearlo en el **built-in node** (el controller). Eso significa que el script intenta hacer `git pull /var/www/html` y `systemctl restart httpd` **en el server jenkins**, no en stapp01 — donde no existen esos directorios ni el servicio.

**Fix**: en **ambos** jobs, marcar "Restrict where this project can be run" con label `stapp01`. Sin esto, los builds funcionan a veces (cuando Jenkins schedula en stapp01 por suerte) y fallan otras (cuando schedula en el built-in node). Es **non-deterministic** y aparece como flaky.

## Pasos

1. Login Jenkins como admin
2. Verificar que el agent `App Server 1` (label `stapp01`) está online
3. Verificar que sarah/tony tiene NOPASSWD para los comandos del script (del Día 79)
4. Crear job **`devops-app-deployment`** (Freestyle):
   - Restrict a label `stapp01`
   - Build step: `sudo git -C /var/www/html pull origin master`
   - Post-build Action: "Build other projects" → `manage-services` → Only if stable
5. Crear job **`manage-services`** (Freestyle):
   - Restrict a label `stapp01`
   - Build step: `sudo systemctl restart httpd`
   - **No** post-build action (es el último de la cadena)
6. Disparar `devops-app-deployment` → Build Now
7. Validar que `manage-services` se dispara automáticamente al finalizar

## Comandos / Código

### 1. Setup previo (si no estaba del Día 79)

```bash
ssh tony@stapp01

# Sudoers para que sarah/tony pueda hacer sudo sin password
sudo tee /etc/sudoers.d/sarah <<'EOF'
sarah ALL=(ALL) NOPASSWD: /usr/bin/git, /usr/bin/systemctl restart httpd, /usr/bin/systemctl reload httpd
EOF
sudo chmod 440 /etc/sudoers.d/sarah
sudo visudo -c

# Fix preventivo del dubious ownership
sudo git config --global --add safe.directory /var/www/html
```

### 2. Job upstream — `devops-app-deployment`

Navegación: **Dashboard → New Item → `devops-app-deployment` → Freestyle project → OK**

**Restrict where this project can be run**: ✅
- Label Expression: `stapp01`

**Build Steps** → **Execute shell**:

```bash
# Fix preventivo si no se aplicó antes (idempotente)
sudo git config --global --add safe.directory /var/www/html

# Deploy: pull del master
sudo git -C /var/www/html pull origin master
```

**Post-build Actions** → **Add post-build action** → **Build other projects**:

| Campo                                       | Valor              |
| ------------------------------------------- | ------------------ |
| Projects to build                           | `manage-services`  |
| Trigger only if build is stable             | ✅ (default)        |

Click **Save**.

### 3. Job downstream — `manage-services`

Navegación: **Dashboard → New Item → `manage-services` → Freestyle project → OK**

**Restrict where this project can be run**: ✅
- Label Expression: `stapp01`

**Build Steps** → **Execute shell**:

```bash
sudo systemctl restart httpd
```

> **Sin Post-build Actions** — este es el último job de la cadena. No tiene downstream propio.

Click **Save**.

### 4. Verificar la relación upstream/downstream en la UI

En la página del job upstream:

```
devops-app-deployment
  └── Downstream Projects:
        └── manage-services
```

En la página del job downstream:

```
manage-services
  └── Upstream Projects:
        └── devops-app-deployment
```

Jenkins detecta la relación automáticamente al guardar el upstream con la post-build action.

### 5. Disparar el flow

`devops-app-deployment` → **Build Now**.

#### Log esperado del upstream

```
Started by user admin
Running as SYSTEM
Building remotely on App Server 1 (stapp01) in workspace /home/sarah/jenkins_agent/workspace/devops-app-deployment
[devops-app-deployment] $ /bin/sh -xe /tmp/jenkins<id>.sh
+ sudo git config --global --add safe.directory /var/www/html
+ sudo git -C /var/www/html pull origin master
From http://gitea:3000/sarah/web
 * branch            master     -> FETCH_HEAD
Already up to date.
Triggering a new build of manage-services
Finished: SUCCESS
```

> Línea clave: **`Triggering a new build of manage-services`** — confirma que el post-build action disparó el downstream.

#### Log esperado del downstream (disparado automáticamente)

```
Started by upstream project "devops-app-deployment" build number 1
originally caused by:
 Started by user admin
Building remotely on App Server 1 (stapp01) in workspace /home/sarah/jenkins_agent/workspace/manage-services
[manage-services] $ /bin/sh -xe /tmp/jenkins<id>.sh
+ sudo systemctl restart httpd
Finished: SUCCESS
```

Detalles a notar:

| Línea                                                                  | Significado                                                              |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `Started by upstream project "devops-app-deployment" build number 1`   | Confirma que fue disparado por el upstream (no manual)                   |
| `originally caused by: Started by user admin`                          | Traza completa: admin → devops-app-deployment → manage-services         |
| `Building remotely on App Server 1`                                    | Ejecutó en el agent correcto (no en el built-in node)                    |
| `+ sudo systemctl restart httpd`                                       | Comando del script con `set -x`                                          |
| `Finished: SUCCESS`                                                    | Restart de httpd exitoso                                                 |

### 6. Validación funcional

```bash
# Tras un build exitoso del chain
curl http://stlb01:8091/
# (debería devolver el contenido del index.html del repo)

# Verificar que httpd está corriendo después del restart
ssh tony@stapp01 sudo systemctl status httpd
# active (running)
```

## Probar que "Only if stable" funciona — test del FAILURE

Para confirmar que el downstream NO se dispara si el upstream falla:

1. Editar el job upstream → Build Steps → cambiar el comando por algo que falle:
   ```bash
   sudo git -C /path/que/no/existe pull origin master
   ```
2. Save → Build Now

Log esperado:

```
+ sudo git -C /path/que/no/existe pull origin master
fatal: Cannot change to '/path/que/no/existe': No such file or directory
Build step 'Execute shell' marked build as failure
Finished: FAILURE
```

Verificar que `manage-services` **NO** tiene un build nuevo en su historial. La cadena se cortó porque el upstream falló y el trigger es "only if stable".

Después de probar, restaurar el comando original.

## Anatomía de la cadena — qué se ejecuta dónde y como quién

```
[admin clicks "Build Now" en devops-app-deployment]
                      │
                      ▼
[Jenkins controller schedula el build en agent App Server 1]
                      │
                      ▼
[Agent en stapp01 ejecuta el script]
                      │
        [user agente: sarah]
                      │
                      ▼
   $ sudo git config --global --add safe.directory /var/www/html
   $ sudo git -C /var/www/html pull origin master
   (corre como root vía sudo NOPASSWD)
                      │
              git pull termina con exit 0
                      │
                      ▼
[Build status: SUCCESS]
                      │
                      ▼
[Post-build Action evalúa: ¿upstream SUCCESS? Sí]
                      │
                      ▼
[Jenkins controller schedula manage-services]
                      │
                      ▼
[Agent en stapp01 ejecuta el script de manage-services]
                      │
                      ▼
   $ sudo systemctl restart httpd
   (corre como root vía sudo NOPASSWD)
                      │
                      ▼
[Build status: SUCCESS — cadena completa]
                      │
                      ▼
[Apache reiniciado sirviendo /var/www/html actualizado]
                      │
                      ▼
[LB stlb01:8091 → Apache stapp01:8080 → contenido nuevo]
```

## Patrón "chained" en otros sistemas CI/CD

| Sistema                | Cómo se hace el chain                                                                  |
| ---------------------- | -------------------------------------------------------------------------------------- |
| **Jenkins Freestyle** (este lab) | Post-build Action "Build other projects" + "Only if stable"                  |
| **Jenkins Pipeline**   | `build job: 'X', wait: true, propagate: false` o stages con `when`                     |
| **GitHub Actions**     | `needs: [previous-job]` en el YAML del workflow                                        |
| **GitLab CI**          | `stages:` ordenados; jobs en stage N esperan a stage N-1                                |
| **Argo Workflows / Tekton** | DAG declarativo en YAML — dependencias explícitas entre tasks                    |
| **Airflow / Prefect**  | Operadores con `>>` o `set_downstream()`                                                |

Todos resuelven la misma pregunta: **"cuándo correr el siguiente paso"** y **"qué hacer si falla algún paso intermedio"**.

## Conexión con días anteriores

- **Día 79 (Deployment Job)**: el mismo `git pull` en `/var/www/html`, pero hoy se separa del `systemctl restart` en dos jobs. La lección "todos los jobs deben correr en el agent stapp01" se aplica también acá.
- **Día 77-78 (Pipeline)**: el equivalente moderno del chained build es **dos stages en un Pipeline**. Para comparar las dos formas, ver la sección "Pipeline equivalente" arriba.
- **Día 75 (Slave Nodes)**: el agent `App Server 1` configurado entonces sigue siendo donde corren los dos jobs.
- **Día 73 (Scheduled Jobs)**: introdujo Post-build Actions implícitamente (no se usó). Hoy aparece la categoría completa de "Build other projects".
- **Día 18 (LAMP Stack)**: el `systemctl restart httpd` del downstream apunta al mismo Apache que se configuró en aquel día.
- **Día 21-34 (Git workflow)**: `git pull origin master` sigue siendo el comando base. Lo único que cambia es **dónde se ejecuta** (agent en stapp01) y **con qué identidad** (sudo → root).

## Reflexión: chained builds vs pipelines vs DAGs modernos

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- Chained builds (Freestyle) vs Pipeline con stages: ¿cuál se siente más natural? El primero distribuye lógica en varios jobs (más modular pero más fragmentado); el segundo lo concentra (más legible pero menos reusable).
- El concepto de "Only if stable": ¿binario suficiente o se necesita lógica más fina (ej. "only if specific tests passed")? En Pipeline `when` permite cualquier expresión Groovy.
- `safe.directory` como fix preventivo: ¿algo conocido o nuevo? El patrón "Git protege contra hooks maliciosos" — ¿le ves utilidad real o protección excesiva?
- Comparación con GitHub Actions / GitLab CI donde el chain es declarativo en YAML: ¿más predecible o más rígido?
- El error de "el job corre en el built-in node por default" (lección del Día 79): ¿lo internalizaste o sigue siendo trampa? ¿Cuál es tu reflejo para evitarlo?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `fatal: detected dubious ownership in repository at '/var/www/html'`    | Git 2.35.2+ rechaza repos donde owner del `.git/` no matchea el user que ejecuta                     | `sudo git config --global --add safe.directory /var/www/html` (una vez, idempotente)              |
| `manage-services` no se dispara aunque `devops-app-deployment` pasó    | Post-build Action mal configurada (typo en el nombre del project, o "Only if stable" estricto)       | Verificar en `devops-app-deployment` → Configure → Post-build Actions                             |
| El downstream se dispara aunque el upstream falló                       | Trigger configurado como "Even if the build fails" en lugar de "Only if stable"                      | Configure el upstream → cambiar a "Trigger only if build is stable"                              |
| Build manual del upstream funciona, pero auto-trigger del downstream no | Filtro del trigger requiere SUCCESS, pero el upstream quedó UNSTABLE                                 | Investigar por qué el upstream queda UNSTABLE — típicamente un post-build de tests con warnings   |
| El build corre en el built-in node en lugar de stapp01                  | Falta "Restrict where this project can be run" o el label no matchea                                 | Cada job → Configure → marcar "Restrict where..." con label `stapp01`                            |
| `sudo: a password is required` en el log                                | sudoers no tiene NOPASSWD para los comandos                                                          | Configurar `/etc/sudoers.d/sarah` con NOPASSWD para `git`, `systemctl restart httpd`             |
| El upstream pasa pero el sitio sigue mostrando contenido viejo          | El restart no se disparó (downstream no corrió) o Apache cachea                                      | Verificar en la UI que `manage-services` corrió. Si sí, hard refresh del browser                  |
| `Already up to date.` y el sitio no cambia                               | No había commits nuevos para deployar — el job pasa pero no aplica nada                              | Hacer commit + push primero, después correr el job                                                |
| El primer build del upstream dispara dos veces el downstream            | Está configurado tanto Post-build "Build other projects" como Build Triggers "Build after other..."  | Quitar uno de los dos — el patrón típico es solo Post-build Action en el upstream                |
| Downstream no aparece en "Upstream Projects" del lab                    | Falta hacer el Save del upstream después de configurar la post-build action                          | Save → verificar que la sección "Downstream Projects" aparece                                     |
| El restart de httpd genera error 500 momentáneo                          | `restart` mata conexiones activas durante ~100ms                                                      | Cambiar `restart` a `reload` — Apache acepta config nueva sin matar requests en curso             |

## Recursos

- [Build other projects (Post-build Action)](https://www.jenkins.io/doc/book/using/working-with-projects/#post-build-actions)
- [Upstream/Downstream jobs](https://www.jenkins.io/doc/book/pipeline/jenkinsfile/#chained-build-pipelines)
- [Build statuses in Jenkins](https://www.jenkins.io/doc/book/using/working-with-projects/#build-result)
- [Git `safe.directory` (CVE-2022-24765)](https://git-scm.com/docs/git-config#Documentation/git-config.txt-safedirectory)
- [Pipeline `build` step](https://www.jenkins.io/doc/pipeline/steps/pipeline-build-step/) — el equivalente moderno
- [`when` directive en Declarative Pipeline](https://www.jenkins.io/doc/book/pipeline/syntax/#when)
- [Apache reload vs restart](https://httpd.apache.org/docs/2.4/stopping.html)
