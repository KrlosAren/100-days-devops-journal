# Día 81 - Jenkins Multistage Pipeline (Deploy + Test con curl + grep)

## Problema / Desafío

Hasta hoy todos los pipelines del journal tenían **una sola stage**. Hoy se introduce el patrón "deploy + verificación": una primera stage que hace el deploy, una segunda que **valida que el deploy funcionó** con un health check HTTP. Si el health check falla, el build queda en FAILURE — visible inmediatamente.

Requirements:

1. Login a Jenkins como `admin` / `Adm!n321`
2. Editar `index.html` en el repo `sarah/web` con contenido `Welcome to xFusionCorp Industries` y push a master
3. Agregar **App Server 1** como agent **vía Launch via SSH** (no inbound JNLP):
   - Name: `App Server 1`
   - Label: `stapp01`
   - Remote root: `/home/sarah/jenkins_agent`
   - Host: `stapp01`
   - Credentials: SSH user `sarah`
4. Instalar `java-17-openjdk` en stapp01 si no está
5. Crear pipeline **`deploy-job`** con **dos stages** (case-sensitive):
   - **Deploy** — git pull del master en `/var/www/html`
   - **Test** — `curl` al LB + `grep` del contenido esperado
6. La pipeline debe correr en label `stapp01`
7. Test debe fallar si el sitio no responde o no tiene el contenido correcto
8. Validar via LB `http://stlb01:8091`

Stack del lab:

| Componente              | Detalle                                                    |
| ----------------------- | ---------------------------------------------------------- |
| **Gitea**               | Repo `sarah/web` con `index.html` actualizado                |
| **stapp01**             | App Server 1 — Apache `:8080`, `/var/www/html` working tree |
| **stlb01:8091**         | LB (haproxy) — frontea Apache                                |
| **Jenkins controller** | Donde se crea el pipeline                                    |

## Conceptos clave

### Multistage Pipeline — el modelo CI/CD profesional

El patrón **deploy + test** es el bloque básico de CI/CD moderno. La estructura:

```groovy
pipeline {
    agent { label 'stapp01' }
    stages {
        stage('Deploy') { steps { /* deploy */ } }
        stage('Test')   { steps { /* health check */ } }
    }
}
```

Si **Deploy** falla, **Test** no se ejecuta — Jenkins corta la cadena. Si Test falla, el build queda en FAILURE y queda visible en la UI como rojo. Este patrón se extiende a:

```
Build → Test → Deploy → Smoke Test → Notify
```

Cada stage es un gate: si falla, las siguientes no corren.

### Launch via SSH — el segundo método de conexión del agent

Hasta el Día 80, los agents se conectaban con **inbound JNLP/WebSocket**: el agent iniciaba conexión al controller corriendo `java -jar agent.jar ...` manualmente. Hoy el lab pide el método alternativo: **Launch via SSH**.

Comparación operacional:

| Aspecto                            | Inbound JNLP (Días 75-80)                          | Launch via SSH (este lab)                     |
| ---------------------------------- | -------------------------------------------------- | --------------------------------------------- |
| Quién inicia la conexión            | Agent → controller                                  | Controller → agent                            |
| Comando manual en el agent          | **Sí** — `java -jar agent.jar ...`                  | **No** — el controller arranca el `agent.jar` |
| Lifecycle del agent                 | Manual (o systemd)                                  | Gestionado automáticamente por el controller  |
| Si el agent muere                   | Queda offline hasta arranque manual                 | Controller reintenta SSH y restart            |
| Requiere SSH inbound al agent       | No                                                  | **Sí** — el controller debe poder hacer SSH al agent |
| Credentials                         | Secret JNLP (string opaco)                          | SSH Username with private key                 |
| Setup en el agent                   | Java + descargar `agent.jar`                        | Java + SSH server (ya viene)                  |

Para producción **SSH es preferible** — el controller hace lifecycle management, no requiere intervención humana al reiniciar. El único requisito: el controller debe poder hacer SSH al agent (típicamente OK en la red interna del cluster).

### Setup del agent — método Launch via SSH

#### 1. En Jenkins → Credentials → Add Credentials

