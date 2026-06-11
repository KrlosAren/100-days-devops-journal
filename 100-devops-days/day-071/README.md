# Día 71 - Configure Jenkins Job for Package Installation (Freestyle + SSH remoto + String Parameter)

## Problema / Desafío

El equipo Nautilus necesita automatizar la instalación de paquetes en el storage server. La solución: un job de Jenkins parametrizado que conecta vía SSH al server destino y corre `yum install` con el nombre del paquete pasado como argumento.

Requirements:

1. Login a la UI de Jenkins como `admin` / `Adm!n321`
2. Crear job **`install-packages`** tipo Freestyle con:
   - **String parameter** llamado `PACKAGE`
   - Build step que instala el paquete `$PACKAGE` en el **storage server** (`ststor01`, Stratos Datacenter)
3. Buildear al menos una vez con `PACKAGE=vim-enhanced` para validar

Servers involucrados:

| Server         | Rol                                      | Usuario      | OS / Package manager       |
| -------------- | ---------------------------------------- | ------------ | -------------------------- |
| `jenkins`      | Server de Jenkins (controller)          | `jenkins`    | Ubuntu 22.04 / apt         |
| `ststor01`     | Storage server (donde instalar paquetes) | `natasha`    | CentOS Stream 9 / yum/dnf  |

> **Nota crítica**: el server de Jenkins **no es el jump host** — es un server dedicado al que se accede vía el dominio del lab. Conectarse al jump host y desde ahí intentar el setup falla porque las claves SSH del jump host no se propagan al jenkins server.

## Conceptos clave

### Tipos de job en Jenkins

Al hacer `New Item` aparecen varios tipos. Los más comunes:

| Tipo                       | Para qué                                                                          |
| -------------------------- | --------------------------------------------------------------------------------- |
| **Freestyle project**      | El más simple — UI con secciones de Parameters, SCM, Build Steps, Post-Build      |
| **Pipeline**               | Job definido como código en un Jenkinsfile (Groovy) — checked-in al repo          |
| **Multibranch Pipeline**   | Descubre branches/PRs automáticamente, crea un Pipeline job por cada una          |
| **Folder**                 | Agrupa jobs jerárquicamente para organización y permisos                          |
| **Organization Folder**    | Versión avanzada de Multibranch para descubrir repos enteros de una org           |

Este lab usa **Freestyle** porque es el más directo para un caso de un solo step shell. En labs futuros aparecerá Pipeline.

### Parameterized jobs

Marcando **"This project is parameterized"** se agregan inputs que aparecen al disparar un build. Tipos de parámetros:

| Tipo                  | Cuándo usar                                                                                   |
| --------------------- | --------------------------------------------------------------------------------------------- |
| **String**            | Texto libre — caso de este lab (`PACKAGE=vim-enhanced`)                                       |
| **Boolean**           | `true`/`false` — flags como `RUN_TESTS`, `SKIP_DEPLOY`                                        |
| **Choice**            | Lista predefinida de valores — environments (`dev`, `staging`, `prod`)                        |
| **Password**          | Como String pero el valor queda **enmascarado** en logs                                       |
| **File**              | Sube un archivo al workspace antes del build                                                  |
| **Multiline String**  | Texto multilínea (configs, scripts)                                                           |
| **Credentials**       | Dropdown que apunta a un Credential del Credentials Manager                                   |

Dentro del build step, el parámetro se accede como **variable de entorno** con el mismo nombre (`$PACKAGE` en shell, `%PACKAGE%` en batch).

### Build steps

Las acciones que el job ejecuta. Para Freestyle, los más comunes:

| Step                           | Qué hace                                                                  |
| ------------------------------ | ------------------------------------------------------------------------- |
| **Execute shell** (Unix)       | Corre comandos shell en el agent (Linux/macOS)                            |
| **Execute Windows batch**      | Equivalente para Windows                                                  |
| **Invoke Ant** / **Invoke Maven** | Herramientas de build Java                                              |
| **Send files over SSH**        | Plugin que copia archivos al server remoto                                |
| **Conditional step**           | Ejecuta otro step solo si una condición se cumple                         |

