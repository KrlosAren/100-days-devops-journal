# Día 78 - Jenkins Conditional Pipeline (parameters + script block + git checkout)

## Problema / Desafío

El equipo de desarrollo trabaja con el repo `sarah/web_app` que tiene dos branches (`master` y `feature`). Hay que crear un pipeline parametrizado que despliegue el branch indicado al disparar el build — sin tener que crear dos jobs separados.

Requirements:

1. Login a Jenkins como `admin` / `Adm!n321`
2. Agent `App Server 1` (label `stapp01`, workdir `/home/sarah/jenkins_agent`) — mismo del Día 77
3. Crear pipeline job **`nautilus-webapp-job`** (Pipeline, **no Multibranch**)
4. Agregar **String parameter** llamado `BRANCH`
5. Una sola **stage** llamada `Deploy` (case-sensitive)
6. Lógica condicional:
   - Si `BRANCH=master` → deploy del branch master
   - Si `BRANCH=feature` → deploy del branch feature
7. Validar via LB que se sirve el contenido correcto según el parámetro

Continúa directamente desde Día 77 (mismo agent, mismo repo, mismo Apache). Lo nuevo: **parámetros + condicionales en Pipeline**.

## Conceptos clave

### `parameters` block en Declarative Pipeline

Hasta el Día 72 los parámetros se configuraban en la UI del job (Freestyle). En Pipeline viven en el código:

```groovy
pipeline {
    agent { label 'stapp01' }
    parameters {
        string(name: 'BRANCH', defaultValue: 'master', description: 'Branch a desplegar')
    }
    stages { ... }
}
```

Tipos de parameters disponibles (equivalente a los del Día 72):

| Tipo                | Sintaxis                                                                    |
| ------------------- | --------------------------------------------------------------------------- |
| **String**          | `string(name: 'X', defaultValue: 'y', description: '...')`                  |
| **Choice**          | `choice(name: 'X', choices: ['a', 'b'], description: '...')`                |
| **Boolean**         | `booleanParam(name: 'X', defaultValue: false, description: '...')`          |
| **Password**        | `password(name: 'X', defaultValue: '', description: '...')` *(enmascarado)*  |
| **File**            | `file(name: 'X', description: '...')`                                       |
| **Multiline text**  | `text(name: 'X', defaultValue: '', description: '...')`                     |

Una propiedad importante: la primera vez que el pipeline se ejecuta, **los parámetros NO están disponibles**. Hay que correr el build una vez para que Jenkins los registre. A partir del segundo build, el botón "Build Now" se convierte en "Build with Parameters".

### Acceder a parámetros — `params.<NAME>` vs `$<NAME>`

Una vez declarado, el parámetro se puede leer de dos formas:

| Forma                          | Dónde se resuelve                                | Cuándo usar                                                                |
| ------------------------------ | ------------------------------------------------ | -------------------------------------------------------------------------- |
| `${params.BRANCH}` (Groovy)    | En Groovy, **antes** de mandar el comando al shell | Cuando se quiere interpolar el valor en un string Groovy                  |
| `$BRANCH` (shell env var)      | En el shell, durante la ejecución                  | Jenkins exporta los parámetros como env vars del shell automáticamente    |
| `env.BRANCH` (Groovy explícito) | En Groovy via el objeto env                       | Cuando se quiere ser explícito sobre que viene del environment            |

Para Declarative + interpolación segura, la convención es **siempre `${params.<NAME>}`** — más explícito, más fácil de auditar.

### `script { }` block — el escape hatch de Declarative

Declarative Pipeline tiene una estructura **rígida**: solo permite los bloques predefinidos (`pipeline`, `stages`, `stage`, `steps`, etc.). Las construcciones de Groovy nativas (`if/else`, `for`, `try/catch`) **no funcionan directamente** dentro de `steps { }`.

Para usar Groovy puro adentro de un `steps`, hay que envolver el código en un bloque `script { }`:

```groovy
steps {
    script {
        // Groovy puro acá adentro
        if (params.BRANCH == 'master') {
            sh '...'
        } else if (params.BRANCH == 'feature') {
            sh '...'
        }
    }
}
```

Sin el `script { }`, Jenkins arroja un error de parseo:

```
WorkflowScript: 5: Expected a step @ line 5, column 13.
                if (params.BRANCH == 'master') {
                ^
```

El `script { }` es la **frontera** entre los dos modos del Pipeline: fuera de él es Declarative (estructurado, validable), dentro es Scripted (Groovy puro, flexible).

