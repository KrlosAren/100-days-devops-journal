# Día 90 - Managing ACLs Using Ansible (módulo `acl` + POSIX ACLs + playbook multi-play)

## Problema / Desafío

El equipo Nautilus necesita crear archivos en los app servers que sean **propiedad de `root`**, pero a la vez dar a un usuario/grupo específico de la app un set de permisos sobre ellos — **sin** cambiar el dueño. Todo con Ansible. La tarea:

1. Crear `/home/thor/ansible/playbook.yml` (el inventario ya existe)
2. **app server 1 (`stapp01`)**: archivo vacío `/opt/data/blog.txt` → ACL de lectura `(r)` al **grupo** `tony`
3. **app server 2 (`stapp02`)**: archivo vacío `/opt/data/story.txt` → ACL lectura+escritura `(rw)` al **usuario** `steve`
4. **app server 3 (`stapp03`)**: archivo vacío `/opt/data/media.txt` → ACL lectura+escritura `(rw)` al **grupo** `banner`

En los tres casos el archivo es propiedad de `root:root`; el acceso extra para el usuario/grupo de la app se da **vía ACL**.

Restricción de validación: se corre con `ansible-playbook -i inventory playbook.yml` — **sin argumentos extra**. El `become` debe vivir dentro del playbook.

> Día 90/100 — y el primero que combina dos conceptos nuevos a la vez: el módulo **`acl`** y un playbook con **múltiples plays** (uno por host), en lugar del clásico `hosts: all`.

## Conceptos clave

### El problema que resuelven las ACLs: el techo del modelo Unix clásico

Los permisos tradicionales de Unix solo distinguen **tres** categorías:

```
-rw-r--r--  root root  blog.txt
 │  │  │
 │  │  └── other  (todos los demás)
 │  └───── group  (UN solo grupo)
 └──────── owner  (UN solo usuario)
```

Solo se puede dar acceso a **un** usuario (el owner) y **un** grupo. El lab pide:

- Owner = `root`
- Pero **además** el grupo `tony` (≠ root) debe poder leer `blog.txt`

Eso es **imposible** con `chmod` solo: para que `tony` lea habría que hacerlo owner/group (rompe "owned by root") o abrir a `other` (da acceso a todos). Las **ACLs (Access Control Lists)** rompen ese techo: añaden reglas por-entidad **sobre** los permisos base.

### Qué es una POSIX ACL

Una ACL es una lista de entradas adicionales que el filesystem guarda junto al inode. Se ven con `getfacl`:

```bash
$ getfacl /opt/data/blog.txt
# file: opt/data/blog.txt
# owner: root          ← dueño sigue siendo root
# group: root
user::rw-              ← permisos base del owner
group::r--             ← permisos base del group
group:tony:r--         ← ★ ACL: el grupo tony tiene lectura (lo que pide el lab)
mask::r--              ← límite máximo de permisos efectivos
other::r--
```

La línea `group:tony:r--` es la entrada ACL: da lectura al grupo `tony` **sin tocar** el dueño ni `other`. Se gestionan a mano con `setfacl -m`, o declarativamente con el módulo `acl` de Ansible.

### El módulo `acl` — gestionar entradas ACL declarativamente

```yaml
- name: ACL read for group tony
  ansible.builtin.acl:
    path: /opt/data/blog.txt
    entity: tony
    etype: group
    permissions: r
    state: present
```

| Parámetro      | Función                                                                  |
| -------------- | ------------------------------------------------------------------------ |
| `path:`        | Archivo o directorio al que aplica la ACL                                |
| `entity:`      | **Quién** — nombre del usuario o grupo                                   |
| `etype:`       | **Tipo de entidad**: `user`, `group`, `other`, `mask`                   |
| `permissions:` | Permisos: combinación de `r`, `w`, `x` (ej. `r`, `rw`, `rwx`)            |
| `state:`       | `present` (añadir/modificar) o `absent` (quitar la entrada)              |
| `default:`     | `yes` → ACL **por defecto** (solo dirs; la heredan los hijos nuevos)     |
| `recursive:`   | Aplicar recursivamente a todo el contenido de un dir                     |

### `entity` + `etype` — el "quién" de la regla