El lab usa **Execute shell** con `ssh natasha@ststor01 sudo yum install $PACKAGE -y`.

### El modelo de identidad en CI/CD — el bug central de este lab

Cuando un job de Jenkins se ejecuta, **no usa la identidad del user que lo dispara** (admin, anita, etc.). Usa la identidad del proceso del **agente** que ejecuta el build. Por default, ese proceso corre como el user **`jenkins`** (creado por el `.deb` en Día 68).

Esto significa:

| Lo que el operador hace en su shell                          | Lo que ve el job de Jenkins                                              |
| ------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `ssh-keygen` como root en `/root/.ssh/`                      | El job no ve esa key — busca en `/var/lib/jenkins/.ssh/`                  |
| `ssh-add` en la sesión interactiva                           | El `ssh-agent` muere al cerrar la terminal — el job no lo hereda          |
| `ssh-copy-id` desde `/root/.ssh/id_xxx.pub`                  | La pubkey está en `~natasha/.ssh/authorized_keys` pero corresponde a `root`, no a `jenkins` |
| Probar manualmente `ssh natasha@ststor01` desde el shell de root | Funciona — porque el shell usa la key de root, no la de jenkins         |

Esta es la trampa pedagógica del lab: **todo "funciona" probado a mano desde el shell del operador, pero el job falla** porque el flujo real es:

```
Operador → click "Build Now" en la UI
                 │
                 ▼
       Jenkins (proceso JVM, user jenkins)
                 │
                 ▼
         /bin/sh -xe /tmp/jenkins-<id>.sh
                 │
                 ▼
            ssh natasha@ststor01
                 │  (busca claves en /var/lib/jenkins/.ssh/, NO en /root/.ssh/)
                 ▼
            Permission denied (publickey)
```

### La regla operacional: `sudo -u jenkins` para todas las credenciales

Para generar y distribuir credenciales que el job va a usar, **siempre ejecutar como el user del agente**:

```bash
# ❌ Mal — genera la key como root, en /root/.ssh/
ssh-keygen -t ed25519 -f ~/.ssh/jenkins_key
ssh-copy-id natasha@ststor01  # copia la key de root

# ✅ Bien — genera y distribuye la key como user jenkins
sudo -u jenkins ssh-keygen -t ed25519 -C "jenkins@ci" \
  -f /var/lib/jenkins/.ssh/id_ed25519 -N ""
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub natasha@ststor01
```

El `sudo -u jenkins` hace que:

1. El comando se ejecute con el **UID/GID del user jenkins**
2. `~` se resuelva a `/var/lib/jenkins/` (su home directory)
3. Los archivos creados queden con `owner: jenkins, group: jenkins`
4. Los permisos de `~/.ssh/` se respeten (700 dir, 600 private key)

### `ssh-copy-id` — qué hace internamente

```bash
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub natasha@ststor01
```

Pasos que ejecuta:

1. Lee `/var/lib/jenkins/.ssh/id_ed25519.pub` (la clave **pública**)
2. Se conecta a `ststor01` como `natasha` (pidiendo password una vez)
3. Append el contenido de la pubkey a `~natasha/.ssh/authorized_keys`
4. Ajusta permisos: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`

A partir de ahí, cualquier intento de `ssh natasha@ststor01` desde un proceso que tenga acceso a `/var/lib/jenkins/.ssh/id_ed25519` (la **privada**) puede autenticarse sin password.

### Por qué `natasha` puede ejecutar `sudo yum` sin password

El comando del build step es:

```bash
ssh natasha@ststor01 sudo yum install $PACKAGE -y
```

Para que esto funcione **sin pedir password de natasha** en el medio, el server `ststor01` tiene que tener configurado:

```
# /etc/sudoers (o un drop-in en /etc/sudoers.d/)
natasha ALL=(ALL) NOPASSWD: /usr/bin/yum
```

> KodeKloud configura esto previamente en el storage server del lab. En producción real, hay que evaluar cuidadosamente qué permisos NOPASSWD se conceden — `NOPASSWD: ALL` es equivalente a darle root sin restricciones.

## Pasos

1. Login como `admin` / `Adm!n321`
2. SSH al server `jenkins` desde el jump host
3. Como user jenkins, generar key SSH: `sudo -u jenkins ssh-keygen ...`
4. Como user jenkins, distribuir la pubkey: `sudo -u jenkins ssh-copy-id ...`
5. Validar la conectividad: `sudo -u jenkins ssh natasha@ststor01 hostname`
6. En la UI de Jenkins, crear el job `install-packages` (Freestyle)
7. Marcar "This project is parameterized" y agregar String Parameter `PACKAGE`
8. Agregar Build Step "Execute shell" con el comando SSH
9. Save → Build with Parameters → `PACKAGE=vim-enhanced` → Build
10. Validar el log del build → debería terminar en `Finished: SUCCESS`
11. (Opcional) Buildear de nuevo con `PACKAGE=tree` u otro para confirmar reusabilidad

## Comandos / Código

### Setup de SSH desde el server `jenkins` (lo que sí funciona)

```bash
# Desde el jump host
ssh root@jenkins

