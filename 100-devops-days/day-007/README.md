# Día 07 - Configurar autenticación SSH sin contraseña (password-less)

## Problema / Desafío

Configurar autenticación SSH sin contraseña para el usuario `thor` desde el servidor jump box hacia todos los app servers, usando el sudo user correspondiente de cada servidor:

| Jump Box | App Server | Sudo User |
|----------|-----------|-----------|
| thor | stapp01 | tony |
| thor | stapp02 | steve |
| thor | stapp03 | banner |

El objetivo es que `thor` pueda conectarse por SSH a cada app server sin ingresar contraseña, usando llaves SSH (key-based authentication).

## Conceptos clave

- **Autenticación por llave SSH**: Mecanismo que usa un par de llaves criptográficas (pública y privada) para autenticar al usuario sin necesidad de contraseña. La llave privada permanece en el cliente y la pública se copia al servidor.
- **Llave privada (`~/.ssh/id_rsa`)**: Archivo secreto que solo debe existir en la máquina del usuario. Nunca se comparte. Es el equivalente a la contraseña, pero criptográfica.
- **Llave pública (`~/.ssh/id_rsa.pub`)**: Archivo que se copia a los servidores remotos. Cualquiera puede verla sin riesgo de seguridad. Se almacena en el archivo `~/.ssh/authorized_keys` del usuario remoto.
- **`authorized_keys`**: Archivo en `~/.ssh/` del usuario remoto que contiene las llaves públicas autorizadas para conectarse como ese usuario. Cada línea es una llave pública.
- **`ssh-keygen`**: Herramienta para generar pares de llaves SSH. Por defecto genera llaves RSA de 3072 bits (en versiones recientes de OpenSSH).
- **`ssh-copy-id`**: Herramienta que copia la llave pública al archivo `authorized_keys` del usuario remoto. Maneja automáticamente la creación del directorio `~/.ssh/` y los permisos correctos.
- **Passphrase vs Password**: La passphrase protege la llave privada localmente. Es diferente a la contraseña de login del servidor. Para autenticación completamente sin interacción, se genera la llave sin passphrase.

## Cómo funciona la autenticación por llave SSH

```
1. thor genera un par de llaves (pública + privada)
2. La llave pública se copia al servidor remoto en ~/.ssh/authorized_keys del sudo user
3. Al conectarse, el servidor envía un desafío cifrado con la llave pública
4. El cliente (thor) descifra el desafío con su llave privada
5. El servidor valida la respuesta y permite el acceso sin contraseña

┌─────────────┐                    ┌─────────────┐
│  Jump Box   │                    │  App Server  │
│             │                    │              │
│ thor        │ ── SSH request ──> │ tony         │
│ ~/.ssh/     │                    │ ~/.ssh/      │
│  id_rsa     │ <── challenge ──── │  authorized_ │
│  id_rsa.pub │ ── response ─────> │  keys        │
│             │ <── access ─────── │              │
└─────────────┘                    └─────────────┘
```

## Pasos

1. Generar el par de llaves SSH para el usuario `thor` en el jump box
2. Copiar la llave pública a `tony` en stapp01
3. Copiar la llave pública a `steve` en stapp02
4. Copiar la llave pública a `banner` en stapp03
5. Verificar la conexión SSH sin contraseña a cada servidor

## Comandos / Código

### 1. Generar el par de llaves SSH

Desde el jump box, como usuario `thor`:

```bash
ssh-keygen -t rsa -b 2048
```

Cuando pregunte por la ubicación, aceptar el valor por defecto (`/home/thor/.ssh/id_rsa`). Cuando pregunte por passphrase, dejar vacío (presionar Enter dos veces) para que la autenticación sea completamente sin interacción:

```
Generating public/private rsa key pair.
Enter file in which to save the key (/home/thor/.ssh/id_rsa): [Enter]
Enter passphrase (empty for no passphrase): [Enter]
Enter same passphrase again: [Enter]
Your identification has been saved in /home/thor/.ssh/id_rsa
Your public key has been saved in /home/thor/.ssh/id_rsa.pub
```

