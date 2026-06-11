# Día 68 - Set Up de Jenkins Server (instalación con apt + setup inicial vía UI)

## Problema / Desafío

El equipo DevOps de xFusionCorp arranca con sus pipelines CI/CD y eligió **Jenkins** como servidor. Hay que instalarlo en la máquina `jenkins` y dejarlo accesible con un usuario admin configurado.

Requirements:

1. **Instalar Jenkins con `apt`** (no manual, no Docker)
2. **Arrancar el servicio con `service`** (no `systemctl` directo)
3. **Crear usuario admin** vía la UI del setup wizard:
   - Username: `theadmin`
   - Password: `Adm!n321`
   - Full name: `Ravi`
   - Email: `ravi@jenkins.stratos.xfusioncorp.com`
4. Si hay timeout al arrancar, revisar `/var/log/jenkins/jenkins.log`

Acceso al server: SSH como `root` con password `S3curePass` desde el jump host.

## Conceptos clave

### Qué es Jenkins y por qué se usa

Jenkins es un **servidor de automatización open source** escrito en Java. Su rol típico:

| Capa                                         | Qué hace Jenkins                                                                       |
| -------------------------------------------- | -------------------------------------------------------------------------------------- |
| **CI (Continuous Integration)**              | Detecta commits a un repo, corre tests, reporta resultados                             |
| **CD (Continuous Delivery / Deployment)**    | Construye artifacts (Docker images, JARs, etc.), los pushea a registries, despliega a servidores |
| **Orquestación de tareas**                   | Cualquier script repetitivo: backups, reportes, batch jobs                              |
| **Plugin marketplace**                       | ~1900+ plugins para integrar con casi cualquier herramienta (Git, K8s, AWS, Slack, etc.) |

Conceptos de Jenkins que aparecerán en days posteriores:

| Concepto       | Definición                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------- |
| **Job / Item** | Una tarea configurada (build, deploy, test). Tipos: Freestyle, Pipeline, Multibranch       |
| **Pipeline**   | Un job definido como código (Jenkinsfile) — Declarativo o Scripted (Groovy)                |
| **Build**      | Una ejecución específica de un job                                                          |
| **Executor**   | Slot de cómputo donde corre un build (puede haber varios en el master y/o en agents)        |
| **Agent / Node** | Máquina (física, VM o container) que ejecuta builds. El master coordina, los agents corren |
| **Workspace**  | Directorio en el agent donde se hace el checkout del repo y se ejecutan los pasos          |
| **Trigger**    | Qué dispara un build: webhook de SCM, scheduler tipo cron, manual, upstream job             |

### Por qué Java 21 (no Java 8 / 11)

Jenkins 2.x usa Java como runtime, pero **cada versión LTS sube los requisitos**. La tabla actual:

| Versión de Jenkins  | Java soportado                  |
| ------------------- | ------------------------------- |
| 2.346.x – 2.426.x   | Java 11 o 17                    |
| 2.427.x+            | Java 17 o 21                    |
| 2.500+ (este lab)   | **Java 17 o 21**                |

> Por eso este lab arranca con `apt install openjdk-21-jre` antes de Jenkins. Con Java 11 el servicio fallaría al arrancar con error de "unsupported class file version".

### Por qué `fontconfig` antes de Java

La librería AWT de Java (usada por Jenkins para generar imágenes — gráficos de build trends, badges) requiere **fonts del sistema**. Sin `fontconfig`, Jenkins arranca pero ciertas operaciones de UI/reportes pueden fallar con `NoClassDefFoundError: Could not initialize class sun.awt.X11FontManager`. Es un requisito histórico de la JVM en Linux, no específico de Jenkins.

### `service jenkins start` vs `systemctl start jenkins`

En Ubuntu 20.04+ (sistemas systemd), los dos comandos son **equivalentes**:

- `service jenkins start` es un wrapper de compatibilidad heredado de sysvinit
- Internamente delega a `systemctl start jenkins.service`
- El output `Synchronizing state of jenkins.service with SysV service script` confirma que systemd reconoce ambos comandos

El lab pide `service` específicamente porque:

1. Es **portable** entre distros (funciona en sistemas viejos sysvinit y nuevos systemd)
2. El wrapper sysv-install garantiza que el unit file de systemd quede registrado correctamente
3. Es la convención más usada en docs históricas — el lab valida que el servicio quede arrancable de esta forma

### Estructura de archivos de Jenkins en Ubuntu

