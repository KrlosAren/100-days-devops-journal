# Día 33 - Resolver conflictos de merge durante git pull --rebase

## Problema / Desafío

Sarah y Max trabajan sobre el mismo repositorio `story-blog` en Gitea. Max tiene cambios locales que necesita pushear, pero el remote tiene commits de Sarah que Max no tiene. Requisitos:

- Pushear los cambios de Max al remote
- El archivo `story-index.txt` debe tener títulos de las 4 historias
- Corregir el typo: `Mooose` → `Mouse` en la línea de The Lion and the Mouse
- No crear un merge commit (usar rebase)

## Conceptos clave

### Por qué falla el push cuando el remote tiene trabajo nuevo

Cuando otro colaborador pushea al mismo branch, el historial del remote avanza. Git rechaza el push local porque sobrescribiría esos cambios:

```
Antes:
  remote: A → B (Sarah push)
  local:  A → C → D (Max commits)

git push falla: el remote está en B, local en D,
pero D no tiene B como ancestro → non-fast-forward
```

La solución es integrar primero los cambios del remote y luego pushear.

### git pull vs git pull --rebase

| Comando | Resultado |
|---------|-----------|
| `git pull` | Hace fetch + merge → crea un merge commit |
| `git pull --rebase` | Hace fetch + rebase → historial lineal, sin merge commit |

Para este challenge se usa `--rebase` para mantener el historial limpio.

### Conflicto durante el rebase

Cuando tanto el local como el remote modificaron el mismo archivo, el rebase no puede aplicar el commit automáticamente y detiene el proceso:

```
CONFLICT (add/add): Merge conflict in story-index.txt
error: could not apply 63ae53c... Added the fox and grapes story
```

El archivo queda marcado con indicadores de conflicto que hay que resolver manualmente.

### Flujo correcto para resolver conflictos en rebase

```
1. git pull --rebase        → conflicto detectado, rebase pausado
2. Editar el archivo        → resolver los marcadores manualmente
3. git add <archivo>        → marcar como resuelto
4. git rebase --continue    → Git crea el commit y continúa
```

> **Importante:** durante el rebase no usar `git commit` — el `--continue` se encarga de commitear. Si se hace `git commit` primero se entra en un estado de "detached HEAD" que complica el flujo.

## Pasos

1. Conectarse como `max` al Storage server
2. Intentar pushear y diagnosticar el error
3. Asegurarse de tener los cambios correctos commiteados localmente
4. Ejecutar `git pull --rebase` para integrar los cambios del remote
5. Resolver el conflicto en `story-index.txt` con vim
6. Continuar el rebase con `git rebase --continue`
7. Pushear al remote

## Comandos / Código

### 1. Verificar estado inicial

```bash
git log --oneline
```

```
63ae53c (HEAD -> master) Added the fox and grapes story
262fe23 (origin/master, origin/HEAD) Merge branch 'story/frogs-and-ox'
971ca5d Fix typo in story title
f7ae83e Completed frogs-and-ox story
855e4e9 Added the lion and mouse story
1fc997d Add incomplete frogs-and-ox story
```

### 2. Primer intento de push — error de autenticación

```bash
git push origin master
# Username: max / Password: (incorrecto)
```

```
remote: Failed to authenticate user
fatal: Authentication failed for 'http://gitea:3000/sarah/story-blog.git/'
```

### 3. Segundo intento — push rechazado (remote tiene trabajo nuevo)

```bash
git push origin master
# Username: max / Password: Max_pass123
```

```
 ! [rejected]        master -> master (fetch first)
error: failed to push some refs to 'http://gitea:3000/sarah/story-blog.git'
hint: Updates were rejected because the remote contains work that you do not
hint: have locally. If you want to integrate the remote changes, use
hint: 'git pull' before pushing again.
```

Sarah había pusheado un nuevo commit con la historia `donkey-and-dog.txt` y la entrada correspondiente en `story-index.txt`.

### 4. Commitear el fix del typo localmente

```bash
# Editar story-index.txt: corregir "Mooose" → "Mouse"
git commit -m "fix: typo"
```

