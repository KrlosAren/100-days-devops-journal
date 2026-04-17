# Día 31 - Restaurar un stash específico con git stash apply

## Problema / Desafío

Un desarrollador del equipo Nautilus tenía cambios en progreso guardados como stash en el repositorio `/usr/src/kodekloudrepos/cluster` (Storage server, Stratos DC). Se necesita:

1. Identificar los stashes existentes en el repositorio
2. Restaurar específicamente el stash con identificador `stash@{1}`
3. Commitear los cambios restaurados
4. Pushear al remote origin

## Conceptos clave

### ¿Qué es git stash?

`git stash` guarda temporalmente cambios no commiteados (tanto staged como unstaged) en una pila interna de Git, dejando el working tree limpio. Es útil cuando se necesita cambiar de contexto sin perder trabajo en progreso.

```
Working tree con cambios:
  modified: info.txt
  new file: welcome.txt
          ↓ git stash
Working tree limpio (como el último commit)
Pila de stashes: stash@{0} → cambios guardados
```

### Pila de stashes: LIFO

Los stashes se apilan como una estructura LIFO (Last In, First Out). El más reciente siempre es `stash@{0}`:

```
git stash        → queda como stash@{0}
git stash        → el anterior pasa a stash@{1}, el nuevo es stash@{0}
git stash        → stash@{0} nuevo, stash@{1} anterior, stash@{2} el más viejo
```

### git stash apply vs git stash pop

| Comando | Restaura cambios | Elimina el stash de la lista |
|---------|-----------------|------------------------------|
| `git stash apply stash@{N}` | Sí | No — el stash permanece en la lista |
| `git stash pop stash@{N}` | Sí | Sí — el stash se elimina al aplicarlo |

Para este challenge se usa `apply` porque el enunciado solo pide restaurar, no limpiar la lista de stashes.

### Estado del stash aplicado

Cuando el stash fue creado con archivos en staging, `git stash apply` los restaura también en staging:

```
git stash apply stash@{1}
→ "Changes to be committed: new file: welcome.txt"
```

El archivo ya está staged — listo para commitear directamente.

## Pasos

1. Conectarse al Storage server como root
2. Ir al repositorio `/usr/src/kodekloudrepos/cluster`
3. Verificar el estado inicial del repo
4. Listar los stashes disponibles con `git stash list`
5. Aplicar el stash `stash@{1}` con `git stash apply`
6. Verificar que los cambios fueron restaurados
7. Commitear los cambios
8. Pushear al remote origin

## Comandos / Código

### 1. Verificar estado inicial del repositorio

```bash
git status
```

```
On branch master
Your branch is up to date with 'origin/master'.

nothing to commit, working tree clean
```

```bash
ls -lhart
```

```
total 16K
drwxr-xr-x 3 root root 4.0K Apr 17 10:44 ..
-rw-r--r-- 1 root root   34 Apr 17 10:44 info.txt
drwxr-xr-x 3 root root 4.0K Apr 17 10:44 .
drwxr-xr-x 7 root root 4.0K Apr 17 10:49 .git
```

```bash
git log --oneline
```

```
b9a0a10 (HEAD -> master, origin/master) initial commit
```

Un solo commit, working tree limpio — los cambios están guardados en stash.

### 2. Listar los stashes disponibles

```bash
git stash list
```

```
stash@{0}: WIP on master: b9a0a10 initial commit
stash@{1}: WIP on master: b9a0a10 initial commit
```

Hay dos stashes. Se debe restaurar `stash@{1}` (el más antiguo).

### 3. Aplicar el stash específico

```bash
git stash apply stash@{1}
```

```
On branch master
Your branch is up to date with 'origin/master'.

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        new file:   welcome.txt
```

El archivo `welcome.txt` fue restaurado y ya está en staging.

### 4. Verificar el estado después del apply

```bash
git status
```

```
On branch master
Your branch is up to date with 'origin/master'.

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        new file:   welcome.txt
```

### 5. Commitear y pushear

```bash
git commit -am 'git stash apply stash@{1}'
```

```
[master 70509ec] git stash apply stash@{1}
 1 file changed, 1 insertion(+)
 create mode 100644 welcome.txt
```

```bash
git push origin
```

```
Enumerating objects: 4, done.
Counting objects: 100% (4/4), done.
Delta compression using up to 16 threads
Compressing objects: 100% (2/2), done.
Writing objects: 100% (3/3), 314 bytes | 314.00 KiB/s, done.
Total 3 (delta 0), reused 0 (delta 0), pack-reused 0 (from 0)
To /opt/cluster.git
   b9a0a10..70509ec  master -> master
```

## Referencia rápida de git stash

```bash
git stash                      # Guarda cambios actuales en el stash
git stash list                 # Lista todos los stashes
git stash apply stash@{N}      # Aplica el stash N sin eliminarlo
git stash pop stash@{N}        # Aplica el stash N y lo elimina de la lista
git stash drop stash@{N}       # Elimina el stash N sin aplicarlo
git stash clear                # Elimina TODOS los stashes
git stash show stash@{N}       # Muestra un resumen de los cambios del stash N
git stash show -p stash@{N}    # Muestra el diff completo del stash N
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `git stash apply` genera conflictos | Resolver los conflictos manualmente y luego hacer `git add` + `git commit` |
| Se aplicó el stash equivocado | Hacer `git restore .` para descartar los cambios y volver a aplicar el correcto |
| No aparecen stashes en `git stash list` | Los stashes son locales — no se sincronizan con el remote ni se clonan |
| El stash aplicado no tiene los archivos esperados | Verificar con `git stash show -p stash@{N}` qué contenía el stash antes de aplicarlo |

## Recursos

- [git stash - documentación oficial](https://git-scm.com/docs/git-stash)
- [Atlassian - git stash](https://www.atlassian.com/git/tutorials/saving-changes/git-stash)
