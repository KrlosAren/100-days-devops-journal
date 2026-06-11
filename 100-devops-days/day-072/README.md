# Día 72 - Jenkins Parameterized Builds (String + Choice Parameter)

## Problema / Desafío

El equipo Nautilus quiere validar que un nuevo DevOps engineer entienda los **parameterized builds** de Jenkins antes de asignarle tareas reales. La tarea: crear un job con dos parámetros distintos y un build step que los imprima.

Requirements:

1. Login a la UI de Jenkins como `admin` / `Adm!n321`
2. Crear job **`parameterized-job`** (Freestyle, parametrizado)
3. Agregar **String Parameter** llamado `Stage` con default `Build`
4. Agregar **Choice Parameter** llamado `env` con choices `Development`, `Staging`, `Production`
5. Build step "Execute shell" que haga `echo` de ambos valores
6. Buildear al menos una vez con `env=Production` para validar

Lab corto pero introduce el **segundo tipo de parámetro** del journal (después del String del Día 71).

## Conceptos clave

### Recap: tipos de parámetros en Jenkins

| Tipo                  | Cuándo usar                                                                                   |
| --------------------- | --------------------------------------------------------------------------------------------- |
| **String**            | Texto libre — Día 71 (`PACKAGE=vim-enhanced`), hoy también para `Stage`                       |
| **Choice**            | Lista predefinida de valores — hoy, para `env` (Development / Staging / Production)           |
| **Boolean**           | `true`/`false` — flags como `RUN_TESTS`, `SKIP_DEPLOY`                                        |
| **Password**          | Como String pero el valor queda **enmascarado** en logs                                       |
| **File**              | Sube un archivo al workspace antes del build                                                  |
| **Multiline String**  | Texto multilínea (configs, scripts)                                                           |
| **Credentials**       | Dropdown que apunta a un Credential del Credentials Manager                                   |

### String vs Choice — cuándo elegir cada uno

| Aspecto                          | String Parameter                                      | Choice Parameter                                              |
| -------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------- |
| Forma en la UI al disparar build | Input de texto libre                                  | Dropdown con valores predefinidos                             |
| Validación                       | Ninguna — el operador puede ingresar cualquier cosa   | Solo acepta valores de la lista                               |
| Default value                    | Configurable explícitamente                            | **La primera línea** del campo `Choices` es el default        |
| Casos típicos                    | Nombres de paquetes, branches, commit SHAs, paths     | Environments (`dev`/`staging`/`prod`), regiones AWS, tipos de deploy |
| Riesgo de typo                   | Alto — el operador puede escribir `prodcution`        | Cero — el dropdown solo muestra opciones válidas              |

Regla práctica: **Choice cuando el universo de valores es finito y conocido**, String cuando es abierto o el operador puede necesitar valores arbitrarios.

### Cómo Jenkins inyecta los parámetros al shell

Cuando un job se ejecuta, **cada parámetro se exporta como variable de entorno** con el mismo nombre. Para este lab:

```bash
# Equivalente a lo que Jenkins hace antes de ejecutar el build step
export Stage="Build"
export env="Production"
/bin/sh -xe /tmp/jenkins<id>.sh
```

Dentro del script, los parámetros se acceden como `$Stage` y `$env` (notación de bash). El comando del lab:

```bash
echo "stage=$Stage env=$env"
```

Después de la substitución:

```bash
echo "stage=Build env=Production"
```

Y el output:

```
stage=Build env=Production
```

> Bash es **case-sensitive**: `$Stage` y `$stage` son variables distintas. El parámetro se llamó `Stage` con mayúscula, así que `$stage` daría vacío.

### Por qué encerrar entre comillas: `"$Stage"`

| Forma                             | Comportamiento                                                          |
| --------------------------------- | ----------------------------------------------------------------------- |
| `echo $Stage - $env`              | Si `$Stage = "foo bar"`, el shell separa en `foo` y `bar` (word splitting) |
| `echo "stage=$Stage env=$env"`    | Las comillas preservan el valor exacto                                  |
| `echo 'stage=$Stage'`             | Comilla simple — **no hace substitución**, imprime literal `$Stage`     |

Para este lab no hace diferencia funcional (los valores no tienen espacios), pero la forma con comillas dobles es la **buena práctica defensiva**.

### Choice Parameter — anatomía del campo `Choices`

El campo es un textarea que acepta **una opción por línea**:

```
Development
Staging
Production
```

Reglas:

- La **primera línea** es el default. Si el operador no toca el dropdown, ese es el valor del build
- Líneas vacías son ignoradas
- No hay forma nativa de marcar otra línea como default (la primera siempre gana)
- Para reordenar, hay que editar el textarea — el dropdown respeta el orden de las líneas

> **Pitfall del lab**: el lab pide buildear con `env=Production`. Como `Development` es el default (primera línea), hay que **cambiar el dropdown** explícitamente al disparar el build. Si se hace click en Build sin tocarlo, corre con Development y el validador puede marcar el lab como incorrecto.

### `Trim the string` — qué hace

