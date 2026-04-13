# Dia 22 - Clonar un repositorio Git bare en el mismo servidor

## Problema / Desafio

El equipo de desarrollo necesita una copia de trabajo de un bare repository existente en el Storage Server:

1. El repositorio bare esta en `/opt/media.git`
2. Clonarlo en `/usr/src/kodekloudrepos/media`
3. Usar el usuario `natasha` sin modificar permisos ni directorios existentes

## Conceptos clave

### git clone — rutas locales vs remotas

`git clone` puede clonar desde diferentes fuentes:

```bash
# Ruta local (mismo servidor)
git clone /opt/media.git /destino/media

# SSH (otro servidor)
git clone natasha@ststor01:/opt/media.git /destino/media

# HTTPS
git clone https://github.com/usuario/media.git /destino/media
```

Si el bare repo y el destino estan en el **mismo servidor**, usar la ruta local es mas eficiente — no hay overhead de red ni autenticacion SSH.

### git clone y el directorio destino

```bash
# Sin especificar destino — crea subcarpeta con el nombre del repo
git clone /opt/media.git
# Resultado: ./media/

# Con destino especifico — clona dentro de esa carpeta
git clone /opt/media.git /usr/src/kodekloudrepos/media
# Resultado: /usr/src/kodekloudrepos/media/
```

| Comando | Resultado |
|---------|-----------|
| `git clone /opt/media.git` | Crea `./media/` en el directorio actual |
| `git clone /opt/media.git mi-copia` | Crea `./mi-copia/` |
| `git clone /opt/media.git /ruta/completa/media` | Crea `/ruta/completa/media/` |

**Importante:** siempre especificar el nombre de la subcarpeta destino para tener control sobre donde queda el repositorio clonado.

### Que sucede al clonar un bare repo

Al clonar un bare repository se obtiene un repositorio **normal** (con working directory):

```
Bare repo (origen):                    Repo clonado (destino):
/opt/media.git/                        /usr/src/kodekloudrepos/media/
├── HEAD                               ├── .git/
├── objects/                           │   ├── HEAD
├── refs/                              │   ├── objects/
└── config                             │   ├── refs/
    bare = true                        │   └── config
                                       │       bare = false
(sin working directory)                ├── archivo1.txt    ← working directory
                                       └── archivo2.txt
```

El repositorio clonado automaticamente configura el origen como remote:

```bash
cd /usr/src/kodekloudrepos/media
git remote -v
```

```
origin  /opt/media.git (fetch)
origin  /opt/media.git (push)
```

## Pasos

1. Conectarse al Storage Server como `natasha`
2. Clonar el bare repository a la ruta destino
3. Verificar el clone

## Comandos / Codigo

### 1. Conectarse al Storage Server

```bash
ssh natasha@ststor01
```

### 2. Clonar el repositorio

```bash
git clone /opt/media.git /usr/src/kodekloudrepos/media
```

```
Cloning into '/usr/src/kodekloudrepos/media'...
done.
```

### 3. Verificar

```bash
# Confirmar que se creo el directorio con el working directory
ls /usr/src/kodekloudrepos/media/

# Verificar el remote configurado
cd /usr/src/kodekloudrepos/media
git remote -v

# Ver el historial
git log --oneline
```

### Lo que hice inicialmente

```bash
# Sin especificar subcarpeta — clona directo en kodekloudrepos/
git clone /opt/media.git /usr/src/kodekloudrepos/
```

Esto funciona si `/usr/src/kodekloudrepos/` esta vacia, pero mezcla los archivos del repo con el directorio destino. Es mejor especificar la subcarpeta para mantener la estructura limpia:

```
# Sin subcarpeta (menos claro):
/usr/src/kodekloudrepos/
├── .git/
├── archivo1.txt
└── archivo2.txt

# Con subcarpeta (recomendado):
/usr/src/kodekloudrepos/
└── media/
    ├── .git/
    ├── archivo1.txt
    └── archivo2.txt
```

## Opciones utiles de git clone

### --depth (shallow clone)

