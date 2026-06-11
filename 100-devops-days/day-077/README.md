# Día 77 - Jenkins Deploy Pipeline (primer Declarative Pipeline + git pull deploy)

## Problema / Desafío

El equipo de desarrollo de xFusionCorp está construyendo un sitio estático que vive en el repositorio Gitea `sarah/web_app`. El repo ya está clonado en `/var/www/html` de `stapp01` (Apache document root). Hay que crear un **Pipeline de Jenkins** que automatice el deploy: cuando se ejecuta, sincroniza el filesystem con el último commit del repo.

Requirements:

1. Login a Jenkins como `admin` / `Adm!n321`
2. Login a Gitea como `sarah` / `Sarah_pass123` (user dueño del repo)
3. Agregar **`stapp01` como agent** con:
   - Label: `stapp01`
   - Remote root directory: `/home/sarah/jenkins_agent`
   - El agent debe correr como user **`sarah`** (no `tony`)
4. Crear pipeline job **`devops-webapp-job`** (Pipeline, **no Multibranch**):
   - Una sola stage llamada **`Deploy`** (case-sensitive)
   - La stage debe ejecutar `git pull` en `/var/www/html` para refrescar el contenido
5. Validar accediendo al LB del lab — debe servir el contenido del repo

Stack del lab:

| Componente             | Detalle                                                            |
| ---------------------- | ------------------------------------------------------------------ |
| **Gitea**              | Self-hosted git server con repo `sarah/web_app`                    |
| **stapp01**            | App Server 1, Apache en puerto 8080, document root `/var/www/html` |
| **Jenkins controller** | Donde se crea el pipeline                                          |
| **LB (KodeKloud proxy)** | URL `https://<lab-id>:8091` — reenvía al Apache de stapp01         |

## Conceptos clave

### Declarative Pipeline — qué cambia respecto a Freestyle

Hasta el Día 76 todos los jobs eran **Freestyle**: config solo en la UI, sin posibilidad de versionar el job en git. Hoy aparece **Pipeline**, que tiene dos sintaxis:

| Sintaxis              | Cuándo usar                                                                            |
| --------------------- | -------------------------------------------------------------------------------------- |
| **Declarative**       | Pipelines estructurados con bloques fijos. Default moderno — más legible y restrictivo. |
| **Scripted**          | Groovy puro — máxima flexibilidad pero más fácil de hacer ilegible.                     |

Este lab usa **Declarative**. La estructura básica:

```groovy
pipeline {
    agent { label 'stapp01' }       // dónde corre
    stages {
        stage('Deploy') {            // nombre de la etapa (case-sensitive)
            steps {
                sh '...'             // qué hace
            }
        }
    }
}
```

Bloques principales del Declarative Pipeline:

| Bloque         | Para qué                                                              |
| -------------- | --------------------------------------------------------------------- |
| `agent`        | En qué nodo/agent corre el pipeline (label, ID, o `any`/`none`)       |
| `stages`       | Contenedor de las etapas del pipeline                                 |
| `stage('X')`   | Una etapa con nombre — aparece como bloque visible en la UI            |
| `steps`        | Las acciones concretas dentro de la stage                              |
| `sh`           | Ejecutar comandos shell (Unix). Equivalente Windows: `bat`             |
| `environment`  | Definir env vars del pipeline                                          |
| `options`      | Configuración extra: timeout, retry, build discard                     |
| `post`         | Acciones después del pipeline: `always`, `success`, `failure`, `unstable` |
| `when`         | Ejecutar la stage solo si una condición se cumple                      |
| `parallel`     | Correr varias stages en paralelo                                       |

### Pipeline vs Freestyle — trade-off