Checkbox que aparece **solo en String Parameter**. Si está marcado, Jenkins elimina whitespace al inicio y final del valor antes de ejecutarlo. Útil cuando el operador pega un valor con un espacio sobrante (común al copiar/pegar nombres desde otro sitio).

Para Choice Parameter no aplica — los valores vienen de la lista predefinida, ya están "limpios".

### El log del build — leer cada línea

```
Started by user admin
Running as SYSTEM
Building in workspace /var/lib/jenkins/workspace/parameterized-job
[parameterized-job] $ /bin/sh -xe /tmp/jenkins14172350960991223659.sh
+ echo stage=Build env=Production
stage=Build env=Production
Finished: SUCCESS
```

| Línea                                                | Significado                                                                  |
| ---------------------------------------------------- | ---------------------------------------------------------------------------- |
| `Started by user admin`                              | Quién disparó el build manualmente                                           |
| `Running as SYSTEM`                                  | Identity context interno (no es el UID del SO — ese es `jenkins`)            |
| `Building in workspace .../parameterized-job`        | Workspace scratch del job — vacío para este job porque no genera archivos    |
| `/bin/sh -xe /tmp/jenkins<id>.sh`                    | Script temporal generado dinámicamente, ejecutado con `-x` (echo) y `-e` (abort on error) |
| `+ echo stage=Build env=Production`                  | El `+` es output de `set -x` — muestra el comando con variables ya expandidas |
| `stage=Build env=Production`                         | El output real del `echo`                                                    |
| `Finished: SUCCESS`                                  | Exit code del shell fue 0                                                    |

## Pasos

1. Login como `admin` / `Adm!n321`
2. Dashboard → New Item → nombre `parameterized-job` → Freestyle project → OK
3. En la página de configuración, marcar **"This project is parameterized"**
4. Add Parameter → **String Parameter**:
   - Name: `Stage`
   - Default Value: `Build`
   - Description: (opcional)
5. Add Parameter → **Choice Parameter**:
   - Name: `env`
   - Choices: `Development` / `Staging` / `Production` (uno por línea)
6. Build Steps → Add build step → **Execute shell**
7. Command: `echo "stage=$Stage env=$env"`
8. Save
9. Build with Parameters → cambiar el dropdown `env` a **Production** → Build
10. Verificar el Console Output que aparezca `Finished: SUCCESS`

## Comandos / Código

### Configuración del String Parameter

| Campo            | Valor               |
| ---------------- | ------------------- |
| Name             | `Stage`             |
| Default Value    | `Build`             |
| Description      | `Stage build env`   |
| Trim the string  | (opcional)          |

### Configuración del Choice Parameter

| Campo        | Valor                                            |
| ------------ | ------------------------------------------------ |
| Name         | `env`                                            |
| Choices      | `Development` <br> `Staging` <br> `Production`   |
| Description  | (opcional)                                       |

> El campo `Choices` es un textarea. Cada línea es una opción. La primera línea (`Development`) es el default.

### Build step

```bash
echo "stage=$Stage env=$env"
```

> Alternativa más explícita que también funciona:
>
> ```bash
> echo "Stage parameter: $Stage"
> echo "Env parameter: $env"
> ```

### Disparar el build

Navegación: `Job parameterized-job → Build with Parameters`

| Campo  | Valor          |
| ------ | -------------- |
| Stage  | `Build` (default — dejar como está) |
| env    | `Production` (cambiar desde el default `Development`) |

Click **Build**.

### Log esperado del Console Output

```
Started by user admin
Running as SYSTEM
Building in workspace /var/lib/jenkins/workspace/parameterized-job
[parameterized-job] $ /bin/sh -xe /tmp/jenkins14172350960991223659.sh
+ echo stage=Build env=Production
stage=Build env=Production
Finished: SUCCESS
```

### Variantes útiles del shell command (referencia)

```bash
# Versión simple
echo "$Stage $env"

# Formato key=value (lo del lab)
echo "stage=$Stage env=$env"

# Con prefijo descriptivo
echo "Running stage [$Stage] in environment [$env]"

# Validar que ambos vienen seteados
if [ -z "$Stage" ] || [ -z "$env" ]; then
  echo "ERROR: missing parameters" >&2
  exit 1
fi
echo "stage=$Stage env=$env"

# Lógica condicional según el env (Choice Parameter en switch)
case "$env" in
  Development) echo "Deploying to dev — skipping smoke tests" ;;
  Staging)     echo "Deploying to staging — running smoke tests" ;;
  Production)  echo "Deploying to prod — full test suite + manual approval" ;;
  *)           echo "Unknown env: $env" >&2; exit 1 ;;
esac
```

## Anatomía del filesystem

`/var/lib/jenkins/jobs/parameterized-job/config.xml` contiene la definición. Bloque relevante:

```xml
<project>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>Stage</name>
          <description>Stage build env</description>
          <defaultValue>Build</defaultValue>
          <trim>false</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.ChoiceParameterDefinition>
          <name>env</name>
          <description></description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>Development</string>
              <string>Staging</string>
              <string>Production</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <builders>
    <hudson.tasks.Shell>
      <command>echo &quot;stage=$Stage env=$env&quot;</command>
    </hudson.tasks.Shell>
  </builders>
</project>
```

