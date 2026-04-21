# Día 34 - Crear un post-update hook para tagging automático en Git

## Problema / Desafío

El equipo de Nautilus tiene el repositorio bare `/opt/news.git` y su clon en `/usr/src/kodekloudrepos/news` (Storage server, Stratos DC). Los requisitos son:

1. Mergear el branch `feature` en `master`
2. Crear un hook `post-update` en el repositorio bare que, cada vez que se pushee a `master`, genere automáticamente un release tag con el formato `release-YYYY-MM-DD`
3. Probar el hook al menos una vez
4. Pushear los cambios
5. No modificar permisos existentes del repositorio

## Conceptos clave

### Git Hooks

Los hooks son scripts ejecutables que Git invoca automáticamente en eventos específicos del ciclo de vida de un repositorio. En un repositorio bare (servidor), viven en el directorio `hooks/`.

```
/opt/news.git/
└── hooks/
    ├── post-update       ← se ejecuta después de recibir un push
    ├── pre-receive       ← se ejecuta antes de aceptar el push
    └── post-receive      ← se ejecuta después de aceptar el push
```

### post-update vs post-receive

| Hook | Cuándo corre | Cómo recibe los refs |
|------|-------------|----------------------|
| `post-receive` | Después de actualizar todas las refs | Stdin: `oldrev newrev refname` por línea |
| `post-update` | Después de actualizar todas las refs | Argumentos `$@`: lista de refnames actualizados |

Esta diferencia es crítica: si se usa `while read` en un `post-update`, el loop nunca ejecuta porque stdin está vacío — el echo que está **fuera** del loop sí aparece en el remote, pero ningún comando dentro del loop corre jamás.

### Repositorio bare

`/opt/news.git` es un repositorio bare: no tiene working tree, solo el contenido de `.git/`. Es el "servidor central" al que los clones pushean y del que pullan. Los hooks del servidor viven en `hooks/` (sin punto).

```
/opt/news.git/     ← bare repo (servidor)
    hooks/         ← hooks se crean aquí

/usr/src/kodekloudrepos/news/    ← clon (cliente)
    .git/hooks/                  ← hooks locales (no aplican aquí)
```

## Pasos

1. En el clon (`/usr/src/kodekloudrepos/news`): mergear `feature` en `master`
2. En el bare repo (`/opt/news.git/hooks/`): crear el script `post-update`
3. Darle permisos de ejecución al hook
4. Desde el clon: pushear a master para disparar el hook
5. Verificar que el tag fue creado

## Comandos / Código

### 1. Verificar estado del clon

```bash
cd /usr/src/kodekloudrepos/news
git status
git log --oneline
git branch
```

```
On branch feature
nothing to commit, working tree clean

137c292 (HEAD -> feature, origin/feature) Add feature
cb62acd (origin/master, master) initial commit

* feature
  master
```

### 2. Mergear feature en master

```bash
git checkout master
git merge feature
```

```
Switched to branch 'master'
Your branch is up to date with 'origin/master'.
Updating cb62acd..137c292
Fast-forward
 ...
```

### 3. Crear el hook post-update en el bare repo

```bash
cd /opt/news.git/hooks
```

Contenido del archivo `post-update`:

```bash
#!/bin/bash

echo "Server update push; started automated tasks..."

for refname in "$@"
do
    if [ "$refname" = "refs/heads/master" ]; then
        echo "Master branch push detected. Running hook..."
        date_format=$(date +%Y-%m-%d)
        tag="release-$date_format"
        echo "Tag=$tag"
        GIT_DIR=/opt/news.git git tag "$tag"
    fi
done
```

> **Nota:** usar `for refname in "$@"` en lugar de `while read` — `post-update` recibe los refs como argumentos, no por stdin.

### 4. Hacer el script ejecutable

```bash
chmod +x /opt/news.git/hooks/post-update
```

### 5. Mergear y pushear desde el clon

```bash
git checkout feature
vi info.txt
git add info.txt
git commit -am 'feat: info'
git push origin feature
```

```
remote: Server update push; started automated tasks...
To /opt/news.git
   443c2f5..95fc34c  feature -> feature
```

El echo del hook aparece pero no "Master branch push detected" — el push fue a `feature`, no a `master`. Correcto.

```bash
git checkout master
git merge feature
git push origin master
```

```
remote: Server update push; started automated tasks...
To /opt/news.git
   75aae65..d74b96d  master -> master
```

El hook corre pero tampoco aparece el echo interno. Esto fue la señal del bug.

### 6. Debugging — por qué no se creó el tag

```bash
git fetch --tags
git tag -l
# (sin output — no se creó ningún tag)
```

**Causa raíz:** el hook usaba `while read oldrev newrev refname` (patrón de `post-receive`). En un hook `post-update`, los refs llegan como argumentos `$@` — stdin está vacío, el loop nunca itera, y el bloque interno nunca ejecuta. El echo fuera del loop sí aparece porque está en el scope principal del script.

### 7. Fix del hook

Reemplazar `while read oldrev newrev refname` por `for refname in "$@"` en `/opt/news.git/hooks/post-update` y volver a pushear.

```bash
git checkout master
git merge feature
git push origin master
```

```
Merge made by the 'ort' strategy.
 info.txt | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

remote: Server update push; started automated tasks...
remote: Master branch push detected. Running hook...
remote: Tag=release-2026-04-21
To /opt/news.git
   d74b96d..67a38ef  master -> master
```

Los tres echos del hook aparecen — el loop entró correctamente con `for refname in "$@"`.

### 8. Verificar el tag creado

```bash
git fetch --all
```

```
From /opt/news
 * [new tag]         release-2026-04-21 -> release-2026-04-21
```

```bash
git tag -l
```

```
release-2026-04-21
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| El hook no se ejecuta | Verificar que tiene permisos de ejecución: `chmod +x hooks/post-update` |
| `Permission denied` al crear el hook | Trabajar con el usuario `natasha` que es dueño del directorio `hooks/` |
| El tag no aparece en el clon después del push | Hacer `git fetch --tags` para traer los tags del remote |
| El hook corre (aparece el primer echo) pero el tag no se crea | El loop interno nunca ejecutó — revisar si se usó `while read` en vez de `for refname in "$@"`. En `post-update` los refs son argumentos, no stdin |
| El hook corre pero el tag no se crea (loop correcto) | Verificar que el comando `git tag` dentro del hook apunta al repo correcto con `GIT_DIR=/opt/news.git git tag "$tag"` |

## Recursos

- [Git Hooks - documentación oficial](https://git-scm.com/docs/githooks)
- [Customizing Git Hooks - Pro Git Book](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
