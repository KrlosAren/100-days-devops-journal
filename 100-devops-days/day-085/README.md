# Día 85 - Create Files on App Servers using Ansible (módulo file + variable mágica `ansible_user`)

## Problema / Desafío

El equipo DevOps de Nautilus prueba módulos de Ansible para **crear archivos** en hosts remotos. El reto tiene un detalle elegante: el owner del archivo **debe ser distinto en cada server** — y resulta que ese owner coincide exactamente con el user de conexión de cada host.

Requirements:

1. Crear inventario `~/playbook/inventory` con **todos** los app servers
2. Crear `~/playbook/playbook.yml` que cree un archivo en blanco `/opt/nfsdata.txt` en **todos** los servers
3. Permisos del archivo: `0777`
4. Owner user/group del archivo: **`tony`** en stapp01, **`steve`** en stapp02, **`banner`** en stapp03

| Host      | User conexión | Owner esperado del archivo |
| --------- | ------------- | -------------------------- |
| `stapp01` | `tony`        | `tony`                     |
| `stapp02` | `steve`       | `steve`                    |
| `stapp03` | `banner`      | `banner`                   |

> **Cambio de path**: este lab usa `~/playbook/` (no `~/ansible/` como los Días 83-84). Es solo otra ruta — el concepto no cambia.

Continúa del Día 83 (módulo `file` + `state: touch`) y del Día 84 (`hosts: all` a la flota), agregando el truco de las **variables de conexión por host**.

## Conceptos clave

### El insight del lab: owner == user de conexión

El requirement pide owner `tony`/`steve`/`banner` por server. La tentación es escribir **tres tasks** o un `when:` por host:

```yaml
# ❌ Verboso y frágil — repite la lógica por host
tasks:
  - name: file en stapp01
    file: { path: /opt/nfsdata.txt, state: touch, owner: tony, group: tony }
    when: inventory_hostname == "stapp01"
  - name: file en stapp02
    file: { path: /opt/nfsdata.txt, state: touch, owner: steve, group: steve }
    when: inventory_hostname == "stapp02"
  # ...
```

Pero el owner pedido **es exactamente el user con el que Ansible se conecta a cada host** (`ansible_user`). Eso permite **un solo task** que se adapta solo:

```yaml
# ✅ Un solo task — la variable resuelve el valor correcto por host
- name: create blank file
  file:
    path: /opt/nfsdata.txt
    state: touch
    mode: '0777'
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
```

### Variables mágicas (magic variables) de Ansible

Ansible expone variables especiales en **cada host** durante la ejecución. No hay que definirlas — están siempre disponibles:

| Variable                  | Contenido                                                             |
| ------------------------- | --------------------------------------------------------------------- |
| `{{ ansible_user }}`      | El user de conexión definido en el inventario (`tony`, `steve`, ...)  |
| `{{ inventory_hostname }}`| El alias del host en el inventario (`stapp01`, `stapp02`, ...)         |
| `{{ inventory_hostname_short }}` | El alias sin dominio (`stapp01` de `stapp01.example.com`)       |
| `{{ ansible_host }}`      | IP/hostname real de conexión (si difiere del alias)                   |
| `{{ groups }}`            | Diccionario con todos los grupos y sus hosts                          |
| `{{ group_names }}`       | Lista de grupos a los que pertenece el host actual                    |
| `{{ hostvars }}`          | Diccionario con las variables de **todos** los hosts                  |
| `{{ play_hosts }}` / `{{ ansible_play_hosts }}` | Hosts activos en el play actual                     |

**Clave conceptual**: estas variables se evalúan **por host**. Cuando el play corre sobre stapp01, `{{ ansible_user }}` vale `tony`; sobre stapp02 vale `steve`. El mismo task produce resultados distintos en cada nodo — sin condicionales.

> **`ansible_user` vs facts**: `ansible_user` viene del **inventario** (variable de conexión), está disponible desde el arranque. Los `ansible_facts.*` (Día 83) vienen del `Gathering Facts` y requieren conectar al host primero. Por eso `ansible_user` funciona aunque se haga `gather_facts: false`.

### El módulo `file` con permisos y owner

Mismo módulo del Día 83, ahora usando más parámetros:

```yaml
- name: create blank file
  file:
    path: /opt/nfsdata.txt
    state: touch                  # ← Crea el archivo vacío
    mode: '0777'                  # ← Permisos
    owner: "{{ ansible_user }}"   # ← chown al user
    group: "{{ ansible_user }}"   # ← chgrp al grupo
```

| Parámetro | Función                                                            |
| --------- | ------------------------------------------------------------------ |
| `path:`   | Path del archivo (obligatorio)                                     |
| `state:`  | `touch` para crear vacío (ver Día 83 para todos los states)        |
| `mode:`   | Permisos — **string entre comillas** (`'0777'`)                    |
| `owner:`  | Dueño del archivo (`chown`) — requiere `become` si no es el user actual |
| `group:`  | Grupo del archivo (`chgrp`)                                        |