### Las tres formas de hacer pipelines condicionales

Hay tres maneras de implementar la lógica del lab. Cada una con trade-offs:

#### Forma 1 — `script { if/else }` (la usada en el lab)

```groovy
stage('Deploy') {
    steps {
        script {
            if (params.BRANCH == 'master') {
                sh '''
                    cd /var/www/html
                    git checkout master
                    git pull origin master
                '''
            } else if (params.BRANCH == 'feature') {
                sh '''
                    cd /var/www/html
                    git checkout feature
                    git pull origin feature
                '''
            }
        }
    }
}
```

**Pros**:
- Explícito sobre qué branches están permitidos
- Si el user pasa un branch inválido (ej. `BRANCH=delete-everything`), nada se ejecuta — comportamiento seguro
- Permite agregar lógica extra fácil (logging por branch, side effects)

**Cons**:
- Más verboso — código duplicado entre las dos ramas
- Si se agrega un branch nuevo (`hotfix`), hay que tocar el código

#### Forma 2 — `when` directive (más idiomática Declarative — **no aplica acá**)

```groovy
stages {
    stage('Deploy master') {
        when { expression { params.BRANCH == 'master' } }
        steps { sh '...' }
    }
    stage('Deploy feature') {
        when { expression { params.BRANCH == 'feature' } }
        steps { sh '...' }
    }
}
```

**Pros**:
- 100% Declarative — sin `script { }`
- La UI de Jenkins muestra qué stages corrieron y cuáles se saltearon (con `Skipped` highlight)

**Cons**:
- **El lab pide una sola stage llamada `Deploy`** — esta forma genera 2 stages, no pasa la validación

#### Forma 3 — parametrización directa (la más concisa)

```groovy
stage('Deploy') {
    steps {
        sh """
            cd /var/www/html
            git checkout ${params.BRANCH}
            git pull origin ${params.BRANCH}
        """
    }
}
```

**Pros**:
- Sin condicional explícito — el código es el mismo para cualquier branch
- Funciona automáticamente con nuevos branches sin tocar el pipeline

**Cons**:
- **Vulnerable a shell injection** si el parámetro no se valida — un user con permiso `Job/Build` podría pasar `BRANCH=master; rm -rf /` y el shell ejecutaría ambos comandos
- No valida que el branch sea uno de los esperados

### Cuándo usar cada forma — guía rápida

| Escenario                                                            | Forma recomendada       |
| -------------------------------------------------------------------- | ----------------------- |
| Lab pide "una sola stage" + necesita validación de input              | **Forma 1** (script if/else) — la del lab |
| Permite múltiples stages + quieres visibilidad de qué corrió/skipped  | **Forma 2** (when directive) |
| Pipeline interno, sin users externos, valores trusted                  | **Forma 3** (parametrización directa) |
| Producción con users externos                                          | **Forma 1 + validación explícita** del input antes |

### Comilla simple vs comilla triple en `sh`

Las tres formas de pasar comandos a `sh` en Pipeline:

| Forma                       | Permite interpolación Groovy        | Cuándo usar                                                                                |
| --------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------ |
| `sh 'comando $var'`         | **No** — comillas simples           | Cuando se quiere usar env vars del shell directamente (sin interpolación Groovy)           |
| `sh "comando ${params.X}"`  | **Sí** — comillas dobles            | Cuando se quiere interpolar params/variables Groovy                                        |
| `sh '''bloque multilínea'''` | **No** — comillas triples simples  | Bloque multi-línea con $ vars del shell (lo que usa el lab — preserva newlines)            |
| `sh """bloque multilínea"""` | **Sí** — comillas triples dobles   | Bloque multi-línea con interpolación Groovy                                                |

Para el lab, las **comillas triples simples** (`'''`) están bien porque el `if/else` Groovy ya filtró el valor de BRANCH antes de llegar al shell.

### Por qué `git checkout` antes de `git pull`

El comando del pipeline hace:

```bash
cd /var/www/html
git checkout <branch>      # Cambia al branch local
git pull origin <branch>   # Trae los commits nuevos del remoto a ese branch
```

Por qué los dos comandos:

| Acción                | Sin `git checkout` previo                                              |
| --------------------- | ---------------------------------------------------------------------- |
| `git pull origin master` desde el branch `feature` | Trae los commits de master pero los **mergea en feature** — bug |
| `git checkout master` antes | Cambia el HEAD a master, así el `pull` afecta a master  |