| Campo                     | Valor                                                                |
| ------------------------- | -------------------------------------------------------------------- |
| Kind                      | **SSH Username with private key**                                    |
| Scope                     | Global                                                               |
| ID                        | `sarah-ssh-key`                                                      |
| Username                  | `sarah`                                                              |
| Private Key               | Enter directly → pegar contenido de `/var/lib/jenkins/.ssh/id_ed25519` |
| Passphrase                | (vacío si la key se generó con `-N ""`)                              |

#### 2. Setup en stapp01 (como tony admin)

```bash
# Asegurar Java 17 instalado
ssh tony@stapp01
sudo yum install -y java-17-openjdk

# Asegurar que sarah tiene SSH key del controller en authorized_keys
# (Si no estaba del Día 77, copiar la pubkey del controller)
```

#### 3. Crear el nodo desde la UI

Navegación: **Manage Jenkins → Nodes → New Node**

| Campo                            | Valor                                                        |
| -------------------------------- | ------------------------------------------------------------ |
| Node name                        | `App Server 1`                                               |
| Type                             | Permanent Agent                                              |
| Number of executors              | `1`                                                          |
| Remote root directory            | `/home/sarah/jenkins_agent`                                  |
| Labels                           | `stapp01`                                                    |
| **Launch method**                | **Launch agents via SSH**                                    |
| Host                             | `stapp01`                                                    |
| Credentials                      | `sarah` (el credential creado en paso 1)                     |
| Host Key Verification Strategy   | Non verifying (para labs) o Known hosts file (para prod)     |

Save. **No hace falta correr nada en el agent** — el controller hace SSH y arranca el `agent.jar` solo.

Validar que el nodo aparece online en `Manage Jenkins → Nodes`. El log del nodo (click sobre el nodo → Log) debe mostrar:

```
[ssh-agent] Connecting to stapp01:22
[ssh-agent] Authenticating as sarah
[ssh-agent] Connected
[ssh-agent] Copying latest remoting.jar...
[ssh-agent] Launching agent...
```

### El comando del Test stage — anatomía de `curl -f | grep`

```bash
curl -f http://stlb01:8091 | grep "Welcome to xFusionCorp Industries"
```

Pipeline de comandos con dos puntos de falla:

| Comando             | Falla con exit ≠ 0 si...                                                   |
| ------------------- | -------------------------------------------------------------------------- |
| `curl -f <URL>`     | Cualquier respuesta HTTP **>= 400** (404, 500, etc.), DNS fail, connection refused |
| `grep <pattern>`    | El stdin no contiene el pattern                                            |

**Por qué `-f` es crítico**: sin él, curl devuelve **exit 0 aunque la respuesta sea 500**. El HTML del error pasa al grep, que solo falla si tampoco encuentra el string esperado — pero podría coincidir por accidente, dando un falso positivo.

```bash
# ❌ Sin -f — falso positivo posible
curl http://stlb01:8091 | grep "Welcome"
# Si Apache devuelve 500 con HTML "Welcome to error page", el test pasa

# ✅ Con -f — falla rápido en error HTTP
curl -f http://stlb01:8091 | grep "Welcome"
# Apache 500 → curl exit 22 → pipe corta inmediatamente
```

### Mejora — `curl -fsS | grep -q`

Versión más limpia del test:

```bash
curl -fsS http://stlb01:8091 | grep -q "Welcome to xFusionCorp Industries"
```

Flags adicionales:

| Flag         | Función                                                                     |
| ------------ | --------------------------------------------------------------------------- |
| `-f`         | Fail on HTTP error (>= 400)                                                  |
| `-s`         | Silent — no muestra progress bar                                              |
| `-S`         | Show errors (compensa `-s`: errores siguen visibles)                          |
| `grep -q`    | Quiet — no imprime el match, solo exit code                                  |

> Para tests automatizados, **silenciar el output** evita ruido en los logs de Jenkins. El test solo importa por su exit code.

### `set -e` semantics del pipeline shell

Jenkins ejecuta cada `sh '...'` con `/bin/sh -xe`:

