# Día 70 - Configure Jenkins User Access (Matrix Authorization Strategy)

## Problema / Desafío

El equipo Nautilus está integrando Jenkins a sus pipelines CI/CD. Hay que configurar el acceso para el equipo de desarrollo — específicamente, agregar a la usuaria `anita` con permisos restringidos sobre Jenkins en general y sobre un job existente.

Requirements:

1. Login a la UI de Jenkins como `admin` / `Adm!n321`
2. Crear el user `anita` con password `LQfKeWWxWD` y full name `Anita`
3. Cambiar la estrategia de autorización a **Project-based Matrix Authorization Strategy** y asignar a `anita` permiso **Overall: Read**
4. **Eliminar todos los permisos** para Anonymous (y Authenticated Users), manteniendo `admin` con **Overall: Administer**
5. Para el job existente, asignar a `anita` **solo Read** sobre ese proyecto específico (ignorando Agent, SCM, etc.)

Nota: la estrategia "Project-based Matrix Authorization Strategy" **no viene preinstalada** — requiere instalar el plugin **Matrix Authorization Strategy** primero.

## Conceptos clave

### Authorization Strategies en Jenkins — qué opciones hay

Jenkins separa **autenticación** (¿quién es?) de **autorización** (¿qué puede hacer?). Para autorización, ofrece varias estrategias en `Manage Jenkins → Security → Authorization`:

| Estrategia                                          | Granularidad                                              | Cuándo usar                                                |
| --------------------------------------------------- | --------------------------------------------------------- | ---------------------------------------------------------- |
| **Anyone can do anything**                          | Sin restricciones                                          | Demos locales — **nunca producción**                       |
| **Legacy mode**                                     | admin = todo, demás = read                                | Compatibilidad con Jenkins muy viejo                       |
| **Logged-in users can do anything** *(default)*     | Cualquier user autenticado tiene Administer               | Setup inicial, single-tenant pequeño                       |
| **Matrix-based security** *(plugin)*                | Matriz global única por user/grupo                        | Multi-user con permisos diferenciados, sin per-project     |
| **Project-based Matrix Authorization Strategy** *(plugin)* | Matriz global **+** matrices por proyecto              | Multi-tenant — cada equipo tiene su job y permisos propios |
| **Role-Based Strategy** *(otro plugin)*             | Roles reutilizables asignables a users                    | Organizaciones grandes con muchos jobs y users             |

Hoy el lab usa la **cuarta opción habilitada con plugin**: Project-based Matrix Authorization Strategy.

### El plugin Matrix Authorization Strategy

| Detalle             | Valor                                                                              |
| ------------------- | ---------------------------------------------------------------------------------- |
| ID del plugin       | `matrix-auth`                                                                       |
| Versión observada   | `3.2.10`                                                                            |
| Tags                | Security, Authentication and User Management                                        |
| Qué agrega          | Las dos opciones `Matrix-based security` y `Project-based Matrix Authorization Strategy` en el dropdown de Authorization |

Sin el plugin instalado, solo aparecen las estrategias built-in del core (`Anyone`, `Legacy`, `Logged-in`).

### Las 6 categorías de permisos en el matrix

Cuando se selecciona "Project-based Matrix Authorization Strategy", aparece una **tabla** con users/grupos en filas y permisos en columnas. Los permisos están agrupados en 6 categorías:

| Categoría     | Permisos típicos                                                       | Para qué                                                                       |
| ------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **Overall**   | `Administer`, `Read`, `RunScripts`, `UploadPlugins`, `ConfigureUpdateCenter`, `ManageDomains` | Permisos a nivel Jenkins global                                                |
| **Agent**     | `Build`, `Configure`, `Connect`, `Create`, `Delete`, `Disconnect`, `Provision` | Gestión de agents/nodos                                                        |
| **Job**       | `Build`, `Cancel`, `Configure`, `Create`, `Delete`, `Discover`, `Read`, `Workspace` | CRUD de jobs                                                                   |
| **Run**       | `Delete`, `Update`, `Replay`                                            | Builds individuales (instancias de jobs)                                       |
| **View**      | `Configure`, `Create`, `Delete`, `Read`                                | Vistas (carpetas/dashboards que agrupan jobs)                                  |
| **SCM**       | `Tag`                                                                   | Operaciones de SCM (típicamente tagging después de un release)                 |

