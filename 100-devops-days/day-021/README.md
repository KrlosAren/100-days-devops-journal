# Dia 21 - Crear un repositorio Git bare en un servidor

## Problema / Desafio

El equipo de desarrollo necesita un repositorio Git centralizado en el Storage Server de Stratos DC:

1. Instalar Git en el Storage Server usando `yum`
2. Crear un **bare repository** en `/opt/cluster.git`

## Conceptos clave

### git init vs git init --bare

Existen dos formas de inicializar un repositorio Git, y cada una tiene un proposito diferente:

#### git init (repositorio normal)

Crea un repositorio con **working directory** — es decir, una carpeta donde puedes ver, editar y trabajar con los archivos del proyecto. La metadata de Git se guarda dentro de una subcarpeta `.git/`:

```
/opt/cluster/
├── .git/            ← metadata de Git (commits, branches, objects)
│   ├── HEAD
│   ├── objects/
│   ├── refs/
│   └── config
├── archivo1.py      ← working directory (archivos editables)
└── archivo2.py
```

#### git init --bare (repositorio bare)

Crea un repositorio **sin working directory**. No hay archivos editables, solo la estructura interna de Git directamente en la carpeta raiz. Por convencion se usa la extension `.git` en el nombre:

```
/opt/cluster.git/
├── HEAD             ← metadata de Git directamente en la raiz
├── objects/
├── refs/
├── config
└── (NO hay archivos de trabajo)
```

### Comparacion

| Aspecto | `git init` | `git init --bare` |
|---------|-----------|-------------------|
| Working directory | Si — puedes ver y editar archivos | No — solo metadata de Git |
| Estructura | Archivos + `.git/` dentro | Solo contenido de `.git/` en la raiz |
| Hacer commits directamente | Si | No — no hay archivos para editar |
| Recibir `git push` | No recomendado (puede corromper el working directory) | Si — disenado para esto |
| Convencion de nombre | `proyecto/` | `proyecto.git` |

### Casos de uso

| Tipo | Cuando usarlo | Ejemplo |
|------|---------------|---------|
| `git init` | Desarrollo local — donde necesitas editar archivos, hacer commits, probar codigo | Tu laptop, tu estacion de trabajo |
| `git init --bare` | Repositorio centralizado/remoto — donde multiples desarrolladores hacen push | Servidor de Git, almacenamiento compartido, equivalente a lo que hace GitHub/GitLab internamente |

```
Flujo tipico con bare repository:

  Dev 1 (git init)              Servidor (git init --bare)              Dev 2 (git init)
  ┌──────────────┐              ┌──────────────────────┐              ┌──────────────┐
  │ working dir   │ ── push ──→ │  /opt/cluster.git     │ ←── push ── │ working dir   │
  │ + .git/       │ ←── pull ── │  (sin working dir)    │ ── pull ──→ │ + .git/       │
  └──────────────┘              └──────────────────────┘              └──────────────┘
```

### Por que NO usar git init para repositorios remotos

Si haces `git push` a un repositorio normal (con working directory), Git muestra esta advertencia:

```
remote: error: refusing to update checked out branch: refs/heads/master
remote: error: By default, updating the current branch in a non-bare repository is denied
```

Esto sucede porque un push modificaria los objects internos pero **no actualizaria los archivos del working directory**, dejando el repositorio en un estado inconsistente. Los bare repos no tienen este problema porque no hay working directory que pueda quedar desincronizado.

## Pasos

1. Conectarse al Storage Server
2. Instalar Git
3. Crear el bare repository en `/opt/cluster.git`
4. Verificar la estructura

## Comandos / Codigo

### 1. Conectarse al Storage Server

```bash
ssh natasha@ststor01
```

### 2. Instalar Git

```bash
sudo yum install -y git
```

### 3. Crear el bare repository

La solucion correcta es usar `--bare`:

```bash
sudo git init --bare /opt/cluster.git
```

```
Initialized empty Git repository in /opt/cluster.git/
```

Esto crea la estructura de Git directamente en `/opt/cluster.git/` sin working directory.

### 4. Verificar la estructura

```bash
ls /opt/cluster.git/
```

```
HEAD  branches  config  description  hooks  info  objects  refs
```