| Aspecto                                  | Freestyle (Día 71-74)                              | Pipeline                                             |
| ---------------------------------------- | -------------------------------------------------- | ---------------------------------------------------- |
| Configuración                            | Solo UI (form-based)                               | Código Groovy en la UI o en un Jenkinsfile           |
| Versionado en git                        | Difícil (XML del job en `JENKINS_HOME`)            | Trivial — el Jenkinsfile vive en el repo              |
| Code review de cambios al pipeline       | No práctico                                        | Igual que código normal — vía PR                      |
| Visualización del flow                   | Lineal (build steps secuenciales)                  | Stages como bloques visuales con timing por stage    |
| Parallel execution                       | No nativo                                          | `parallel { ... }`                                   |
| Reusabilidad entre jobs                  | Copy-paste                                         | Shared libraries (groovy compartido entre pipelines) |
| Curva de aprendizaje                     | Baja                                               | Mayor (Groovy + idioms de Jenkins)                   |

> **Tendencia industria**: Freestyle está en mantenimiento. Pipeline es la dirección moderna. Para producción, casi siempre Pipeline.

### `agent { label '<x>' }` — targeting al nodo

Hasta ahora los Freestyle jobs targetearon agents via "Restrict where this project can be run". Pipeline lo hace via `agent`:

| Forma                              | Significado                                                                      |
| ---------------------------------- | -------------------------------------------------------------------------------- |
| `agent { label 'stapp01' }`        | Cualquier agent con el label `stapp01` (el de este lab)                          |
| `agent { label 'linux && stable' }` | Agent que tenga **ambos** labels                                                |
| `agent any`                        | Cualquier agent disponible                                                       |
| `agent none`                       | El pipeline no se ata a un agent — cada stage debe declarar el suyo              |
| `agent { node { label 'X' ... } }` | Forma extendida con opciones extra (customWorkspace, etc.)                       |

### El detalle clave del lab — el agent corre como user `sarah`

Este lab cambia el patrón establecido en el Día 75. En aquel lab los agents corrían como `tony`, `steve`, `banner` — los "users de SO" de cada server. Hoy el agent **debe correr como `sarah`** porque:

| Razón                                          | Detalle                                                                                  |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Los archivos de `/var/www/html` son de sarah   | `git clone` original fue hecho por sarah → `owner: sarah:sarah`                          |
| `git pull` debe poder escribir esos archivos   | Si el agent corre como otro user, `Permission denied`                                    |
| Las credenciales de git están en sarah         | El `git remote -v` muestra `http://sarah:Sarah_pass123@gitea:3000/...` — válidas solo para sarah |
| Apache lee `/var/www/html` con su user — diferente | Apache puede leer sin importar el owner; el pipeline necesita **escribir**            |

**Regla anclada**: cuando un pipeline modifica archivos en disco, el agent debe correr como **el user dueño de esos archivos**. Confundir esto es uno de los bugs más comunes en setups distribuidos.

### `nohup ... &` — agent en background sin systemd

El comando del Día 75 (`java -jar agent.jar ...`) corre en foreground y muere al cerrar el shell. Para este lab se usó:

```bash
nohup java -jar agent.jar \
  -url http://jenkins:8080/ \
  -secret $SECRET \
  -name "App Server 1" \
  -webSocket \
  -workDir "/home/sarah/jenkins_agent" \
  > ~/agent.log 2>&1 &
```

Decodificación:

| Parte                       | Función                                                                       |
| --------------------------- | ----------------------------------------------------------------------------- |
| `nohup`                     | Ignora SIGHUP — el proceso sobrevive al cierre del shell                      |
| `> ~/agent.log 2>&1`        | Redirige stdout y stderr al archivo `agent.log` (para debugging)              |
| `&`                         | Pone el proceso en background — el shell vuelve al prompt inmediatamente      |

**Sigue muriendo si el server reboota**. Para producción real, ver la sección "Agent como servicio systemd" del Día 75.

### Apache + LB en este lab

El flow del request del usuario al sitio:

