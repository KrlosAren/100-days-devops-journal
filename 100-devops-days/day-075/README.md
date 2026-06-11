# Día 75 - Jenkins Slave Nodes (Controller + 3 Agents, inbound JNLP)

## Problema / Desafío

El equipo Nautilus necesita que Jenkins ejecute tareas **directamente en los 3 app servers** en lugar de hacer SSH cada vez desde el controller. La solución: configurar los servers como **agents permanentes** de Jenkins.

Requirements:

1. Login a la UI de Jenkins como `admin` / `Adm!n321`
2. Agregar los 3 app servers como SSH build agents:

| Nodo            | Server real | Label    | Remote root directory |
| --------------- | ----------- | -------- | --------------------- |
| `App_server_1`  | `stapp01`   | `stapp01` | `/home/tony/jenkins`     |
| `App_server_2`  | `stapp02`   | `stapp02` | `/home/steve/jenkins`    |
| `App_server_3`  | `stapp03`   | `stapp03` | `/home/banner/jenkins`   |

3. Los 3 agents deben quedar **online**

## Conceptos clave

### Controller vs Agent — terminología actualizada

Hasta Jenkins 2.319 la terminología era "master/slave". Desde entonces el proyecto migró a **controller/agent** por razones inclusivas:

| Terminología vieja          | Terminología actual             |
| --------------------------- | ------------------------------- |
| Master                      | **Controller**                  |
| Slave                       | **Agent**                       |
| Slave node                  | **Permanent Agent**             |

> La UI de Jenkins todavía muestra "Slave Nodes" en algunos lugares y el lab también usa "slave". Pero al crear un nodo, el tipo correcto es **"Permanent Agent"**. Saber las dos palabras es útil al leer docs de distintas épocas.

### Por qué distribuir builds en agents

Hasta ahora todos los builds del journal (Días 71-74) corrieron en el **controller** (`Running as SYSTEM` + workspace en `/var/lib/jenkins/workspace/<job>`). Ese modelo tiene límites:

| Problema en single-node                                              | Solución con agents distribuidos                                  |
| -------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Builds compiten por CPU/memoria del controller                       | Cada build corre en un agent dedicado                             |
| Builds pesados (compilación, tests) impactan la UI del controller    | El controller solo coordina; el peso queda en los agents          |
| Imposible correr builds que requieran OS distintos (Windows + Linux) | Cada agent puede ser de un OS distinto                            |
| Imposible aislar builds por entorno (dev vs prod)                    | Labels en los agents + targeting por label en los jobs            |
| Single point of failure                                              | El controller cae pero los agents ya pueden completar su build    |

Para este lab los 3 agents son redundantes desde el punto de vista de capacidad (3 servers Linux idénticos). La utilidad real está en el **targeting por label**: un job que necesita acceder a `stapp02` puede ir directo a ese agent en lugar de hacer SSH desde el controller.

### Anatomía de un agent

Cada agent corre un proceso Java (`agent.jar`) que:

1. Establece conexión con el controller (puerto 50000 por TCP/JNLP, o WebSocket sobre HTTPS al puerto 8080)
2. Recibe comandos del controller (workspace setup, ejecución de scripts, transferencia de archivos)
3. Reporta status, logs y resultados back al controller

```
┌─────────────────────────┐                ┌─────────────────────────┐
│  Jenkins Controller     │                │  Agent (stapp01)        │
│  (server jenkins)       │                │  user: tony             │
│                         │                │                         │
│  Web UI                 │  WebSocket /   │  java -jar agent.jar    │
│  Job scheduler  ◄──────►│  TCP socket   ◄─►  Workspace:           │
│  Build queue            │  (puerto 8080  │    /home/tony/jenkins   │
│  Plugins                │   o 50000)     │  Executor (1 slot)      │
│                         │                │                         │
└─────────────────────────┘                └─────────────────────────┘
```

### Métodos de conexión agent ↔ controller