| Flag    | Comportamiento                                                       |
| ------- | -------------------------------------------------------------------- |
| `-x`    | Echo de cada comando antes de ejecutarlo (el `+ ...` del log)        |
| `-e`    | Abort en el primer comando con exit ≠ 0                              |

Esto significa que en un bloque `sh '''cmd1; cmd2; cmd3'''`, si **cmd1** falla, cmd2 y cmd3 **no se ejecutan**. El bloque entero devuelve el exit code del comando fallido, y la stage marca FAILURE.

**Sutileza con pipes**: por default, el exit code del pipeline (`a | b | c`) es el del **último** comando (`c`). Si `a` falla pero `c` exit 0, el pipe completo es exitoso. Para fallar si **cualquier** comando del pipe falla:

```bash
set -o pipefail
curl -f ... | grep ...
```

Para este lab no es crítico porque `grep` falla si curl no produce output, pero anclar `pipefail` es buena práctica para producción.

### Detalle de Pipeline — Test no corre si Deploy falló

```groovy
pipeline {
    stages {
        stage('Deploy') {
            steps { sh 'comando que falla' }
        }
        stage('Test') {
            steps { sh 'curl ...' }  // ← NO se ejecuta si Deploy falló
        }
    }
}
```

Comportamiento por default de Declarative Pipeline: **falla rápido**. Si una stage falla, las siguientes se saltean. Para forzar que ciertas stages corran siempre (cleanup, notifications), usar `post`:

```groovy
pipeline {
    stages {
        stage('Deploy') { ... }
        stage('Test') { ... }
    }
    post {
        always   { echo 'Siempre — pase o falle el build' }
        success  { echo 'Solo si pipeline SUCCESS' }
        failure  { echo 'Solo si pipeline FAILURE' }
        unstable { echo 'Solo si pipeline UNSTABLE' }
        changed  { echo 'Solo si el resultado cambió respecto al build anterior' }
    }
}
```

## Pasos

1. Login Jenkins como admin
2. (Si no estaba del Día 79) Configurar sudoers en stapp01 para sarah con `NOPASSWD` sobre `git` y `systemctl`
3. Si el agent anterior (inbound JNLP) está configurado, **borrarlo o cambiar el launch method a SSH**
4. Crear credential SSH "sarah-ssh-key" en Jenkins Credentials Manager
5. Crear nodo `App Server 1` con launch via SSH apuntando a stapp01:22
6. Validar que el nodo conecta y queda online (sin correr nada manualmente)
7. Crear pipeline `deploy-job` (Pipeline, no Multibranch)
8. Pegar el script con dos stages: Deploy + Test
9. Actualizar `index.html` en Gitea (vía git push desde stapp01) con el contenido pedido
10. Save → Build Now
11. Validar el log: dos stages en SUCCESS + curl al LB devuelve contenido correcto

## Comandos / Código

### 1. Actualizar el contenido del repo (como sarah)

```bash
ssh sarah@stapp01
cd /home/sarah/web   # ó /var/www/html, ambos son working trees del mismo repo

# Editar index.html con el contenido EXACTO que pide el lab
cat > index.html <<'EOF'
Welcome to xFusionCorp Industries
EOF

# Commit y push
git add index.html
git commit -m "Update welcome message"
git push origin master
```

> Si el repo está en `/var/www/html` con `.git/` owned por root, hacerlo desde `/home/sarah/web` (working tree de sarah) y push. Después el pipeline Deploy lo pull en `/var/www/html`.

### 2. Setup del agent vía Launch via SSH

#### Crear credential

Navegación: **Manage Jenkins → Credentials → System → Global → Add Credentials**

| Campo            | Valor                                            |
| ---------------- | ------------------------------------------------ |
| Kind             | SSH Username with private key                    |
| ID               | `sarah-ssh-key`                                  |
| Username         | `sarah`                                          |
| Private Key      | Enter directly → contenido de `/var/lib/jenkins/.ssh/id_ed25519` (sin la versión .pub) |
| Passphrase       | (vacío)                                          |

> El private key se obtiene del controller con `sudo cat /var/lib/jenkins/.ssh/id_ed25519`. La pubkey ya debe estar en `~sarah/.ssh/authorized_keys` de stapp01 (configurado en Días 77+).