Los más importantes para este lab:

- **Overall: Administer** = master switch, implica todos los demás
- **Overall: Read** = mínimo necesario para ver la UI de Jenkins (sin esto el user no puede ni hacer login funcionalmente)
- **Job: Read** = permite ver el job en la lista y consultar su historial; sin esto el job ni aparece

### Implicit permissions y la trampa del Administer

Marcar **Overall: Administer** implica automáticamente todos los demás permisos en cualquier categoría — no hace falta marcar individualmente Job:Build, Agent:Connect, etc. Pero la inversa **no es cierta**: marcar Job:Build no implica Overall:Read; si el user no tiene Overall:Read, ni siquiera puede llegar a la UI para ver el job.

> **Regla práctica**: cualquier user que vaya a usar la UI debe tener **al menos Overall:Read**. Después se le agregan permisos específicos.

### Matriz global vs matriz por proyecto — la distinción clave

Esta es la diferencia entre "Matrix-based security" y "Project-based Matrix Authorization Strategy":

| Estrategia                                          | Matrices                                                                                  |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| **Matrix-based security**                           | Una sola matriz **global**. Lo que se asigna ahí aplica a todo Jenkins                    |
| **Project-based Matrix Authorization Strategy**     | Matriz **global** + matrices adicionales por job (configurable en cada job individual)    |

Para este lab:

- **Matriz global** (en `Manage Jenkins → Security`): `anita` recibe `Overall: Read`
- **Matriz por proyecto** (en el job existente → Configure → Enable project-based security): `anita` recibe `Job: Read`

Sin la matriz por proyecto, `anita` tendría **Read sobre Jenkins** pero **no podría ver el job** (porque por default los jobs heredan "deny" para todos los users que no estén explícitamente listados).

### Anonymous vs Authenticated Users (entender bien)

Dos "users especiales" aparecen siempre en la matriz:

| Entrada               | Quién es                                                                                  |
| --------------------- | ----------------------------------------------------------------------------------------- |
| **Anonymous**         | Cualquiera que acceda a la UI **sin login**                                                |
| **Authenticated Users** | Cualquier user logueado (no aplica solo a un user específico)                              |

El lab pide remover **todos los permisos para Anonymous**. Antes del plugin, había un checkbox separado `Allow anonymous read access` (visible en screenshot 33) — con el plugin esto se traslada a la fila `Anonymous` de la matriz.

> **Pitfall**: si `Authenticated Users` tiene permisos, **todos** los users autenticados los reciben automáticamente. Para granularidad fina, hay que dejar esa fila vacía y asignar permisos por user.

### Riesgo de lock-out (el peligro real de este lab)

Si al guardar la matriz **no se le asigna `Overall: Administer` a `admin`**, el user `admin` pierde el acceso administrativo y queda imposible cambiar la config desde la UI. La única recuperación:

1. SSH al server
2. Editar `/var/lib/jenkins/config.xml`
3. Buscar el bloque `<authorizationStrategy>` y reemplazarlo por `<authorizationStrategy class="hudson.security.AuthorizationStrategy$Unsecured"/>`
4. `sudo service jenkins restart`
5. Volver a configurar todo desde cero

Por eso el orden seguro es:

1. **Antes** de cambiar la estrategia: confirmar que `admin` está en la lista de users
2. **Al cambiar la estrategia**: marcar `Administer` para `admin` antes de hacer Save
3. **Hacer Save**: verificar que el login con `admin` sigue funcionando antes de cerrar la sesión

## Pasos