```
[master 5a54827] fix: type
 1 file changed, 2 insertions(+), 2 deletions(-)
```

### 5. Integrar cambios del remote con rebase

```bash
git pull origin --rebase
```

```
From http://gitea:3000/sarah/story-blog
   262fe23..93c4426  master     -> origin/master
Auto-merging story-index.txt
CONFLICT (add/add): Merge conflict in story-index.txt
error: could not apply 63ae53c... Added the fox and grapes story
hint: Resolve all conflicts manually, mark them as resolved with
hint: "git add/rm <conflicted_files>", then run "git rebase --continue".
```

### 6. Inspeccionar el conflicto

```bash
git diff story-index.txt
```

```diff
diff --cc story-index.txt
--- a/story-index.txt
+++ b/story-index.txt
@@@ -1,3 -1,4 +1,10 @@@
++<<<<<<< HEAD
 +1. The Lion and the Mouse
 +2. The Frogs and the Ox
 +3. The Fox and the Grapes
++=======
+ 1. The Lion and the Mooose
+ 2. The Frogs and the Ox
+ 3. The Fox and the Grapes
 -4. The Donkey and the Dog
++4. The Donkey and the Dog
++>>>>>>> 63ae53c (Added the fox and grapes story)
```

El conflicto muestra:
- **HEAD (remote)**: tiene 3 historias (con "Mooose") + "The Donkey and the Dog"
- **Local**: tiene 3 historias (con "Mouse" ya corregido) pero sin "The Donkey and the Dog"

La resolución correcta combina ambas versiones: 4 historias con el typo corregido.

### 7. Resolver el conflicto con vim

```bash
vim story-index.txt
```

El archivo final después de eliminar los marcadores de conflicto:

```
1. The Lion and the Mouse
2. The Frogs and the Ox
3. The Fox and the Grapes
4. The Donkey and the Dog
```

### 8. Marcar como resuelto y continuar el rebase

```bash
git add story-index.txt
git rebase --continue
```

```
dropping 5a5482744972877dc845eaf720a7e141af225975 fix: type -- patch contents already upstream
Successfully rebased and updated refs/heads/master.
```

> Git detectó que el commit `fix: type` (corrección del typo) ya estaba incorporado en el upstream — lo descartó automáticamente para evitar duplicados.

### 9. Verificar estado final

```bash
git status
```

```
On branch master
Your branch is ahead of 'origin/master' by 3 commits.
  (use "git push" to publish your local commits)

nothing to commit, working tree clean
```

### 10. Push final

```bash
git push origin master
# Username: max / Password: Max_pass123
```

```
To http://gitea:3000/sarah/story-blog.git
   93c4426...<nuevo>  master -> master
```

## Estado final del story-index.txt

```
1. The Lion and the Mouse
2. The Frogs and the Ox
3. The Fox and the Grapes
4. The Donkey and the Dog
```

Las 4 historias con el typo corregido.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `Authentication failed` al hacer push | Verificar usuario y contraseña — en este caso `max` / `Max_pass123` |
| Push rechazado `(fetch first)` | El remote tiene commits que el local no tiene — ejecutar `git pull --rebase` antes de pushear |
| Conflicto durante `git pull --rebase` | Editar el archivo, resolver los marcadores `<<<<<<< / ======= / >>>>>>>`, luego `git add` + `git rebase --continue` |
| El commit `fix` fue descartado (`dropping`) | Git detectó que esos cambios ya existían en el upstream — no es un error, es Git evitando commits duplicados |
| `git commit` durante el rebase crea "detached HEAD" | Durante el rebase usar siempre `git rebase --continue` en lugar de `git commit` para avanzar al siguiente paso |

## Recursos

- [git pull --rebase - Atlassian](https://www.atlassian.com/git/tutorials/syncing/git-pull)
- [Resolving merge conflicts - GitHub Docs](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/addressing-merge-conflicts/resolving-a-merge-conflict-using-the-command-line)
- [git rebase --continue](https://git-scm.com/docs/git-rebase)