# Generar key SSH como user jenkins (no como root)
sudo -u jenkins ssh-keygen -t ed25519 -C "jenkins@ci" \
  -f /var/lib/jenkins/.ssh/id_ed25519 -N ""

# Distribuir la pubkey a natasha@ststor01
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub natasha@ststor01
# (pide password de natasha una vez)

# Validar la conectividad como user jenkins
sudo -u jenkins ssh -o StrictHostKeyChecking=no natasha@ststor01 hostname
```

Output esperado del último comando:

```
ststor01.stratos.xfusioncorp.com
```

> `-N ""` en `ssh-keygen` crea la key **sin passphrase**. Esto es necesario porque Jenkins no tiene shell interactivo donde ingresarla. Para producción con compliance, usar `ssh-agent` o el plugin `SSH Agent` de Jenkins.

> `-o StrictHostKeyChecking=no` en el primer SSH evita la pregunta interactiva "Are you sure you want to continue?". Una vez aceptada la host key, queda en `/var/lib/jenkins/.ssh/known_hosts`.

### Crear el job `install-packages`

Navegación: `Dashboard → New Item`

| Campo               | Valor                |
| ------------------- | -------------------- |
| Enter an item name  | `install-packages`   |
| Item type           | `Freestyle project`  |

Click **OK**.

### Configuración del job

**1. Sección "General" → marcar "This project is parameterized"**

Click **Add Parameter → String Parameter**:

| Campo            | Valor                                            |
| ---------------- | ------------------------------------------------ |
| Name             | `PACKAGE`                                        |
| Default Value    | (vacío — o `vim-enhanced` como hint)             |
| Description      | `Install packages on the storage server (Stratos Datacenter)` |
| Trim the string  | ✅                                                |

> **`Trim the string`** elimina whitespace al inicio/final del valor — útil para evitar errores cuando el operador copia/pega un paquete con un espacio sobrante.

**2. Sección "Build Steps" → Add build step → Execute shell**

Command:

```bash
ssh natasha@ststor01 sudo yum install $PACKAGE -y
```

> Notar que **no hay `-T`** ni `-tt` — el shell de Jenkins no necesita pseudo-terminal. Si se intentara `ssh -t`, el log mostraría `Pseudo-terminal will not be allocated because stdin is not a terminal.` (lo cual es warning, no error).

Click **Save**.

### Disparar un build

Navegación: `Job install-packages → Build with Parameters`

| Campo     | Valor          |
| --------- | -------------- |
| PACKAGE   | `vim-enhanced` |

Click **Build**.

### Log de un build exitoso

```
Started by user admin
Running as SYSTEM
Building in workspace /var/lib/jenkins/workspace/install-packages
[install-packages] $ /bin/sh -xe /tmp/jenkins<...>.sh
+ ssh natasha@ststor01 sudo yum install vim-enhanced -y
Last metadata expiration check: 1:39:00 ago on Mon Jun  1 09:40:56 2026.
Dependencies resolved.
================================================================================
 Package             Arch        Version                   Repository      Size