| Método                                          | Quién inicia la conexión        | Cuándo usar                                                  |
| ----------------------------------------------- | ------------------------------- | ------------------------------------------------------------ |
| **Launch agent by connecting it to the controller** (inbound JNLP — usado en este lab) | El agent → al controller | Agent detrás de NAT/firewall, no reachable desde controller  |
| **Launch agents via SSH**                       | El controller → al agent (SSH)  | Producción típica — controller arranca el agent solo         |
| **Launch agent by JNLP** (legacy)               | El agent → al controller (TCP)  | Versiones viejas; reemplazado por WebSocket en moderno       |

El lab usa el primer método: el comando `java -jar agent.jar ...` se ejecuta **en el agent**, autenticándose con un `-secret <token>` único que el controller generó al crear el nodo.

### Estructura del comando de conexión

```bash
java -jar agent.jar \
  -url http://jenkins:8080/ \
  -secret f2b3b659a8b9e020b31affc4ce04bdcf9c433167147624c6441c9de095467268 \
  -name "App_server_1" \
  -webSocket \
  -workDir "/home/tony/jenkins"
```

| Flag              | Significado                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------- |
| `-url`            | URL del controller (`http://jenkins:8080/`)                                                  |
| `-secret`         | Token único por agent — actúa como "password" para que el controller acepte la conexión      |
| `-name`           | Nombre del nodo tal como aparece en la UI                                                    |
| `-webSocket`      | Usa WebSocket (HTTP/HTTPS) en lugar de TCP/JNLP — atraviesa proxies y firewalls HTTP        |
| `-workDir`        | Directorio raíz en el filesystem del agent donde Jenkins crea workspaces, caches, logs       |

> El `secret` se invalida si el agent ya está conectado o si el nodo se borra/recrea. Para reconectar después de una desconexión transitoria, el mismo secret funciona — pero si el nodo se borró y recreó, hay que copiar el nuevo secret desde la UI.

### Por qué los agents necesitan Java instalado

`agent.jar` es un proceso Java — corre sobre la JVM. **Cada agent necesita Java instalado** (la misma versión LTS que el controller idealmente, mínimo Java 17 para Jenkins 2.500+).

```bash
sudo yum install -y java-17-openjdk    # RHEL/CentOS Stream 9 (este lab)
sudo apt install -y openjdk-17-jre     # Debian/Ubuntu
```

> El agent **no necesita Jenkins instalado** — solo el JRE y el `agent.jar` que se descarga desde el controller.

### Glosario del manifest del nodo

| Campo                          | Significado                                                                                       |
| ------------------------------ | ------------------------------------------------------------------------------------------------- |
| **Name**                       | Identificador único del nodo (`App_server_1`)                                                     |
| **Description**                | (Opcional) texto libre — útil en clusters grandes                                                 |
| **Number of executors**        | Cuántos builds paralelos puede ejecutar este agent (default 1)                                    |
| **Remote root directory**      | Workspace base — Jenkins crea subdirectorios por job (`<workDir>/workspace/<job-name>/`)          |
| **Labels**                     | Tags arbitrarios — un agent puede tener varios labels separados por espacios                      |
| **Usage**                      | `Use this node as much as possible` (default) o `Only build jobs with label expressions matching` |
| **Launch method**              | `Launch agent by connecting it to the controller` (inbound) o `Launch agents via SSH`             |
| **Availability**               | `Keep this agent online as much as possible` (default) o variantes con schedule                   |

### Labels — el mecanismo de targeting

Los labels son **strings arbitrarios** que el operador define. Un agent puede tener varios separados por espacios:

```
stapp01 linux app-tier datacenter-1
```

Un job puede declarar a qué label dirigirse:

| Tipo de job  | Cómo se declara                                            |
| ------------ | ---------------------------------------------------------- |
| **Freestyle** | Marcar "Restrict where this project can be run" → ingresar el label  |
| **Pipeline (declarative)** | `pipeline { agent { label 'stapp01' } ... }`            |
| **Pipeline (scripted)**    | `node('stapp01') { ... }`                                |

Sintaxis de label expressions:

