# Día 69 - Install Jenkins Plugins (Git + GitLab) vía Update Center

## Problema / Desafío

El equipo Nautilus instaló Jenkins en el Día 68 y ahora necesita preparar el server con los plugins base que van a usar la mayoría de los jobs CI/CD.

Requirements:

1. Login a la UI de Jenkins como `admin` / `Adm!n321`
2. Instalar dos plugins:
   - **Git** — integración con repos Git genéricos
   - **GitLab** — integración con GitLab CE/EE (webhooks, MR builds, status reporting)
3. Si Jenkins lo pide, marcar "Restart Jenkins when installation is complete and no jobs are running"
4. Esperar a que la página de login vuelva a aparecer antes de continuar

> **Detalle del lab**: en el primer intento se seleccionaron **Git + GitHub** en lugar de **Git + GitLab** (son plugins distintos — GitLab integra con `gitlab.com`/self-hosted GitLab, GitHub integra con `github.com`). El fix consistió en volver a Available Plugins, buscar `gitlab`, y agregar el plugin **GitLab 1.9.13** (tag `Build Triggers`). Después de instalarlo + restart, los dos plugins requeridos (Git + GitLab) quedaron operativos.

## Conceptos clave

### Qué es un plugin de Jenkins

Un plugin es un **paquete Java empaquetado como `.jpi` o `.hpi`** (legacy) que extiende Jenkins. Pueden:

- Agregar nuevos **tipos de job** (Pipeline, Multibranch, etc.)
- Conectar con sistemas externos (Git, Docker, Kubernetes, AWS, Slack)
- Agregar **build steps** y **post-build actions** disponibles en jobs Freestyle
- Definir **DSL de Pipeline** (extensiones del Jenkinsfile)
- Modificar la UI (themes, dashboards custom)

Jenkins **no funciona** sin plugins en la práctica — incluso operaciones básicas como "Build now" o "Checkout SCM" están implementadas como plugins.

### Anatomía del Update Center

El **Update Center** es el componente que descubre, descarga e instala plugins. Por default apunta a:

```
https://updates.jenkins.io/update-center.json
```

Este archivo contiene el catálogo completo (~1900 plugins) con sus metadatos: versión actual, compatibilidad con versiones de Jenkins, dependencias, hash de verificación.

| Paso del install                            | Qué hace internamente                                                                |
| ------------------------------------------- | ------------------------------------------------------------------------------------ |
| 1. Click "Install" sobre un plugin          | Jenkins resuelve el **árbol de dependencias** del plugin                            |
| 2. Descarga del `.jpi`                      | HTTP GET al mirror de Jenkins, validación de hash SHA-256                            |
| 3. Copia a `/var/lib/jenkins/plugins/`      | Filesystem operation, propiedad de user `jenkins`                                    |
| 4. Resolución de dependencias               | Cada plugin declara qué otros necesita (versión mínima)                              |
| 5. Restart (opcional)                       | Algunos plugins necesitan reload del classloader Java — restart es la forma garantizada |

### Plugins que vienen preinstalados (suggested) del setup wizard

Si en Día 68 se eligió **"Install suggested plugins"**, vienen ya instalados:

| Categoría             | Plugins                                                              |
| --------------------- | -------------------------------------------------------------------- |
| **SCM**               | Git, GitHub Branch Source, Pipeline: GitHub Groovy Libraries         |
| **Pipeline**          | Pipeline, Pipeline Graph View, Pipeline: Stage View                  |
| **UI**                | Dark Theme, Timestamper, Build Timeout                               |
| **Build**             | Ant, Gradle, Maven Integration                                       |
| **Workspace**         | Workspace Cleanup                                                    |
| **Auth**              | Matrix Authorization Strategy, LDAP                                  |
| **Credentials**       | Credentials Binding                                                  |
| **Notificación**      | Email Extension, Mailer                                              |
| **Infra**             | SSH Build Agents                                                     |
| **Format**            | OWASP Markup Formatter                                               |

> Esto explica que **"Git" ya esté instalado** al iniciar Día 69 — viene en el set sugerido. Por eso al intentar reinstalarlo, el progress muestra `Git: Failure`. No es bug; es duplicado.

### Git plugin vs GitLab plugin vs GitHub plugin (distinguir bien)

Estos tres plugins se confunden porque todos hablan de "Git", pero hacen cosas distintas:

| Plugin                                  | Para qué sirve                                                                              | Cuándo se usa                                                       |
| --------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| **Git** (`git`)                         | Cliente Git genérico. Hace `git clone`, `git checkout`, etc. desde un job                  | Casi todo job que necesite código de un repo Git                    |
| **GitLab** (`gitlab-plugin`)            | Integración con servidores GitLab — webhooks de push/MR, status reporting de vuelta         | Pipelines que viven en GitLab (gitlab.com o self-hosted GitLab CE/EE) |
| **GitHub** (`github`)                   | Integración con GitHub — webhooks, status checks, GitHub Apps                               | Pipelines que viven en GitHub                                       |
| **GitHub Branch Source** (`github-branch-source`) | Descubrimiento automático de branches/PRs en GitHub para Multibranch Pipelines       | Multibranch jobs en GitHub                                          |
| **GitLab Branch Source** (`gitlab-branch-source`) | Equivalente para GitLab                                                              | Multibranch jobs en GitLab                                          |

**Regla de selección**:

- Si el repo está en `github.com` → instalar GitHub
- Si el repo está en `gitlab.com` o un GitLab self-hosted → instalar GitLab
- Si el repo está en Bitbucket, Gitea u otro → instalar Git (el cliente genérico)
- **Siempre** se necesita el plugin Git como base — los otros son capas de integración encima

### Por qué algunos plugins requieren restart

Jenkins corre sobre la JVM con un classloader específico. Cuando un plugin **define clases nuevas** (no solo configuración), esas clases tienen que cargarse al classloader **al inicio** — no en runtime.

- Plugins que **NO** necesitan restart: solo agregan jobs, builders, vistas (la mayoría)
- Plugins que **SÍ** necesitan restart: cambian extensiones del core, agregan SCM providers, modifican el security realm

El UI de Jenkins detecta cuándo es necesario y muestra la opción "Restart Jenkins when installation is complete". La opción "**when no jobs are running**" agrega un drain: espera a que los builds activos terminen antes de reiniciar.

### Páginas del Plugin Manager — qué muestra cada una

| Página                     | Contenido                                                                          |
| -------------------------- | ---------------------------------------------------------------------------------- |
| **Updates** (`/manage/pluginManager/?filter=updates`)        | Plugins instalados con versión nueva disponible                                    |
| **Available plugins** (`/manage/pluginManager/available`)    | Todos los plugins del Update Center no instalados todavía                          |
| **Installed plugins** (`/manage/pluginManager/installed`)    | Plugins actualmente instalados con versión actual                                  |
| **Advanced settings** (`/manage/pluginManager/advanced`)     | URL del Update Center, proxy HTTP, upload manual de `.hpi/.jpi`                    |
| **Download progress** (`/manage/pluginManager/updates/`)     | Página de progreso durante una instalación en curso                                |

## Pasos

1. Abrir la UI de Jenkins en `http://<jenkins-host>:8080`
2. Login como `admin` con password `Adm!n321`
3. Navegar a **Manage Jenkins → Plugins → Available plugins**
4. En la barra de búsqueda, buscar `git` — marcar el checkbox del plugin **Git**
5. Limpiar la búsqueda, buscar `gitlab` — marcar el checkbox del plugin **GitLab**
6. Click en el botón **Install** (arriba a la derecha)
7. En la página de progreso, marcar el checkbox **"Restart Jenkins when installation is complete and no jobs are running"**
8. Esperar a que todos los downloads pasen de `Pending` → `Success` (≈30s)
9. Jenkins se reinicia automáticamente — la UI redirige a la página de login al volver
10. Verificar en **Manage Jenkins → Plugins → Installed plugins** que aparezcan **Git** y **GitLab**

## Comandos / Código

### Login a la UI

Apuntar el browser a la URL del Jenkins (en KodeKloud es el proxy `https://8080-port-<lab-id>.labs.kodekloud.com/`):

| Campo        | Valor      |
| ------------ | ---------- |
| Username     | `admin`    |
| Password     | `Adm!n321` |

### Navegación a Plugin Manager

```
Manage Jenkins (sidebar izquierda con ícono ⚙)
    └── Plugins (sección "System Configuration")
        └── Available plugins
```

URL directa: `http://<jenkins-host>:8080/manage/pluginManager/available`

### Selección de plugins

| Plugin esperado | Búsqueda en el filtro | ID interno              | Versión observada en lab |
| --------------- | --------------------- | ----------------------- | ------------------------ |
| **Git**         | `git`                 | `git`                   | 5.10.1                   |
| **GitLab**      | `gitlab`              | `gitlab-plugin`         | 1.9.13 (tag `Build Triggers`) |

> El plugin Git puede aparecer ya como instalado (preinstalado del setup wizard del Día 68). Si está como **instalado**, no hace falta reinstalar — pasa directo a buscar GitLab.

> Al buscar `gitlab`, la página devuelve tres resultados típicos: **GitLab** (`gitlab-plugin`, el principal — tag `Build Triggers`), **Generic Webhook Trigger** (alternativa más amplia que también acepta GitLab), y **GitLab API** (dependencia de librería, se instala automáticamente). El plugin correcto a marcar es el primero — el de tag `Build Triggers`, que es el que el lab espera.

### Confirmar la selección antes de instalar

