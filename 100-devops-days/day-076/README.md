# Día 76 - Jenkins Project Security (Project-based Matrix + Inheritance Strategy)

## Problema / Desafío

xFusionCorp contrató dos developers nuevos (`sam` y `rohan`) que necesitan permisos sobre un job existente llamado `Packages`. Los users ya están creados; falta asignarles permisos finos sobre **ese job específico** sin afectar otros jobs.

Requirements:

1. Login a la UI de Jenkins como `admin` / `Adm!n321`
2. Users ya existen:
   - `sam` con password `sam@pass12345`
   - `rohan` con password `rohan@pass12345`
3. Job ya existe: `Packages`
4. Sobre el job `Packages`, configurar **Project-based security** con:
   - **Inheritance Strategy**: `Inherit permissions from parent ACL`
   - Permisos para **sam**: `Build`, `Configure`, `Read`
   - Permisos para **rohan**: `Build`, `Cancel`, `Configure`, `Read`, `Update`, `Tag`

## Conceptos clave

### Recap rápido — Matrix Authorization Strategy (Día 70)

El plugin **Matrix Authorization Strategy** (`matrix-auth`) habilita dos estrategias en `Manage Jenkins → Security → Authorization`:

| Estrategia                                          | Granularidad                                          |
| --------------------------------------------------- | ----------------------------------------------------- |
| **Matrix-based security**                           | Una sola matriz global, sin override por proyecto    |
| **Project-based Matrix Authorization Strategy**     | Matriz global **+** matrices adicionales por job     |

Para este lab se necesita la **segunda**, igual que en Día 70.

### Inheritance Strategy — el concepto nuevo del Día 76

Cuando un job tiene su propia matriz de permisos, hay que decidir **qué hacer con los permisos globales** (los de `Manage Jenkins → Security → Authorization`). Eso lo controla **Inheritance Strategy**, un dropdown que aparece dentro del job al activar "Enable project-based security":

| Inheritance Strategy                                              | Comportamiento                                                                                            |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| **Inherit permissions from parent ACL** *(este lab)*              | Los permisos del global **se suman** a los del job. El user con `Overall/Read` global + `Job/Build` por-proyecto tiene los dos. |
| **Do not inherit permission grants from other ACLs**              | Solo se respeta lo definido en el job. Si en el job no se da `Overall/Read`, el user **no puede acceder ni al dashboard** desde la perspectiva del job |
| **Inherit global ACL only**                                       | Hereda solo los permisos definidos a nivel global, **ignora** permisos de folders intermedios            |
| **Inherit parent ACL only when there is no AnonymousACL**         | Caso especial histórico — raro de usar                                                                    |

La opción **"Inherit from parent ACL"** es la más usada y la que pide el lab. Es la opción "suma" — el global da una base, el job agrega permisos finos.

### Anatomía de la matriz del job

A diferencia de la matriz global, la del job **solo muestra categorías relevantes a builds**:

| Categoría    | Permisos del job (no aparecen los de la matriz global) |
| ------------ | ------------------------------------------------------ |
| **Job**      | Build, Cancel, Configure, Delete, Discover, Read, Workspace |
| **Run**      | Delete, **Update**, Replay                              |
| **SCM**      | Tag                                                     |

Categorías **ausentes** en la matriz per-proyecto (porque no aplican):

- **Overall** (gestión de Jenkins en general — Administer, Read)
- **Agent** (gestión de nodos)
- **View** (visibilidad de vistas/folders)

> Importante: si el job pide otorgar `Overall/Read` a un user, **no se hace desde la matriz del job** — se hace en la matriz global. La matriz del job solo controla lo específico al build.

### El detalle más sutil del lab — `update` ≠ `Job/Update`

El lab pide para rohan: `Build, Cancel, Configure, Read, Update, Tag`. Al buscar "Update" en la matriz del job, **no aparece bajo Job** — aparece bajo **Run**:

```
Job          | Run               | SCM
-----        | -----             | -----
Build        | Delete            | Tag
Cancel       | Update    ← acá   |
Configure    | Replay            |
Delete       |                   |
Discover     |                   |
Read         |                   |
Workspace    |                   |
```

Por qué: `Run/Update` significa permiso para **modificar una build instance específica** (cambiar su descripción, badge, archivar artifacts, etc.), no para "modificar el job". El "Configure" del job ya cubre la edición del job — `Update` es a nivel de cada **ejecución individual**.

> **Regla mental**: si el lab dice "update" sin más contexto en el ámbito de un job, casi seguro se refiere a `Run/Update`. Para "modificar el job en sí" usaría `Configure`.

### El bug que el user identificó — falta `Overall/Read` global

Al asignar solo los permisos del job a sam y rohan **sin tocar el global**, los users no pueden hacer login funcional:

| Paso del flow del user                            | Qué pasa                                                                  |
| ------------------------------------------------- | ------------------------------------------------------------------------- |
| sam intenta login con sam@pass12345               | Autenticación OK                                                          |
| sam llega al dashboard `/`                         | Recibe 403 / pantalla vacía — no tiene `Overall/Read` global              |
| sam nunca llega al job Packages                   | El job hereda permisos pero el user no puede ni navegar para usarlos      |

**Fix**: agregar `Overall/Read` a sam y rohan **en la matriz global** (Manage Jenkins → Security → Authorization). Una vez con `Overall/Read` global:

1. sam y rohan pueden entrar al dashboard
2. Pueden ver el job `Packages` (porque tienen `Job/Read` heredado del proyecto)
3. Pueden hacer Build (porque tienen `Job/Build` del proyecto)
4. No pueden ver `Manage Jenkins` (no tienen `Overall/Administer`)
5. No pueden ver otros jobs (solo `Job/Read` sobre Packages, no sobre los demás)

> Este es el patrón consolidado: **`Overall/Read` global da entrada al sistema; permisos por-job dan capacidades específicas**. Sin el primero, los segundos son inaccesibles.

### Matriz completa esperada al final del lab

#### Matriz global (Manage Jenkins → Security → Authorization)

| User/Group              | Overall/Administer | Overall/Read | Resto       |
| ----------------------- | ------------------ | ------------ | ----------- |
| Anonymous               | ❌                  | ❌            | ❌           |
| Authenticated Users     | ❌                  | ❌            | ❌           |
| admin                   | ✅ (implica todo)   | (implícito)  | (implícito) |
| rohan                   | ❌                  | ✅            | ❌           |
| sam                     | ❌                  | ✅            | ❌           |

#### Matriz del job `Packages` (Configure → Enable project-based security)

| User    | Job/Build | Job/Cancel | Job/Configure | Job/Read | Run/Update | SCM/Tag |
| ------- | --------- | ---------- | ------------- | -------- | ---------- | ------- |
| sam     | ✅         | ❌          | ✅             | ✅        | ❌          | ❌       |
| rohan   | ✅         | ✅          | ✅             | ✅        | ✅          | ✅       |

Con **Inheritance Strategy: Inherit permissions from parent ACL**, el efecto final para sam es:

- Hereda `Overall/Read` del global → puede entrar a Jenkins
- Tiene `Job/Build`, `Job/Configure`, `Job/Read` sobre Packages → puede usarlo
- No tiene permisos sobre otros jobs → no los ve

## Pasos

1. Login como `admin` / `Adm!n321`
2. (Si no está instalado) Instalar el plugin **Matrix Authorization Strategy** y reiniciar
3. **Manage Jenkins → Security → Authorization**:
   - Estrategia: **Project-based Matrix Authorization Strategy**
   - Mantener `admin` con **Overall/Administer**
   - Agregar `sam` con **Overall/Read**
   - Agregar `rohan` con **Overall/Read**
   - Save
4. Dashboard → job **`Packages`** → **Configure**
5. En la sección General, marcar **"Enable project-based security"**
6. **Inheritance Strategy**: seleccionar **"Inherit permissions from parent ACL"**
7. Agregar usuarios y marcar sus permisos:
   - `sam`: Job/Build, Job/Configure, Job/Read
   - `rohan`: Job/Build, Job/Cancel, Job/Configure, Job/Read, **Run/Update**, **SCM/Tag**
8. Save
9. Validar logueándose como sam y rohan en sesiones separadas

## Comandos / Código

### 1. Verificar que los users existen

Navegación: **Manage Jenkins → Users** (o `Manage Jenkins → Jenkins' own user database`).

Output esperado (screenshot inicial del lab):

```
User ID   Name
admin     admin
rohan     rohan
sam       sam
```

Tres usuarios. Si falta alguno, crearlo con **Create User** (no es el caso del lab — ya están).

### 2. Configurar la matriz global

Navegación: **Manage Jenkins → Security → Authorization**.

Cambiar el dropdown a **`Project-based Matrix Authorization Strategy`**. La matriz inicial muestra:

```
User/group         | Overall/Administer | Overall/Read | ...
Anonymous          | ❌                  | ❌            |
Authenticated Users| ❌                  | ❌            |
```

Click **Add user...** y agregar:

| User    | Overall/Administer | Overall/Read |
| ------- | ------------------ | ------------ |
| admin   | ✅                  | (implícito)  |
| sam     | ❌                  | ✅            |
| rohan   | ❌                  | ✅            |

> **No olvidar** marcar `Overall/Administer` para admin antes de Save — sino hay lock-out. Ver Día 70 sección "Recuperación de lock-out".

Click **Save**.

### 3. Configurar la matriz del job Packages