| Expresión           | Matchea                                                         |
| ------------------- | --------------------------------------------------------------- |
| `stapp01`           | Cualquier agent con el label `stapp01`                          |
| `linux && stable`   | Agents que tengan **ambos** labels                              |
| `linux \|\| windows` | Agents con **al menos uno** de los dos                          |
| `linux && !windows` | Agents con `linux` pero **sin** `windows`                       |
| `master`            | Reservado — el controller (si tiene executors habilitados)      |

### Estado de un nodo

| Status              | Significado                                                                       |
| ------------------- | --------------------------------------------------------------------------------- |
| ✅ **Online**        | Conectado, listo para recibir builds                                              |
| ❌ **Offline**       | No conectado — agent muerto, comando interrumpido, network failure                |
| ⏸ **Temporarily offline** | Marcado offline manualmente por el operador (mantenimiento, etc.)           |
| 🔄 **Connecting**    | Negociando handshake con el controller                                            |

Recuperación de un agent offline:

1. SSH al agent
2. Verificar si el proceso `java -jar agent.jar` sigue corriendo: `ps -ef | grep agent.jar`
3. Si murió, re-ejecutar el comando completo (con el secret de la UI)

## Pasos

1. Login como `admin` / `Adm!n321`
2. **Manage Jenkins → Nodes → New Node**
3. Crear nodo `App_server_1`:
   - Type: **Permanent Agent**
   - Number of executors: `1`
   - Remote root directory: `/home/tony/jenkins`
   - Labels: `stapp01`
   - Launch method: **Launch agent by connecting it to the controller**
   - Save
4. Hacer click sobre el nodo recién creado — Jenkins muestra el comando exacto a ejecutar en el agent (con el secret incluido)
5. SSH al server `stapp01` (como `tony`)
6. Instalar Java 17: `sudo yum install -y java-17-openjdk`
7. Crear el directorio `mkdir -p /home/tony/jenkins`
8. Descargar `agent.jar`: `curl -sO http://jenkins:8080/jnlpJars/agent.jar`
9. Ejecutar el comando `java -jar agent.jar ...` con el secret del paso 4
10. Verificar en la UI que el nodo pasó a **Online**
11. Repetir 3-10 para `App_server_2` (stapp02, user `steve`) y `App_server_3` (stapp03, user `banner`)

## Comandos / Código

### 1. Crear el nodo desde la UI

Navegación: **Manage Jenkins → Nodes → + New Node**

| Campo                         | Valor para App_server_1                              |
| ----------------------------- | ---------------------------------------------------- |
| Node name                     | `App_server_1`                                       |
| Type                          | Permanent Agent                                      |
| Number of executors           | `1`                                                  |
| Remote root directory         | `/home/tony/jenkins`                                 |
| Labels                        | `stapp01`                                            |
| Usage                         | Use this node as much as possible                    |
| Launch method                 | Launch agent by connecting it to the controller      |
| Availability                  | Keep this agent online as much as possible           |

Click **Save**.

### 2. Vista del nodo recién creado (offline)

```
S    Name           Architecture  Clock Difference  Free Disk Space  ...
❌   App_server_1   N/A           N/A               N/A              N/A
✅   Built-In Node  Linux (amd64) In sync           312.76 GiB       ...
```

El ícono ❌ indica offline. Click sobre `App_server_1` para ver las instrucciones de conexión.

### 3. Comando que el controller genera

Jenkins muestra el comando exacto a copiar al agent:

```bash
curl -sO https://<jenkins-url>/jnlpJars/agent.jar
java -jar agent.jar \
  -url https://<jenkins-url>/ \
  -secret f2b3b659a8b9e020b31affc4ce04bdcf9c433167147624c6441c9de095467268 \
  -name "App_server_1" \
  -webSocket \
  -workDir "/home/tony/jenkins"
```

> El `secret` es **único por nodo**. Copiar el de cada nodo respectivo (`App_server_1`, `App_server_2`, `App_server_3`) cuando se conecta cada agent.

### 4. En el agent `stapp01` — preparación

```bash
# Desde el jump host
ssh tony@stapp01

# Instalar Java 17 (necesario para correr el agent.jar)
sudo yum install -y java-17-openjdk

# Verificar
java -version
# openjdk version "17.0.12" ...
```