```
Usuario → https://<lab-id>:8091          ← LB de KodeKloud (terminación HTTPS, proxy)
              │
              ▼
        stapp01 (haproxy)                ← LB interno escuchando en :8091
              │
              ▼
        stapp01:8080 (Apache httpd)      ← Apache sirviendo /var/www/html
              │
              ▼
        /var/www/html/index.html
```

El `netstat` que el user corrió mostró:
- `:8091` haproxy (LB interno del lab)
- `:8080` httpd (Apache)
- `:22` sshd

El pipeline solo necesita modificar `/var/www/html`. Apache + LB ya estaban configurados; el job no toca esa parte.

## Pasos

1. Login Jenkins como admin
2. Distribuir SSH key del user `jenkins` a `tony@stapp01` (login al server)
3. SSH a stapp01 como tony → `sudo su - sarah` (cambiar al user sarah)
4. Como sarah: instalar Java, descargar `agent.jar`, ejecutar con `nohup`
5. En Jenkins UI: Manage Jenkins → Nodes → New Node:
   - Name: `App Server 1`
   - Label: `stapp01`
   - Remote root directory: `/home/sarah/jenkins_agent`
   - Launch method: inbound
6. Copiar el secret del nodo recién creado
7. Volver al server y arrancar el agent con el secret correcto
8. Validar en la UI que el nodo está online
9. (Si no está instalado) Instalar plugin **Pipeline**
10. New Item → `devops-webapp-job` → tipo **Pipeline** (no Multibranch)
11. En la sección Pipeline, pegar el script Declarative
12. Save → Build Now
13. Validar en `https://<LB-URL>:8091` que el contenido se sirve correctamente

## Comandos / Código

### 1. Setup del agent como user sarah

Conectarse al server stapp01:

```bash
# Desde el jump host (en el server jenkins, generar y distribuir key como en días previos)
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub tony@stapp01

# Ahora desde el jump host, conectarse a stapp01
ssh tony@stapp01

# Switch al user sarah
sudo su - sarah
```

Instalar Java y crear el workdir:

```bash
# Como sarah en stapp01
sudo yum install -y java-17-openjdk
mkdir -p /home/sarah/jenkins_agent
cd /home/sarah/jenkins_agent

# Descargar agent.jar desde el controller
curl -sO http://jenkins:8080/jnlpJars/agent.jar
```

### 2. Crear el nodo desde la UI de Jenkins

Navegación: **Manage Jenkins → Nodes → + New Node**

| Campo                         | Valor                                            |
| ----------------------------- | ------------------------------------------------ |
| Node name                     | `App Server 1`                                   |
| Type                          | Permanent Agent                                  |
| Number of executors           | `1`                                              |
| Remote root directory         | `/home/sarah/jenkins_agent`                      |
| Labels                        | `stapp01`                                        |
| Launch method                 | Launch agent by connecting it to the controller  |

Save. Click sobre el nodo recién creado para ver el comando con el secret.

### 3. Arrancar el agent como sarah

```bash
# Como sarah en stapp01
export SECRET=36425a4ff9461fcd57338a2610f52a490f8a2c414a6a29f19e854aa24ec87fb6
# (copiar el secret real del UI del nodo)

nohup java -jar agent.jar \
  -url http://jenkins:8080/ \
  -secret $SECRET \
  -name "App Server 1" \
  -webSocket \
  -workDir "/home/sarah/jenkins_agent" \
  > ~/agent.log 2>&1 &
```

Verificar que el proceso quedó corriendo:

```bash
ps -ef | grep agent.jar
# sarah  12345  ...  java -jar agent.jar -url http://jenkins:8080/ ...

tail -20 ~/agent.log
# INFO: Connected
```

En la UI: el nodo `App Server 1` debe aparecer **online**.

### 4. Validar el repo en stapp01