Si ves estos archivos directamente (sin una subcarpeta `.git/`), el bare repository se creo correctamente.

### Lo que hice inicialmente (incorrecto para este caso)

```bash
# Esto crea un repo NORMAL, no bare
mkdir /opt/cluster
cd /opt/cluster
git init
```

```
Initialized empty Git repository in /opt/cluster/.git/
```

Esto crea `/opt/cluster/.git/` — un repositorio normal con working directory. No cumple el requisito porque:
- La ruta del repositorio es `/opt/cluster/.git/`, no `/opt/cluster.git`
- No es un bare repository, por lo que no esta disenado para recibir `push` de otros desarrolladores

### Otros comandos utiles con bare repos

```bash
# Clonar desde un bare repository
git clone usuario@servidor:/opt/cluster.git

# Agregar como remote en un repo existente
git remote add origin usuario@servidor:/opt/cluster.git

# Ver la configuracion del bare repo
cat /opt/cluster.git/config
```

```ini
[core]
    repositoryformatversion = 0
    filemode = true
    bare = true       ← confirma que es bare
```

## Tu propio servidor Git desde cero

Con un bare repo y acceso SSH tienes un repositorio central completo — es lo que GitHub/GitLab hacen internamente, pero sin la interfaz web.

### Flujo completo

```bash
# 1. En el servidor (una sola vez)
ssh usuario@mi-servidor
git init --bare /opt/mi-proyecto.git

# 2. En tu maquina local — iniciar proyecto y conectar al servidor
git init mi-proyecto
cd mi-proyecto
git remote add origin usuario@mi-servidor:/opt/mi-proyecto.git

# 3. Trabajar normalmente
echo "hola" > archivo.txt
git add archivo.txt
git commit -m "primer commit"
git push origin main

# 4. Otro dev clona desde el mismo servidor
git clone usuario@mi-servidor:/opt/mi-proyecto.git
```

### Deploy automatico con hooks

Los bare repos soportan hooks — scripts que se ejecutan en eventos de Git. Un caso clasico es hacer deploy automatico cada vez que alguien hace push:

```bash
# Crear el hook post-receive
vi /opt/mi-proyecto.git/hooks/post-receive
```

```bash
#!/bin/bash
git --work-tree=/var/www/html --git-dir=/opt/mi-proyecto.git checkout -f
echo "Deploy completado en /var/www/html"
```

```bash
chmod +x /opt/mi-proyecto.git/hooks/post-receive
```

```
Flujo con hook:

  Dev hace push → Bare repo recibe → post-receive se ejecuta → Archivos se copian a /var/www/html
```

| Hook | Cuando se ejecuta |
|------|-------------------|
| `pre-receive` | Antes de aceptar el push (puede rechazarlo) |
| `post-receive` | Despues de aceptar el push (ideal para deploys, notificaciones) |
| `update` | Por cada branch actualizada (control granular) |

### Autenticacion y control de acceso

Un bare repo por si solo no tiene sistema de autenticacion propio — depende del protocolo de transporte que uses para conectarte.

#### Opcion 1: SSH (la mas comun y recomendada)

La autenticacion la maneja el sistema operativo a traves de SSH. Cada desarrollador necesita una cuenta en el servidor o acceso por llave SSH:

```bash
# Crear un usuario dedicado para Git
sudo useradd -m -s /usr/bin/git-shell git
sudo mkdir -p /home/git/.ssh
sudo touch /home/git/.ssh/authorized_keys

# Agregar la llave publica de cada desarrollador
sudo cat dev1_id_rsa.pub >> /home/git/.ssh/authorized_keys
sudo cat dev2_id_rsa.pub >> /home/git/.ssh/authorized_keys

# Crear el bare repo bajo el home del usuario git
sudo git init --bare /home/git/mi-proyecto.git
sudo chown -R git:git /home/git/mi-proyecto.git
```

```bash
# Los devs clonan asi:
git clone git@mi-servidor:mi-proyecto.git
```

**`git-shell`** es una shell restringida que solo permite operaciones Git — el usuario `git` no puede ejecutar comandos arbitrarios en el servidor.

