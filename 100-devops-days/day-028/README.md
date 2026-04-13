# Día 28 - Cherry-pick: copiar un commit específico entre branches

## Problema / Desafío

El repositorio `/usr/src/kodekloudrepos/games` tiene dos branches: `master` y `feature`. Un desarrollador tiene trabajo en progreso en `feature`, pero uno de sus commits ya está listo para ir a `master`. Se necesita:

1. Identificar el commit con mensaje `Update info.txt` en el branch `feature`
2. Copiarlo a `master` sin traer el resto de commits de `feature`
3. Pushear `master` al origin

## Conceptos clave

### git cherry-pick

`git cherry-pick` copia uno o más commits de cualquier branch y los aplica sobre el branch actual. No mueve ni elimina el commit original — lo **clona** con un nuevo hash:

```
Antes:
feature:  initial → Add welcome.txt → [Update info.txt] → Update welcome.txt
master:   initial → Add welcome.txt

git cherry-pick 4ea6166 (estando en master):

Despues:
feature:  initial → Add welcome.txt → Update info.txt → Update welcome.txt
master:   initial → Add welcome.txt → Update info.txt (nuevo hash: 8dc2868)
```

El commit en `feature` no cambia. En `master` aparece una copia con un hash diferente porque el parent es distinto.

### Casos de uso de cherry-pick

| Situacion | Por que usar cherry-pick |
|-----------|--------------------------|
| **Hotfix en produccion** | Un bug fue corregido en `develop` pero se necesita en `main` sin mergear todo `develop` |
| **Feature parcialmente lista** | Solo algunos commits de un branch feature estan listos para produccion |
| **Commit en el branch equivocado** | Se hizo un commit en `feature-a` pero pertenecia a `feature-b` |
| **Backport a versiones anteriores** | Una correccion de seguridad de `v3` necesita aplicarse en `v2` y `v1` |
| **Recuperar trabajo de un branch eliminado** | Se puede cherry-pick un commit por su hash aunque el branch ya no exista |

### Cherry-pick vs Merge vs Rebase

| | `cherry-pick` | `merge` | `rebase` |
|--|--|--|--|
| Que trae | Un commit especifico | Todos los commits del branch | Todos los commits, reescritos |
| Crea nuevo commit | Si (con nuevo hash) | Si (merge commit) | Si (reescritos) |
| Reescribe historia | No | No | Si |
| Caso tipico | Commits puntuales | Integrar un branch completo | Limpiar historia antes de mergear |

### Identificar el commit correcto

Antes de hacer cherry-pick siempre conviene ver el log del branch fuente:

```bash
git log feature --oneline          # ver todos los commits de feature
git log feature --oneline --graph  # con grafico de branches
git show 4ea6166                   # ver el diff exacto del commit
```

## Pasos

1. Conectarse al Storage Server y elevar privilegios con `sudo su`
2. Navegar al repositorio
3. Revisar los branches y el log de `feature`
4. Identificar el hash del commit `Update info.txt`
5. Cambiarse a `master`
6. Ejecutar `git cherry-pick <hash>`
7. Pushear `master` al origin

## Comandos / Código

### 1. Conectarse y navegar al repo

```bash
ssh natasha@ststor01
cd /usr/src/kodekloudrepos/games
sudo su
```

### 2. Verificar branches y log

```bash
git branch
```

```
* feature
  master
```

```bash
git log --oneline
```

```
63e001f (HEAD -> feature, origin/feature) Update welcome.txt
4ea6166 Update info.txt
7e60514 (origin/master, master) Add welcome.txt
7e14328 initial commit
```

El commit que se necesita es `4ea6166` — está entre el HEAD de `feature` y el HEAD de `master`.

### 3. Cambiarse a master y hacer cherry-pick

```bash
git checkout master
git cherry-pick 4ea6166
```

```
[master 8dc2868] Update info.txt
 Date: Fri Apr 10 10:38:36 2026 +0000
 1 file changed, 1 insertion(+), 1 deletion(-)
```

El nuevo commit en `master` tiene hash `8dc2868` — diferente al `4ea6166` original en `feature` porque su commit parent es distinto.

### 4. Pushear al origin

```bash
git push origin master
```

```
Enumerating objects: 5, done.
Counting objects: 100% (5/5), done.
Writing objects: 100% (3/3), 316 bytes | 316.00 KiB/s, done.
To /opt/games.git
   7e60514..8dc2868  master -> master
```

### Verificacion final del estado

```bash
git log --oneline --all --graph
```

```
* 63e001f (origin/feature, feature) Update welcome.txt
* 4ea6166 Update info.txt
| * 8dc2868 (HEAD -> master, origin/master) Update info.txt  ← cherry-pick
|/
* 7e60514 Add welcome.txt
* 7e14328 initial commit
```

Se puede ver que `master` tiene la copia del commit y `feature` sigue intacto con su propio flujo.

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `error: could not apply <hash>` + conflictos | Cherry-pick genera conflicto. Resolver los archivos, luego `git add` y `git cherry-pick --continue` |
| `fatal: bad object <hash>` | El hash es incorrecto o pertenece a otro repo. Verificar con `git log feature` |
| Cherry-pick aplicado en el branch equivocado | Usar `git revert HEAD` para deshacerlo y repetir desde el branch correcto |
| Se necesitan varios commits seguidos | `git cherry-pick <hash1>..<hash2>` aplica un rango de commits |

## Recursos

- [Git - git-cherry-pick Documentation](https://git-scm.com/docs/git-cherry-pick)
- [Atlassian - Git Cherry Pick](https://www.atlassian.com/git/tutorials/cherry-pick)