```bash
# Como sarah
cd /var/www/html
git status
# On branch master
# Your branch is up to date with 'origin/master'.

git remote -v
# origin  http://sarah:Sarah_pass123@gitea:3000/sarah/web_app.git (fetch)
# origin  http://sarah:Sarah_pass123@gitea:3000/sarah/web_app.git (push)

ls -la
# total 20K
# drwxr-xr-x sarah sarah  ...  .
# drwxr-xr-x root  root   ...  ..
# -rw-r--r-- sarah sarah   35  index.html
# drwxr-xr-x sarah sarah     .git
```

> Los archivos son property de `sarah:sarah` — confirmación de que el agent debe correr como sarah para poder hacer pull.

### 5. Crear el pipeline job

Navegación: **Dashboard → New Item**

| Campo               | Valor                |
| ------------------- | -------------------- |
| Enter item name     | `devops-webapp-job`  |
| Item type           | **Pipeline**         |

Click **OK**.

### 6. Configurar el Pipeline script

En la sección **Pipeline**, dejar "Definition: Pipeline script" (no "Pipeline script from SCM" todavía).

Pegar el script Declarative:

```groovy
pipeline {
    agent { label 'stapp01' }
    stages {
        stage('Deploy') {
            steps {
                sh '''
                    cd /var/www/html
                    git pull origin master
                '''
            }
        }
    }
}
```

Click **Save**.

### 7. Disparar el build

`Job → Build Now`.

### Log esperado del Console Output

```
Started by user admin
[Pipeline] Start of Pipeline
[Pipeline] node
Running on App Server 1 in /home/sarah/jenkins_agent/workspace/devops-webapp-job
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Deploy)
[Pipeline] sh
+ cd /var/www/html
+ git pull origin master
From http://gitea:3000/sarah/web_app
 * branch            master     -> FETCH_HEAD
Already up to date.
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS
```

Detalles a notar:

| Línea                                                                   | Significado                                                                  |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `Running on App Server 1 in /home/sarah/jenkins_agent/workspace/...`    | Pipeline corre **en el agent**, no en el controller                          |
| `[Pipeline] { (Deploy)`                                                 | Inicio de la stage Deploy — el nombre aparece literalmente del script        |
| `+ cd /var/www/html` y `+ git pull origin master`                       | `set -x` echo de cada comando del bloque `sh`                                |
| `Already up to date.`                                                   | git pull no encontró cambios — el repo ya estaba sincronizado                |
| `Finished: SUCCESS`                                                     | Exit code 0 de todos los pasos                                               |

> `Already up to date` **no es error**. Significa que el local ya tiene los últimos commits del remoto. La validación del lab pasa si el `git pull` se ejecuta sin fallos, no si descarga datos.

### 8. Validación funcional via LB

```bash
curl https://<lab-id>:8091/
# Welcome to xFusionCorp Industries!
```

Para verificar deploy real con cambios:

1. Login a Gitea como `sarah` (Sarah_pass123)
2. Editar `index.html` directamente desde Gitea UI
3. Commit el cambio
4. Volver a Jenkins → Build Now
5. `curl` al LB nuevamente — debería mostrar el contenido actualizado

## Anatomía del filesystem en el agent durante el build

```
# En stapp01 mientras el pipeline corre
/home/sarah/jenkins_agent/
├── agent.jar                    ← Binario del agent
├── remoting/                    ← State del agent
│   └── logs/
└── workspace/
    └── devops-webapp-job/       ← Workspace del job (vacío para este pipeline)
                                   El pipeline no clona en este workspace porque el
                                   git pull se hace directamente en /var/www/html

# El document root real (donde Apache sirve)
/var/www/html/
├── .git/                        ← Repo local (sarah es owner)
├── index.html
└── (otros archivos del sitio)
```

> El pipeline **no usa el workspace** del agent — opera directamente en `/var/www/html`. Esto es deliberado porque el repo ya está clonado ahí. Si el repo no estuviera, el patrón normal sería: clonar/checkout en el workspace, después `cp` o `rsync` a `/var/www/html`.

### Patrón alternativo — checkout en workspace + deploy