#### Crear el nodo

**Manage Jenkins → Nodes → + New Node**

| Campo                              | Valor                                       |
| ---------------------------------- | ------------------------------------------- |
| Node name                          | `App Server 1`                              |
| Type                               | Permanent Agent                             |
| Number of executors                | `1`                                         |
| Remote root directory              | `/home/sarah/jenkins_agent`                 |
| Labels                             | `stapp01`                                   |
| Launch method                      | **Launch agents via SSH**                   |
| Host                               | `stapp01`                                   |
| Credentials                        | `sarah` (el creado arriba)                  |
| Host Key Verification Strategy     | Non verifying Verification Strategy         |

Save. El controller intenta SSH inmediatamente. En el log del nodo:

```
[ssh-agent] Connecting to stapp01:22
[ssh-agent] Authenticating as sarah
[ssh-agent] Authentication successful
[ssh-agent] Remote user's home directory: /home/sarah
[ssh-agent] Copying latest remoting.jar...
[ssh-agent] Starting agent process: cd /home/sarah/jenkins_agent && java -jar remoting.jar -workDir /home/sarah/jenkins_agent
INFO: Connected
```

El nodo queda **online sin intervención manual** en stapp01.

### 3. Crear el pipeline `deploy-job`

**Dashboard → New Item → `deploy-job` → Pipeline → OK**

En la sección Pipeline → Definition: Pipeline script. Pegar:

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
        stage('Test') {
            steps {
                sh '''
                    curl -fsS http://stlb01:8091 | grep -q "Welcome to xFusionCorp Industries"
                '''
            }
        }
    }
}
```

Save → Build Now.

### Log esperado del Console Output

```
Started by user admin
[Pipeline] Start of Pipeline
[Pipeline] node
Running on App Server 1 in /home/sarah/jenkins_agent/workspace/deploy-job
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Deploy)
[Pipeline] sh
+ sudo git config --global --add safe.directory /var/www/html
+ sudo git -C /var/www/html pull origin master
From http://gitea:3000/sarah/web
 * branch            master     -> FETCH_HEAD
Already up to date.
[Pipeline] }
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Test)
[Pipeline] sh
+ curl -fsS http://stlb01:8091
+ grep -q 'Welcome to xFusionCorp Industries'
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS
```

Detalles a notar:

| Línea                                    | Significado                                                            |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| `[Pipeline] { (Deploy)`                   | Inicio de la stage Deploy                                              |
| `[Pipeline] sh`                          | Comando shell de la stage                                              |
| `+ sudo git ...`                         | Echo del comando (set -x)                                              |
| `Already up to date.`                    | git pull no encontró cambios (si ya estaba al día)                     |
| `[Pipeline] } / [Pipeline] // stage`     | Cierre de Deploy                                                       |
| `[Pipeline] { (Test)`                    | Inicio de Test (solo porque Deploy SUCCESS)                            |
| `+ curl -fsS http://stlb01:8091`         | Echo del curl                                                          |
| `+ grep -q 'Welcome to xFusionCorp Industries'` | Echo del grep (sin output porque `-q`)                          |
| `Finished: SUCCESS`                       | Ambas stages OK                                                        |

### Validación funcional

```bash
# Desde el agente o desde el jump host
curl http://stlb01:8091
# Welcome to xFusionCorp Industries
```

## Probar que Test detecta una falla — test de FAILURE

Para validar que el pipeline cumple su rol de gate, probarlo con un contenido equivocado:

### Opción A: cambiar el contenido en el repo

```bash
ssh sarah@stapp01
cd /home/sarah/web
echo "Hello World" > index.html
git add index.html
git commit -m "Wrong content for test"
git push origin master
```

Después correr el pipeline:

```
[Pipeline] { (Deploy)
+ sudo git -C /var/www/html pull origin master
Updating ... 1 file changed
[Pipeline] // stage
[Pipeline] { (Test)
+ curl -fsS http://stlb01:8091
+ grep -q 'Welcome to xFusionCorp Industries'
Hello World      ← curl devolvió esto pero grep no encontró el string
script returned exit code 1
[Pipeline] // stage
[Pipeline] End of Pipeline
ERROR: script returned exit code 1
Finished: FAILURE
```