La clave del lab está en combinar bien estos dos campos. Un mismo nombre puede existir como usuario **y** como grupo, así que `etype` desambigua:

| Host    | Archivo     | `entity` | `etype`  | `permissions` | Significado                          |
| ------- | ----------- | -------- | -------- | ------------- | ------------------------------------ |
| stapp01 | `blog.txt`  | `tony`   | `group`  | `r`           | El **grupo** tony puede leer         |
| stapp02 | `story.txt` | `steve`  | `user`   | `rw`          | El **usuario** steve puede leer/escribir |
| stapp03 | `media.txt` | `banner` | `group`  | `rw`          | El **grupo** banner puede leer/escribir |

> **Trampa del lab**: el caso de `steve` es `etype: user` (no `group`), aunque los otros dos son grupos. Leer cada requisito al pie de la letra — el enunciado dice explícitamente "entity is steve and etype is **user**". Confundir `user`/`group` crea una ACL que la validación no encuentra.

### El `mask` — el límite invisible de permisos efectivos

Al añadir una ACL, el filesystem mantiene una entrada `mask::` que define el **máximo** de permisos efectivos para usuarios nombrados y grupos (no para el owner ni `other`):

```
group:tony:rw-     ← permiso solicitado
mask::r--          ← ¡pero el mask lo limita a r!
                   → permiso EFECTIVO de tony = r--
```

El módulo `acl` recalcula el mask automáticamente al añadir entradas, así que normalmente no hay que tocarlo. Pero si una ACL "no funciona" pese a estar puesta, el `mask` suele ser el culpable — `getfacl` lo muestra y marca las entradas afectadas con `#effective:`.

### Dos pasos por host: crear el archivo, luego la ACL

Cada archivo requiere dos tasks en orden:

```yaml
- name: create empty file owned by root
  ansible.builtin.file:
    path: /opt/data/blog.txt
    state: touch          # ← crea el archivo vacío (Día 83/85)
    owner: root
    group: root

- name: ACL read for group tony
  ansible.builtin.acl:
    path: /opt/data/blog.txt
    entity: tony
    etype: group
    permissions: r
    state: present
```

Primero el módulo `file` con `state: touch` crea el archivo vacío propiedad de `root:root` (reusa lo del Día 85). Después el módulo `acl` añade la regla por-entidad encima. El orden importa: la ACL falla si el archivo aún no existe.

### Playbook **multi-play**: un play por host

Hasta ahora todos los playbooks eran un solo play con `hosts: all`. Hoy es distinto: como **cada archivo va a un host diferente con una entidad ACL diferente**, el playbook tiene **tres plays separados**:

```yaml
- name: blog.txt in app01
  hosts: stapp01            # ← play 1: solo stapp01
  become: true
  tasks: [...]

- name: story.txt in app02
  hosts: stapp02            # ← play 2: solo stapp02
  become: true
  tasks: [...]

- name: media.txt in app03
  hosts: stapp03            # ← play 3: solo stapp03
  become: true
  tasks: [...]
```

Cada play es una unidad independiente con su propio `hosts`, `become` y `tasks`. El PLAY RECAP los agrega por host al final. Este es el patrón cuando los hosts necesitan **configuraciones genuinamente distintas**, no la misma tarea repetida.

> Alternativa más DRY: un solo play con `hosts: all` + variables por host (`host_vars`) + un loop. Ver "Variantes". Para 3 hosts con 3 reglas distintas, los plays separados son más legibles; para 30 hosts, las variables ganan.

## Pasos

1. Login al jump host como `thor`; `cd /home/thor/ansible`
2. Validar conectividad: `ansible -i inventory all -m ping`
3. Crear `/home/thor/ansible/playbook.yml` con **3 plays**, cada uno: `file` (touch root:root) → `acl`
4. Correr `ansible-playbook -i inventory playbook.yml`
5. Validar con `getfacl` en cada host

## Comandos / Código

### Playbook (solución utilizada)