> **Nota**: En entornos de producción se recomienda usar passphrase junto con `ssh-agent` para no comprometer la seguridad. En este ejercicio se omite para cumplir el requisito de acceso sin interacción.

### 2. Copiar la llave pública a cada app server

```bash
ssh-copy-id tony@stapp01
ssh-copy-id steve@stapp02
ssh-copy-id banner@stapp03
```

Cada comando pedirá la contraseña del usuario remoto **una sola vez**. Después de esto, ya no será necesaria.

Salida esperada:

```
/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/home/thor/.ssh/id_rsa.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s)
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is because of the password

Number of key(s) added: 1

Now try logging into the machine with: "ssh 'tony@stapp01'"
and check to make sure that only the key(s) you wanted were added.
```

### 3. Verificar la conexión sin contraseña

```bash
ssh tony@stapp01 "whoami && hostname"
ssh steve@stapp02 "whoami && hostname"
ssh banner@stapp03 "whoami && hostname"
```

Salida esperada (sin solicitar contraseña):

```
tony
stapp01

steve
stapp02

banner
stapp03
```

## Qué hace `ssh-copy-id` internamente

`ssh-copy-id` es un atajo que realiza varias acciones en el servidor remoto:

```bash
# Esto es lo que ssh-copy-id hace por debajo:
# 1. Crea el directorio ~/.ssh si no existe
mkdir -p ~/.ssh

# 2. Establece permisos correctos en el directorio
chmod 700 ~/.ssh

# 3. Agrega la llave pública al archivo authorized_keys
cat id_rsa.pub >> ~/.ssh/authorized_keys

# 4. Establece permisos correctos en el archivo
chmod 600 ~/.ssh/authorized_keys
```

Si `ssh-copy-id` no está disponible en el sistema, se puede hacer manualmente:

```bash
cat ~/.ssh/id_rsa.pub | ssh tony@stapp01 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

## Permisos críticos en SSH

SSH es muy estricto con los permisos. Si los permisos no son correctos, la autenticación por llave falla silenciosamente y SSH pide contraseña como fallback.

| Archivo/Directorio | Permiso | Descripción |
|-------------------|---------|-------------|
| `~/.ssh/` | `700` (`drwx------`) | Solo el dueño puede leer/escribir/entrar |
| `~/.ssh/id_rsa` (llave privada) | `600` (`-rw-------`) | Solo el dueño puede leer/escribir |
| `~/.ssh/id_rsa.pub` (llave pública) | `644` (`-rw-r--r--`) | Todos pueden leer, solo el dueño escribe |
| `~/.ssh/authorized_keys` | `600` (`-rw-------`) | Solo el dueño puede leer/escribir |
| `/home/usuario/` (home dir) | `755` o más restrictivo | No debe tener permisos de escritura para group/others |

Si algo falla, lo primero que se debe verificar son estos permisos.

## Tipos de llaves SSH

`ssh-keygen` soporta varios algoritmos. La elección del tipo de llave afecta la seguridad y compatibilidad:

| Tipo | Flag | Tamaño por defecto | Recomendación |
|------|------|--------------------|---------------|
| RSA | `-t rsa` | 3072 bits | Amplia compatibilidad. Usar mínimo 2048, preferible 4096 |
| Ed25519 | `-t ed25519` | 256 bits (fijo) | Más seguro y rápido que RSA. Recomendado si el servidor lo soporta |
| ECDSA | `-t ecdsa` | 256 bits | Buen rendimiento, pero menos adoptado que Ed25519 |
| DSA | `-t dsa` | 1024 bits | Obsoleto. No usar |

```bash
# Generar llave Ed25519 (recomendado para sistemas modernos)
ssh-keygen -t ed25519