El pipeline queda en **FAILURE** porque grep retornó 1.

### Opción B: matar Apache antes del Test

```bash
ssh tony@stapp01
sudo systemctl stop httpd

# Disparar el pipeline manualmente
```

```
[Pipeline] { (Test)
+ curl -fsS http://stlb01:8091
curl: (52) Empty reply from server
script returned exit code 52
[Pipeline] // stage
ERROR: script returned exit code 52
Finished: FAILURE
```

> Con `-fsS`, los errores siguen visibles a pesar del `-s`. Sin `-S`, el log mostraría solo "exit 52" sin contexto.

## Mejoras opcionales del pipeline

### Versión con timeout y retry

```groovy
pipeline {
    agent { label 'stapp01' }
    options {
        timeout(time: 5, unit: 'MINUTES')   // todo el pipeline falla a los 5 min
    }
    stages {
        stage('Deploy') {
            steps {
                sh '''
                    sudo git config --global --add safe.directory /var/www/html
                    sudo git -C /var/www/html pull origin master
                '''
            }
        }
        stage('Test') {
            steps {
                retry(3) {
                    sleep 2
                    sh 'curl -fsS http://stlb01:8091 | grep -q "Welcome to xFusionCorp Industries"'
                }
            }
        }
    }
    post {
        failure {
            echo 'Pipeline failed — Apache puede estar caído o el contenido no se desplegó correctamente.'
        }
    }
}
```

Mejoras:

- `timeout`: aborta el pipeline si tarda más de 5 minutos
- `retry(3)`: reintenta el Test hasta 3 veces (Apache puede tardar unos segundos en servir contenido nuevo)
- `sleep 2`: espera 2 segundos entre reintentos
- `post { failure { ... } }`: mensaje claro cuando falla

### Versión con health endpoint específico

Si la app tiene un endpoint `/health`:

```groovy
stage('Test') {
    steps {
        sh '''
            curl -fsS http://stlb01:8091/health | grep -q "OK"
        '''
    }
}
```

Es la práctica de producción — separar el contenido de la página de la verificación de salud.

## Comparación: chained jobs (Día 80) vs multistage pipeline (este lab)

Las dos formas resuelven el mismo problema:

| Aspecto                      | Chained Freestyle (Día 80)                       | Multistage Pipeline (este lab)                       |
| ---------------------------- | ------------------------------------------------ | ---------------------------------------------------- |
| Número de jobs               | 2 jobs separados                                  | 1 job con 2 stages                                   |
| Configuración                | Post-build "Build other projects"                 | Bloques `stages { stage('A') { } stage('B') { } }`  |
| Visualización                | Diagrama upstream/downstream                      | Pipeline visualization con barras de stage timing    |
| Workspace compartido         | No (cada job tiene su workspace)                  | Sí (las stages comparten workspace)                  |
| Errores entre stages         | `Only if stable` (binario)                        | Default fail-fast + `post`, `when`, `try/catch`     |
| Versionable en git           | Difícil (config.xml por job)                      | Trivial (Jenkinsfile único)                          |
| Visibilidad del flow         | Necesitás mirar dos jobs distintos                | Todo en un solo build run                            |
| Retry granular               | A nivel de job entero                              | `retry(N) { ... }` dentro de una stage              |

**Cuándo usar cada uno**:

- **Chained jobs**: cuando los pasos son fundamentalmente independientes y reutilizables (ej. un job de "notify-slack" que muchos otros disparan)
- **Multistage pipeline**: cuando los pasos forman una unidad lógica y comparten contexto (deploy + test + cleanup del mismo release)

Para este lab, **multistage es lo correcto** — los dos pasos están acoplados al ciclo de un deploy individual.

## Notas adicionales — del CI/CD demo al CI/CD productivo

### 1. El salto del "happy path" al "verified deploy"