```yaml
# /home/thor/ansible/playbook.yml
- name: blog.txt in app01
  hosts: stapp01
  become: true
  tasks:
    - name: create empty file owned by root
      ansible.builtin.file:
        path: /opt/data/blog.txt
        state: touch
        owner: root
        group: root

    - name: ACL read for group tony
      ansible.builtin.acl:
        path: /opt/data/blog.txt
        entity: tony
        etype: group
        permissions: r
        state: present

- name: story.txt in app02
  hosts: stapp02
  become: true
  tasks:
    - name: create empty file owned by root
      ansible.builtin.file:
        path: /opt/data/story.txt
        state: touch
        owner: root
        group: root

    - name: ACL read+write for user steve
      ansible.builtin.acl:
        path: /opt/data/story.txt
        entity: steve
        etype: user           # ← steve es USER, no group
        permissions: rw
        state: present

- name: media.txt in app03
  hosts: stapp03
  become: true
  tasks:
    - name: create empty file owned by root
      ansible.builtin.file:
        path: /opt/data/media.txt
        state: touch
        owner: root
        group: root

    - name: ACL read+write for group banner
      ansible.builtin.acl:
        path: /opt/data/media.txt
        entity: banner
        etype: group
        permissions: rw
        state: present
```

### Ejecutar el playbook

```bash
ansible-playbook -i inventory playbook.yml
```

Output real del lab (recortado):

```
PLAY [blog.txt in app01] ***************************************
TASK [create empty file owned by root] *  changed: [stapp01]
TASK [ACL read for group tony] *********  changed: [stapp01]

PLAY [story.txt in app02] **************************************
TASK [create empty file owned by root] *  changed: [stapp02]
TASK [ACL read+write for user steve] ***  changed: [stapp02]

PLAY [media.txt in app03] **************************************
TASK [create empty file owned by root] *  changed: [stapp03]
TASK [ACL read+write for group banner] *  changed: [stapp03]

PLAY RECAP *****************************************************
stapp01 : ok=3  changed=2  unreachable=0  failed=0
stapp02 : ok=3  changed=2  unreachable=0  failed=0
stapp03 : ok=3  changed=2  unreachable=0  failed=0
```

`changed=2` por host (file touch + acl). Cada play corre solo sobre su host objetivo.

> Ojo con `state: touch`: **no es idempotente** (Día 83) — actualiza el mtime en cada corrida, así que el task `file` saldrá `changed` siempre. El `acl`, en cambio, sí es idempotente: una segunda corrida da `ok` si la entrada ya existe.

### Verificación

```bash
# app01 — la entrada group:tony debe estar con r
ansible -i inventory stapp01 -m shell -a "getfacl /opt/data/blog.txt" --become

# Salida esperada (parcial):
# owner: root
# group: root
# group:tony:r--

# app02 — user:steve con rw
ansible -i inventory stapp02 -m shell -a "getfacl /opt/data/story.txt" --become
# user:steve:rw-

# app03 — group:banner con rw
ansible -i inventory stapp03 -m shell -a "getfacl /opt/data/media.txt" --become
# group:banner:rw-
```

## Variantes (referencia)

### Versión DRY: un solo play + host_vars + loop

```yaml
# host_vars/stapp01.yml → acl_file: /opt/data/blog.txt, acl_entity: tony, acl_etype: group, acl_perms: r
# host_vars/stapp02.yml → ... steve / user / rw
# host_vars/stapp03.yml → ... banner / group / rw

- hosts: all
  become: true
  tasks:
    - name: crear archivo root:root
      ansible.builtin.file:
        path: "{{ acl_file }}"
        state: touch
        owner: root
        group: root

    - name: aplicar ACL por host
      ansible.builtin.acl:
        path: "{{ acl_file }}"
        entity: "{{ acl_entity }}"
        etype: "{{ acl_etype }}"
        permissions: "{{ acl_perms }}"
        state: present
```

Los datos viven en `host_vars` (Día 85: datos vs lógica); el play es uno solo. Más escalable, menos legible para pocos hosts.

### ACL por defecto en un directorio (herencia)

```yaml
- name: que los archivos nuevos hereden la ACL
  ansible.builtin.acl:
    path: /opt/data
    entity: tony
    etype: group
    permissions: rx
    default: yes        # ← solo dirs: los hijos nuevos heredan esta ACL
    state: present
```

### Quitar una ACL

```yaml
- ansible.builtin.acl:
    path: /opt/data/blog.txt
    entity: tony
    etype: group
    state: absent       # con state absent no se pasa permissions
```

### Equivalente manual con `setfacl`