| Path                                       | Qué contiene                                                                          |
| ------------------------------------------ | ------------------------------------------------------------------------------------- |
| `/var/lib/jenkins/`                        | **JENKINS_HOME** — config, jobs, plugins, builds, secrets. Backup point principal     |
| `/var/lib/jenkins/secrets/initialAdminPassword` | Password de un solo uso para desbloquear el setup wizard                              |
| `/var/lib/jenkins/jobs/<job-name>/`        | Configuración y builds de cada job                                                    |
| `/var/lib/jenkins/plugins/`                | Plugins instalados (`.jpi` o `.hpi`)                                                  |
| `/var/lib/jenkins/users/`                  | Usuarios y sus credenciales (incluido el admin que se crea en el wizard)              |
| `/var/log/jenkins/jenkins.log`             | Log principal del servicio — lo primero a revisar en cualquier problema               |
| `/etc/default/jenkins`                     | Variables de entorno del servicio (memoria de JVM, puerto, etc.)                      |
| `/usr/lib/systemd/system/jenkins.service`  | Unit file de systemd                                                                  |
| `/usr/share/java/jenkins.war`              | El .war ejecutable de Jenkins (no se toca a mano)                                     |

### El setup wizard — qué pasa al arrancar Jenkins por primera vez

Al levantar Jenkins, escucha en `:8080` y **bloquea el acceso** hasta completar 4 pasos:

1. **Unlock**: ingresar el `initialAdminPassword` (sale en el log y en `/var/lib/jenkins/secrets/initialAdminPassword`)
2. **Plugins**: instalar el set sugerido (Git, Pipeline, GitHub, etc.) o seleccionar específicos
3. **Crear admin user**: username, password, full name, email
4. **Instance config**: URL pública del Jenkins (para webhooks y notificaciones)

El initialAdminPassword se **invalida** después del wizard — el acceso pasa al admin user creado en el paso 3.

## Pasos

1. Conectarse al jenkins server desde el jump host
2. Instalar `fontconfig` y `openjdk-21-jre`
3. Agregar el APT repo oficial de Jenkins (key + sources list)
4. `apt install jenkins`
5. Habilitar el servicio con `systemctl enable jenkins`
6. Arrancar con `service jenkins start`
7. Verificar estado y proceso
8. Leer el initial admin password
9. Acceder a la UI por `http://<jenkins-host>:8080/`
10. Completar el wizard creando el usuario admin con los datos del lab

## Comandos / Código

### 1. Conexión al jenkins server

```bash
# Desde el jump host
ssh root@jenkins
# password: S3curePass
```

### 2. Pre-requisitos: Java 21 y fontconfig

```bash
sudo apt update
sudo apt install -y fontconfig openjdk-21-jre
```

Validación:

```bash
java -version
```

```
openjdk version "21.0.11" 2026-04-21
OpenJDK Runtime Environment (build 21.0.11+10-1-24.04.2-Ubuntu)
OpenJDK 64-Bit Server VM (build 21.0.11+10-1-24.04.2-Ubuntu, mixed mode, sharing)
```

### 3. Agregar el APT repo oficial de Jenkins