Después de marcar los checkboxes, el contador de plugins seleccionados aparece arriba a la derecha. Click en **Install**.

### Página de progreso (Download progress)

Jenkins lista todos los plugins que va a descargar — incluyendo dependencias transitivas. Para el GitLab plugin típicamente arrastra:

| Dependencia                  | Por qué                                                                          |
| ---------------------------- | -------------------------------------------------------------------------------- |
| GitLab API Plugin            | Cliente Java de la API de GitLab                                                 |
| Display URL API              | Para generar URLs canónicas hacia Jenkins                                        |
| Mailer                       | Para notificaciones por email (re-uso de la dependencia preinstalada)            |
| Token Macro                  | Sustitución de tokens `${VAR}` en strings (URLs, mensajes)                       |
| OkHttp                       | Cliente HTTP usado por varios plugins                                            |
| JAXB, JSON API, SnakeYAML    | Serialización de datos                                                           |

### Checkbox de restart

Al final de la página de progreso:

```
[x] Restart Jenkins when installation is complete and no jobs are running
```

> Marcarlo **al inicio** del install evita tener que esperar la página, hacer click manual, etc. Jenkins reinicia solo cuando los downloads terminan y no hay jobs activos.

### Espera del restart

Durante el restart:

- La UI muestra spinner "Please wait while Jenkins is restarting..."
- El servicio se reinicia (JVM termina, systemd lo levanta de nuevo)
- ~30-60 segundos después, la página de login vuelve a aparecer

Equivalente desde el server (si se quiere monitorear):

```bash
sudo tail -f /var/log/jenkins/jenkins.log
```

Líneas a esperar:

```
INFO    hudson.lifecycle.Lifecycle#onStop: Stopping Jenkins
INFO    Main#runJenkins: Jenkins is fully up and running
```

### Verificación post-restart

Login de nuevo con `admin` / `Adm!n321`. Navegar a:

```
Manage Jenkins → Plugins → Installed plugins
```

Validar que aparezcan en la lista:

- **Git** (versión 5.10.1 o superior)
- **GitLab** (versión 1.9.x o superior)

Filtrar la lista escribiendo `git` o `gitlab` en el buscador de la página para localizarlos rápido.

### Vía CLI — alternativa para automatización

Aunque el lab pide hacerlo por UI, vale conocer la alternativa por **`jenkins-cli`** para futuras automatizaciones:

```bash
# Descargar el cliente
wget http://<jenkins-host>:8080/jnlpJars/jenkins-cli.jar

# Listar plugins instalados
java -jar jenkins-cli.jar -s http://<jenkins-host>:8080/ \
  -auth admin:Adm!n321 \
  list-plugins

# Instalar plugins
java -jar jenkins-cli.jar -s http://<jenkins-host>:8080/ \
  -auth admin:Adm!n321 \
  install-plugin git gitlab-plugin

# Restart después del install
java -jar jenkins-cli.jar -s http://<jenkins-host>:8080/ \
  -auth admin:Adm!n321 \
  safe-restart
```

> `safe-restart` es el equivalente CLI del checkbox "when no jobs are running" — espera a que terminen los builds activos.

### Vía Configuration as Code (JCasC) — para entornos productivos

En clusters reales, los plugins se declaran en un archivo YAML versionado en git:

```yaml
# plugins.txt
git:latest
gitlab-plugin:latest
```

Y se aplican con `jenkins-plugin-cli`:

```bash
jenkins-plugin-cli --plugin-file plugins.txt
```

Esto se hace típicamente al **construir la imagen Docker** custom de Jenkins, no en runtime.

## Anatomía del filesystem después del install

```bash
ls /var/lib/jenkins/plugins/ | grep -E '^(git|gitlab)'
```

Output esperado:

```
git
git.jpi
git-client
git-client.jpi
gitlab-plugin
gitlab-plugin.jpi
gitlab-api
gitlab-api.jpi
```

Detalles:

| Archivo                | Qué es                                                                         |
| ---------------------- | ------------------------------------------------------------------------------ |
| `<plugin>.jpi`         | El paquete .jar del plugin (renombrado a .jpi)                                  |
| `<plugin>/` (dir)      | El plugin explotado — Jenkins lo descomprime para cargar las clases             |
| Multi-plugins por uno  | Un plugin como `gitlab-plugin` puede arrastrar `gitlab-api` (dependencia)       |

## Conexión con días anteriores

