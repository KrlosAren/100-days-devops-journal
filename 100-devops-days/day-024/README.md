# Dia 24 - Crear branches en un repositorio Git

## Problema / Desafio

Los desarrolladores de Nautilus necesitan crear un nuevo branch para mantener cambios de nuevas funcionalidades separados del codigo principal:

1. En el Storage Server (`ststor01`), ir al repositorio `/usr/src/kodekloudrepos/official`
2. Crear un nuevo branch `xfusioncorp_official` a partir de `master`
3. No modificar ningun archivo del codigo

## Conceptos clave

### git branch — gestion de branches

Un branch en Git es simplemente un puntero movil a un commit. Crear un branch es una operacion ligera — no duplica archivos, solo crea un nuevo puntero:

```
master:               A → B → C (HEAD)

Despues de crear branch:
master:               A → B → C
                                ↑
xfusioncorp_official:           C (nuevo puntero)
```

### Comandos basicos de branches

```bash
# Listar branches locales (* indica el branch actual)
git branch

# Crear un branch nuevo (sin cambiarse a el)
git branch nombre-branch

# Crear un branch desde otro branch especifico
git branch nombre-branch origen

# Crear y cambiarse al nuevo branch
git checkout -b nombre-branch origen

# Equivalente moderno (Git 2.23+)
git switch -c nombre-branch origen

# Eliminar un branch
git branch -d nombre-branch
```

### checkout -b vs branch

| Comando | Crea branch | Se cambia al branch |
|---------|:-----------:|:-------------------:|
| `git branch nombre` | Si | No |
| `git checkout -b nombre` | Si | Si |
| `git switch -c nombre` | Si | Si |

### safe.directory — repositorios con otro owner

Desde Git 2.35.2, Git rechaza operaciones en repositorios cuyo owner no coincide con el usuario actual. Esto es una medida de seguridad contra ataques de escalacion de privilegios:

```bash
# Error cuando el repo pertenece a root pero ejecutas como natasha
git branch
# fatal: detected dubious ownership in repository at '/usr/src/kodekloudrepos/official'

# Agregar excepcion (permite operaciones de lectura sin ser owner)
git config --global --add safe.directory /usr/src/kodekloudrepos/official
```

Despues de agregar la excepcion, los comandos de **lectura** (`git branch`, `git log`) funcionan. Para comandos de **escritura** (`checkout`, `commit`), se necesita ejecutar con `sudo` ya que el repo pertenece a `root`.

### index.lock — bloqueo de operaciones Git

El archivo `.git/index.lock` es un mecanismo de bloqueo que Git usa para evitar operaciones concurrentes. Tambien falla si no tienes permisos de escritura en `.git/`:

```bash
# Error de permisos — no puedes escribir en .git/
git checkout master
# fatal: Unable to create '/usr/src/kodekloudrepos/official/.git/index.lock': Permission denied
```

El `safe.directory` solo permite a Git **leer** el repositorio, pero operaciones que modifican el estado (como `checkout`) necesitan **escribir** en `.git/`. Para resolver esto sin cambiar permisos, se puede ejecutar el comando Git con `sudo`:

```bash
# safe.directory + comando como natasha = solo lectura
git checkout -b nombre master    # ✗ Permission denied

# sudo = ejecuta como root (el owner real del repo)
sudo git checkout -b nombre master    # ✓ funciona
```

**Importante:** No usar `sudo chown` para cambiar los permisos del repositorio — en entornos de laboratorio o produccion, cambiar el ownership puede romper validaciones o afectar a otros servicios que dependen de que el repo pertenezca a `root`.

```
safe.directory (como natasha):      sudo git (como root):
├── git branch     ✓ (lectura)     ├── sudo git branch     ✓
├── git log        ✓ (lectura)     ├── sudo git log        ✓
├── git checkout   ✗ (escritura)   ├── sudo git checkout   ✓
├── git commit     ✗ (escritura)   ├── sudo git commit     ✓
└── git merge      ✗ (escritura)   └── sudo git merge      ✓
```

## Pasos

1. Conectarse al Storage Server como `natasha`
2. Navegar al repositorio
3. Resolver el error de `dubious ownership` con `safe.directory`
4. Crear el branch con `sudo git checkout -b` (el repo pertenece a root)
5. Verificar

## Comandos / Codigo

### 1. Conectarse y navegar al repositorio

```bash
ssh natasha@ststor01
cd /usr/src/kodekloudrepos/official/
```

### 2. Primer intento — dubious ownership

```bash
git branch
```

```
fatal: detected dubious ownership in repository at '/usr/src/kodekloudrepos/official'
To add an exception for this directory, call:
        git config --global --add safe.directory /usr/src/kodekloudrepos/official
```

El repositorio pertenece a `root` pero estamos operando como `natasha`:

```bash
ls -lhart
```

```
drwxr-xr-x 7 root root 4.0K Mar 18 12:04 .git
-rw-r--r-- 1 root root   34 Mar 18 12:04 info.txt
-rw-r--r-- 1 root root   34 Mar 18 12:04 data.txt
```

### 3. Agregar safe.directory

```bash
git config --global --add safe.directory /usr/src/kodekloudrepos/official
```

Ahora `git branch` funciona:

```bash
git branch
```

```
* kodekloud_official
  master
```

### 4. Segundo problema — Permission denied en checkout

```bash
git checkout -b xfusioncorp_official master
```

```
fatal: Unable to create '/usr/src/kodekloudrepos/official/.git/index.lock': Permission denied
```

El `safe.directory` permite lectura pero no escritura en `.git/`. Como el repositorio pertenece a `root`, no debemos cambiar el ownership (`chown`) porque rompe la validacion del laboratorio. La solucion correcta es ejecutar el comando con `sudo`:

### 5. Crear el branch con sudo

```bash
sudo git checkout -b xfusioncorp_official master
```

```
Switched to a new branch 'xfusioncorp_official'
```

### 6. Verificar

```bash
git branch
```

```
  kodekloud_official
  master
* xfusioncorp_official
```

El branch `xfusioncorp_official` fue creado desde `master` y es el branch activo.

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `fatal: detected dubious ownership` | El repo pertenece a otro usuario. Usar `git config --global --add safe.directory <ruta>` |
| `fatal: Unable to create .git/index.lock: Permission denied` | No tienes permisos de escritura en `.git/`. Ejecutar el comando con `sudo` (no cambiar ownership con `chown` si puede romper validaciones) |
| `fatal: A branch named 'x' already exists` | El branch ya existe. Verificar con `git branch` |
| `fatal: not a valid object name: 'master'` | El branch origen no existe. Verificar branches disponibles con `git branch -a` |

## Recursos

- [Git - git-branch Documentation](https://git-scm.com/docs/git-branch)
- [Git - safe.directory](https://git-scm.com/docs/git-config#Documentation/git-config.txt-safedirectory)
- [Git 2.35.2 Security Fix (dubious ownership)](https://github.blog/open-source/git/git-security-vulnerability-announced/)