# Generar llave RSA de 4096 bits (máxima compatibilidad)
ssh-keygen -t rsa -b 4096
```

En este ejercicio se usa RSA por ser el más compatible en entornos mixtos.

## Passphrase: qué es, cuándo usarla y cuándo no

### Qué es la passphrase

La passphrase es una contraseña que **cifra la llave privada** en disco. Sin passphrase, cualquier persona que obtenga acceso al archivo `~/.ssh/id_rsa` puede usarlo directamente para autenticarse en todos los servidores donde esté autorizada esa llave. Con passphrase, la llave privada está cifrada y es inútil sin conocer la frase.

```
Sin passphrase:
  Alguien roba id_rsa → tiene acceso inmediato a todos los servidores

Con passphrase:
  Alguien roba id_rsa → archivo cifrado, no puede usarlo sin la passphrase
```

### Por qué NO usarla en sistemas automatizados

En este ejercicio generamos la llave sin passphrase. Esto es intencional y es la práctica estándar en contextos de automatización. La razón es simple: **si la llave tiene passphrase, alguien debe ingresarla cada vez que se usa**.

Escenarios donde la passphrase rompe la automatización:

- **Cron jobs** que se conectan por SSH a otros servidores
- **Scripts de deploy** que copian archivos o reinician servicios
- **Ansible/Terraform/Chef** que ejecutan tareas en hosts remotos
- **Pipelines de CI/CD** que hacen SSH a servidores de staging/producción
- **Herramientas de backup** que transfieren archivos entre servidores

En todos estos casos no hay un humano presente para escribir la passphrase. Si la llave la tiene, el proceso falla o se queda colgado esperando input.

### Cuándo SÍ usar passphrase

Para **acceso interactivo** (un humano conectándose manualmente por SSH), siempre se recomienda passphrase. Si alguien compromete tu laptop o workstation, la passphrase es la última línea de defensa.

### `ssh-agent`: passphrase sin repetirla

`ssh-agent` es un proceso que corre en segundo plano y **almacena en memoria las llaves privadas descifradas**. Se ingresa la passphrase una sola vez al inicio de la sesión, y `ssh-agent` la recuerda hasta que se cierre la sesión o se elimine manualmente.

```bash
# Iniciar ssh-agent (si no está corriendo)
eval $(ssh-agent)

# Agregar la llave (pide la passphrase una vez)
ssh-add ~/.ssh/id_rsa
Enter passphrase for /home/thor/.ssh/id_rsa: [ingresa passphrase]
Identity added: /home/thor/.ssh/id_rsa

# A partir de aquí, SSH usa la llave sin pedir passphrase
ssh tony@stapp01    # entra sin pedir nada
ssh steve@stapp02   # entra sin pedir nada
```

`ssh-agent` solo sirve para sesiones interactivas. No resuelve el problema de automatización porque requiere que alguien ingrese la passphrase al menos una vez por sesión.

### Cómo proteger llaves sin passphrase

Si la llave no tiene passphrase (como en automatización), se compensa con otras medidas de seguridad:

| Medida | Qué hace |
|--------|----------|
| Permisos `600` en `id_rsa` | Solo el dueño puede leer la llave |
| Limitar el usuario en el servidor | El usuario remoto tiene permisos mínimos (principio de menor privilegio) |
| Restringir comandos en `authorized_keys` | Permite solo un comando específico por llave (ver sección siguiente) |
| Rotación de llaves | Regenerar llaves periódicamente y revocar las anteriores |
| Monitoreo de acceso | Revisar logs de `/var/log/secure` o `/var/log/auth.log` |

## Opciones avanzadas de SSH

### Restringir comandos por llave en `authorized_keys`

Se puede limitar qué comando puede ejecutar una llave específica. Útil para llaves de automatización sin passphrase:

```bash
# En ~/.ssh/authorized_keys del servidor remoto:
command="/usr/local/bin/backup.sh",no-port-forwarding,no-X11-forwarding ssh-rsa AAAA...== thor@jumpbox
```

Con esta configuración, aunque alguien robe la llave, solo puede ejecutar `backup.sh`. Cualquier otro comando se ignora.

### Restringir por IP de origen

Se puede limitar desde qué IPs se acepta una llave:

```bash
# Solo acepta conexiones desde 192.168.1.100
from="192.168.1.100" ssh-rsa AAAA...== thor@jumpbox