1. Login como `admin` / `Adm!n321`
2. Crear user `anita` en `Manage Jenkins → Users → Create User`
3. Instalar plugin Matrix Authorization Strategy en `Manage Jenkins → Plugins → Available`, con restart
4. Esperar a que vuelva el login
5. Login de nuevo como `admin`
6. Cambiar la estrategia en `Manage Jenkins → Security → Authorization` a `Project-based Matrix Authorization Strategy`
7. En la matriz global:
   - Marcar `Overall: Administer` para `admin`
   - Marcar `Overall: Read` para `Anita`
   - Dejar `Anonymous` y `Authenticated Users` sin permisos
8. **Save** (validar que admin sigue pudiendo entrar)
9. Ir al job existente → `Configure` → Enable project-based security
10. Agregar `Anita` a la matriz del job con `Job: Read`
11. Save y validar logueando como `anita` que ve el job pero no puede modificarlo

## Comandos / Código

### 1. Crear el user `anita`

Navegación:

```
Manage Jenkins → Users → Create User
```

Form:

| Campo            | Valor          |
| ---------------- | -------------- |
| Username         | `anita`        |
| Password         | `LQfKeWWxWD`   |
| Confirm password | `LQfKeWWxWD`   |
| Full name        | `Anita`        |

> El password se almacena hasheado en `/var/lib/jenkins/users/anita_<random-id>/config.xml`. Jenkins usa bcrypt para los hashes.

### 2. Instalar el plugin Matrix Authorization Strategy

Navegación:

```
Manage Jenkins → Plugins → Available plugins
```

Filtro: `matrix a` (o `matrix authorization`)

Resultado esperado:

```
Matrix Authorization Strategy   3.2.10
Tags: Security, Authentication and User Management
Offers matrix-based security authorization strategies (global and per-project).
```

Marcar checkbox → click **Install** → marcar **"Restart Jenkins when installation is complete and no jobs are running"** → esperar al restart.

### 3. Cambiar la estrategia de autorización

Navegación:

```
Manage Jenkins → Security → Authorization
```

Estado previo (según screenshot 33):

```
Authorization: Logged-in users can do anything
[x] Allow anonymous read access
```

Cambiar el dropdown a **`Project-based Matrix Authorization Strategy`**. Al hacerlo, aparece la matriz con tres filas por default:

- `Anonymous` — todos los checkboxes vacíos
- `Authenticated Users` — todos los checkboxes vacíos
- (otros — vacío)

### 4. Agregar `admin` y `Anita` a la matriz global

Click **Add user...** → ingresar `admin` → confirmar.
Click **Add user...** → ingresar `Anita` → confirmar.

Estado de checkboxes esperado (matriz **global**, paso 3 del lab):

| User / Permiso          | Overall: Administer | Overall: Read | Resto |
| ----------------------- | ------------------- | ------------- | ----- |
| Anonymous               | ❌                  | ❌            | ❌    |
| Authenticated Users     | ❌                  | ❌            | ❌    |
| admin                   | ✅                  | (implícito)   | (implícito por Administer) |
| Anita                   | ❌                  | ✅            | ❌    |

> El `Overall: Administer` del admin **incluye implícitamente** todos los demás permisos. No hace falta marcarlos individualmente.

Click **Save** al final de la página.

> **Validación crítica antes de cerrar la sesión**: abrir un browser incógnito y verificar que `admin` puede loguearse y acceder a `/manage`. Si falla, hay que editar `/var/lib/jenkins/config.xml` desde SSH para recuperar el acceso.

### 5. Matriz por proyecto (Job → Configure)

Navegación al job existente:

```
Dashboard → <nombre-del-job> → Configure
```

Buscar la sección **"Enable project-based security"** y activarla. Aparece una segunda matriz, equivalente a la global pero **scoped solo a este job**.

Click **Add user...** → ingresar `Anita`. Marcar **únicamente** `Job: Read`.

Estado de checkboxes (matriz **del job**, paso 5 del lab):