Una propiedad sutil del Pipeline cuando se compara con todos los CI/CD del journal hasta ahora: **hoy es la primera vez que un pipeline verifica que el deploy funcionó**. Hasta el Día 80, los jobs hacían "deploy successful = lab passed". Hoy es "deploy successful AND content matches expected = lab passed".

Ese salto del "happy path solo" al "verified deploy" es exactamente lo que distingue un CI/CD demo de uno productivo. Para sistemas reales, la cadena se extiende:

```
build → unit tests → deploy staging → integration tests → smoke tests → canary deploy → full deploy → post-deploy monitoring
```

Cada eslabón es un **gate**: si falla, el deploy se aborta. La pipeline del lab es la versión mínima de este patrón — dos etapas que ya capturan la idea fundamental.

### 2. Launch via SSH como agents gestionados por el controller

El método **Launch via SSH** que el lab pide explícitamente abre una nueva categoría operacional: **agents gestionados por el controller**. Comparado con inbound JNLP (donde el operador del agent debe arrancar `java -jar agent.jar ...` manualmente), SSH inbound delega el lifecycle al controller.

Paralelo con K8s para ubicarlo conceptualmente:

| Patrón Jenkins         | Equivalente K8s                                                          |
| ---------------------- | ------------------------------------------------------------------------ |
| Inbound JNLP           | Pods standalone — el operador los crea y mantiene a mano                  |
| **Launch via SSH**     | **DaemonSets** — el control plane garantiza que el daemon está corriendo  |

Es la misma idea (el plano de control gestiona el ciclo de vida de los workers) pero implementada distinto. Jenkins usa SSH para hacer push del binario y arrancarlo; K8s usa kubelet + container runtime. Saber esto hace más fácil pasar mentalmente entre los dos modelos.

### 3. La escalera de sofisticación de los smoke tests

El patrón `curl -fsS | grep -q` del lab es **el smoke test mínimo viable**. Los siguientes pasos en sofisticación son:

| Nivel | Técnica                                              | Qué valida                                                          |
| ----- | ---------------------------------------------------- | ------------------------------------------------------------------- |
| 1     | `curl -fsS \| grep -q`                                | HTTP 200 + string match básico (este lab)                          |
| 2     | `curl -fsS -w '%{time_total}'` + assert < N segundos | Status + body + latencia                                            |
| 3     | `curl ... \| jq --exit-status '.field == "value"'`    | Validación de JSON estructurado                                     |
| 4     | **Postman / Newman**                                  | Suite completa de requests con assertions                           |
| 5     | **Selenium / Playwright**                             | E2E con navegador real (rendering, JS, interacciones)               |
| 6     | **Contract testing (Pact)**                           | APIs respetan su schema declarado entre consumer y provider          |

Para un sitio estático como el del lab, **nivel 1 es perfectamente suficiente**. La sofisticación aumenta proporcional a la criticidad del servicio y a la frecuencia de cambios. Una API pública con miles de clientes amerita Pact; un microservicio interno puede vivir con Newman; un sitio estático con grep está bien.

> **Regla práctica**: el costo del test debe ser **proporcional al costo del bug que evita**. Tests demasiado simples dejan pasar regresiones; tests demasiado complejos se vuelven mantenimiento que nadie quiere hacer.

## Conexión con días anteriores

- **Día 75 (Slave Nodes)**: el método inbound JNLP que se vio entonces. Hoy aparece el otro método — **Launch via SSH** — con sus ventajas operacionales.
- **Día 77-78 (Declarative Pipelines)**: el primer Pipeline (Día 77) tenía una stage; el de hoy tiene dos. Misma sintaxis declarativa, más stages.
- **Día 80 (Chained Builds)**: el patrón "deploy + restart" como dos jobs. Hoy es el mismo patrón pero como dos stages **en un solo pipeline** — más limpio y versionable.
- **Día 79 (Deployment Job)**: el setup de NOPASSWD para sarah y el patrón de deploy. Reutilizable acá.
- **Día 18-20 (Apache)**: el target server stapp01 con Apache en `:8080`.
- **Día 21-34 (Git workflow)**: la edición de `index.html` + commit + push es el flow del Día 25-29 — ahora automatizado en un pipeline.