> Sin el `git checkout`, el pipeline puede dejar el repo en un estado inconsistente — branches mezclados. El comando explícito es defensivo.

### Riesgo de Shell Injection (anclar para producción)

La Forma 3 (parametrización directa) tiene un riesgo de seguridad si el parámetro viene de un usuario no confiable:

```groovy
// ❌ Mal — vulnerable a injection
sh "git checkout ${params.BRANCH}"

// Si el user pasa BRANCH=master; rm -rf /, el shell ve:
// git checkout master; rm -rf /
```

Mitigaciones:

| Estrategia                                     | Cómo se aplica                                                              |
| ---------------------------------------------- | --------------------------------------------------------------------------- |
| **Validación explícita en Groovy**             | `if (!['master', 'feature'].contains(params.BRANCH)) { error("Invalid branch") }` |
| **Choice parameter en lugar de String**        | `choice(name: 'BRANCH', choices: ['master', 'feature'])` — la UI no acepta otros valores |
| **Escape via shell quoting**                   | `sh "git checkout '${params.BRANCH}'"` — pero comillas simples NO escapan `'` mismo |
| **Pasar como env var en lugar de interpolación** | `withEnv(["BRANCH=${params.BRANCH}"]) { sh 'git checkout "$BRANCH"' }` |

Para este lab, la **Forma 1 (if/else explícito)** efectivamente valida el input — solo ejecuta si el valor matchea uno de los dos esperados.

## Pasos

1. Login Jenkins como admin
2. Reutilizar el agent `App Server 1` configurado en Día 77 (o re-arrancarlo si murió)
3. Dashboard → New Item → `nautilus-webapp-job` → tipo **Pipeline** (no Multibranch)
4. En la sección Pipeline, pegar el script Declarative con `parameters` + `script { if/else }`
5. Save
6. Build Now (primera vez — Jenkins registra los parámetros, no acepta input todavía)
7. Build with Parameters → BRANCH=`master` → Build
8. Validar via LB
9. Crear/usar el branch `feature` en Gitea con contenido distinto
10. Build with Parameters → BRANCH=`feature` → Build
11. Validar via LB — debe mostrar el contenido del branch feature

## Comandos / Código

### El Pipeline completo (versión del lab)

```groovy
pipeline {
    agent { label 'stapp01' }

    parameters {
        string(
            name: 'BRANCH',
            defaultValue: 'master',
            description: 'Branch a desplegar (master o feature)'
        )
    }

    stages {
        stage('Deploy') {
            steps {
                script {
                    if (params.BRANCH == 'master') {
                        sh '''
                            cd /var/www/html
                            git checkout master
                            git pull origin master
                        '''
                    } else if (params.BRANCH == 'feature') {
                        sh '''
                            cd /var/www/html
                            git checkout feature
                            git pull origin feature
                        '''
                    }
                }
            }
        }
    }
}
```

### Versión más defensiva — agregando validación + error explícito

```groovy
pipeline {
    agent { label 'stapp01' }

    parameters {
        string(name: 'BRANCH', defaultValue: 'master', description: 'Branch a desplegar')
    }

    stages {
        stage('Deploy') {
            steps {
                script {
                    def validBranches = ['master', 'feature']
                    if (!validBranches.contains(params.BRANCH)) {
                        error("Branch inválido: ${params.BRANCH}. Permitidos: ${validBranches}")
                    }

                    sh """
                        cd /var/www/html
                        git checkout ${params.BRANCH}
                        git pull origin ${params.BRANCH}
                    """
                }
            }
        }
    }
}
```

Diferencias respecto a la versión del lab:

- Falla rápido con mensaje claro si el branch es inválido
- Sin código duplicado entre `master` y `feature`
- Mismo nivel de seguridad — el `error()` aborta antes de llegar al `sh`

### Versión idiomática para más branches (referencia, no aplica al lab estricto)

Si el lab no exigiera "una sola stage llamada Deploy", la forma más Pipeline-idiomática sería con `when`:

```groovy
pipeline {
    agent { label 'stapp01' }
    parameters {
        choice(name: 'BRANCH', choices: ['master', 'feature'], description: 'Branch a desplegar')
    }
    stages {
        stage('Deploy master') {
            when { expression { params.BRANCH == 'master' } }
            steps {
                sh '''
                    cd /var/www/html
                    git checkout master
                    git pull origin master
                '''
            }
        }
        stage('Deploy feature') {
            when { expression { params.BRANCH == 'feature' } }
            steps {
                sh '''
                    cd /var/www/html
                    git checkout feature
                    git pull origin feature
                '''
            }
        }
    }
}
```