- **Día 68 (Set Up Jenkins Server)**: el `JENKINS_HOME` (`/var/lib/jenkins`) y los archivos creados por el `.deb` son la base donde aterrizan los plugins de hoy. El user `jenkins` es el que tiene permisos sobre `plugins/`.
- **Día 21–34 (Git workflow)**: los plugins instalados hoy son lo que permite que un job Jenkins haga `git clone` contra el repo del Día 21 / 22, o trabaje contra un fork de Gitea como el del Día 23.
- **Día 29 (Pull Requests en Gitea)**: el plugin equivalente para Gitea sería instalado de forma análoga. La UI de Plugin Manager es la misma — solo cambia el ID del plugin a buscar.
- **Día 35–47 (Docker)**: el plugin `Docker Pipeline` (no instalado hoy) será necesario más adelante para que jobs de Jenkins puedan construir/publicar imágenes Docker.
- **Día 48–67 (Kubernetes)**: el plugin `Kubernetes` permitirá que Jenkins **despliegue** contra el cluster K8s desde dentro de un pipeline — cerrando la cadena `git push → build → deploy`.

## Reflexión: plugins como modelo de extensibilidad

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- El modelo de Jenkins como "core mínimo + ~1900 plugins": ¿elegante o frágil? Compararlo con alternativas modernas (GitHub Actions usa marketplace de actions, GitLab CI integra todo nativo, ArgoCD es más restrictivo).
- La distinción Git / GitHub / GitLab plugin: ¿clara desde el principio o confusa al ver tres opciones similares?
- El restart después de instalar: ¿anticuado vs herramientas que recargan en hot? ¿O es honesto sobre el modelo JVM/classloader?
- La opción "when no jobs are running": ¿te parece elegante para un sistema multi-tenant donde varios equipos comparten el server? ¿O agrega complejidad innecesaria?
- Comparar UI vs CLI vs JCasC: ¿cuál preferirías para gestionar plugins en producción? ¿La UI sirve para descubrimiento, CLI para scripts, y JCasC para gitops?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Validador del lab marca el plugin como faltante                          | Se instaló GitHub en lugar de GitLab (confusión por nombre similar)                                  | Volver a Available Plugins, buscar `gitlab` específicamente, instalar y verificar en Installed     |
| Plugin "Git" aparece como `Failure` en la página de progreso             | Ya estaba instalado del setup wizard. El instalador detecta el duplicado y lo marca como Failure     | No es bug. Verificar en Installed plugins que Git esté presente con versión correcta              |
| Botón "Install" deshabilitado                                            | Ningún plugin seleccionado, o todos los seleccionados ya están instalados a su última versión        | Marcar al menos un checkbox de un plugin no instalado o con update disponible                     |
| Download queda en `Pending` indefinidamente                              | Sin internet o el Update Center no responde                                                          | `curl https://updates.jenkins.io/update-center.json` desde el server para validar conectividad   |
| `Hashes don't match!` durante el install                                 | Archivo corrupto en download (mirror inconsistente) o el manifest del Update Center está desfasado    | Reintentar; si persiste, cambiar el mirror en Advanced settings                                   |
| Jenkins no reinicia automáticamente aunque el checkbox esté marcado     | Hay un job activo bloqueando el restart                                                              | Ir a "Build Queue"/jobs activos y abortar, o esperar; alternativa: forzar restart manual          |
| Después del restart, los plugins instalados no aparecen                  | Permisos rotos en `/var/lib/jenkins/plugins/`                                                        | `sudo chown -R jenkins:jenkins /var/lib/jenkins/plugins/` y reiniciar                              |
| El restart toma > 5 minutos                                              | Plugins con migraciones de datos pesadas (el primer install de Workflow Aggregator puede tardar)     | Paciencia. Verificar en `/var/log/jenkins/jenkins.log` que no haya errores                        |
| Después del restart, la UI tira `Loading...` perpetuo                    | El servicio crashea en el classloader por un plugin incompatible                                     | SSH al server, `sudo tail /var/log/jenkins/jenkins.log` para el stack trace                       |
| Plugin instalado pero las opciones nuevas no aparecen en jobs            | El restart no se completó realmente, o el plugin requería restart y se saltó                          | Forzar restart desde URL: `<jenkins-url>/safeRestart`                                              |
| Dependencias circulares al instalar varios plugins                       | Versiones incompatibles en el árbol de dependencias                                                  | Update Center suele resolverlo; si no, instalar uno a uno empezando por las dependencias          |

## Recursos

- [Managing Plugins (oficial)](https://www.jenkins.io/doc/book/managing/plugins/)
- [Plugin Index](https://plugins.jenkins.io/)
- [Git plugin](https://plugins.jenkins.io/git/)
- [GitLab plugin](https://plugins.jenkins.io/gitlab-plugin/)
- [GitHub plugin](https://plugins.jenkins.io/github/) — para distinguir vs GitLab
- [`jenkins-plugin-cli` (para JCasC)](https://github.com/jenkinsci/plugin-installation-manager-tool)
- [Configuration as Code Plugin (JCasC)](https://plugins.jenkins.io/configuration-as-code/)
- [Update Center JSON](https://updates.jenkins.io/update-center.json) — el catálogo crudo