| User / Permiso         | Overall: Read | Job: Read | Job: Build | View: Read | Resto |
| ---------------------- | ------------- | --------- | ---------- | ---------- | ----- |
| Anita                  | (heredado de global) | ✅       | ❌         | (opcional) | ❌    |

> El lab pide **disregard other permissions** — significa NO marcar Job: Build, Configure, Workspace, etc. Solo Read.

Click **Save**.

### 6. Validación funcional

Logout de admin. Login como `anita` con password `LQfKeWWxWD`.

Resultado esperado:

- Anita ve el dashboard de Jenkins (gracias al `Overall: Read` global)
- Anita ve el job en la lista (gracias al `Job: Read` del proyecto)
- Anita **no** ve el botón "Build Now" (no tiene `Job: Build`)
- Anita **no** puede entrar a "Configure" del job
- Anita **no** ve `Manage Jenkins` en el menú (no tiene `Overall: Administer`)

## Anatomía del filesystem — dónde queda guardada esta config

| Archivo                                                          | Qué contiene                                                              |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `/var/lib/jenkins/config.xml`                                    | Estrategia de autorización + matriz global                                |
| `/var/lib/jenkins/users/anita_<random-id>/config.xml`           | Datos del user `anita` (full name, email, password hash)                  |
| `/var/lib/jenkins/jobs/<job-name>/config.xml`                    | Config del job, incluyendo la matriz por-proyecto                          |
| `/var/lib/jenkins/plugins/matrix-auth.jpi`                       | El plugin instalado                                                       |

Bloque relevante de `/var/lib/jenkins/config.xml` después del save:

```xml
<authorizationStrategy class="hudson.security.ProjectMatrixAuthorizationStrategy">
  <permission>hudson.model.Hudson.Administer:admin</permission>
  <permission>hudson.model.Hudson.Read:Anita</permission>
</authorizationStrategy>
```

> El formato es `<permiso>:<user>`. Cada permiso es una entrada separada.

## Validación por filesystem (sin pasar por UI)

```bash
sudo cat /var/lib/jenkins/config.xml | grep -A 5 'authorizationStrategy'
```

```bash
sudo cat /var/lib/jenkins/jobs/<job-name>/config.xml | grep -A 5 'AuthorizationMatrixProperty'
```

Esto es útil cuando hay que automatizar la config con JCasC o Ansible — la fuente de verdad es el XML.

## Recuperación de un lock-out (referencia, no aplica si todo salió bien)

Si en el paso 4 se hace Save sin haber marcado `Overall: Administer` para `admin`:

1. Cerrar la sesión del browser inmediatamente
2. SSH al server: `ssh root@jenkins`
3. Editar `/var/lib/jenkins/config.xml`:

```bash
sudo vim /var/lib/jenkins/config.xml
```

4. Reemplazar el bloque `<authorizationStrategy>` por:

```xml
<authorizationStrategy class="hudson.security.AuthorizationStrategy$Unsecured"/>
```

5. Reiniciar el servicio:

```bash
sudo service jenkins restart
```

6. Volver al UI — ahora cualquier user (incluido admin) tiene Administer.
7. Repetir el flujo del lab, esta vez marcando admin antes de Save.

## Conexión con días anteriores

- **Día 68 (Set Up Jenkins Server)**: el `JENKINS_HOME` es el filesystem donde se guarda toda la config de hoy. `/var/lib/jenkins/config.xml` es el archivo que define la estrategia de autorización.
- **Día 69 (Install Jenkins Plugins)**: mismo flujo del plugin manager. La diferencia: el plugin de hoy (Matrix Authorization Strategy) **modifica el comportamiento del core** — agrega opciones al dropdown de Authorization. Por eso requiere restart.
- **Día 22-29 (Git workflow + PRs)**: la motivación de tener permisos diferenciados surge del trabajo en equipo — el patrón de "developers ven los jobs pero no los modifican" es exactamente lo que el lab implementa.
- **Día 63, 66, 67 (multi-tenant K8s)**: la idea de RBAC con scope (global vs per-namespace en K8s) es análoga al matrix Project-based aquí (global + per-job). Mismo patrón: "matriz global da los permisos base, scopes adicionales agregan permisos finos".

