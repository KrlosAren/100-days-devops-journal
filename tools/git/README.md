# git — Editar commits

`git` es un sistema de control de versiones distribuido. Cada commit en git es **inmutable**: una vez creado, su contenido y su hash SHA-1 son fijos. "Editar" un commit en realidad significa **crear uno nuevo que reemplaza al viejo**, y mover la referencia del branch para que apunte ahí. El commit original queda huérfano hasta que el garbage collector lo limpia.

Esta sección cubre los flujos comunes para "editar" commits: cambiar el mensaje, cambiar el contenido, combinar commits, eliminarlos, reordenarlos, y recuperar trabajo cuando algo sale mal.

---

## Idea base: "editar" = reescribir historia

Un commit en git contiene tres cosas que determinan su hash:

1. El árbol de archivos (snapshot completo del repo en ese punto).
2. El padre (commit anterior).
3. Metadata: autor, fecha, mensaje.

Si cambias **cualquiera** de las tres, el hash cambia y el commit es técnicamente otro. Por eso decimos que git "rescribe historia" — siempre genera commits nuevos en lugar de mutar los existentes.

Esto tiene una consecuencia práctica que define todas las reglas:

> **Reescribir historia local es libre. Reescribir historia pública es peligroso.**

Los comandos de esta página son seguros si el commit aún no fue pusheado al remoto. Si ya lo pusheaste y otros lo han pulled, hay que coordinar con el equipo antes de aplicarlos (o aceptar que se rompen los clones de los demás).

---

## Modificar el último commit: `--amend`

`--amend` reemplaza el commit más reciente con uno nuevo. Es el caso más común: te das cuenta de un error apenas haces commit y quieres corregirlo.

### Cambiar solo el mensaje

```bash
# Pasando el mensaje en la línea de comando
git commit --amend -m "nuevo mensaje aquí"

# Abriendo el editor con el mensaje actual para modificarlo
git commit --amend
```

### Cambiar el contenido (agregar archivos olvidados)

```bash
# 1. Stagear lo que falta
git add archivo_olvidado.py

# 2. Amendar manteniendo el mismo mensaje
git commit --amend --no-edit

# 3. (O amendar y modificar también el mensaje)
git commit --amend -m "feat(add): incluye archivo_olvidado.py"
```

`--no-edit` es la flag que dice "reusa el mensaje del commit actual" — sin ella, git abriría el editor.

### Quitar archivos del último commit

```bash
# 1. Sacar el archivo del commit (sigue en el working tree)
git reset HEAD~ -- archivo_a_quitar.py

# 2. Re-commitear sin él
git commit --amend --no-edit
```

---

## Modificar commits anteriores al último: `rebase -i`

`--amend` solo toca el último commit. Para editar uno más atrás se usa rebase interactivo.

```bash
git rebase -i HEAD~3      # los últimos 3 commits
git rebase -i <hash>      # rebase desde un commit específico (exclusive)
```

git abre un editor con una lista de commits y palabras clave que indican qué hacer con cada uno:

```
pick   abc1234  feat(add): primer commit
pick   def5678  feat(add): segundo commit
pick   ghi9012  feat(add): tercer commit

# Comandos:
# p, pick    = usar el commit
# r, reword  = usar el commit, pero cambiar su mensaje
# e, edit    = usar el commit, pero detener para modificar contenido
# s, squash  = usar el commit, pero fusionar con el anterior (combina mensajes)
# f, fixup   = como squash, pero descarta el mensaje de este commit
# d, drop    = eliminar el commit
```

Para reordenar: cambias el orden de las líneas en el editor antes de guardar.

### Cambiar solo el mensaje de un commit antiguo

```
reword  abc1234  feat(add): primer commit
pick    def5678  feat(add): segundo commit
pick    ghi9012  feat(add): tercer commit
```

Al guardar, git va a parar en el commit marcado `reword` y abre el editor para que cambies el mensaje. Tras guardar, continúa con los demás.

### Combinar varios commits en uno (squash)

```
pick    abc1234  feat(add): empezar feature
squash  def5678  feat(add): seguir feature
squash  ghi9012  feat(add): terminar feature
```

git fusiona los tres en uno solo y abre el editor con los tres mensajes concatenados para que escribas el mensaje final.

### Modificar el contenido de un commit antiguo

```
edit    abc1234  feat(add): primer commit
pick    def5678  feat(add): segundo commit
```

git va a parar en `abc1234`, te deja en un working tree donde puedes hacer cambios, stage, y luego:

```bash
# Después de hacer tus cambios:
git add archivos_modificados
git commit --amend           # o --amend --no-edit
git rebase --continue        # vuelve a aplicar los commits siguientes
```

