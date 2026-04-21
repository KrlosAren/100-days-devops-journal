# Día 32 - Rebase de feature branch sobre master

## Problema / Desafío

El equipo de Nautilus tiene el repositorio `/opt/games.git` clonado en `/usr/src/kodekloudrepos/games` (Storage server, Stratos DC). Un desarrollador trabajó en el branch `feature`, pero mientras tanto se integraron cambios al branch `master`. Los requisitos son:

- Rebasar el branch `feature` sobre `master` para incorporar los cambios nuevos
- **No** crear un merge commit
- No perder ningún cambio del branch `feature`
- Pushear el resultado al remote

## Conceptos clave

### git rebase vs git merge

| Característica | `git merge` | `git rebase` |
|----------------|-------------|--------------|
| Integra cambios de otro branch | Sí | Sí |
| Crea un merge commit | Sí | No |
| Preserva el historial exacto | Sí (divergencia visible) | No (reescribe commits) |
| Historial resultante | No lineal | Lineal |
| Requiere force push al remote | No | Sí (cuando el branch ya existe en el remote) |

### Qué hace git rebase internamente

Antes del rebase, el historial diverge desde el commit `initial commit`:

```
master:   1514106 → ebba27e (Update info.txt)
feature:  1514106 → 4bb1814 (Add new feature)
```

`git rebase master` "despega" los commits de `feature` y los vuelve a aplicar encima del HEAD de `master`:

```
Antes:                          Después:
                                master:   1514106 → ebba27e
master:   1514106 → ebba27e     feature:  1514106 → ebba27e → 54384a3
feature:  1514106 → 4bb1814                                   (nuevo hash)
```

El commit `Add new feature` obtiene un **nuevo hash** (`54384a3`) porque su commit padre cambió — aunque el contenido del commit es el mismo.

### Por qué falla git push después del rebase

El remote `origin/feature` todavía apunta al hash viejo (`4bb1814`). Desde la perspectiva de Git, el local "retrocedió" y tiene una historia diferente — el push normal lo rechaza para proteger el historial remoto. La solución es `git push --force`, que sobreescribe el remote con la nueva historia local.

## Pasos

1. Verificar el estado del repo y el branch actual (`feature`)
2. Cambiar a `master` y asegurar que está actualizado con `git pull`
3. Volver a `feature` y ejecutar `git rebase master`
4. Verificar el nuevo historial lineal
5. Pushear con `--force` al remote

## Comandos / Código

### 1. Verificar estado inicial

```bash
git status
```

```
On branch feature
nothing to commit, working tree clean
```

```bash
git log --oneline
```

```
4bb1814 (HEAD -> feature, origin/feature) Add new feature
1514106 initial commit
```

```bash
git branch -a
```

```
* feature
  master
  remotes/origin/feature
  remotes/origin/master
```

El branch `feature` está por detrás de `master` — `master` tiene el commit `ebba27e` que `feature` aún no tiene.

### 2. Actualizar master y volver a feature

```bash
git checkout master
```

```
Switched to branch 'master'
Your branch is up to date with 'origin/master'.
```

```bash
git pull origin master
```

```
From /opt/games
 * branch            master     -> FETCH_HEAD
Already up to date.
```

`master` ya estaba sincronizado con el remote — el paso del `pull` es una buena práctica para asegurar que el rebase se hace contra la versión más reciente.

```bash
git checkout feature
```

```
Switched to branch 'feature'
```

### 3. Ejecutar el rebase

```bash
git rebase master
```

```
Successfully rebased and updated refs/heads/feature.
```

### 4. Verificar el historial después del rebase

```bash
git log --oneline
```

```
54384a3 (HEAD -> feature) Add new feature
ebba27e (origin/master, master) Update info.txt
1514106 initial commit
```

El historial ahora es lineal: el commit `Add new feature` está encima de `Update info.txt`. El hash cambió de `4bb1814` a `54384a3` — mismo contenido, nuevo padre.

### 5. Force push al remote

```bash
git push -f origin feature
```

```
To /opt/games.git
 + 4bb1814...54384a3 feature -> feature (forced update)
```

## Troubleshooting

### Error: push rechazado después del rebase

```
! [rejected]        feature -> feature (non-fast-forward)
error: failed to push some refs to '/opt/games.git'
```

**Causa:** El rebase reescribió el hash del commit. El remote tiene `4bb1814`, el local tiene `54384a3` — Git ve historiales divergentes y rechaza el push normal.

**Solución:** `git push -f origin feature` (force push).

---

### Error al intentar git pull para "resolver" el rechazo

```bash
git pull origin feature
# fatal: Need to specify how to reconcile divergent branches.
```

**Causa:** El `pull` intentaría hacer un merge entre el `feature` local (rebased) y el `origin/feature` (viejo), lo que crearía exactamente el merge commit que el rebase quería evitar. Además Git no sabe qué estrategia usar sin configuración previa.

**Por qué no es la solución:** Hacer `git pull` aquí contamina el historial con un merge commit innecesario. La solución correcta siempre es `git push --force` después de un rebase sobre un branch que ya existe en el remote.

---

### Conflictos durante el rebase

Si hubiera conflictos, el rebase se detiene y muestra:

```
CONFLICT (content): Merge conflict in archivo.txt
error: could not apply <hash>... <mensaje>
```

La secuencia para resolverlos:

```bash
# 1. Editar los archivos con conflicto
# 2. Marcarlos como resueltos
git add archivo.txt
# 3. Continuar el rebase
git rebase --continue
# Para abortar y volver al estado anterior:
git rebase --abort
```

## Recursos

- [git rebase - documentacion oficial](https://git-scm.com/docs/git-rebase)
- [Atlassian - git rebase](https://www.atlassian.com/git/tutorials/rewriting-history/git-rebase)
- [Merging vs Rebasing - Atlassian](https://www.atlassian.com/git/tutorials/merging-vs-rebasing)