```bash
# Crear el directorio destino
mkdir -p /home/tony/jenkins
cd /home/tony/jenkins

# Descargar el agent.jar desde el controller
curl -sO http://jenkins:8080/jnlpJars/agent.jar

# Validar que el archivo bajó
ls -la agent.jar
# -rw-r--r-- 1 tony tony 4.2M Jun 6 ... agent.jar
```

### 5. Ejecutar el agent

```bash
java -jar agent.jar \
  -url http://jenkins:8080/ \
  -secret f2b3b659a8b9e020b31affc4ce04bdcf9c433167147624c6441c9de095467268 \
  -name "App_server_1" \
  -webSocket \
  -workDir "/home/tony/jenkins"
```

Output esperado:

```
INFO: Using /home/tony/jenkins/remoting as a remoting work directory
INFO: Both error and output logs will be printed to /home/tony/jenkins/remoting
INFO: Locating server among [http://jenkins:8080/]
INFO: Agent discovery successful
  Agent address: jenkins
  Agent port:    50000
  Identity:      27:xx:xx:xx:...
INFO: Handshaking
INFO: Connecting to jenkins:50000
INFO: Trying protocol: JNLP4-connect
INFO: Remote identity confirmed
INFO: Connected
```

El proceso **se queda corriendo en foreground**. Si se cierra el shell, el agent muere. Para producción real, ver la sección "Mejora: agent como servicio systemd" más abajo.

### 6. Verificar en la UI

Volver a **Manage Jenkins → Nodes**. El nodo aparece ahora online:

```
S    Name           Architecture   Clock Difference  Free Disk Space
✅   App_server_1   Linux (amd64)  In sync           327.72 GiB
✅   Built-In Node  Linux (amd64)  In sync           312.76 GiB
```

### 7. Repetir para `App_server_2` y `App_server_3`

| Nodo            | User SSH | Server     | Label     | Remote root           |
| --------------- | -------- | ---------- | --------- | --------------------- |
| `App_server_1`  | `tony`   | `stapp01`  | `stapp01` | `/home/tony/jenkins`     |
| `App_server_2`  | `steve`  | `stapp02`  | `stapp02` | `/home/steve/jenkins`    |
| `App_server_3`  | `banner` | `stapp03`  | `stapp03` | `/home/banner/jenkins`   |

El flow es idéntico para los 3 — solo cambia el user, el path y el secret de cada nodo.

### 8. Vista final con los 3 agents online

```
S    Name           Architecture   Clock Difference  Free Disk Space  Free Swap Space  Response Time
✅   App_server_1   Linux (amd64)  In sync           327.72 GiB       0 B             22ms
✅   App_server_2   Linux (amd64)  In sync           317.97 GiB       0 B             149ms
✅   App_server_3   Linux (amd64)  In sync           354.59 GiB       0 B             68ms
✅   Built-In Node  Linux (amd64)  In sync           309.95 GiB       0 B             0ms
```

## Mejora: agent como servicio systemd

El comando `java -jar agent.jar ...` corre en foreground. Si el shell SSH se cierra, el agent muere y el nodo queda offline. Para producción real, conviene envolverlo en un **servicio systemd**:

```bash
# Como root en stapp01
sudo tee /etc/systemd/system/jenkins-agent.service <<'EOF'
[Unit]
Description=Jenkins Agent (App_server_1)
After=network.target

[Service]
Type=simple
User=tony
WorkingDirectory=/home/tony/jenkins
ExecStart=/usr/bin/java -jar /home/tony/jenkins/agent.jar \
  -url http://jenkins:8080/ \
  -secret f2b3b659a8b9e020b31affc4ce04bdcf9c433167147624c6441c9de095467268 \
  -name "App_server_1" \
  -webSocket \
  -workDir "/home/tony/jenkins"
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now jenkins-agent.service
sudo systemctl status jenkins-agent.service
```

