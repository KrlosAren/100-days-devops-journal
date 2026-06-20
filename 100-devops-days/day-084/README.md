# Día 84 - Copy Data to App Servers using Ansible (módulo copy + hosts: all + become)

## Problema / Desafío

El equipo DevOps de Nautilus necesita **copiar datos desde el jump host hacia todos los application servers** de Stratos DC usando Ansible. Es el primer lab que apunta a **toda la flota** (no a un solo host como el Día 83) y que copia un archivo desde el control node.

Requirements:

1. Crear `/home/thor/ansible/inventory` con **todos** los application servers como managed nodes
2. Crear `/home/thor/ansible/playbook.yml` que copie `/usr/src/finance/index.html` a `/opt/finance` en **todos** los servers
3. La validación corre `ansible-playbook -i inventory playbook.yml` — sin args extra

Datos de los hosts destino:

| Host      | User    | Password   |
| --------- | ------- | ---------- |
| `stapp01` | `tony`  | `Ir0nM@n`  |
| `stapp02` | `steve` | `Am3ric@`  |
| `stapp03` | `banner`| `BigGr33n` |

Continúa del Día 83 — mismo formato INI, pero ahora con **3 hosts** y el módulo `copy` en lugar de `file`.

## Conceptos clave

### `hosts: all` — apuntar a toda la flota

En el Día 83 el play apuntaba a un host específico (`hosts: stapp01`). Hoy el target es **todos los hosts del inventario**:

```yaml
- hosts: all      # ← Todos los managed nodes definidos en el inventory
```

`all` es un **grupo implícito** que Ansible crea automáticamente con cada host del inventario. No hay que declararlo. Otras formas de seleccionar hosts:

| Patrón en `hosts:`        | A qué apunta                                              |
| ------------------------- | -------------------------------------------------------- |
| `all` / `*`               | Todos los hosts del inventario                           |
| `stapp01`                 | Un host específico (por alias)                           |
| `stapp01,stapp02`         | Lista explícita de hosts                                 |
| `webservers`              | Un grupo definido en el inventario                        |
| `webservers:&production`  | Intersección — en `webservers` **Y** en `production`     |
| `webservers:!stapp03`     | En `webservers` **excepto** `stapp03`                    |
| `stapp0*`                 | Wildcard — todos los que empiezan con `stapp0`           |

### Inventario multi-host con credenciales por línea

A diferencia del Día 83 (un solo host), aquí cada host tiene su **propio user y password** porque son cuentas distintas en cada server:

```ini
stapp01 ansible_user=tony ansible_ssh_pass=Ir0nM@n ansible_ssh_common_args='-o StrictHostKeyChecking=no'
stapp02 ansible_user=steve ansible_ssh_pass=Am3ric@ ansible_ssh_common_args='-o StrictHostKeyChecking=no'
stapp03 ansible_user=banner ansible_ssh_pass=BigGr33n ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

> **Producción**: las credenciales inline son un anti-pattern. Lo correcto es **SSH keys** (Día 7) o **Ansible Vault** para cifrar los secretos. Para el lab, inline es lo más directo.

Cuando las variables se repiten (como `ansible_ssh_common_args`), se pueden factorizar en un grupo:

```ini
[appservers]
stapp01 ansible_user=tony ansible_ssh_pass=Ir0nM@n
stapp02 ansible_user=steve ansible_ssh_pass=Am3ric@
stapp03 ansible_user=banner ansible_ssh_pass=BigGr33n