# Acepta desde una subred
from="192.168.1.0/24" ssh-rsa AAAA...== thor@jumpbox

# Combinar con restricción de comando
from="192.168.1.100",command="/usr/local/bin/deploy.sh" ssh-rsa AAAA...== thor@jumpbox
```

### Archivo `~/.ssh/config` para simplificar conexiones

En lugar de recordar usuarios, hosts y puertos, se pueden definir alias en `~/.ssh/config`:

```bash
# ~/.ssh/config
Host app1
    HostName stapp01.stratos.xfusioncorp.com
    User tony
    IdentityFile ~/.ssh/id_rsa

Host app2
    HostName stapp02.stratos.xfusioncorp.com
    User steve
    IdentityFile ~/.ssh/id_rsa

Host app3
    HostName stapp03.stratos.xfusioncorp.com
    User banner
    IdentityFile ~/.ssh/id_rsa
```

Después solo se usa el alias:

```bash
# En vez de:
ssh tony@stapp01.stratos.xfusioncorp.com

# Se usa:
ssh app1
```

También se pueden definir opciones globales:

```bash
Host *
    ServerAliveInterval 60       # Enviar keepalive cada 60 segundos
    ServerAliveCountMax 3        # Desconectar después de 3 keepalives sin respuesta
    StrictHostKeyChecking no     # No preguntar al conectar a hosts nuevos (solo en labs)
    IdentitiesOnly yes           # Solo usar la llave especificada, no probar todas
```

### Comparación de métodos de autenticación SSH

| Método | Seguridad | Automatización | Caso de uso |
|--------|-----------|----------------|-------------|
| Contraseña | Baja (vulnerable a brute force) | No (requiere input) | Acceso temporal o inicial |
| Llave sin passphrase | Media (depende de protección del archivo) | Sí | Scripts, cron, CI/CD, Ansible |
| Llave con passphrase | Alta | No (requiere input) | Acceso interactivo diario |
| Llave + passphrase + ssh-agent | Alta | Parcial (requiere input al inicio de sesión) | Acceso interactivo frecuente |
| Llave + restricción de comando/IP | Alta | Sí | Automatización en producción |
| Certificados SSH | Muy alta (gestión centralizada) | Sí | Infraestructura grande con muchos servidores |

## Control de privilegios sudo después de la conexión SSH

SSH solo controla **quién puede conectarse**. Una vez dentro del servidor, los privilegios se controlan con `sudo` y el archivo `/etc/sudoers`.

### Sin sudo (por defecto)

Un usuario normal no tiene sudo a menos que se le otorgue explícitamente:

```bash
$ sudo systemctl restart httpd
tony is not in the sudoers file. This incident will be reported.
```

### Sudo completo

Acceso total a cualquier comando como cualquier usuario:

```bash
# En /etc/sudoers o /etc/sudoers.d/tony
tony ALL=(ALL) ALL
```

Es lo más común pero lo menos seguro. El usuario puede hacer cualquier cosa como root.

### Sudo limitado a comandos específicos

Solo permite ejecutar ciertos comandos:

```bash
# tony solo puede reiniciar httpd y ver logs
tony ALL=(ALL) /usr/bin/systemctl restart httpd, /usr/bin/cat /var/log/messages
```

Si intenta `sudo rm -rf /`, se le niega.

### Sudo sin contraseña (`NOPASSWD`)

No pide la contraseña del usuario al ejecutar sudo. Necesario para automatización:

```bash
# Sin contraseña para todo
tony ALL=(ALL) NOPASSWD: ALL