Clona solo los ultimos N commits en lugar del historial completo. Muy util para repos grandes donde no necesitas todo el historial:

```bash
# Solo el ultimo commit
git clone --depth 1 /opt/media.git /destino/media

# Ultimos 5 commits
git clone --depth 5 /opt/media.git /destino/media
```

```
Clone completo:                     Shallow clone (--depth 1):
commit 4 (HEAD)                     commit 4 (HEAD)  ← solo este
commit 3                            (historial truncado)
commit 2
commit 1 (initial)
```

| Aspecto | Clone completo | Shallow clone |
|---------|:--------------:|:-------------:|
| Historial | Todo | Solo los ultimos N commits |
| Tamaño en disco | Mayor | Mucho menor |
| `git log` completo | Si | No — solo muestra N commits |
| `git blame` completo | Si | No — puede faltar contexto |
| Hacer push | Si | Si (con limitaciones) |

**Caso de uso:** pipelines de CI/CD donde solo necesitas el codigo actual para compilar/testear, no el historial completo.

```bash
# Convertir un shallow clone en completo si luego necesitas el historial
git fetch --unshallow
```

### --branch (clonar un branch especifico)

Por defecto `git clone` posiciona el HEAD en el branch default (generalmente `main` o `master`). Con `--branch` puedes clonar y posicionarte directamente en otro branch:

```bash
# Clonar y posicionarse en el branch develop
git clone --branch develop /opt/media.git /destino/media

# Tambien funciona con tags
git clone --branch v2.1.0 /opt/media.git /destino/media
```

**Nota:** esto aun descarga **todos** los branches, solo cambia en cual quedas posicionado.

### --single-branch (solo un branch)

Combinar con `--branch` para descargar **unicamente** un branch, sin traer los demas:

```bash
# Solo descarga el branch develop, nada mas
git clone --branch develop --single-branch /opt/media.git /destino/media
```

```
Clone normal:                       --single-branch develop:
  main                                (no descargado)
  develop    ← todos los branches     develop  ← solo este
  feature-x                           (no descargado)
```

```bash
# Verificar — solo aparece un branch
git branch -a
```

```
* develop
  remotes/origin/develop
```

**Caso de uso:** cuando solo necesitas un branch especifico y quieres ahorrar ancho de banda y espacio. Se puede combinar con `--depth 1` para el clone mas ligero posible:

```bash
# El clone mas ligero: un solo branch, un solo commit
git clone --branch develop --single-branch --depth 1 /opt/media.git /destino/media
```

### --mirror (clon espejo para backups)

Crea una copia exacta del repositorio como bare repo, incluyendo **todas** las referencias (branches, tags, notas, stashes remotos):

```bash
git clone --mirror /opt/media.git /backup/media.git
```

```
Origen:                             Mirror:
/opt/media.git/                     /backup/media.git/
├── HEAD                            ├── HEAD
├── refs/                           ├── refs/          ← copia exacta
│   ├── heads/                      │   ├── heads/
│   └── tags/                       │   └── tags/
└── objects/                        └── objects/        ← todos los objects
```

| Aspecto | `git clone` | `git clone --bare` | `git clone --mirror` |
|---------|:-----------:|:------------------:|:--------------------:|
| Working directory | Si | No | No |
| Branches remotos | Como remotes | Como locales | Como locales |
| Tags | Si | Si | Si |
| Refs especiales (notas, PRs) | No | No | Si |
| Remote configurado | origin | No | origin (con fetch mirror) |

**Caso de uso:** backups completos de repositorios o migrar un repo entre servidores.

```bash
# Actualizar el mirror con los ultimos cambios del origen
cd /backup/media.git
git remote update
```

### --recurse-submodules (incluir submodulos)

Si el repositorio usa submodulos (otros repos Git dentro del repo), `git clone` por defecto **no** los descarga. Quedan como carpetas vacias:

```bash
# Clone normal — submodulos quedan vacios
git clone /opt/media.git /destino/media
ls /destino/media/libs/utils/    # vacio

# Clone con submodulos — todo se descarga
git clone --recurse-submodules /opt/media.git /destino/media
ls /destino/media/libs/utils/    # archivos presentes
```