## Reflexión: el modelo de autorización por matrix vs RBAC moderno

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- La matriz de checkboxes vs RBAC moderno (roles con bindings, como K8s o AWS IAM): ¿elegante por simple o frágil por difícil de escalar?
- El riesgo de lock-out: ¿te resulta razonable que la herramienta confíe en el operador, o debería haber un safeguard (avisar "estás por perder tu propio acceso")?
- La distinción Matrix global vs Project-based: ¿útil o demasiado granular? Compararla con el patrón de RoleBinding + ClusterRoleBinding en K8s.
- El paso de instalar un plugin para tener una funcionalidad básica (RBAC): ¿adecuado para el modelo Jenkins o muestra que la herramienta arrastra deuda de design del 2005?
- Comparar con GitHub Actions / GitLab CI donde la autorización viene del propio sistema SCM: ¿es más simple o pierde flexibilidad?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `Project-based Matrix Authorization Strategy` no aparece en el dropdown | El plugin Matrix Authorization Strategy no está instalado                                            | `Manage Jenkins → Plugins → Available`, buscar `matrix authorization`, instalar y restart        |
| Después del Save, `admin` no puede entrar                                | Lock-out por no haber marcado `Overall: Administer` en la matriz                                     | Recuperación vía `/var/lib/jenkins/config.xml` (ver sección dedicada)                             |
| `anita` no ve el job aunque tenga `Overall: Read`                       | Falta la matriz por-proyecto (`Job: Read` en el job específico)                                      | Job → Configure → Enable project-based security → agregar `Anita` con `Job: Read`                |
| `anita` ve el job pero también puede modificarlo                         | Se marcaron permisos adicionales en la matriz por-proyecto (Configure, Build, etc.)                  | Volver al job → Configure → desmarcar todo menos `Job: Read`                                     |
| Anonymous puede entrar aunque sin login                                  | La fila `Anonymous` de la matriz tiene `Overall: Read` marcado                                       | Desmarcar todos los checkboxes en la fila Anonymous y Save                                       |
| `Authenticated Users` da permisos a `anita` que no debería tener         | Esta fila aplica a **todos** los users logueados                                                     | Dejar la fila `Authenticated Users` vacía; asignar permisos por user específico                  |
| El user `Anita` no se puede agregar a la matriz                         | El user no existe todavía. La matriz solo acepta users ya creados                                    | Primero crear el user en `Manage Jenkins → Users`, después agregarlo a la matriz                  |
| El user se llama `anita` pero en la matriz aparece `Anita`              | Jenkins distingue **username** (login, case-sensitive en algunos contextos) de **full name** (display) | Usar el username exacto (`anita`) al agregar a la matriz, no el full name (`Anita`)              |
| Después de instalar el plugin, la página de Security se ve igual         | El restart no se completó                                                                            | Esperar 30-60s y refrescar. Verificar con `/var/log/jenkins/jenkins.log` que dice "fully up"     |
| Save tarda mucho y devuelve timeout                                      | Si hay muchos jobs, recalcular permisos puede ser costoso                                            | Esperar; verificar logs                                                                            |

## Recursos

- [Authorize Project Plugin docs (oficial)](https://plugins.jenkins.io/matrix-auth/)
- [Securing Jenkins — Authorization (oficial)](https://www.jenkins.io/doc/book/security/managing-security/)
- [Project-based Matrix Authorization Strategy guide](https://www.jenkins.io/doc/book/security/access-control/permissions/)
- [Recuperación de lock-out (oficial)](https://www.jenkins.io/doc/book/security/access-control/#recovery)
- [Role-Based Authorization Strategy (alternativa)](https://plugins.jenkins.io/role-strategy/)
- [Comparación de strategies (artículo)](https://www.cloudbees.com/blog/jenkins-security-authorization-strategies)