> Esta versión rompe el requirement del lab ("una sola stage") pero es lo que se vería en producción real.

### Disparar el build con un parámetro

Primera vez después de crear el job:

```
Job → Build Now (sin parámetros — Jenkins registra los params)
```

Segunda vez en adelante:

```
Job → Build with Parameters
  BRANCH: [master/feature] → Build
```

### Log esperado — build con `BRANCH=master`

```
Started by user admin
[Pipeline] Start of Pipeline
[Pipeline] node
Running on App Server 1 in /home/sarah/jenkins_agent/workspace/nautilus-webapp-job
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Deploy)
[Pipeline] script
[Pipeline] {
[Pipeline] sh
+ cd /var/www/html
+ git checkout master
Already on 'master'
Your branch is up to date with 'origin/master'.
+ git pull origin master
From http://gitea:3000/sarah/web_app
 * branch            master     -> FETCH_HEAD
Already up to date.
[Pipeline] }
[Pipeline] // script
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS
```

Detalles a notar:

| Línea                              | Significado                                                           |
| ---------------------------------- | --------------------------------------------------------------------- |
| `[Pipeline] script`                | Inicio del bloque `script { }` — Groovy puro                          |
| `[Pipeline] sh`                    | Inicio del comando shell                                              |
| `+ cd /var/www/html`               | `set -x` del shell (echo de cada comando)                             |
| `Already on 'master'`              | El branch local ya estaba en master                                    |
| `Already up to date.`              | No había commits nuevos para traer                                    |
| `[Pipeline] // script`             | Fin del bloque `script { }`                                           |
| `[Pipeline] // stage`              | Fin de la stage Deploy                                                |

### Log con `BRANCH=feature` (primer cambio real)

```
+ cd /var/www/html
+ git checkout feature
Branch 'feature' set up to track remote branch 'feature' from 'origin'.
Switched to a new branch 'feature'
+ git pull origin feature
From http://gitea:3000/sarah/web_app
 * branch            feature    -> FETCH_HEAD
Updating abc1234..def5678
Fast-forward
 index.html | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
Finished: SUCCESS
```

> `Switched to a new branch 'feature'` indica que el branch feature **no existía localmente** (solo en remoto). Git lo creó como tracking branch. La próxima vez ya está local y solo dice `Switched to branch 'feature'`.

### Validación funcional

```bash
# Con BRANCH=master desplegado
curl https://<lab-id>:8091/
# (contenido del branch master)

# Con BRANCH=feature desplegado
curl https://<lab-id>:8091/
# (contenido del branch feature, distinto si los archivos cambiaron)
```

## Anatomía — ciclo de vida del param en runtime

```
1. User dispara "Build with Parameters" → BRANCH=feature
                  │
                  ▼
2. Jenkins crea el build, inyecta BRANCH como:
     - params.BRANCH en Groovy
     - env BRANCH en el shell
                  │
                  ▼
3. Pipeline arranca en agent stapp01
                  │
                  ▼
4. stage('Deploy') → steps → script { }
                  │
                  ▼
5. Groovy evalúa: if (params.BRANCH == 'master') → false
                  if (params.BRANCH == 'feature') → true
                  │
                  ▼
6. Ejecuta el sh '''cd ... git checkout feature ... '''
                  │
                  ▼
7. Shell ejecuta los comandos en /var/www/html del agent (que es stapp01)
                  │
                  ▼
8. Archivos del filesystem cambian (al branch feature)
                  │
                  ▼
9. Apache (corriendo en stapp01:8080) sirve los archivos nuevos
                  │
                  ▼
10. LB (en :8091) recibe requests del proxy KodeKloud y los reenvía a Apache
```

## Conexión con días anteriores