# Sin contraseña solo para comandos específicos (más seguro)
tony ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart httpd
```

### Sudo por grupo

Permite dar privilegios a todos los miembros de un grupo con `%`:

```bash
# Todos los del grupo "deployers" pueden hacer deploy sin contraseña
%deployers ALL=(ALL) NOPASSWD: /usr/local/bin/deploy.sh
```

### Limitar a qué usuario puede escalar

Por defecto, `sudo` ejecuta como `root`. Se puede restringir a otro usuario:

```bash
# tony solo puede ejecutar comandos como "www-data", no como root
tony ALL=(www-data) /usr/bin/systemctl restart httpd
```

```bash
# Se especifica el usuario destino con -u
sudo -u www-data systemctl restart httpd
```

### Anatomía de una línea en sudoers

```
tony    ALL=(ALL)    NOPASSWD:    /usr/bin/systemctl restart httpd
│       │    │        │            │
│       │    │        │            └─ Comando(s) permitido(s)
│       │    │        └─ No pedir contraseña (opcional)
│       │    └─ Como qué usuario puede ejecutar (ALL = cualquiera)
│       └─ Desde qué host (ALL = cualquier host)
└─ Usuario o %grupo
```

### Buena práctica: usar `/etc/sudoers.d/`

En vez de editar `/etc/sudoers` directamente, crear un archivo por usuario o rol en `/etc/sudoers.d/`:

```bash
# Siempre editar con visudo (valida sintaxis antes de guardar)
sudo visudo -f /etc/sudoers.d/tony
```

**Por qué `visudo` y no editar directo**: Si hay un error de sintaxis en `/etc/sudoers`, puedes quedarte **sin acceso a sudo en todo el sistema**. `visudo` valida la sintaxis antes de guardar y rechaza archivos con errores.

### Relación entre SSH y sudo en este ejercicio

En el contexto de este día, el flujo completo es:

```
thor (jump box) ──SSH sin contraseña──> tony (stapp01) ──sudo──> root
```

1. **SSH** controla la conexión: thor se autentica con llave pública en stapp01 como tony
2. **sudo** controla los privilegios: tony puede (o no) escalar a root según lo definido en sudoers

Son dos capas de seguridad independientes. Tener acceso SSH no implica tener sudo, y tener sudo configurado no sirve sin poder conectarse primero.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| SSH sigue pidiendo contraseña después de copiar la llave | Verificar permisos: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` en el servidor remoto |
| `ssh-copy-id: command not found` | Copiar manualmente con `cat ~/.ssh/id_rsa.pub \| ssh user@host "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"` |
| `Permission denied (publickey)` | La llave no está en `authorized_keys` del usuario remoto, o los permisos del home directory son demasiado abiertos |
| `Agent admitted failure to sign` | Agregar la llave al agente: `ssh-add ~/.ssh/id_rsa` |
| `WARNING: UNPROTECTED PRIVATE KEY FILE!` | La llave privada tiene permisos demasiado abiertos. Corregir con `chmod 600 ~/.ssh/id_rsa` |
| `Host key verification failed` | Primera conexión al servidor. Agregar el host con `ssh-keyscan stapp01 >> ~/.ssh/known_hosts` o aceptar manualmente |
| Funciona con un usuario pero no con otro | Verificar que la llave se copió al usuario correcto en el servidor correcto. Revisar `~/.ssh/authorized_keys` de cada usuario |

## Recursos

- [ssh-keygen - Manual](https://man7.org/linux/man-pages/man1/ssh-keygen.1.html)
- [ssh-copy-id - Manual](https://man7.org/linux/man-pages/man1/ssh-copy-id.1.html)
- [OpenSSH Key Management](https://www.ssh.com/academy/ssh/keygen)
- [SSH Public Key Authentication](https://www.ssh.com/academy/ssh/public-key-authentication)
- [sudoers Manual](https://man7.org/linux/man-pages/man5/sudoers.5.html)
- [visudo Manual](https://man7.org/linux/man-pages/man8/visudo.8.html)