[appservers:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

### El módulo `copy` — del control node al remoto

El módulo `copy` transfiere un archivo **desde el control node** (jump host) **hacia los managed nodes**:

```yaml
- name: copy file
  ansible.builtin.copy:
    src: /usr/src/finance/index.html   # ← Path en el CONTROL NODE (jump host)
    dest: /opt/finance                  # ← Path en el REMOTO (cada app server)
```

| Parámetro    | Función                                                                       |
| ------------ | ----------------------------------------------------------------------------- |
| `src:`       | Origen — archivo en el **control node** (o relativo a `files/` del playbook)   |
| `dest:`      | Destino — path en el **remoto** (obligatorio)                                  |
| `owner:`     | Dueño del archivo destino (`chown`)                                           |
| `group:`     | Grupo del archivo destino (`chgrp`)                                           |
| `mode:`      | Permisos: `'0644'` o `u=rw,g=r,o=r`                                            |
| `backup:`    | `true` para crear un backup con timestamp si el destino ya existía            |
| `force:`     | `true` (default) sobreescribe; `false` solo copia si el destino no existe     |
| `remote_src:`| `true` si `src` está en el **remoto** (copia local en el remoto, no transfiere)|
| `content:`   | Contenido inline en vez de un archivo `src` (mutuamente excluyente con `src`)  |

### `dest` como directorio vs archivo — la regla del trailing slash

Detalle clave de `copy` (y `template`): el comportamiento de `dest` depende de si termina en `/` y de si el path ya existe como directorio:

| `dest`                       | Si es directorio existente              | Si NO existe                          |
| ---------------------------- | --------------------------------------- | ------------------------------------- |
| `/opt/finance` (sin `/`)     | copia como `/opt/finance/index.html`    | crea un archivo llamado `/opt/finance`|
| `/opt/finance/` (con `/`)    | copia como `/opt/finance/index.html`    | **error** — el directorio debe existir|

En este lab `/opt/finance` **ya existe como directorio**, así que `dest: /opt/finance` deja el archivo en `/opt/finance/index.html`. Si `/opt/finance` no existiera como directorio, Ansible crearía un **archivo** con ese nombre — un error silencioso común.

### `become: true` — por qué hace falta aquí

`/opt/` pertenece a `root`. Los users del inventario (`tony`, `steve`, `banner`) no pueden escribir ahí sin escalar privilegios:

```yaml
- hosts: all
  become: true        # ← Ejecuta las tasks con sudo (root)
```

Diferencia con el Día 83: ahí el destino era `/tmp/` (world-writable), así que `become` no era necesario. Aquí el destino es `/opt/finance` → **sí** hace falta.

| Directiva       | Default | Función                                       |
| --------------- | ------- | --------------------------------------------- |
| `become:`       | `false` | Activar escalada de privilegios               |
| `become_user:`  | `root`  | A qué usuario escalar                         |
| `become_method:`| `sudo`  | Método: `sudo`, `su`, `doas`, `pbrun`, ...    |

### `copy` SÍ es idempotente (a diferencia de `touch`)

Punto de contraste fuerte con el Día 83. El `file` con `state: touch` **siempre** marcaba `changed=true`. El módulo `copy` es **idempotente de verdad**:

```
TASK [copy file] ********************************************
ok: [stapp01]          ← ok, NO changed
ok: [stapp02]
ok: [stapp03]

PLAY RECAP **************************************************
stapp01    : ok=2    changed=0    ...
```

Cómo lo logra: `copy` calcula el **checksum (SHA1)** del archivo origen y lo compara con el del destino:

- **Hash distinto** (o el destino no existe) → copia el archivo → reporta `changed`
- **Hash idéntico** → no hace nada → reporta `ok`

Por eso un `changed=0` en este lab significa que **el archivo ya estaba con el mismo contenido** (o se corrió el playbook dos veces). La **primera** corrida real sobre servers vacíos mostraría `changed=3`.

```
# Primera corrida (destino vacío):
stapp01    : ok=2    changed=1    ...

# Segunda corrida (mismo contenido):
stapp01    : ok=2    changed=0    ...   ← idempotencia real
```

| Módulo (state)        | ¿Idempotente?         | Cómo decide si cambió                       |
| --------------------- | --------------------- | ------------------------------------------- |
| `file` + `state: touch` | No (siempre changed) | Actualiza `mtime` cada vez                  |
| `copy`                | Sí                    | Compara checksum SHA1 origen vs destino     |
| `template`            | Sí                    | Compara el resultado renderizado vs destino |

## Pasos

1. Login al jump host como `thor`
2. `cd /home/thor/ansible/`
3. Crear el inventario con los 3 app servers y sus credenciales
4. Validar conectividad con `ansible all -m ping -i inventory`
5. Crear `playbook.yml` con `hosts: all`, `become: true` y el módulo `copy`
6. Correr `ansible-playbook -i inventory playbook.yml`
7. Validar en cada host con `ls /opt/finance/`

## Comandos / Código

### 1. Crear el inventario

```bash
cat > /home/thor/ansible/inventory <<'EOF'
stapp01 ansible_user=tony ansible_ssh_pass=Ir0nM@n ansible_ssh_common_args='-o StrictHostKeyChecking=no'
stapp02 ansible_user=steve ansible_ssh_pass=Am3ric@ ansible_ssh_common_args='-o StrictHostKeyChecking=no'
stapp03 ansible_user=banner ansible_ssh_pass=BigGr33n ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
```

### 2. Validar conectividad a toda la flota

```bash
ansible all -m ping -i /home/thor/ansible/inventory
```

Output esperado (un bloque por host):

```
stapp01 | SUCCESS => { "ping": "pong" }
stapp02 | SUCCESS => { "ping": "pong" }
stapp03 | SUCCESS => { "ping": "pong" }
```

Si los 3 responden `pong`, los 3 sets de credenciales son correctos.

### 3. Crear el playbook

```yaml
# /home/thor/ansible/playbook.yml
- hosts: all
  become: true
  tasks:
    - name: copy file
      ansible.builtin.copy:
        src: /usr/src/finance/index.html
        dest: /opt/finance
```

### 4. Ejecutar el playbook

```bash
ansible-playbook -i /home/thor/ansible/inventory /home/thor/ansible/playbook.yml
```

Output real del lab:

```
PLAY [all] ******************************************************************

TASK [Gathering Facts] ******************************************************
ok: [stapp02]
ok: [stapp03]
ok: [stapp01]

TASK [copy file] ************************************************************
ok: [stapp02]
ok: [stapp03]
ok: [stapp01]

PLAY RECAP ******************************************************************
stapp01    : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
stapp02    : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
stapp03    : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

> **Nota sobre el orden**: los hosts aparecen en orden variable (`stapp02` antes que `stapp01`) porque Ansible ejecuta en **paralelo** sobre los hosts (hasta 5 a la vez por default — el `forks`). El orden del output refleja cuál terminó primero, no el orden del inventario.

### 5. Validar en los hosts destino

```bash
# Vía Ansible (más rápido — un solo comando para los 3)
ansible all -i /home/thor/ansible/inventory -m shell -a "ls -l /opt/finance/"

# O manualmente por host
ssh tony@stapp01 'cat /opt/finance/index.html'
```

## Análisis — diferencias clave con el Día 83

| Aspecto             | Día 83 (file + touch)        | Día 84 (copy)                          |
| ------------------- | ---------------------------- | -------------------------------------- |
| Target              | `hosts: stapp01` (1 host)    | `hosts: all` (3 hosts)                 |
| Módulo              | `file` (`state: touch`)      | `copy`                                 |
| Qué hace            | Crea archivo vacío           | Transfiere archivo del control node    |
| Destino             | `/tmp/` (world-writable)     | `/opt/finance` (de root)               |
| `become`            | No necesario                 | **Sí necesario**                       |
| Idempotencia        | No (siempre `changed`)       | **Sí** (compara checksum)              |
| Credenciales        | 1 set                        | 3 sets (uno por host)                  |

## Variantes del playbook (referencia)

### Variante con permisos y dueño explícitos

```yaml
- hosts: all
  become: true
  tasks:
    - name: copy index.html con permisos
      ansible.builtin.copy:
        src: /usr/src/finance/index.html
        dest: /opt/finance/index.html
        owner: root
        group: root
        mode: '0644'
```

### Variante con backup del archivo previo

```yaml
- name: copy con backup
  ansible.builtin.copy:
    src: /usr/src/finance/index.html
    dest: /opt/finance/
    backup: true        # ← Guarda /opt/finance/index.html.2026-06-15@...~ si ya existía
```

### Variante con `remote_src` (copia dentro del propio remoto)

```yaml
# src ya está en el remoto — Ansible NO transfiere desde el control node
- name: copiar dentro del remoto
  ansible.builtin.copy:
    src: /usr/src/finance/index.html
    dest: /opt/finance/
    remote_src: true
```

## Reflexión: push de archivos con Ansible vs scp/rsync manual

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- copy idempotente (checksum) vs un `scp` o `for host in ...; do scp ...; done`: scp siempre transfiere y sobreescribe; copy solo si el hash difiere. ¿Qué implica esto operacionalmente al correr el mismo playbook 10 veces?
- hosts: all sobre 3 servers en paralelo vs un loop secuencial de scp: ¿qué se gana además de velocidad? (consistencia, reporte unificado, fallar-parcial sin abortar todo)
- El changed=0 del lab: ¿es buena o mala señal? ¿Cómo distingo "no copió porque ya estaba bien" de "no copió porque algo falló silenciosamente"?
- become: true aquí pero no en el Día 83: la diferencia /opt vs /tmp. ¿Vale la pena pensar siempre "¿quién es dueño del destino?" antes de escribir una task de copy/file?
- copy vs template: hoy el archivo es estático. ¿Cuándo el index.html dejaría de servir con copy y necesitaría template (Jinja2)?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                              | Causa                                                                              | Solución                                                                                       |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `Permission denied` al escribir en `/opt/finance`                     | Falta `become: true` — el user no es dueño de `/opt`                               | Agregar `become: true` al play                                                                 |
| El archivo se copia como `/opt/finance` (archivo, no dentro del dir)  | `/opt/finance` no existía como directorio en el remoto                             | Crear el dir antes (`file: state=directory`) o usar `dest: /opt/finance/` con el dir ya creado |
| `Could not find or access '/usr/src/finance/index.html'`              | El `src` no existe en el **control node** (jump host), no en el remoto             | Verificar `ls /usr/src/finance/index.html` en el jump host                                     |
| `unreachable` en uno de los 3 hosts                                   | Credenciales incorrectas para ese host específico                                  | `ansible all -m ping -i inventory` para aislar cuál falla; revisar user/password de ese host   |
| `changed=0` en la primera corrida y se sospecha que no copió          | El destino ya tenía el mismo contenido (checksum idéntico) — comportamiento normal | Validar con `ansible all -m shell -a "cat /opt/finance/index.html"`                            |
| Solo un host recibe el archivo                                        | `hosts:` apunta a un host específico en vez de `all`                               | Cambiar a `hosts: all`                                                                          |
| `ssh: Host key verification failed`                                   | known_hosts sin la host key                                                        | El `StrictHostKeyChecking=no` del inventario lo resuelve                                        |
| `sudo: a password is required`                                        | `become` necesita password de sudo y no se proveyó                                 | En los labs el user suele tener sudo NOPASSWD; si no, agregar `--ask-become-pass` (rompe la validación sin args) |

## Recursos

- [`copy` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [Patterns: targeting hosts and groups](https://docs.ansible.com/ansible/latest/inventory_guide/intro_patterns.html)
- [`become` — privilege escalation](https://docs.ansible.com/ansible/latest/playbook_guide/become.html)
- [`template` module (cuando copy no basta)](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Vault — cifrar secretos del inventario](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
