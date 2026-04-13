# Día 27 - Revertir el último commit con git revert

## Problema / Desafío

El equipo de desarrollo reportó un problema con los commits recientes en `/usr/src/kodekloudrepos/ecommerce`. Se necesita revertir el HEAD al commit anterior:

1. Revertir el último commit (HEAD) al commit previo (initial commit)
2. Usar `revert ecommerce` como mensaje del nuevo commit (todo en minúsculas)
3. Pushear los cambios al origin

## Conceptos clave

### git revert vs git reset

| | `git revert` | `git reset --hard` |
|--|--|--|
| Que hace | Crea un nuevo commit que deshace los cambios | Mueve el puntero HEAD hacia atras |
| Historia | La preserva (no reescribe) | La reescribe |
| Seguro en repos compartidos | Si | No — destructivo para otros colaboradores |
| Recuperable | Si (el commit original sigue en el log) | Dificil si ya fue pusheado |

**Regla:** Si el commit ya fue pusheado a un remote compartido, usar siempre `git revert`. `git reset` solo es seguro en commits locales que nadie mas tiene.

### git revert HEAD --no-commit

Por defecto, `git revert` abre un editor para escribir el mensaje del nuevo commit. El flag `--no-commit` (o `-n`) hace el revert en el staging area sin crear el commit automaticamente, permitiendo escribir el mensaje exacto:

```bash
git revert HEAD --no-commit   # prepara el revert en staging
git commit -m "mensaje exacto"  # crea el commit con el mensaje deseado
```

Alternativa si se quiere editar el mensaje en el editor:
```bash
git revert HEAD   # abre el editor con el mensaje por defecto
```

### Como funciona el revert internamente

```
Antes:
8471b57  initial commit
068ddf4  add data.txt file  ← HEAD

git revert HEAD aplica el inverso del diff de 068ddf4:

Despues:
8471b57  initial commit
068ddf4  add data.txt file
f8b31da  revert ecommerce  ← nuevo HEAD
```

El commit `068ddf4` sigue existiendo en la historia — el revert no lo borra, solo crea uno nuevo que lo deshace.

## Pasos

1. Conectarse al Storage Server y elevar privilegios con `sudo su`
2. Navegar al repositorio
3. Verificar el log para identificar HEAD y el commit previo
4. Ejecutar `git revert HEAD --no-commit`
5. Commitear con el mensaje exacto requerido
6. Verificar el log
7. Pushear al origin

## Comandos / Código

### 1. Conectarse y navegar al repo

```bash
ssh natasha@ststor01
cd /usr/src/kodekloudrepos/ecommerce/
sudo su
```

### 2. Verificar el estado y el log

```bash
git status
```

```
On branch master
Your branch is up to date with 'origin/master'.

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        ecommerce.txt

nothing added to commit but untracked files present
```

```bash
git log --oneline
```

```
068ddf4 (HEAD -> master, origin/master) add data.txt file
8471b57 initial commit
```

El HEAD apunta a `068ddf4`. Se necesita revertir a `8471b57` (initial commit).

### 3. Revertir HEAD con mensaje personalizado

```bash
git revert HEAD --no-commit
git commit -m "revert ecommerce"
```

```
[master f8b31da] revert ecommerce
 1 file changed, 1 insertion(+)
 create mode 100644 info.txt
```

### 4. Verificar el log

```bash
git log --oneline
```

```
f8b31da (HEAD -> master) revert ecommerce
068ddf4 (origin/master) add data.txt file
8471b57 initial commit
```

Tres commits: el original, el que se revirtió, y el nuevo commit de revert.

### 5. Pushear al origin

```bash
git push origin master
```

```
Enumerating objects: 4, done.
Counting objects: 100% (4/4), done.
Writing objects: 100% (3/3), 273 bytes | 273.00 KiB/s, done.
Total 3 (delta 0), reused 0 (delta 0), pack-reused 0 (from 0)
To /opt/ecommerce.git
   068ddf4..f8b31da  master -> master
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| El editor se abre al hacer `git revert HEAD` | Usar `--no-commit` para evitar el editor, luego `git commit -m "mensaje"` |
| `error: commit <hash> is a merge but no -m option was given` | Es un merge commit. Usar `git revert -m 1 HEAD` para especificar el mainline parent |
| `error: your local changes would be overwritten by revert` | Hay cambios sin commitear. Hacer `git stash` antes del revert |
| `git push` rechazado despues del revert | Con `git reset` (no revert) se reescribe historia. Nunca usar `git push --force` en ramas compartidas |

## Recursos

- [Git - git-revert Documentation](https://git-scm.com/docs/git-revert)
- [Atlassian - Git Revert](https://www.atlassian.com/git/tutorials/undoing-changes/git-revert)
- [Git - Undoing Things](https://git-scm.com/book/en/v2/Git-Basics-Undoing-Things)
