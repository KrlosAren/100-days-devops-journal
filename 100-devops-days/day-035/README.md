# Día 35 - Instalar Docker CE e iniciar el servicio

## Problema / Desafío

El equipo de Nautilus DevOps necesita preparar el App Server 2 para trabajar con contenedores. Los requisitos son:

- Instalar `docker-ce` y `docker-compose` en App Server 2 (`stapp02`)
- Iniciar el servicio Docker

## Conceptos clave

### docker-ce vs el docker de los repos del sistema

CentOS Stream 9 incluye `podman-docker` en sus repositorios oficiales — un reemplazo compatible con la CLI de Docker pero que funciona sin daemon (daemonless). `docker-ce` (Community Edition) es el Docker original de Docker Inc., con su daemon (`dockerd`) y el ecosistema completo.

| Paquete | Proveedor | Daemon | Comando |
|---------|-----------|--------|---------|
| `podman-docker` | Fedora/CentOS | No (rootless por defecto) | `docker` (alias de podman) |
| `docker-ce` | Docker Inc. | Sí (`dockerd`) | `docker` |

Para entornos de producción y compatibilidad con herramientas que dependen del socket de Docker (`/var/run/docker.sock`), se necesita `docker-ce`.

### Componentes instalados

```
docker-ce              → daemon de Docker (dockerd)
docker-ce-cli          → cliente CLI (docker)
containerd.io          → runtime de contenedores subyacente
docker-buildx-plugin   → plugin para builds multi-arquitectura
docker-compose-plugin  → Compose integrado como subcomando (docker compose)
```

### systemctl enable --now

Combina dos operaciones en una:
```bash
systemctl enable docker   # habilita el servicio para arrancar al boot
systemctl start docker    # lo inicia ahora mismo
# equivale a:
systemctl enable --now docker
```

## Pasos

1. Verificar la distribución del servidor
2. Buscar el paquete en los repos del sistema (para entender por qué no está)
3. Agregar el repositorio oficial de Docker
4. Instalar los paquetes necesarios
5. Habilitar e iniciar el servicio
6. Verificar la instalación

## Comandos / Código

### 1. Verificar la distribución

```bash
cat /etc/os-release
```

```
NAME="CentOS Stream"
VERSION="9"
ID="centos"
PRETTY_NAME="CentOS Stream 9"
```

App Server 2 corre **CentOS Stream 9**.

### 2. Buscar docker-ce en los repos del sistema

```bash
yum search docker
```

```
ansible-collection-community-docker.noarch
pcp-pmda-docker.x86_64
podman-docker.noarch        ← el sistema ofrece podman-docker, no docker-ce
python3-docker.noarch
...
```

```bash
yum search docker-ce
# No matches found.
```

`docker-ce` no está en los repos de CentOS — hay que agregar el repo oficial de Docker.

### 3. Agregar el repositorio oficial de Docker

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
```

Esto agrega `/etc/yum.repos.d/docker-ce.repo` con los paquetes de Docker apuntando a los servidores de Docker Inc.

### 4. Instalar Docker CE y sus componentes

```bash
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 5. Habilitar e iniciar el servicio

```bash
sudo systemctl enable --now docker
```

### 6. Verificar la instalación

```bash
docker --version
```

```
Docker version 29.4.1, build 055a478
```

```bash
docker compose version
```

```
Docker Compose version v5.1.3
```

```bash
sudo docker run hello-world
```

```
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
4f55086f7dd0: Pull complete
Digest: sha256:f9078146db2e05e794366b1bfe584a14ea6317f44027d10ef7dad65279026885
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.
```

Docker instalado, servicio activo, primer contenedor corriendo.

## Qué hace docker run hello-world internamente

```
docker run hello-world
      ↓
Docker CLI envía la peticion al daemon (dockerd)
      ↓
El daemon busca la imagen "hello-world" localmente → no existe
      ↓
El daemon la descarga de Docker Hub (library/hello-world)
      ↓
El daemon crea un contenedor desde esa imagen
      ↓
El contenedor ejecuta su proceso y produce el output
      ↓
El daemon envía el output al cliente CLI → se imprime en terminal
```

## DNF — el gestor de paquetes

**DNF** (Dandified YUM) es el gestor de paquetes de las distribuciones Red Hat modernas y el sucesor directo de `yum`.

```
RHEL/CentOS 7   →  yum  (Python 2, más lento)
RHEL/CentOS 8+  →  dnf  (Python 3, resolución de dependencias mejorada)
```

En CentOS Stream 9 `yum` es un alias de `dnf` — apuntan al mismo binario:

```bash
which yum
# /usr/bin/yum → symlink a dnf
```

Por eso en este challenge se usaron `yum search` y `sudo dnf install` indistintamente.

### Lo que hace cada comando dnf usado en este día

```bash
# Instala el plugin que agrega el subcomando config-manager a dnf
sudo dnf -y install dnf-plugins-core

# Agrega un archivo .repo en /etc/yum.repos.d/
# Le dice a dnf dónde buscar los paquetes de Docker
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Instala paquetes desde los repos configurados (incluido el recién agregado)
sudo dnf install docker-ce docker-ce-cli containerd.io ...
```

### Referencia rápida de dnf

```bash
dnf search <pkg>          # buscar paquetes
dnf install <pkg>         # instalar
dnf remove <pkg>          # desinstalar
dnf update                # actualizar todo el sistema
dnf list installed        # listar paquetes instalados
dnf repolist              # ver repositorios activos
dnf info <pkg>            # ver detalles de un paquete
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `docker-ce` no encontrado con `yum search` | Agregar el repo oficial: `dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo` |
| `Permission denied` al correr docker sin sudo | Agregar el usuario al grupo docker: `sudo usermod -aG docker $USER` y volver a iniciar sesión |
| El servicio no inicia | Verificar con `sudo systemctl status docker` y revisar logs con `sudo journalctl -u docker` |
| `Cannot connect to the Docker daemon` | El daemon no está corriendo — ejecutar `sudo systemctl start docker` |

## Recursos

- [Install Docker Engine on CentOS - docs.docker.com](https://docs.docker.com/engine/install/centos/)
- [Post-installation steps for Linux](https://docs.docker.com/engine/install/linux-postinstall/)