Navegación: **Dashboard → Packages → Configure**.

En la sección **General**, marcar:

```
[x] Enable project-based security
```

**Inheritance Strategy** (dropdown):

```
Inherit permissions from parent ACL  ✓
```

Click **Add user...** y agregar `sam`. Marcar:

| Job/Build | Job/Configure | Job/Read |
| --------- | ------------- | -------- |
| ✅         | ✅             | ✅        |

Click **Add user...** y agregar `rohan`. Marcar:

| Job/Build | Job/Cancel | Job/Configure | Job/Read | Run/Update | SCM/Tag |
| --------- | ---------- | ------------- | -------- | ---------- | ------- |
| ✅         | ✅          | ✅             | ✅        | ✅          | ✅       |

> Detalle visual: el campo "Update" del lab vive bajo la columna **Run**, no Job. Confundirse con `Run/Update` ↔ `Run/Replay` también es común — Update es modificar metadata; Replay es re-ejecutar el build con cambios. El lab quiere **Update**.

Click **Save**.

### 4. Validación funcional

Logout de admin. Login como `sam` / `sam@pass12345`.

Resultado esperado:

- Dashboard accesible (gracias a Overall/Read global)
- Job `Packages` visible
- Puede entrar a `Packages` → ver historial
- Botón **"Build Now"** disponible
- Puede entrar a **"Configure"** del job (gracias a Job/Configure)
- **No** ve `Manage Jenkins` en el menú
- **No** ve otros jobs además de `Packages`

Logout y login como `rohan` / `rohan@pass12345`:

- Igual que sam, **más**:
- Puede cancelar builds en curso (Job/Cancel)
- Puede modificar metadata de builds individuales (Run/Update — ej. agregar descripción a un build específico)
- Puede crear tags en el SCM desde la UI (SCM/Tag)

### Layout final visible en la UI (matriz del job)

```
              Job                                       Run            SCM
              Build Cancel Conf Del Disc Read Worksp   Del Update Repl  Tag
Anonymous     ❌     ❌      ❌    ❌   ❌    ❌    ❌      ❌    ❌      ❌    ❌
Auth Users    ❌     ❌      ❌    ❌   ❌    ❌    ❌      ❌    ❌      ❌    ❌
sam           ✅     ❌      ✅    ❌   ❌    ✅    ❌      ❌    ❌      ❌    ❌
rohan         ✅     ✅      ✅    ❌   ❌    ✅    ❌      ❌    ✅      ❌    ✅
```

## Anatomía del filesystem — qué cambia en disco

El cambio se persiste en dos archivos:

```
/var/lib/jenkins/config.xml
└── <authorizationStrategy class="hudson.security.ProjectMatrixAuthorizationStrategy">
      <permission>hudson.model.Hudson.Administer:admin</permission>
      <permission>hudson.model.Hudson.Read:sam</permission>
      <permission>hudson.model.Hudson.Read:rohan</permission>
    </authorizationStrategy>

/var/lib/jenkins/jobs/Packages/config.xml
└── <properties>
      <com.cloudbees.hudson.plugins.folder.properties.AuthorizationMatrixProperty>
        <inheritanceStrategy class="org.jenkinsci.plugins.matrixauth.inheritance.InheritParentStrategy"/>
        <permission>hudson.model.Item.Build:sam</permission>
        <permission>hudson.model.Item.Configure:sam</permission>
        <permission>hudson.model.Item.Read:sam</permission>
        <permission>hudson.model.Item.Build:rohan</permission>
        <permission>hudson.model.Item.Cancel:rohan</permission>
        <permission>hudson.model.Item.Configure:rohan</permission>
        <permission>hudson.model.Item.Read:rohan</permission>
        <permission>hudson.model.Run.Update:rohan</permission>
        <permission>hudson.scm.SCM.Tag:rohan</permission>
      </com.cloudbees.hudson.plugins.folder.properties.AuthorizationMatrixProperty>
    </properties>
```

> Útil para automatización: este XML es la fuente de verdad. Configuration as Code (JCasC) o un script Ansible pueden generarlo directamente sin pasar por la UI.

## Conexión con días anteriores

- **Día 70 (Configure Jenkins User Access)**: introdujo Matrix Authorization Strategy con un solo user nuevo (anita). Hoy se aplica el patrón a **dos users** sobre un **job pre-existente**, y agrega el concepto nuevo de **Inheritance Strategy**.
- **Día 68 (Set Up Jenkins Server)** + **Día 69 (Install Plugins)**: el plugin `matrix-auth` ya debería estar instalado del Día 70. Si no, instalarlo igual que en Día 69.
- **Día 71-74 (Jobs Jenkins)**: los jobs creados en esos días (`install-packages`, `parameterized-job`, `copy-logs`, `database-backup`) **no tienen** project-based security activado. Cualquier user con `Overall/Read` global los puede ver. Para limitarlos, aplicar la misma técnica del lab de hoy.
- **Día 75 (Slave Nodes)**: los permisos sobre los agents (`Agent/Build`, `Agent/Configure`, etc.) viven en la **matriz global**, no en la per-proyecto. Si rohan necesitara conectar/desconectar agents, sería un permiso global, no del job Packages.