================================================================================
Installing:
 vim-enhanced        x86_64      2:8.2.2637-29.el9         appstream      1.7 M
Installing dependencies:
 gpm-libs            x86_64      1.20.7-29.el9             appstream       21 k
 vim-common          x86_64      2:8.2.2637-29.el9         appstream      7.0 M
 vim-filesystem      noarch      2:8.2.2637-29.el9         baseos          14 k

Transaction Summary
================================================================================
Install  4 Packages

[...]

Installed:
  gpm-libs-1.20.7-29.el9.x86_64         vim-common-2:8.2.2637-29.el9.x86_64
  vim-enhanced-2:8.2.2637-29.el9.x86_64 vim-filesystem-2:8.2.2637-29.el9.noarch

Complete!
Finished: SUCCESS
```

Detalles a notar en el log:

| Línea / pattern                                          | Significado                                                                  |
| -------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `Started by user admin`                                  | Quién disparó el build (admin desde la UI)                                   |
| `Running as SYSTEM`                                      | El proceso del agente corre con identidad `SYSTEM` (= user jenkins en el OS) |
| `Building in workspace /var/lib/jenkins/workspace/install-packages` | Directorio scratch donde el job hace su trabajo                              |
| `/bin/sh -xe /tmp/jenkins<id>.sh`                        | El script generado dinámicamente con `set -x` (echo de cada comando) y `set -e` (abort on error) |
| `+ ssh natasha@ststor01 ...`                             | El `+` es el output de `set -x` — muestra cada comando antes de ejecutarlo  |
| Output de yum                                            | El stdout/stderr del comando remoto se redirige al log del build vía SSH    |
| `Finished: SUCCESS`                                      | El exit code del shell fue 0                                                |

## Autopsia del bug — el mismatch de claves SSH

### Lo que se hizo inicialmente (no funcionó)

```bash
# Como root en el server jenkins
ssh-keygen -t rsa -b 4096 -f ~/.ssh/jenkins_key

# Copiar la pubkey a natasha SIN especificar -i
ssh-copy-id natasha@ststor01
```

El segundo comando es la trampa: **sin `-i`, `ssh-copy-id` usa la clave default del directory `~/.ssh/`**, que para root podría ser `id_ed25519.pub` (existente por otro setup) en lugar de la recién creada `jenkins_key.pub`.

```bash
# Agregar la clave al ssh-agent — esto solo afecta a la sesión actual de root
eval $(ssh-agent)
ssh-add ~/.ssh/jenkins_key
```

### Lo que el job de Jenkins ve

```
Started by user admin
Running as SYSTEM
[install-packages] $ /bin/sh -xe /tmp/jenkins14904113336962844015.sh
+ ssh natasha@ststor01
Pseudo-terminal will not be allocated because stdin is not a terminal.
Permission denied, please try again.
Permission denied, please try again.
natasha@ststor01: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password).
Build step 'Execute shell' marked build as failure
Finished: FAILURE
```

Por qué falla:

1. El comando `ssh natasha@ststor01` corre como user `jenkins`, no como root
2. Jenkins busca claves en `/var/lib/jenkins/.ssh/` — directorio que **no contiene `jenkins_key`** (la generaste en `/root/.ssh/`)
3. El `ssh-agent` que se inició como root no es visible para el proceso de jenkins
4. SSH cae a "password authentication", pero el server `ststor01` está configurado solo para pubkey

### El fix correcto (lo que sí funciona)

```bash
# Generar la key como user jenkins, en su home directory
sudo -u jenkins ssh-keygen -t ed25519 -C "jenkins@ci" \
  -f /var/lib/jenkins/.ssh/id_ed25519 -N ""

