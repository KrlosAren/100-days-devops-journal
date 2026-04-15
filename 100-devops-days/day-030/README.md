# Día 30 - Limpiar historial de commits con git reset

## Problema / Desafío

El equipo de desarrollo de Nautilus tiene un repositorio de pruebas en `/usr/src/kodekloudrepos/games` (Storage server, Stratos DC). Se hicieron varios commits de prueba y ahora quieren limpiar el repositorio dejando únicamente dos commits en el historial:

1. `initial commit`
2. `add data.txt file`

Cualquier commit posterior debe eliminarse del historial y el remote debe actualizarse.

## Conceptos clave

### git reset vs git revert

| Característica | `git reset` | `git revert` |
|----------------|-------------|--------------|
| Qué hace | Mueve el puntero HEAD (y el branch) a un commit anterior | Crea un nuevo commit que deshace cambios |
| Historial | **Destruye** commits posteriores al punto elegido | Preserva todo el historial |
| Requiere force push | Sí (el remote queda adelante) | No |
| Uso recomendado | Ramas locales o de prueba | Ramas compartidas / produccion |
| Recuperable | Solo via `git reflog` (~90 días) | Siempre visible en el log |

En este caso `git reset` es la opcion correcta porque el objetivo explícito es eliminar el historial de commits de prueba.

### Modos de git reset

```
git reset --soft <hash>    # Mueve HEAD, conserva cambios en staging
git reset --mixed <hash>   # Mueve HEAD, conserva cambios en working tree (default)
git reset --hard <hash>    # Mueve HEAD, DESCARTA todos los cambios
```

Para limpiar completamente se usa `--hard` — el working tree queda identico al estado del commit destino.

### Por qué se necesita force push

```
Antes del reset:
  remote: A → B → C → D (HEAD)
  local:  A → B → C → D (HEAD)

Después del git reset --hard B:
  remote: A → B → C → D (HEAD)   ← el remote sigue adelante
  local:  A → B (HEAD)            ← el local retrocedió

git push normal falla porque el remote está "más adelante".
git push --force sobreescribe el remote con el estado local.
```

## Pasos

1. Conectarse al Storage server
2. Ir al repositorio `/usr/src/kodekloudrepos/games`
3. Revisar el historial de commits con `git log`
4. Identificar el hash del commit `add data.txt file`
5. Ejecutar `git reset --hard <hash>` para apuntar HEAD a ese commit
6. Verificar que el historial quedó con solo dos commits
7. Hacer `git push --force` para actualizar el remote

## Comandos / Código

### 1. Conectarse al servidor y navegar al repo

```bash
ssh natasha@ststor01
cd /usr/src/kodekloudrepos/games
```

### 2. Revisar el historial completo

```bash
git log --oneline
```

Salida de ejemplo (antes del reset):

```
f3a2d1c (HEAD -> master, origin/master) added test data
8b4e9f2 modified data.txt
a1c3e5d add data.txt file
2b7f8a1 initial commit
```

Se necesita el hash del commit `add data.txt file` → `a1c3e5d`.

### 3. Ejecutar el reset

```bash
git reset --hard a1c3e5d
```

```
HEAD is now at a1c3e5d add data.txt file
```

### 4. Verificar el historial después del reset

```bash
git log --oneline
```

```
a1c3e5d (HEAD -> master) add data.txt file
2b7f8a1 initial commit
```

Solo quedan los dos commits requeridos.

### 5. Force push al remote

```bash
git push -f origin master
```

```
Total 0 (delta 0), reused 0 (delta 0), pack-reused 0
To <remote-url>
 + f3a2d1c...a1c3e5d master -> master (forced update)
```

### Verificación final

```bash
git log --oneline
git status
```

```
a1c3e5d (HEAD -> master, origin/master) add data.txt file
2b7f8a1 initial commit

On branch master
Your branch is up to date with 'origin/master'.
nothing to commit, working tree clean
```

## Diferencia entre --hard, --mixed y --soft aplicado a este caso

```bash
# --soft: HEAD retrocede, pero los archivos de los commits eliminados
#         quedan en staging listos para un nuevo commit
git reset --soft a1c3e5d

# --mixed (default): HEAD retrocede, archivos quedan en working tree
#                    pero no en staging
git reset --mixed a1c3e5d

# --hard: HEAD retrocede, working tree y staging quedan igual al commit
#         destino — archivos de commits eliminados desaparecen
git reset --hard a1c3e5d   ← el usado aquí
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `git push` rechazado con `rejected (non-fast-forward)` | El remote tiene commits que el local no — usar `git push --force` o `git push -f` |
| Se usó el hash incorrecto | Verificar con `git reflog` y volver a hacer el reset con el hash correcto |
| `git push -f` rechazado (branch protegido) | El branch tiene proteccion de force push en el servidor — desactivarla desde la UI del repo o con permisos de admin |
| Se perdieron cambios que no debían perderse | Buscar en `git reflog` el hash del commit perdido y hacer `git cherry-pick` o `git reset --hard <hash-anterior>` |

## Recursos

- [Git reset - Atlassian](https://www.atlassian.com/git/tutorials/undoing-changes/git-reset)
- [git reset - documentacion oficial](https://git-scm.com/docs/git-reset)
- [Diferencia entre reset, revert y restore](https://git-scm.com/docs/git#_reset_restore_and_revert)