Pasos según [la doc oficial](https://www.jenkins.io/doc/book/installing/linux/#debianubuntu):

```bash
# Importar la clave GPG del repo
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

# Agregar el repo a las sources de apt
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
  "https://pkg.jenkins.io/debian-stable binary/" | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Refresh del cache de apt
sudo apt update
```

> **Por qué `signed-by=` en lugar de `apt-key add`**: `apt-key` está deprecated desde Debian 11 / Ubuntu 22.04. El método moderno es referenciar la clave en el archivo de sources directamente — más seguro porque la clave solo aplica a ese repo, no a todo apt.

### 4. Instalar Jenkins

```bash
sudo apt install -y jenkins
```

Validación de versión:

```bash
jenkins --version
```

```
2.555.2
```

### 5. Habilitar y arrancar el servicio

```bash
sudo systemctl enable jenkins
```

```
Synchronizing state of jenkins.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable jenkins
```

```bash
sudo service jenkins start
```

```
 * Starting Jenkins Automation Server jenkins                                    Setting up max open files limit to 8192
```

```bash
sudo service jenkins status
```

```
 * jenkins is running
```

### 6. Verificar el proceso

```bash
sudo ps aux | grep jenkins
```

```
jenkins  3982  0.0  1.1 9314068 771568 ?  Sl  03:36  0:14  /usr/bin/java ...
```

Detalles a notar:

| Campo            | Valor      | Significado                                                              |
| ---------------- | ---------- | ------------------------------------------------------------------------ |
| Usuario          | `jenkins`  | UID dedicado, no root. El paquete lo crea automáticamente               |
| `VSZ` (memoria virtual) | `9314068 KB` (~9.3 GB) | Address space reservado por la JVM — no es uso real          |
| `RSS` (memoria real)    | `771568 KB` (~771 MB)  | Memoria residente actual. Sube según número de builds activos  |
| Comando          | `/usr/bin/java ...` | El runtime — Jenkins es un proceso Java                                  |

> Que `VSZ` sea 9.3 GB es **normal** en procesos Java — la JVM reserva mucho address space pero solo usa lo que necesita. La métrica relevante es `RSS`.

### 7. Leer el initial admin password

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

```
ea7f2b7938904bc19bc9820ec000d741
```

> El log también lo expone:
>
> ```
> ==> /var/log/jenkins/jenkins.log <==
> [LF]> This may also be found at: /var/lib/jenkins/secrets/initialAdminPassword
> ```

### 8. Verificar que la UI responde

```bash
curl -I https://<jenkins-host>:8080/login?from=%2F
```

```
HTTP/2 200
content-type: text/html;charset=utf-8
x-hudson: 1.395
x-jenkins: 2.555.2
x-jenkins-session: 3039cc01
```

Headers a notar:

- `x-jenkins: 2.555.2` — versión confirmada por el header
- `x-hudson: 1.395` — header legacy del proyecto Hudson (Jenkins forkeó Hudson en 2011, mantiene el header por compat)
- `x-frame-options: sameorigin` — protección contra clickjacking
- `cross-origin-opener-policy: same-origin` — aislamiento de procesos del browser

### 9. Setup wizard vía UI

Pasos en el browser apuntando a `http://<jenkins-host>:8080/`:

1. **Unlock Jenkins**: pegar el `initialAdminPassword` (`ea7f2b7938904bc19bc9820ec000d741`)
2. **Customize Jenkins**: elegir **"Install suggested plugins"** — instala ~30 plugins core (Git, Pipeline, GitHub, Folders, Build Timeout, Credentials Binding, Timestamper, etc.)
3. **Create First Admin User**:

| Campo       | Valor del lab                                  |
| ----------- | ---------------------------------------------- |
| Username    | `theadmin`                                     |
| Password    | `Adm!n321`                                     |
| Full name   | `Ravi`                                         |
| Email       | `ravi@jenkins.stratos.xfusioncorp.com`         |

4. **Instance Configuration**: aceptar la URL pública que detecta Jenkins (en KodeKloud es la URL del proxy del lab)
5. **Start using Jenkins**: dashboard final con "Welcome to Jenkins!"

### Validación final

Después del wizard:

- Dashboard muestra "Welcome to Jenkins!" con el nombre del admin user
- `http://<jenkins-host>:8080/me` muestra el perfil del user con `Full name: Ravi` y email correcto
- `/var/lib/jenkins/users/theadmin_<id>/config.xml` contiene el user creado

## Anatomía del proceso instalado — qué crea el paquete .deb

| Recurso                                  | Creado por el `.deb`                                                                |
| ---------------------------------------- | ----------------------------------------------------------------------------------- |
| Usuario `jenkins` (UID/GID)             | `useradd` automático en post-install                                                |
| Directorio `/var/lib/jenkins/`           | Como `JENKINS_HOME`, propiedad de `jenkins:jenkins`                                  |
| Unit file `jenkins.service`              | Registrado en systemd, `enabled` opcional manualmente                                |
| Log dir `/var/log/jenkins/`              | Propiedad de `jenkins:adm`                                                          |
| `/etc/default/jenkins`                   | Defaults editables: `HTTP_PORT=8080`, `JAVA_ARGS`, etc.                              |
| Firewall del nodo                        | **No se toca** — el paquete no abre puertos. Hay que abrir 8080 si hay firewall    |

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `service jenkins start` da timeout                                      | Falta Java o la versión no es compatible (Jenkins 2.500+ requiere Java 17 o 21)                      | `java -version` para verificar. Si falta, `apt install openjdk-21-jre`                            |
| `service jenkins status` reporta inactive después del start             | Falla al levantar la JVM por OOM o config inválida                                                   | Revisar `/var/log/jenkins/jenkins.log` para el stack trace del error                              |
| Log muestra `NoClassDefFoundError: ... X11FontManager`                  | Falta `fontconfig` — la JVM no puede inicializar AWT                                                 | `sudo apt install fontconfig` y reiniciar el servicio                                              |
| `apt install jenkins` falla con `Unable to locate package jenkins`      | El APT repo de Jenkins no está agregado o no se hizo `apt update` después de agregarlo               | Repetir los pasos de agregar el GPG key + sources list, luego `apt update`                        |
| El log muestra `Permission denied` al escribir en `/var/lib/jenkins/`   | Permisos rotos del JENKINS_HOME                                                                      | `chown -R jenkins:jenkins /var/lib/jenkins/` y reiniciar                                          |
| La UI responde pero el setup wizard no aparece (va directo al dashboard) | Jenkins ya pasó el setup (instalación previa con state). El `initialAdminPassword` quedó invalidado | Borrar `/var/lib/jenkins/` (cuidado: borra todo) y reiniciar, o seguir con el admin existente     |
| `curl` al puerto 8080 da `Connection refused`                            | El servicio no terminó de arrancar (Jenkins tarda ~30s en levantar) o no escucha en `0.0.0.0`       | Esperar 30-60s; verificar con `ss -tlnp | grep 8080`                                              |
| Olvidé el admin password después del wizard                              | El admin se crea con hash en `/var/lib/jenkins/users/`                                               | Editar `/var/lib/jenkins/config.xml` y deshabilitar security temporalmente, o resetear el hash    |
| `x-jenkins-session` cambia cada request                                  | Comportamiento normal — cada response trae el ID de sesión del nodo                                  | No es un bug                                                                                       |

## Conexión con días anteriores

Día 68 marca la transición del journal de **Kubernetes (Días 48–67)** a **CI/CD**. Los puentes entre los dos mundos:

- **Git (Días 21–34)**: Jenkins típicamente se conecta a un repo Git, hace checkout, corre tests, construye. Los hooks de `post-update` del Día 34 son la versión "casera" de un trigger de Jenkins.
- **Docker (Días 35–47)**: pipelines de Jenkins típicamente construyen imágenes Docker (`docker build`), las pushean a registries, y luego despliegan.
- **Kubernetes (Días 48–67)**: el deploy step de un pipeline moderno es `kubectl apply` o `helm upgrade` contra el cluster. Jenkins suele tener un Service Account con RBAC limitado al namespace de la app.

La cadena completa en producción típica:

```
Developer → git push
              ↓
         GitHub webhook
              ↓
      Jenkins pipeline (Día 68+)
              ├── git checkout
              ├── unit tests
              ├── docker build + push
              ├── kubectl apply (Día 49+)
              └── notificación a Slack
```

En el journal vienen días de pipelines, freestyle jobs, integraciones — todos construyen sobre la instalación de hoy.

## Reflexión: el cambio de contexto K8s → CI/CD

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- El cambio temático: después de 20 días de K8s, ¿cómo se siente volver a "linux puro" con apt + service + revisar logs en /var/log?
- Jenkins específicamente: ¿lo habías usado antes? Si sí, ¿cuál es tu opinión vs alternativas modernas (GitHub Actions, GitLab CI, ArgoCD, Tekton)?
- Java como runtime: ¿te sorprende que una herramienta tan central de DevOps esté en Java? ¿Notaste el peso (9.3GB VSZ) vs herramientas escritas en Go?
- La práctica de no usar root para el proceso del servicio (UID `jenkins`): ¿es algo que se toma como dado o se configura explícitamente al montar un servicio en producción?
- El `initialAdminPassword` como mecanismo de bootstrap: ¿elegante o anticuado? ¿Cómo lo resolverían otras herramientas (ej. Vault con auto-unseal, ArgoCD con admin password en Secret)?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [Jenkins LTS Installation — Debian/Ubuntu (oficial)](https://www.jenkins.io/doc/book/installing/linux/#debianubuntu)
- [Java requirements for Jenkins](https://www.jenkins.io/doc/book/platform-information/support-policy-java/)
- [Securing Jenkins (oficial)](https://www.jenkins.io/doc/book/security/)
- [JENKINS_HOME explicado](https://www.jenkins.io/doc/book/managing/system-configuration/#jenkins-home)
- [Best practices for backing up Jenkins](https://www.jenkins.io/doc/book/system-administration/backing-up/)
- [Jenkins vs alternatives — comparison](https://www.jenkins.io/doc/book/getting-started/why-jenkins/)