# Distribuir la pubkey desde el filesystem de jenkins, autenticando como jenkins
sudo -u jenkins ssh-copy-id -i /var/lib/jenkins/.ssh/id_ed25519.pub natasha@ststor01
```

Esto:

- Crea `/var/lib/jenkins/.ssh/id_ed25519` (private) y `.pub` (public) con owner `jenkins:jenkins`
- `ssh-copy-id` se conecta a `natasha@ststor01` y appendea **esa pubkey específica** a `~natasha/.ssh/authorized_keys`
- A partir de ahí, cualquier proceso del user `jenkins` (incluido el job) puede `ssh natasha@ststor01` usando la privada

Después del fix, el build #3 termina en `Finished: SUCCESS` (visible en la screenshot final con las 3 entradas de Builds: #1 y #2 con X roja, #3 con check verde).

## Anatomía del filesystem después del fix

```
/var/lib/jenkins/.ssh/
├── id_ed25519          (private key, chmod 600, owner jenkins:jenkins)
├── id_ed25519.pub      (public key, chmod 644)
└── known_hosts         (registro de host keys aceptadas)

/var/lib/jenkins/workspace/install-packages/     (workspace del job, vacío — el job no genera archivos)

/var/lib/jenkins/jobs/install-packages/
├── config.xml          (definición del job — incluye el parámetro PACKAGE y el shell script)
├── builds/
│   ├── 1/              (build #1 — falló)
│   │   ├── log         (output del build)
│   │   └── build.xml
│   ├── 2/              (build #2 — también falló)
│   └── 3/              (build #3 — success con vim-enhanced)
└── nextBuildNumber     (contiene "4" — el próximo build será #4)
```

```
# En ststor01, después de ssh-copy-id:
~natasha/.ssh/authorized_keys
# contiene la línea:
# ssh-ed25519 AAAAC3Nz...wMrwm0= jenkins@ci
```

## Alternativas a este enfoque (referencia, no aplica al lab)

| Alternativa                              | Cuándo conviene                                                                |
| ---------------------------------------- | ------------------------------------------------------------------------------ |
| **SSH Agent plugin de Jenkins**          | Permite usar el Credentials Manager para almacenar la private key — más seguro que tenerla en disco |
| **Jenkins Credentials Binding**          | Inyectar la key en runtime, no en disco permanente                             |
| **Ansible (vía plugin)**                 | El job invoca un playbook que sabe hablar con yum/apt/etc. sin ssh manual      |
| **Agents remotos** (`ststor01` como agent) | El propio storage server se conecta como agent — Jenkins ejecuta el step directamente ahí |
| **Configuration management** (Puppet, Salt) | El job no instala paquetes; pone un manifest en git, el agente lo aplica       |

Para un lab y para uso simple, el enfoque de hoy (SSH directo con key) es el más educativo. En producción real, **SSH Agent plugin + Credentials Manager** es el camino estándar — evita tener la private key como archivo en disco.

## Conexión con días anteriores

- **Día 7 (SSH sin password)**: introdujo `ssh-keygen` + `ssh-copy-id` para el operador. Hoy se vuelve a aplicar pero **para un servicio** (user `jenkins`), no para el operador — la lección clave es la diferencia.
- **Día 68 (Set Up Jenkins Server)**: el `JENKINS_HOME` (`/var/lib/jenkins/`) creado por el `.deb` es donde aterriza el `.ssh/` del user `jenkins` hoy. El user `jenkins` se creó automáticamente en Día 68.
- **Día 70 (Configure User Access)**: el user `admin` que dispara el build es distinto del user `jenkins` que lo ejecuta. La autorización (quién puede disparar) y la identidad de ejecución (quién corre el comando) son dos planos separados.
- **Día 17, 18 (yum/dnf)**: la familia de package managers de RHEL/CentOS aparece de nuevo. La diferencia es que ahora se invoca desde un job CI, no manualmente.
- **Día 21–34 (Git workflow)**: en próximos days el `PACKAGE=vim-enhanced` se reemplazará por `BRANCH=main` u otros parámetros que vengan de un webhook de git. La idea de **job parametrizado** es la base.

## Reflexión: el modelo de identidad en CI/CD

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- El bug central — keys generadas como root pero el job corre como jenkins. ¿Lo viste a la primera o tardó en hacer click? ¿En tu experiencia previa con CI (Jenkins, GitHub Actions, etc.) habías topado con algo similar?
- `sudo -u jenkins` como regla operacional: ¿es un patrón que conocías o algo nuevo? ¿En qué otros contextos lo aplicarías (cron de un servicio, postgres, www-data)?
- El bug "todo funciona a mano pero el job falla" es uno de los más frustrantes del CI/CD. ¿Te ayudó leer el log del build cuidadosamente o probaste primero a tocar configs al azar?
- Comparación con GitHub Actions / GitLab CI: ahí no manejás SSH keys directamente — el runner suele ser efímero y las credentials se inyectan vía secrets. ¿Te parece preferible o pierde flexibilidad?
- Sobre los Freestyle jobs: ¿son cómodos para casos simples como este o la falta de versionado (no hay Jenkinsfile en git) los hace inviables para equipos?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `Permission denied (publickey)` en el log del build                     | La key SSH no está en `/var/lib/jenkins/.ssh/` o no está en `authorized_keys` de natasha             | Generar la key con `sudo -u jenkins ssh-keygen ...` y distribuir con `sudo -u jenkins ssh-copy-id` |
| `ssh-copy-id` copió la clave equivocada                                  | No se usó el flag `-i` — `ssh-copy-id` tomó la clave default del directorio                          | Especificar `-i /var/lib/jenkins/.ssh/id_ed25519.pub` explícitamente                              |
| `Pseudo-terminal will not be allocated because stdin is not a terminal` | Warning informacional cuando `ssh` corre sin terminal. **No es error**                               | Ignorar. Si molesta visualmente, agregar `-T` al `ssh` para suprimir la asignación                |
| `Host key verification failed`                                           | Primera conexión al server destino — `~/.ssh/known_hosts` del user jenkins no tiene la host key      | Conectarse una vez con `sudo -u jenkins ssh -o StrictHostKeyChecking=no natasha@ststor01`         |
| El build #N+1 falla con "yum lock"                                      | Hay otro build corriendo en paralelo o yum tiene un lock huérfano                                    | Desactivar concurrencia (no marcar "Execute concurrent builds"), o `sudo rm /var/run/yum.pid`     |
| `sudo: a password is required` en el log del build                       | El user `natasha` no tiene NOPASSWD configurado para yum                                             | Verificar `/etc/sudoers` en ststor01; agregar `natasha ALL=(ALL) NOPASSWD: /usr/bin/yum`         |
| `Package XXX not available`                                              | Typo en el nombre del paquete, o falta el repo del que viene                                         | Probar manualmente: `ssh natasha@ststor01 yum search <name>`                                     |
| El build se queda colgado sin output                                     | `ssh` está intentando autenticación interactiva (password prompt invisible)                          | Verificar que la key pubkey-only esté funcionando con `sudo -u jenkins ssh natasha@ststor01`     |
| Build OK pero el paquete no aparece instalado en ststor01                | Falsa instalación (el paquete ya estaba); o `yum install` lo instaló pero en otro nodo               | `ssh natasha@ststor01 rpm -q vim-enhanced` para verificar                                        |
| Después de cambiar el build step, el comando viejo se sigue ejecutando  | Hay que hacer Save antes de Build (la UI no aplica cambios in-flight)                                | Cualquier cambio en config requiere Save → Build                                                  |
| `Permission denied` aún después del fix                                  | La pubkey terminó en `authorized_keys` mal formateada (saltos de línea, espacios)                    | Editar manualmente `~natasha/.ssh/authorized_keys`, una key por línea, sin caracteres extra      |

## Recursos

- [Parameterized Builds (oficial)](https://www.jenkins.io/doc/book/pipeline/syntax/#parameters)
- [Freestyle Projects (oficial)](https://www.jenkins.io/doc/book/using/working-with-projects/)
- [SSH Agent plugin](https://plugins.jenkins.io/ssh-agent/) — alternativa moderna a SSH keys en disco
- [Credentials in Jenkins (oficial)](https://www.jenkins.io/doc/book/using/using-credentials/)
- [`sudo -u` man page](https://www.sudo.ws/docs/man/sudo.man/) — el flag clave del lab
- [`ssh-copy-id` man page](https://man.openbsd.org/ssh-copy-id) — cuidado con el `-i`
- [Best practices for CI/CD credential management (OWASP)](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