```bash
setfacl -m g:tony:r   /opt/data/blog.txt    # -m = modify; g: = group
setfacl -m u:steve:rw /opt/data/story.txt   # u: = user
getfacl /opt/data/blog.txt                  # ver el resultado
setfacl -x g:tony     /opt/data/blog.txt    # -x = quitar entrada
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `ansible-acl: command not found` / `Failed to set ACL`          | El paquete `acl` (`setfacl`/`getfacl`) no está instalado en el host            | Instalar con un task `yum: name=acl state=present` antes de usar el módulo     |
| `Operation not supported` al aplicar la ACL                     | El filesystem está montado sin la opción `acl`                                 | Remontar con `mount -o remount,acl /` o añadir `acl` en `/etc/fstab`            |
| `entity X not found` / no aplica                                | El usuario o grupo no existe en el host destino                                | Crear el user/group antes (módulo `user`/`group`), o verificar el nombre        |
| ACL puesta pero el permiso "no funciona"                        | El `mask` está limitando el permiso efectivo                                    | `getfacl` muestra `#effective:`; ajustar el `mask` o re-aplicar la entrada      |
| Se confundió `etype: group` con `user` (caso steve)             | El enunciado mezcla user y group entre los 3 hosts                              | Leer literal: steve = `user`, tony/banner = `group`                            |
| El task `file` sale `changed` en cada corrida                   | `state: touch` no es idempotente (actualiza mtime)                             | Normal; usar `state: present` si solo se quiere "que exista" sin tocar mtime    |
| `Path /opt/data/blog.txt does not exist` en el task acl         | El `acl` corrió antes de crear el archivo                                       | Asegurar que el task `file` está **antes** del `acl` en el play                 |
| Funciona con `--become` pero no sin args                        | La validación corre sin `--become`                                            | Poner `become: true` **en cada play**                                          |

## Conexión con días anteriores

- **Días 83/85 (`file` + `state: touch`)**: el primer task de cada play reusa exactamente eso — crear archivo vacío con owner/group. Hoy se le suma la capa ACL.
- **Día 85 (datos en inventario vs lógica)**: la variante DRY mueve `entity`/`etype`/`perms` a `host_vars`, justo el patrón "el dato de qué-va-en-qué-host vive en variables, no en el play".
- **Días 84-89 (`hosts: all`)**: hoy rompe el molde — primer playbook **multi-play**, un play por host, porque cada uno necesita config distinta.
- **Permisos clásicos (Día 85, `mode: '0777'`)**: las ACLs son la respuesta a "necesito dar acceso a un tercero sin abrir a todos ni cambiar el dueño" — lo que `chmod` no puede.

## Reflexión: ACLs vs el modelo de permisos clásico

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- ACLs resuelven "owner root + acceso a un tercero" sin chmod 777 ni cambiar dueño. ¿En qué escenario real las usarías vs simplemente agregar el user al grupo del archivo? ¿Cuándo una ACL es la herramienta correcta y cuándo es complejidad innecesaria?
- multi-play (un play por host) vs hosts: all + host_vars + loop: para 3 hosts elegiste plays separados (legible). ¿A partir de cuántos hosts/reglas cambiarías al enfoque con variables? ¿El trade-off legibilidad vs DRY tiene un punto claro?
- el caso steve (user) entre tony/banner (group): un enunciado que mezcla tipos a propósito. ¿Es un buen recordatorio de "traducir el requisito literal al campo YAML" (mismo patrón del validador K8s de días 65/67)?
- el mask invisible: una ACL puede estar "puesta" pero no surtir efecto por el mask. ¿Qué dice esto sobre verificar siempre con getfacl en vez de asumir que el changed=1 significa que funciona?
- el paquete acl como dependencia oculta: el módulo falla si setfacl no está instalado. ¿Vale la pena hacer el playbook defensivo (instalar acl primero) o asumir que está?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`acl` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/acl_module.html)
- [`file` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [POSIX Access Control Lists (Arch Wiki)](https://wiki.archlinux.org/title/Access_Control_Lists)
- [`setfacl(1)` man page](https://man7.org/linux/man-pages/man1/setfacl.1.html)
- [`getfacl(1)` man page](https://man7.org/linux/man-pages/man1/getfacl.1.html)
