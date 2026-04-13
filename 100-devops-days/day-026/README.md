# Día 26 - Agregar un remote adicional en Git y pushear a él

## Problema / Desafío

El equipo de DevOps agregó nuevos remotes en el servidor Git. Se necesita actualizar el repositorio `/usr/src/kodekloudrepos/cluster` con lo siguiente:

1. Agregar un nuevo remote `dev_cluster` apuntando a `/opt/xfusioncorp_cluster.git`
2. Copiar `/tmp/index.html` al repo, agregar y commitear en `master`
3. Pushear `master` al nuevo remote `dev_cluster`

## Conceptos clave

### git remote — gestión de remotes

Un repositorio Git puede tener múltiples remotes. Cada remote es un alias que apunta a una URL (o ruta local). El nombre `origin` es solo una convención — no tiene nada de especial frente a cualquier otro nombre:

```bash
# Ver remotes actuales
git remote -v

# Agregar un remote nuevo
git remote add <nombre> <url-o-ruta>

# Eliminar un remote
git remote remove <nombre>

# Renombrar un remote
git remote rename <nombre-viejo> <nombre-nuevo>
```

### Múltiples remotes: casos de uso

| Caso | Configuracion tipica |
|------|---------------------|
| Fork workflow | `origin` = tu fork, `upstream` = repo original |
| Deploy a multiples entornos | `origin` = repo principal, `staging` = servidor staging |
| Mirror/backup | `origin` = GitHub, `backup` = servidor interno |
| Este reto | `origin` = `/opt/cluster.git`, `dev_cluster` = `/opt/xfusioncorp_cluster.git` |

### git push `<remote>` `<branch>`

`git push` sin argumentos empuja al upstream del branch actual (generalmente `origin`). Para especificar a cuál remote pushear:

```bash
git push dev_cluster master   # empuja master al remote dev_cluster
git push origin master        # empuja master al remote origin
```

Ambos remotes son independientes — un push a `dev_cluster` no afecta a `origin` ni viceversa.

### git commit -am vs git add + git commit

```bash
# -a agrega automaticamente todos los archivos tracked modificados
# -m especifica el mensaje de commit
git commit -am 'mensaje'

# Equivalente explícito
git add archivo.html
git commit -m 'mensaje'
```

El flag `-a` solo funciona con archivos que Git ya trackea (aparecen en `git status` como `modified`). Para archivos nuevos (`untracked`) se necesita `git add` explícito primero — aunque en este caso `cp` creó un archivo nuevo, Git lo trackeó correctamente porque el commit fue justo despues del `cp`.

> Nota: `git commit -am` incluye archivos `untracked` recien copiados solo si Git los detecta como parte del working tree en ese momento. Para mayor seguridad, usar `git add` + `git commit -m`.

## Pasos

1. Conectarse al Storage Server y elevar privilegios con `sudo su`
2. Navegar al repositorio clonado
3. Verificar los remotes existentes
4. Agregar el nuevo remote `dev_cluster`
5. Copiar `index.html` y commitear en `master`
6. Pushear `master` al nuevo remote

## Comandos / Código

### 1. Conectarse y navegar al repo

```bash
ssh natasha@ststor01
sudo su
cd /usr/src/kodekloudrepos/cluster
```

### 2. Verificar remotes existentes

```bash
git remote -v
```

```
origin  /opt/cluster.git (fetch)
origin  /opt/cluster.git (push)
```

### 3. Agregar el nuevo remote

```bash
git remote add dev_cluster /opt/xfusioncorp_cluster.git
git remote -v
```

```
dev_cluster     /opt/xfusioncorp_cluster.git (fetch)
dev_cluster     /opt/xfusioncorp_cluster.git (push)
origin          /opt/cluster.git (fetch)
origin          /opt/cluster.git (push)
```

### 4. Copiar el archivo y commitear

```bash
cp /tmp/index.html .
git commit -am 'add: index.html'
```

```
[master d3bbd7a] add: index.html
 1 file changed, 10 insertions(+)
 create mode 100644 index.html
```

### 5. Pushear master al nuevo remote

```bash
git push dev_cluster master
```

```
Counting objects: 3, done.
Writing objects: 100% (3/3), 347 bytes | 347.00 KiB/s, done.
To /opt/xfusioncorp_cluster.git
 * [new branch]      master -> master
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `fatal: 'dev_cluster' does not appear to be a git repository` | La ruta del remote no existe o es incorrecta. Verificar con `ls /opt/xfusioncorp_cluster.git` |
| `error: remote dev_cluster already exists` | El remote ya fue agregado. Verificar con `git remote -v` |
| `git commit -am` no incluye el archivo nuevo | `-a` solo trackea archivos ya conocidos por Git. Usar `git add archivo` antes del commit |
| `error: failed to push some refs` | El remote tiene commits que el local no tiene. Hacer `git pull dev_cluster master` antes |

## Recursos

- [Git - git-remote Documentation](https://git-scm.com/docs/git-remote)
- [Git - Working with Remotes](https://git-scm.com/book/en/v2/Git-Basics-Working-with-Remotes)