> El secret queda en el unit file de systemd (`/etc/systemd/system/jenkins-agent.service`). Para mayor seguridad, leerlo de un archivo separado con `EnvironmentFile=` y `-secret @/etc/jenkins-agent/secret`.

## Validación funcional — disparar un job en un agent específico

Crear un job de prueba que use el label:

| Campo                                       | Valor          |
| ------------------------------------------- | -------------- |
| Restrict where this project can be run      | ✅              |
| Label Expression                            | `stapp01`      |
| Build Steps → Execute shell                 | `hostname; whoami; pwd` |

Build Now. El log esperado:

```
Running as SYSTEM
Building remotely on App_server_1 (stapp01) in workspace /home/tony/jenkins/workspace/test-agent-job
[test-agent-job] $ /bin/sh -xe /tmp/jenkins<id>.sh
+ hostname
stapp01.stratos.xfusioncorp.com
+ whoami
tony
+ pwd
/home/tony/jenkins/workspace/test-agent-job
Finished: SUCCESS
```

Lo que cambia respecto a builds anteriores:

| Línea                                                 | Significado                                              |
| ----------------------------------------------------- | -------------------------------------------------------- |
| `Building remotely on App_server_1 (stapp01)`         | El build se ejecutó en el agent, no en el controller     |
| `Workspace /home/tony/jenkins/workspace/...`          | Workspace en el filesystem del agent, no del controller  |
| `whoami → tony`                                       | El proceso corre como el user del agent, no como `jenkins` del controller |

> Importante: a partir de ahora, los jobs anteriores (Día 71-74) que hacían `ssh tony@stapp01 ...` desde el controller podrían **simplificarse** ejecutándose directamente en el agent `stapp01`. Sin `ssh`, sin SSH keys, ejecutando como user nativo del server.

## Anatomía del filesystem en un agent

```
# En stapp01 (después del setup)
/home/tony/jenkins/
├── agent.jar                       ← El binario descargado del controller
├── remoting/                       ← Working dir de la conexión
│   ├── logs/                       ← Logs del agent (no de los jobs)
│   └── temp/
└── workspace/                      ← Workspaces de cada job que corre acá
    └── <job-name>/
        └── ... archivos del build
```

## Conexión con días anteriores

- **Día 68 (Jenkins Server Setup)**: el controller que se instaló entonces es lo que ahora coordina los 3 agents. El `/var/lib/jenkins/` del controller sigue siendo el `JENKINS_HOME`, pero los workspaces de los builds que usan agents viven en el filesystem del agent.
- **Día 8 (Instalar Ansible con pip3)** y **Día 11 (Apache Tomcat)**: ambos involucraron instalación de Java en servers. Hoy se repite ese patrón para los agents.
- **Día 71-74 (Jenkins jobs con SSH)**: todos esos jobs hacían `ssh <user>@<server>` desde el controller. Con agents configurados, los jobs **podrían ejecutarse directamente en el server** sin SSH manual:
  - Día 71 (install-packages): correr el job en el agent `stapp02` directamente con `agent { label 'stapp02' }`, sin necesidad del `ssh natasha@ststor01` (aunque para llegar al storage server, sí seguiría siendo necesario)
  - Día 73 (copy-logs): correr en el agent `stapp02` directamente, `cat /var/log/httpd/access_log` local, después `scp` solo a ststor01
- **Día 70 (User Access)**: el user `jenkins` del controller no aplica en los agents. Cada agent tiene su user dedicado (`tony`, `steve`, `banner`). Los builds que corren en un agent ejecutan como **ese** user, no como `jenkins`.