## Reflexión: Test stage como gate y la madurez del CI/CD

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- Multistage pipeline vs chained builds (Día 80): ¿cuál se siente más natural? El primero centraliza el flow, el segundo lo distribuye.
- El Test stage como **gate**: ¿cambia tu mental model del CI/CD vs Día 77 donde el Deploy era el único paso? El concepto de "el deploy no termina hasta que la verificación pasa".
- Launch via SSH (este lab) vs inbound JNLP (Días 75-80): ¿cuál es preferible para producción? El primero requiere SSH inbound al agent — ¿restricción aceptable o blocker?
- `curl -fsS | grep -q` como test: ¿suficiente para producción real? ¿En qué casos llevarías esto a tests más complejos (Postman/Newman, Selenium, contract testing)?
- `post { always { ... } }` para cleanup/notifications: ¿útil en producción o overhead innecesario?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Launch via SSH no conecta: "Connection refused"                          | sshd no corriendo en stapp01, o el puerto 22 bloqueado por firewall                                  | `ssh sarah@stapp01` desde el controller para verificar; `systemctl status sshd` en stapp01        |
| Launch via SSH falla con "Permission denied (publickey)"                 | La pubkey del Jenkins controller no está en `~sarah/.ssh/authorized_keys` de stapp01                  | `ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub sarah@stapp01` (como user jenkins)          |
| Launch via SSH conecta pero el agente no arranca: "Java not found"        | Java no instalado en stapp01                                                                          | `sudo yum install -y java-17-openjdk` en stapp01                                                  |
| Test stage falla con `curl: (7) Failed to connect`                       | LB no accesible — el host `stlb01:8091` no resuelve o el haproxy no está corriendo                   | `ping stlb01` desde el agent; verificar config de haproxy                                         |
| Test pasa pero el contenido del sitio es viejo                           | Apache cacheó o el LB tiene un caché propio                                                          | `curl http://stlb01:8091` desde fuera del pipeline para validar manualmente                       |
| Pipeline pasa pero el validador del lab marca incorrecto                 | El `index.html` tiene contenido distinto al esperado por el lab (typo, newline, etc.)                | Verificar byte-a-byte: `xxd /var/www/html/index.html | head`                                       |
| Test stage hace `curl` pero el grep matchea por accidente                | Sin `-f` en curl, el HTML de error puede contener el string esperado                                 | Siempre usar `curl -f` para fallar en HTTP 4xx/5xx                                                |
| El pipeline corre en el built-in node en lugar de stapp01                | `agent { label 'stapp01' }` no matchea el label del agent configurado                                | Verificar que el nodo tiene exactamente el label `stapp01` (case-sensitive)                       |
| Test funciona local pero falla desde el pipeline                          | La sesión interactiva tiene PATH/env vars distintos al del job                                       | Loggear `which curl` y `echo $PATH` dentro del pipeline para debuggear                            |
| `script returned exit code 1` sin más detalle                            | `set -e` aborta sin contexto                                                                          | Agregar `|| { echo "DEBUG: ..."; exit 1 }` después de cada comando crítico                       |
| Después de cambiar el script, el pipeline corre el viejo                 | Falta Save antes de Build Now                                                                         | Save → ver versión del script → Build Now                                                         |

## Recursos

- [Multistage Pipelines (oficial)](https://www.jenkins.io/doc/book/pipeline/syntax/#stages)
- [Launch via SSH agent (oficial)](https://plugins.jenkins.io/ssh-slaves/)
- [SSH Credentials in Jenkins](https://www.jenkins.io/doc/book/using/using-credentials/#configuring-credentials)
- [`curl --fail` documentation](https://curl.se/docs/manpage.html#-f)
- [`grep -q` quiet mode](https://man7.org/linux/man-pages/man1/grep.1.html)
- [`post` directive en Declarative](https://www.jenkins.io/doc/book/pipeline/syntax/#post)
- [`retry` step en Pipeline](https://www.jenkins.io/doc/pipeline/steps/workflow-basic-steps/#retry-retry-the-body-up-to-n-times)
- [Bash `pipefail` y exit codes en pipes](https://www.gnu.org/software/bash/manual/html_node/Pipelines.html)