> ⚠️ Si un commit posterior depende de algo que cambiaste en el commit editado, puede haber **conflictos de rebase**. git te detiene, los resuelves, `git add`, `git rebase --continue`. Si te enredas: `git rebase --abort` deja todo como estaba antes.

---

## Cuando el commit ya está pusheado: force push

Si ya pusheaste y necesitas amendar:

```bash
git commit --amend -m "nuevo mensaje"
git push --force-with-lease origin <branch>
```

### `--force` vs `--force-with-lease`

| Flag | Comportamiento | Cuándo usar |
|------|----------------|-------------|
| `--force` (`-f`) | Pisa el remoto sin verificar nada. Si alguien empujó commits desde tu último fetch, **se pierden** | Casi nunca. Solo en branches personales sin colaboradores |
| `--force-with-lease` | Aborta el push si el remoto recibió commits nuevos desde tu último fetch | Default seguro para reescribir historia pusheada |

`--force-with-lease` es la versión "con cinturón de seguridad": revisa que tu copia local del estado remoto coincida con el estado actual del remoto antes de pisar. Si alguien más empujó algo, falla y tú decides qué hacer.

### Reglas de cortesía

- Nunca force-pushear a `main` / `master` / branches compartidos sin aviso explícito al equipo.
- Quien ya hizo `git pull` antes del force-push tiene el commit viejo en su clon y necesita resincronizarse (`git fetch && git reset --hard origin/<branch>`).
- En PRs activos, force-push después de un review puede invalidar comentarios atados a líneas específicas. Algunas plataformas (GitHub, GitLab) lo manejan, pero el flujo no es el mismo.

---

## Red de seguridad: `git reflog`

Cuando reescribes historia, los commits "viejos" no desaparecen inmediatamente — quedan huérfanos por un tiempo (default ~90 días) y siguen accesibles vía hash.

```bash
git reflog
```

```
1a2b3c4 HEAD@{0}: commit (amend): nuevo mensaje
5d6e7f8 HEAD@{1}: commit: mensaje viejo que querías recuperar
9a8b7c6 HEAD@{2}: checkout: moving from main to feature
```

`reflog` muestra **todas las posiciones por las que pasó tu HEAD**, incluso las que ya no son alcanzables desde ningún branch. Para volver a un commit que pensabas perdido:

```bash
git reset --hard 5d6e7f8     # ¡destructivo! revisa que sea el commit correcto
# o más seguro:
git checkout -b recuperado 5d6e7f8   # crea un branch nuevo apuntando ahí
```

> El reflog es **local**: solo sabe de operaciones hechas en tu clon. No te ayuda a recuperar trabajo de otra máquina ni del remoto. Tampoco se transfiere con `clone` o `push`.

---

## Cuándo NO usar amend / rebase

- **El commit ya fue pusheado a un branch compartido** y otros han hecho pull. Reescribirlo rompe sus clones.
- **Estás en `main` / `master` con protección de branch.** La política del repo lo bloqueará (correctamente).
- **No estás seguro de qué cambia el reescritor.** Probar en un branch desechable primero — `git branch tmp` antes de un rebase es gratis y te deja un punto de regreso.

---

## Tabla resumen

| Quiero... | Comando |
|-----------|---------|
| Cambiar el mensaje del último commit | `git commit --amend -m "nuevo"` |
| Agregar un archivo olvidado al último commit | `git add f && git commit --amend --no-edit` |
| Cambiar el mensaje de un commit antiguo | `git rebase -i HEAD~N` → `reword` |
| Combinar varios commits en uno | `git rebase -i HEAD~N` → `squash` |
| Eliminar un commit del historial | `git rebase -i HEAD~N` → `drop` |
| Modificar el contenido de un commit antiguo | `git rebase -i HEAD~N` → `edit` |
| Reordenar commits | `git rebase -i HEAD~N` → reordenar líneas |
| Recuperar un commit "perdido" | `git reflog` + `git reset --hard <hash>` |
| Subir cambios después de reescribir | `git push --force-with-lease` |
| Cancelar un rebase a medias | `git rebase --abort` |

---

## Recursos

- [Pro Git book — capítulo 7.6: Rewriting History](https://git-scm.com/book/en/v2/Git-Tools-Rewriting-History)
- [git commit --amend — referencia](https://git-scm.com/docs/git-commit#Documentation/git-commit.txt---amend)
- [git rebase --interactive — referencia](https://git-scm.com/docs/git-rebase#_interactive_mode)
- [--force-with-lease vs --force](https://git-scm.com/docs/git-push#Documentation/git-push.txt---force-with-leaseltrefnamegt)