Para un pipeline más "production-ready" que no asume que el repo ya está clonado en el destino:

```groovy
pipeline {
    agent { label 'stapp01' }
    stages {
        stage('Checkout') {
            steps {
                git branch: 'master', url: 'http://sarah:Sarah_pass123@gitea:3000/sarah/web_app.git'
            }
        }
        stage('Deploy') {
            steps {
                sh '''
                    sudo rsync -av --delete --exclude='.git' . /var/www/html/
                '''
            }
        }
    }
}
```

Pros y contras de cada enfoque:

| Enfoque                                | Pros                                       | Contras                                                       |
| -------------------------------------- | ------------------------------------------ | ------------------------------------------------------------- |
| **`git pull` directo en /var/www/html** (este lab) | Simple, sin copias intermedias              | El document root tiene `.git/` (security risk si Apache sirve dotfiles) |
| **Checkout en workspace + rsync**      | El `.git/` queda fuera del document root   | Más complejo; requiere sudo o permisos especiales para rsync  |
| **Build artifact + scp**               | Reproducible, versionable                  | Requiere etapa de "package" antes del deploy                  |

Para este lab el enfoque del primer pipeline es válido. Para producción, el segundo es más seguro.

## Pipeline as Code — el paso conceptual del día

Hasta hoy todos los jobs Jenkins del journal tenían su definición **solo en la UI**:

- Día 71 (`install-packages`): config en `/var/lib/jenkins/jobs/install-packages/config.xml`
- Día 73 (`copy-logs`): igual
- Día 74 (`database-backup`): igual
- Día 76 (`Packages`): igual

El `config.xml` se versiona si se hace backup del `JENKINS_HOME`, pero no es práctico para code review. Pipeline cambia esto:

| Pattern                             | Versionado                                                       |
| ----------------------------------- | ---------------------------------------------------------------- |
| **Pipeline script** (este lab)      | El script vive en el `config.xml` del job — igual que Freestyle  |
| **Pipeline script from SCM**        | El script vive en un archivo `Jenkinsfile` en un repo git        |

La opción "from SCM" es la que se usa en producción real. Permite:

- Code review del pipeline en PRs
- Branch-based pipelines (un branch puede tener un Jenkinsfile distinto)
- Rollback histórico (revertir el commit del Jenkinsfile, no del job)
- Shared libraries (groovy compartido entre repos)

Para los próximos labs vale anticipar esto: el siguiente paso natural después de hoy es mover el script al repo y cambiar el job a "Pipeline script from SCM".

## Conexión con días anteriores

- **Día 21-34 (Git workflow)**: el `git pull origin master` del pipeline es exactamente el comando del Día 25/29. La diferencia: ahora lo ejecuta un robot, no un humano.
- **Día 23 (Fork en Gitea)**: Gitea como SCM server — el repo `sarah/web_app` vive en el mismo Gitea que se vio en aquel día.
- **Día 18-20 (Apache + LAMP)**: el `/var/www/html` como document root es exactamente el setup de aquellos días. Apache no se toca hoy — ya estaba configurado.
- **Día 71-74 (Jenkins Freestyle jobs)**: el patrón "job que se conecta a server X via SSH" se reemplaza hoy con "job que corre directamente en el agent del server X". Ahorra el `ssh ...` de cada step.
- **Día 75 (Slave Nodes)**: el agent se conecta de la misma forma (inbound JNLP), pero hoy corre como `sarah` en vez de `tony`. La identidad del user determina los permisos sobre el filesystem.
- **Día 76 (Project Security)**: si este job tuviera permisos por-proyecto, los users con `Job/Build` podrían disparar el deploy. La capa de seguridad se aplica igual a Pipelines que a Freestyle.