| Control | Como implementarlo |
|---------|-------------------|
| Quien puede hacer push/pull | Agregar/remover su llave publica de `authorized_keys` |
| Restringir a solo Git (no bash) | Usar `git-shell` como shell del usuario |
| Acceso por branch | Hook `update` que valida el usuario y el branch |

#### Opcion 2: HTTP/HTTPS con git-http-backend

Se usa Nginx o Apache como proxy. La autenticacion se maneja con basic auth o certificados:

```nginx
# Configuracion de Nginx para servir repos Git via HTTP
server {
    listen 443 ssl;
    server_name git.ejemplo.com;

    ssl_certificate /etc/ssl/certs/git.pem;
    ssl_certificate_key /etc/ssl/private/git.key;

    location ~ ^/(.+\.git)(/.*)$ {
        auth_basic "Git Repository";
        auth_basic_user_file /etc/nginx/.gitpasswd;

        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        fastcgi_param SCRIPT_FILENAME /usr/libexec/git-core/git-http-backend;
        fastcgi_param GIT_PROJECT_ROOT /opt/repos;
        fastcgi_param PATH_INFO $2;
        include fastcgi_params;
    }
}
```

```bash
# Crear usuarios con htpasswd
htpasswd -c /etc/nginx/.gitpasswd dev1
htpasswd /etc/nginx/.gitpasswd dev2
```

#### Opcion 3: Gitolite (control de acceso avanzado)

Cuando necesitas permisos granulares (quien puede escribir en que branch, que repos puede ver cada usuario) sin instalar GitLab completo:

```bash
# Instalar Gitolite
sudo yum install -y gitolite3

# Configurar con la llave del admin
gitolite setup -pk admin.pub
```

```ini
# Archivo de configuracion de Gitolite (gitolite-admin/conf/gitolite.conf)
repo mi-proyecto
    RW+     =   admin        # admin puede hacer force push
    RW      =   dev1 dev2    # dev1 y dev2 pueden leer y escribir
    R       =   @all         # todos pueden leer
```

### Comparacion de opciones

| Metodo | Complejidad | Autenticacion | Control granular | Caso de uso |
|--------|:-----------:|---------------|:----------------:|-------------|
| SSH + `authorized_keys` | Baja | Llaves SSH | No | Equipos pequenos, acceso total o nada |
| SSH + `git-shell` | Baja | Llaves SSH | No | Igual que arriba pero mas seguro |
| HTTP + basic auth | Media | Usuario/password | No | Acceso sin llaves SSH, tras firewall/proxy |
| Gitolite | Media | Llaves SSH | Si | Permisos por repo, branch y usuario |
| GitLab/Gitea (self-hosted) | Alta | Web + SSH + tokens | Si | Interfaz web, CI/CD, issues, code review |

### Que aportan GitHub/GitLab sobre un bare repo

Un bare repo con SSH te da el nucleo de Git. Los servicios como GitHub agregan capas adicionales:

| Funcionalidad | Bare repo + SSH | GitHub/GitLab |
|---------------|:---------------:|:-------------:|
| Push / Pull / Clone | Si | Si |
| Control de acceso basico | Si (SSH keys) | Si |
| Pull Requests / Merge Requests | No | Si |
| Code Review | No | Si |
| Issues / Project management | No | Si |
| CI/CD integrado | Parcial (hooks) | Si |
| Interfaz web | No | Si |
| Fork / Stars / Social | No | Si |

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `Permission denied` al crear en `/opt/` | Usar `sudo git init --bare /opt/cluster.git` |
| Se creo con `git init` en vez de `--bare` | Eliminar y recrear: `sudo rm -rf /opt/cluster && sudo git init --bare /opt/cluster.git` |
| Push rechazado a un repo normal | El repo destino no es bare. Recrear con `--bare` o configurar `receive.denyCurrentBranch=ignore` (no recomendado) |
| El nombre no termina en `.git` | Convencion, no obligatorio. Pero el reto pide exactamente `/opt/cluster.git` |

## Recursos

- [Git - git-init Documentation](https://git-scm.com/docs/git-init)
- [Git - What is a bare repository?](https://git-scm.com/book/en/v2/Git-on-the-Server-Getting-Git-on-a-Server)
- [Git on the Server - Setting Up the Server](https://git-scm.com/book/en/v2/Git-on-the-Server-Setting-Up-the-Server)