### Por qué `mode` va entre comillas — el gotcha del octal

`mode: '0777'` con comillas, no `mode: 0777`. Es uno de los errores más comunes en Ansible:

- En YAML, `0777` **sin comillas** se interpreta como número. Según la versión, puede leerse como **octal** (511 decimal) o **decimal** (777), produciendo permisos impredecibles.
- `'0777'` **como string** Ansible lo parsea siempre como octal correctamente → `rwxrwxrwx`.

```yaml
mode: '0777'    # ✅ rwxrwxrwx — owner, group, others: todo
mode: 0777      # ⚠️ ambiguo — puede dar permisos incorrectos
mode: 777       # ⚠️ se lee como decimal → octal 1411 → permisos basura
```

Regla: **siempre comillas en `mode`**. Vale para `file`, `copy`, `template`.

### `0777` — qué significa world-writable

`0777` = `rwxrwxrwx` → lectura + escritura + ejecución para owner, grupo y **todos los demás**.

| Dígito | Aplica a | `7` = `rwx`                |
| ------ | -------- | -------------------------- |
| 1°     | owner    | read + write + execute     |
| 2°     | group    | read + write + execute     |
| 3°     | others   | read + write + execute     |

En el output del lab se ve reflejado: `-rwxrwxrwx 1 tony tony 0 ... nfsdata.txt`. Para el lab está bien, pero `0777` en producción es un **riesgo de seguridad** — cualquier user del sistema puede modificar o borrar el archivo.

### `become: true` — necesario igual que el Día 84

El destino es `/opt/` (de root). Sin `become`, el user no puede crear ni hacer `chown` ahí:

```yaml
- hosts: all
  become: true      # ← sudo para crear en /opt y hacer chown/chgrp
```

Además, hacer `chown` a otro user **siempre** requiere privilegios root, aunque el directorio fuera escribible.

## Pasos

1. Login al jump host como `thor`
2. Crear `~/playbook/inventory` con los 3 app servers y sus credenciales
3. Validar conectividad: `ansible -i ~/playbook/inventory all -m ping`
4. Crear `~/playbook/playbook.yml` con `hosts: all`, `become: true` y el módulo `file`
5. Usar `{{ ansible_user }}` en `owner`/`group` para resolver el dueño por host
6. Correr `ansible-playbook -i inventory playbook.yml`
7. Validar en cada host: `ls -lhart /opt/nfsdata.txt`

## Comandos / Código

### 1. Crear el inventario

```bash
cat > ~/playbook/inventory <<'EOF'
stapp01 ansible_user=tony ansible_ssh_pass=Ir0nM@n ansible_ssh_common_args='-o StrictHostKeyChecking=no'
stapp02 ansible_user=steve ansible_ssh_pass=Am3ric@ ansible_ssh_common_args='-o StrictHostKeyChecking=no'
stapp03 ansible_user=banner ansible_ssh_pass=BigGr33n ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
```

### 2. Validar conectividad

```bash
ansible -i ~/playbook/inventory all -m ping
```

Output esperado (los 3 responden `pong`):

```
stapp01 | SUCCESS => { ... "ping": "pong" }
stapp02 | SUCCESS => { ... "ping": "pong" }
stapp03 | SUCCESS => { ... "ping": "pong" }
```

### 3. Crear el playbook

```yaml
# ~/playbook/playbook.yml
- hosts: all
  become: true
  tasks:
    - name: create blank file
      file:
        path: /opt/nfsdata.txt
        state: touch
        mode: '0777'
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"
```

### 4. Ejecutar el playbook

```bash
ansible-playbook -i ~/playbook/inventory ~/playbook/playbook.yml
```

Output real del lab:

```
PLAY [all] *********************************************************************

TASK [Gathering Facts] *********************************************************
ok: [stapp03]
ok: [stapp02]
ok: [stapp01]

TASK [create blank file] *******************************************************
changed: [stapp02]
changed: [stapp03]
changed: [stapp01]

PLAY RECAP *********************************************************************
stapp01    : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
stapp02    : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
stapp03    : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

> **`changed=1` y no `0`**: a diferencia del Día 84 (módulo `copy`, idempotente), `state: touch` **siempre** marca `changed` porque actualiza el `mtime` en cada corrida. Ver Día 83 para el detalle.

### 5. Validar en el host destino

```bash
ssh tony@stapp01
ls -lhart /opt/nfsdata.txt
# -rwxrwxrwx 1 tony tony 0 Jun 17 01:51 nfsdata.txt
```

Lo que confirma cada parte:

- `-rwxrwxrwx` → permisos `0777` aplicados ✅
- `tony tony` → owner y group correctos (resuelto por `{{ ansible_user }}`) ✅
- `0` → archivo vacío (blank file) ✅

Validar los 3 de una vez sin SSH manual:

```bash
ansible -i ~/playbook/inventory all -m shell -a "ls -l /opt/nfsdata.txt"
# stapp01: -rwxrwxrwx 1 tony   tony   ...
# stapp02: -rwxrwxrwx 1 steve  steve  ...
# stapp03: -rwxrwxrwx 1 banner banner ...
```

Cada host muestra **su propio owner** — la prueba de que `{{ ansible_user }}` se evaluó por host.

## Variantes (referencia)

### Variante explícita con `when:` por host (lo que evitamos)

Funciona, pero es lo que `{{ ansible_user }}` reemplaza con elegancia:

```yaml
- hosts: all
  become: true
  vars:
    owners:
      stapp01: tony
      stapp02: steve
      stapp03: banner
  tasks:
    - name: create blank file
      file:
        path: /opt/nfsdata.txt
        state: touch
        mode: '0777'
        owner: "{{ owners[inventory_hostname] }}"
        group: "{{ owners[inventory_hostname] }}"