```bash
# Si ya clonaste sin submodulos, puedes inicializarlos despues
cd /destino/media
git submodule init
git submodule update

# O en un solo comando
git submodule update --init --recursive
```

**Caso de uso:** proyectos que dependen de librerias externas incluidas como submodulos (comun en proyectos C/C++, proyectos monorepo, o configuraciones con modulos compartidos).

### --shallow-since (shallow clone por fecha)

En lugar de limitar por numero de commits, limitar por fecha:

```bash
# Solo commits desde enero 2025
git clone --shallow-since="2025-01-01" /opt/media.git /destino/media
```

**Caso de uso:** cuando necesitas el historial reciente (por ejemplo, ultimos 6 meses) pero no el historico completo del proyecto.

## Protocolos de git clone

Git soporta diferentes protocolos para clonar. Cada uno tiene diferencias en rendimiento, autenticacion y seguridad:

```bash
# Local — ruta en el mismo servidor
git clone /opt/media.git

# Local (file://) — fuerza transporte de red sobre ruta local
git clone file:///opt/media.git

# SSH — el mas comun para servidores propios
git clone usuario@servidor:/opt/media.git

# HTTPS — el mas comun para servicios como GitHub
git clone https://github.com/usuario/media.git

# Git protocol (git://) — solo lectura, sin autenticacion
git clone git://servidor/media.git
```

| Protocolo | Autenticacion | Encriptado | Velocidad | Escritura (push) | Caso de uso |
|-----------|:-------------:|:----------:|:---------:|:-----------------:|-------------|
| Ruta local | Sistema de archivos | N/A | La mas rapida | Si | Mismo servidor |
| `file://` | Sistema de archivos | N/A | Mas lenta que local | Si | Mismo servidor (aislado) |
| SSH | Llaves SSH / password | Si | Rapida | Si | Servidores propios |
| HTTPS | Token / password | Si | Rapida | Si | GitHub, GitLab, servicios web |
| `git://` | Ninguna | No | Rapida | No (solo lectura) | Mirrors publicos |

### Diferencia entre ruta local y file://

```bash
# Ruta local — Git usa hardlinks cuando es posible (mas rapido, menos espacio)
git clone /opt/media.git

# file:// — Git usa el mecanismo de transporte de red (mas lento pero mas aislado)
git clone file:///opt/media.git
```

La ruta local es mas eficiente porque Git puede usar hardlinks para los objects en disco. `file://` fuerza el mismo proceso que usaria con SSH/HTTPS, lo cual es mas seguro si no confias en el repositorio origen (evita copiar objects corruptos).

### Resumen de opciones

| Opcion | Funcion | Ejemplo practico |
|--------|---------|------------------|
| `--depth N` | Solo ultimos N commits | CI/CD pipelines |
| `--branch nombre` | Posicionarse en un branch | Clonar y trabajar directo en `develop` |
| `--single-branch` | Descargar solo un branch | Ahorrar espacio en entornos limitados |
| `--mirror` | Copia exacta como bare repo | Backups, migracion entre servidores |
| `--recurse-submodules` | Incluir submodulos | Proyectos con dependencias Git |
| `--shallow-since` | Commits desde una fecha | Historial reciente sin todo el historico |
| `--bare` | Clonar como bare repo | Crear un nuevo servidor central |

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `fatal: destination path already exists` | El directorio destino ya existe y no esta vacio. Verificar con `ls` antes de clonar |
| `Permission denied` al clonar | Verificar permisos de lectura en `/opt/media.git` y escritura en `/usr/src/kodekloudrepos/` |
| `fatal: repository not found` | Verificar que la ruta del bare repo es correcta: `ls /opt/media.git/HEAD` |
| Se uso ruta SSH en el mismo servidor | Funciona pero es innecesario. Usar ruta local directa: `/opt/media.git` |

## Recursos

- [Git - git-clone Documentation](https://git-scm.com/docs/git-clone)
- [Git - Cloning a Repository](https://git-scm.com/book/en/v2/Git-Basics-Getting-a-Git-Repository)