## Reflexión: matriz global + per-proyecto como modelo de delegación

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- La distinción Job/Configure vs Run/Update: ¿se identifica al primer vistazo o requiere leer la doc? El modelo "permisos por categoría" de Jenkins (Job/Run/SCM/View/Agent/Overall) — ¿claro o demasiado fragmentado?
- El requisito "Overall/Read global" como prerequisito para cualquier permiso por-proyecto: ¿obvio en retrospectiva o un bug de diseño? En K8s/AWS IAM no hay este "permiso de entrada al sistema" — RBAC es solo permisos sobre recursos. ¿Jenkins arrastra deuda de UI o tiene sentido por algo?
- Inheritance Strategy "Inherit from parent ACL": ¿el comportamiento que se esperaría por default? La opción "Do not inherit" parece útil pero peligrosa (anula los permisos del global). ¿En qué casos usarías cada una?
- Comparación con K8s RBAC: en K8s tendrías un Role por job + RoleBinding por user. La gran diferencia: K8s es **declarativo** (todo en YAML versionado), Jenkins matrix es **point-and-click** (clicks en la UI que cambian config.xml). ¿Cuál se siente más confiable?
- El bug del Overall/Read faltante: ¿algo que solo se descubre al testear con un user no-admin? ¿Cómo automatizarías el catch (escribir un health-check que loguee como sam y valide acceso al dashboard)?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| sam/rohan no pueden entrar a Jenkins (403/pantalla vacía)               | Falta `Overall/Read` global                                                                          | Manage Jenkins → Security → Authorization → agregar `Overall/Read` para los users                |
| El checkbox "Enable project-based security" no aparece en el job        | La estrategia global no es `Project-based Matrix Authorization Strategy`                             | Cambiar la estrategia global (con admin como Administer para evitar lock-out)                    |
| Marqué `Update` bajo Job pero el lab dice incorrecto                    | La columna `Update` correcta está bajo **Run**, no Job                                               | Buscar `Update` en la sección Run del matrix, no Job                                              |
| sam ve `Packages` pero no puede hacer Build                             | Solo tiene `Job/Read`, no `Job/Build`                                                                | Marcar `Job/Build` en la matriz del job Packages                                                  |
| El job Packages aparece como editable pero los cambios no persisten     | El user no tiene `Job/Configure` realmente, solo lee el form                                         | Verificar la matriz que `Job/Configure` esté marcado                                              |
| `Inheritance Strategy` no aparece como opción                            | Versión vieja del plugin matrix-auth — actualizar                                                    | Manage Jenkins → Plugins → Updates → matrix-auth                                                  |
| Al hacer Save del job, otros jobs cambian su configuración              | Ningún job cambia automáticamente — la matriz es per-job                                             | Verificar que solo se editó `Packages` y no se tocó la lista global                              |
| sam puede ver otros jobs además de Packages                              | La matriz global da más que `Overall/Read`                                                           | Solo `Overall/Read` global; cualquier otro permiso global se hereda a TODOS los jobs              |
| `Anonymous` tiene permisos accidentalmente                               | La fila Anonymous en la matriz global o per-job tiene checkboxes marcados                            | Desmarcar todos los permisos para Anonymous (global y por-job)                                    |
| Run/Update no afecta lo que se esperaba                                  | Run/Update permite editar metadata de builds individuales, no del job                                 | Para "editar el job" usar `Job/Configure`; Run/Update es para builds individuales                |
| El user puede entrar pero ve "no jobs" en el dashboard                  | No tiene `Job/Read` o `Job/Discover` sobre ningún job                                                | Verificar que tenga al menos `Job/Read` sobre Packages                                            |

## Recursos

- [Matrix Authorization Strategy Plugin](https://plugins.jenkins.io/matrix-auth/)
- [Project-based Matrix Authorization](https://www.jenkins.io/doc/book/security/access-control/permissions/)
- [Inheritance Strategy explained](https://github.com/jenkinsci/matrix-auth-plugin#inheritance-strategies)
- [Permission types in Jenkins](https://www.jenkins.io/doc/book/security/access-control/permissions/#permissions)
- [Run permissions (Update vs Replay)](https://javadoc.jenkins.io/hudson/model/Run.html)
- [Configuration as Code (JCasC) for Matrix Authorization](https://plugins.jenkins.io/configuration-as-code/)