- **Día 72 (Parameterized Builds Freestyle)**: introdujo String + Choice parameters en jobs Freestyle. Hoy es el equivalente Pipeline — misma idea, sintaxis Groovy en lugar de UI.
- **Día 77 (Deploy Pipeline)**: la base — primer Declarative Pipeline. Hoy agrega `parameters` + `script { if/else }`.
- **Día 24-25 (Git branches + workflow)**: el `git checkout` + `git pull` por branch es lo que se vio entonces, ahora automatizado en un job.
- **Día 73 (Scheduled Jobs)**: cron sin parámetros. Hoy con parámetros pero sin cron. Cualquier combinación es posible — un Pipeline puede tener cron + parameters + Multi-stage.
- **Día 74 (Database Backup)**: Credential binding en Freestyle. En Pipeline el equivalente es `withCredentials([string(credentialsId: 'X', variable: 'MY_VAR')])` — patrón que va a aparecer en próximos labs.

## Reflexión: el balance entre simplicidad y seguridad en pipelines parametrizados

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- Las tres formas (if/else, when, parametrización directa) — ¿cuál se siente más natural? La del lab (Forma 1) es más defensiva pero verbosa; la Forma 3 es elegante pero peligrosa.
- El `script { }` block como "escape hatch" de Declarative: ¿solución limpia o señal de que Declarative se queda corto?
- Shell injection risk con `${params.X}` interpolado al shell — ¿algo que tenías presente o nuevo? ¿En qué otros contextos aplica (curl con URL parameters, SQL, Docker build args)?
- Choice parameter (Día 72) vs String parameter + validación (este lab) — ¿cuál es la mejor herramienta para forzar valores válidos?
- El primer Build Now después de crear un pipeline parametrizado no muestra los params — ¿UX bug o limitación intencional?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `WorkflowScript: ... Expected a step` al usar `if/else` directo         | `if/else` Groovy no funciona dentro de `steps { }` — necesita `script { }`                            | Envolver el if/else en `script { ... }`                                                           |
| El primer Build Now no muestra el botón "Build with Parameters"          | Jenkins necesita correr el pipeline una vez para registrar los parámetros declarados                  | Hacer Build Now la primera vez; a partir del segundo aparece "Build with Parameters"              |
| `params.BRANCH` evalúa a `null` o vacío                                  | El nombre del parámetro en el script no matchea el declarado en `parameters { }` (case-sensitive)    | Verificar que `name: 'BRANCH'` coincida con `params.BRANCH`                                       |
| Pipeline pasa con cualquier BRANCH (incluido inválido) pero no hace nada | La Forma 1 (if/else explícito) ignora valores no listados — comportamiento esperado                  | Para fallar explícitamente, agregar `else { error("Branch inválido") }`                          |
| `git checkout feature` falla con "did not match any file(s)"           | El branch `feature` no existe en el remoto o no está fetcheado localmente                            | `git fetch --all` antes; o crear el branch en Gitea primero                                       |
| El sitio no cambia entre builds master y feature                         | Los dos branches tienen el mismo `index.html` — git pull no encuentra diferencias                    | Editar el `index.html` en Gitea (branch feature) para que tenga contenido distinto               |
| `Already on 'master'` se imprime aunque pediste feature                 | El `git checkout master` corre primero (caso master) — el log muestra el primer caso del if/else    | Comportamiento esperado del shell — el log refleja exactamente lo ejecutado                       |
| El job no respeta el case del parámetro (`MASTER` vs `master`)           | Groovy `==` es case-sensitive — `'MASTER' != 'master'`                                                | Normalizar el input con `.toLowerCase()` antes de comparar, o usar Choice parameter              |
| Shell injection cuando se usa `${params.BRANCH}` directo                | El user puede pasar input arbitrario en un String parameter                                          | Cambiar a Choice parameter, o validar explícitamente con `if (!validList.contains(...))`         |
| `Pipeline` script accede a `BRANCH` sin `params.` y funciona            | Jenkins también inyecta los params como variables Groovy de top-level (legacy support)                | Conviene siempre usar `params.<NAME>` para ser explícito sobre el origen del valor               |

## Recursos

- [Pipeline `parameters` directive (oficial)](https://www.jenkins.io/doc/book/pipeline/syntax/#parameters)
- [`script` block in Declarative](https://www.jenkins.io/doc/book/pipeline/syntax/#script)
- [`when` directive](https://www.jenkins.io/doc/book/pipeline/syntax/#when)
- [Pipeline best practices](https://www.jenkins.io/doc/book/pipeline/pipeline-best-practices/)
- [Shell injection in Jenkins Pipelines](https://www.jenkins.io/doc/book/security/groovy-sandbox/) — sandbox de Groovy y limitaciones
- [Parameterized Pipelines (tutorial)](https://www.jenkins.io/doc/book/pipeline/syntax/#parameters)