## Reflexión: arquitectura distribuida en CI/CD

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- El cambio conceptual de single-node a multi-agent: ¿se siente como un salto grande operacionalmente? ¿Cuál es la imagen mental que queda al separar "coordinación" (controller) de "ejecución" (agents)?
- Antes había que hacer `ssh tony@stapp01 ...` desde el controller. Ahora un job puede correr **directamente en stapp01** con `agent { label 'stapp01' }`. ¿En qué casos preferirías cada enfoque?
- Comparación con K8s: el controller de Jenkins es como el control plane (api-server + scheduler), los agents son como los workers. Misma arquitectura conceptual aunque la plomería es distinta.
- El método "inbound JNLP" del lab vs "SSH inbound": ¿qué te parece más limpio? El inbound requiere que el agent siempre esté corriendo (con el comando manual), SSH inbound el controller arranca el agent solo. ¿Trade-off entre control y conveniencia?
- El detalle de que `java -jar agent.jar` muere si se cierra el shell — ¿es una falla de diseño o un patrón "Unix-like" donde el operador es responsable de la durabilidad del proceso (con systemd, nohup, tmux)?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `java: command not found` al ejecutar `java -jar agent.jar`              | Java no instalado en el agent                                                                        | `sudo yum install -y java-17-openjdk` (RHEL) o `sudo apt install openjdk-17-jre` (Debian)         |
| `Error: A JNI error has occurred, please check your installation`        | Versión de Java demasiado vieja (Jenkins 2.500+ requiere Java 17 mínimo)                             | Reinstalar con `java-17-openjdk` o `java-21-openjdk`                                              |
| `Connection refused` al ejecutar el agent                                | El hostname `jenkins` no resuelve, o el puerto 50000/8080 no es alcanzable                           | Verificar con `ping jenkins` y `curl http://jenkins:8080/`                                        |
| `Authentication failed` al conectar el agent                             | Secret incorrecto, o el nodo se borró/recreó después de copiar el comando                            | Volver a la UI del nodo, copiar el secret actualizado                                             |
| Nodo aparece offline después de cerrar el shell SSH                      | El proceso `java -jar agent.jar` murió al cerrar el shell                                            | Usar `nohup`, `tmux`, o crear servicio systemd (ver sección dedicada)                             |
| Después de reboot del agent, queda offline                              | El comando se ejecutó en foreground; reboot lo mata                                                  | Servicio systemd con `Restart=on-failure` y `WantedBy=multi-user.target`                          |
| Permission denied al crear `/home/tony/jenkins/`                         | Permisos del home directory de tony no permiten escribir                                             | `sudo chown tony:tony /home/tony/jenkins` o crear como user tony desde el inicio                  |
| El nodo aparece online pero los builds fallan con "executor unavailable" | El nodo tiene 0 executors configurados                                                               | Manage Jenkins → Nodes → App_server_X → Configure → Number of executors >= 1                      |
| Job dirigido a label `stapp01` no se schedule                            | Ningún agent tiene ese label, o el agent con ese label está offline                                  | Verificar labels: `Manage Jenkins → Nodes → App_server_X → Configure → Labels`                    |
| `JNLP4: peer didn't accept any of our protocols` al conectar              | Mismatch de versiones entre controller y agent.jar (descargado de otro Jenkins)                      | Re-descargar `agent.jar` desde el mismo controller con `curl -sO http://jenkins:8080/jnlpJars/agent.jar` |
| El agent conecta pero los builds fallan con "Can't find any executable" | Falta `git`, `docker`, herramientas específicas en el agent                                          | Pre-instalar las herramientas que los builds necesitan, o usar Docker agents                      |
| Logs del agent (no de los builds) — dónde buscar                         | `<workDir>/remoting/logs/` en el agent contiene logs del agent.jar                                   | `tail -f /home/tony/jenkins/remoting/logs/remoting.log`                                           |

## Recursos

- [Distributed builds (oficial)](https://www.jenkins.io/doc/book/using/using-agents/)
- [Permanent agents](https://www.jenkins.io/doc/book/managing/nodes/)
- [Launching agents (oficial)](https://www.jenkins.io/doc/book/using/using-agents/#launching-agents)
- [Inbound TCP/WebSocket agents](https://www.jenkins.io/doc/administration/requirements/inbound-agents/)
- [Labels and node selection](https://www.jenkins.io/doc/book/pipeline/syntax/#agent-parameters)
- [Jenkins terminology update (master → controller)](https://www.jenkins.io/blog/2020/06/18/terminology-update/)
- [Running agent as systemd service (community guide)](https://www.jenkins.io/doc/book/managing/nodes/#using-systemd)