```

Útil cuando el owner **no** coincide con el user de conexión. Aquí sí coincide, así que `{{ ansible_user }}` es más simple.

### Variante con host_vars

Definir el owner como variable por host en archivos `host_vars/`:

```yaml
# host_vars/stapp01.yml  →  file_owner: tony
# host_vars/stapp02.yml  →  file_owner: steve
# host_vars/stapp03.yml  →  file_owner: banner

- name: create blank file
  file:
    path: /opt/nfsdata.txt
    state: touch
    mode: '0777'
    owner: "{{ file_owner }}"
    group: "{{ file_owner }}"
```

## Troubleshooting

| Problema                                                            | Causa                                                                            | Solución                                                                                  |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Permisos salen mal (ej. `0511` en vez de `0777`)                    | `mode: 0777` sin comillas — YAML lo interpreta como número                       | Usar siempre `mode: '0777'` como string                                                   |
| `chown failed: failed to look up user X`                            | El user no existe en ese host remoto                                             | Verificar que el owner existe; con `{{ ansible_user }}` está garantizado (es quien conecta) |
| `Permission denied` al crear o hacer chown                          | Falta `become: true` — chown siempre requiere root                               | Agregar `become: true` al play                                                            |
| `{{ ansible_user }}` queda literal o da `undefined`                 | El inventario no define `ansible_user` para ese host                             | Asegurar `ansible_user=...` en cada línea del inventario                                  |
| Owner igual en los 3 hosts (todos `tony`)                           | Se hardcodeó el owner en vez de usar la variable                                 | Usar `owner: "{{ ansible_user }}"` para que resuelva por host                             |
| `changed=1` en cada re-run                                          | `state: touch` actualiza mtime siempre — comportamiento documentado              | Normal; para idempotencia estricta ver Día 83 (`state: file` o `creates:`)               |
| `unreachable` en un host                                            | Credenciales incorrectas de ese host                                             | `ansible all -m ping -i inventory` para aislar cuál falla                                 |

## Conexión con días anteriores

- **Día 83 (Ansible Playbook)**: introdujo el módulo `file` + `state: touch` + Gathering Facts + PLAY RECAP. Hoy reusa `touch` agregando `mode`/`owner`/`group`.
- **Día 84 (copy a app servers)**: introdujo `hosts: all` + `become: true` a la flota de 3 servers. Hoy mismo target, distinto módulo.
- **Contraste de idempotencia 84↔85**: el `copy` del Día 84 era idempotente (`changed=0` en re-run); el `touch` de hoy **siempre** marca `changed`. Mismo PLAY RECAP, lectura distinta.
- **Día 78 (Conditional Pipeline en Jenkins)**: el paralelo conceptual — ahí se parametrizaba el comportamiento con `params`; aquí con variables de inventario. Ambos evitan hardcodear valores por entorno.

## Reflexión: variables de inventario vs lógica condicional

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- {{ ansible_user }} como "configuración que viaja con el host" vs un when:/if por host en el playbook: ¿dónde debería vivir el conocimiento "stapp01 → tony"? ¿En el inventario (datos) o en el playbook (lógica)? ¿Qué pasa cuando agrego stapp04?
- El playbook quedó agnóstico al número de hosts: el mismo task sirve para 3 o 300 servers. ¿Es esto lo que hace a Ansible "declarativo" de verdad, o es solo una variable bien elegida?
- El truco funcionó porque owner == user de conexión por casualidad del lab. ¿Cuándo se rompe esa suposición y obliga a host_vars o un dict? ¿Es peligroso depender de esa coincidencia?
- mode: '0777' world-writable: cómodo para el lab, riesgo en prod. ¿Vale la pena que Ansible no advierta sobre permisos peligrosos, o está bien que confíe en el operador?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`file` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [Magic variables (special variables)](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
- [Using variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html)
- [host_vars y group_vars](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#organizing-host-and-group-variables)
- [Filesystem permissions (modo octal)](https://en.wikipedia.org/wiki/File-system_permissions#Numeric_notation)