## Reflexión: Pipeline como código vs Freestyle

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- El salto Freestyle → Pipeline: ¿se siente más limpio (todo en código) o más complejo (Groovy + idioms)?
- Pipeline script en UI vs Pipeline script from SCM (Jenkinsfile en git): ¿cuál es preferible y cuándo?
- El detalle de que el agent corre como sarah (no como tony): ¿se vio a la primera o tomó pensarlo? ¿En qué otros casos aplica el patrón "el proceso corre como el user dueño de los archivos"?
- El `nohup ... &` como solución casera al problema del agent que muere: ¿funcional o atajo peligroso? Para producción real, ¿systemd unit o agents efímeros tipo K8s?
- El pipeline operando en `/var/www/html` directamente (con .git/ ahí también) — ¿aceptable o code smell? La alternativa "checkout en workspace + rsync" es más limpia pero requiere setup adicional.
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| El tipo "Pipeline" no aparece al crear el job                            | Plugin Pipeline no instalado                                                                         | Manage Jenkins → Plugins → Available → instalar `pipeline-aggregator` + dependencies + restart    |
| El pipeline corre en el controller en lugar del agent                    | `agent { label 'stapp01' }` está mal escrito o el label del agent no matchea                         | Verificar que el agent tenga literalmente el label `stapp01` (case-sensitive)                    |
| `Permission denied` al hacer `git pull` en `/var/www/html`               | El agent corre como user que no es owner de los archivos                                             | Reiniciar el agent como `sarah` (no `tony`)                                                       |
| `fatal: not a git repository (or any of the parent directories): .git`  | `cd /var/www/html` no funcionó o el repo no está realmente clonado ahí                               | Verificar `ls -la /var/www/html/.git` desde el agent                                              |
| `Authentication failed` durante git pull                                 | Las credenciales del git remote no son válidas para el user que ejecuta                              | Verificar `git remote -v` — incluye `user:pass` en el URL                                         |
| Stage llamada `deploy` minúscula falla la validación del lab            | El lab pide `Deploy` con mayúscula                                                                   | `stage('Deploy')` (no `stage('deploy')`)                                                          |
| El curl al LB devuelve "No upstream" o 502                               | El haproxy del lab no encuentra Apache, o Apache está caído                                          | `ssh tony@stapp01 systemctl status httpd` para verificar                                          |
| Pipeline pasa pero el contenido del sitio no cambia                      | `Already up to date` — no hay commits nuevos en el remoto                                            | Hacer un commit en Gitea primero, después correr el pipeline                                      |
| Agent online pero builds quedan "pending" indefinidamente                | Número de executors = 0 en el agent                                                                  | Manage Jenkins → Nodes → App Server 1 → Configure → Number of executors >= 1                      |
| El proceso `agent.jar` muere al cerrar el SSH a stapp01                  | Falta `nohup` o `disown`                                                                             | Re-arrancar con `nohup ... > log 2>&1 &` (visto en este lab) o servicio systemd                  |
| `Started by user admin` pero el agent muestra "Running as anonymous"    | El user de Jenkins que disparó el build no tiene `Overall/Read`                                      | (Solo aplica si Matrix Auth está activo) — dar permisos                                          |
| El pipeline falla con `script returned exit code 128` en git pull        | Conflict de merge — el local tiene cambios que conflictan con el remoto                              | `git stash` o `git reset --hard origin/master` antes del pull en el script                        |

## Recursos

- [Pipeline overview (oficial)](https://www.jenkins.io/doc/book/pipeline/)
- [Declarative Pipeline syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [Pipeline `agent` directive](https://www.jenkins.io/doc/book/pipeline/syntax/#agent)
- [Pipeline steps reference](https://www.jenkins.io/doc/pipeline/steps/)
- [`git` step in Pipeline](https://www.jenkins.io/doc/pipeline/steps/git/)
- [Pipeline script from SCM](https://www.jenkins.io/doc/book/pipeline/getting-started/#defining-a-pipeline-in-scm)
- [Shared Libraries](https://www.jenkins.io/doc/book/pipeline/shared-libraries/)