Para automatizar con Jenkins Configuration as Code (JCasC) o crear muchos jobs similares por API, este XML es la fuente de verdad.

## Conexión con días anteriores

- **Día 71 (Jenkins Job: Package Installation)**: introdujo String Parameter + Execute shell. Hoy se agrega Choice Parameter como segundo tipo de parámetro. Mismo flow general.
- **Día 68 (Set Up Jenkins Server)**: el `JENKINS_HOME` donde aterriza el `config.xml` del job.
- **Día 70 (User Access)**: el user `admin` que aparece en `Started by user admin` es el creado en el wizard. Si `anita` también pudiera disparar este job, su nombre aparecería en lugar de admin.
- **Día 57 (env vars + `$(VAR)` substitution en K8s)**: el patrón de **inyectar valores a un proceso vía env vars** es el mismo. Diferencia: en K8s las env vars vienen de `valueFrom` (ConfigMap/Secret); en Jenkins vienen del parámetro del job. La sintaxis de la shell para consumirlas es idéntica (`$VAR` o `${VAR}`).
- **Días 21-34 (Git workflow)**: en próximos labs, el Choice Parameter probablemente se reemplazará por la **lista de branches** del repo (vía Multibranch Pipeline o el plugin Git Parameter). Hoy es el primer paso.

## Reflexión: el rol de los parámetros en CI/CD

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- Choice vs String: ¿qué patrón se anticipa usar más en producción real? ¿La validación que da Choice compensa la rigidez (cada valor nuevo requiere editar el job)?
- El detalle del `Stage` con mayúscula vs `env` en minúsculas: ¿convención válida o un naming inconsistente que en producción rompería un Jenkinsfile complejo? ¿Convendría una convención uniforme (todo MAYÚSCULAS_SNAKE_CASE como env vars POSIX)?
- Comparación con CLI: el mismo build se podría disparar con `curl -X POST .../buildWithParameters?Stage=Build&env=Production`. ¿La UI con dropdowns es más segura o solo más cómoda?
- Los parámetros como interfaz pública del job: ¿conviene pensar los jobs como "funciones" con su signature de parámetros? ¿O más como scripts ad-hoc?
- En GitHub Actions / GitLab CI los parámetros equivalentes son `workflow_dispatch.inputs` y `pipeline.parameters`. ¿Te resulta más estructurado tenerlos en YAML versionado vs en la UI de Jenkins?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| El output del echo muestra vacío para una variable                       | Typo o case mismatch en el nombre (`$stage` vs `$Stage`)                                            | Bash es case-sensitive — usar el nombre exacto del parámetro                                      |
| El validador del lab marca el build como incorrecto                      | Se disparó con `env=Development` (default) en lugar de `Production`                                  | Build with Parameters → cambiar el dropdown a `Production` antes de hacer Build                  |
| El dropdown `env` muestra solo `Development` (sin Staging/Production)   | El campo Choices tiene solo una línea, o las otras están comentadas / con whitespace                 | Verificar el textarea: una línea por opción, sin líneas vacías                                    |
| Build dispara pero el job no aparece como parametrizado                 | Se olvidó marcar **"This project is parameterized"** al crear el job                                 | Configure del job → marcar el checkbox → Save → reintentar Build with Parameters                  |
| Comando del echo aparece vacío en el log                                 | El shell evaluó las variables a vacío porque no se llamaron desde Build with Parameters             | Disparar siempre desde **Build with Parameters**, no desde "Build now" (que usa defaults)         |
| `Stage` aparece con espacio o caracteres extras                          | El operador ingresó valor con whitespace y `Trim the string` no está marcado                         | Marcar `Trim the string` en la config del String Parameter                                       |
| Choice Parameter no respeta el orden definido en el textarea            | El textarea tiene espacios o caracteres invisibles al inicio de algunas líneas                       | Editar el textarea cuidadosamente; verificar con vista previa                                     |
| `Build with Parameters` no aparece en el menú del job                    | El job no está marcado como parametrizado                                                            | Configure → marcar **"This project is parameterized"** → agregar al menos un parámetro            |
| Los parámetros se mantienen del build anterior                          | Comportamiento esperado — Jenkins recuerda los últimos valores como "next default"                   | No es bug. Si molesta, los defaults siempre se pueden restaurar en la UI                          |
| Build pasa pero el log no muestra el output esperado                    | El comando shell tiene un typo o el step no es "Execute shell"                                       | Revisar la config del job; verificar que el Build Step sea "Execute shell" con el command correcto |

## Recursos

- [Parameterized Builds (oficial)](https://www.jenkins.io/doc/book/pipeline/syntax/#parameters)
- [Choice Parameter (Plugin docs)](https://plugins.jenkins.io/build-with-parameters/)
- [Triggering builds remotely via API](https://www.jenkins.io/doc/book/using/remote-access-api/)
- [Jenkinsfile parameters (Pipeline equivalent)](https://www.jenkins.io/doc/book/pipeline/syntax/#parameters)
- [Bash variable expansion (referencia)](https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html)
