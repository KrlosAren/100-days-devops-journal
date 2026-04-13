# Día 25 - Flujo completo de branch: crear, commitear, mergear y pushear

## Problema / Desafío

El equipo de desarrollo de Nautilus trabaja sobre el repositorio `/opt/demo.git` (bare), clonado en `/usr/src/kodekloudrepos/demo` en el Storage Server. Los requerimientos son:

1. Crear un nuevo branch `devops` desde `master` en `/usr/src/kodekloudrepos/demo`
2. Copiar el archivo `/tmp/index.html` (presente en el servidor) al repositorio
3. Agregar y commitear el archivo en el branch `devops`
4. Mergear `devops` de vuelta a `master`
5. Pushear ambos branches al origin

## Conceptos clave

### Fast-forward merge

Cuando un branch no ha divergido del branch origen, Git no crea un commit de merge — simplemente mueve el puntero hacia adelante. Esto se llama **fast-forward**:

```
Antes del merge:
master:  A → B
               ↑
devops:        B → C (index.html)

Despues de git merge devops (desde master):
master:  A → B → C   ← el puntero avanza, sin merge commit
devops:      B → C   ← no cambia
```

Para forzar un merge commit aunque sea fast-forward: `git merge --no-ff devops`

### Por que mergear master en devops al final

Despues de mergear `devops` en `master`, si el merge fue fast-forward, `devops` ya apunta al mismo commit que `master` y el `git merge master` es un no-op. Pero si hubiera habido commits nuevos en `master` que `devops` no tenia, este paso sincroniza `devops` con esos cambios. Es el patron de mantener el feature branch actualizado.

### git push origin `<branch>`

`git push` sin argumentos solo empuja la rama actual si tiene un upstream configurado. Para empujar una rama especifica (o una que no tiene upstream aun):

```bash
git push origin master    # empuja master al remote 'origin'
git push origin devops    # empuja devops al remote 'origin'
```

Si el branch no existe en el remote, se crea automaticamente.

### Repositorios bare vs clonados

| | Repositorio bare (`demo.git`) | Repositorio clonado (`demo/`) |
|---|---|---|
| Contiene | Solo la historia Git (sin working tree) | Working tree + `.git/` |
| Uso | Servidor central, recibe pushes | Desarrollo local |
| Configuracion | `bare = true` en config | `bare = false` |

El flujo es: trabajar en el clon → pushear al bare → otros clonan/pullan del bare.

## Pasos

1. Conectarse al Storage Server como `natasha`
2. Elevar privilegios con `sudo su` (el repositorio pertenece a `root`)
3. Navegar al repositorio clonado
4. Verificar el estado del repo y los branches existentes
5. Crear el branch `devops` desde `master`
6. Copiar `index.html` al directorio del repo
7. Agregar y commitear el archivo
8. Mergear `devops` en `master`
9. Mergear `master` en `devops` para mantenerlo sincronizado
10. Pushear ambos branches al origin

## Comandos / Código

### 1. Conectarse y elevar privilegios

```bash
ssh natasha@ststor01
sudo su
```

### 2. Navegar al repositorio y verificar estado

```bash
cd /usr/src/kodekloudrepos/demo
git branch
```

```
* master
```

### 3. Crear el branch devops desde master

```bash
git checkout -b devops master
```

```
Switched to a new branch 'devops'
```

### 4. Copiar el archivo al repositorio y commitearlo

```bash
cp /tmp/index.html .
git add index.html
git commit -m 'add: index.html'
```

```
[devops 3a1f2c4] add: index.html
 1 file changed, 1 insertion(+)
 create mode 100644 index.html
```

### 5. Mergear devops en master

```bash
git checkout master
git merge devops
```

```
Updating b2c1d3e..3a1f2c4
Fast-forward
 index.html | 1 +
 1 file changed, 1 insertion(+)
 create mode 100644 index.html
```

El merge es fast-forward: no hay commits en `master` que `devops` no tuviera.

### 6. Mergear master en devops (sincronizar)

```bash
git checkout devops
git merge master
```

```
Already up to date.
```

Como el merge anterior fue fast-forward, `devops` ya apunta al mismo commit que `master`.

### 7. Pushear ambos branches al origin

```bash
git push origin master
git push origin devops
```

```
Counting objects: 3, done.
Writing objects: 100% (3/3), 274 bytes | 274.00 KiB/s, done.
To /opt/demo.git
   b2c1d3e..3a1f2c4  master -> master
```

```
Total 0 (delta 0), reused 0 (delta 0)
To /opt/demo.git
 * [new branch]      devops -> devops
```

### Verificacion final

```bash
git log --oneline --all --graph
```

```
* 3a1f2c4 (HEAD -> devops, origin/master, origin/devops, master) add: index.html
* b2c1d3e Initial commit
```

Ambos branches apuntan al mismo commit y estan sincronizados con el origin.

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `fatal: detected dubious ownership` | El repo pertenece a root. Ejecutar como root con `sudo su` o usar `git config --global --add safe.directory <ruta>` |
| `fatal: Unable to create .git/index.lock: Permission denied` | No hay permisos de escritura en `.git/`. Usar `sudo su` antes de operar |
| `error: failed to push some refs` | El remote tiene commits que el local no tiene. Hacer `git pull origin <branch>` antes del push |
| `fatal: 'origin' does not appear to be a git repository` | El remote `origin` no esta configurado. Verificar con `git remote -v` |
| La validacion del lab falla con "required changes are not pushed to new branch" | Los merges se hicieron localmente pero no se pushearon al remote. Ejecutar `git push origin master` y `git push origin devops` |

## Recursos

- [Git - git-merge Documentation](https://git-scm.com/docs/git-merge)
- [Git - About fast-forward merges](https://git-scm.com/book/en/v2/Git-Branching-Basic-Branching-and-Merging)
- [Git - git-push Documentation](https://git-scm.com/docs/git-push)
