# Día 83 - Troubleshoot and Create Ansible Playbook (primer playbook real + módulo file)

## Problema / Desafío

Un compañero del equipo dejó a medias un trabajo: un inventario apuntando al server equivocado y sin playbook. Hay que **corregir el inventario** para que apunte a App Server 1 y **escribir el playbook** que cree un archivo vacío en `/tmp/`.

Requirements:

1. Ajustar `/home/thor/ansible/inventory` para que apunte a **App Server 1** (`stapp01`)
2. Crear `/home/thor/ansible/playbook.yml` con una task que cree `/tmp/file.txt` (archivo vacío)
3. La validación corre `ansible-playbook -i inventory playbook.yml` — sin args extras

Estado inicial del inventario (lo que dejó el compañero):

```ini
stapp03 ansible_user=banner ansible_ssh_pass=$pwd ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

Problemas a corregir:

| Problema                       | Fix                                                                |
| ------------------------------ | ------------------------------------------------------------------ |
| Apunta a `stapp03`              | Cambiar a `stapp01`                                                 |
| User `banner` (de stapp03)     | Cambiar a `tony` (user de stapp01)                                 |
| Password `$pwd` (placeholder)  | Cambiar al password real de tony: `Ir0nM@n`                        |

Continúa directamente del Día 82 — mismo enfoque de inventario INI, ahora con su playbook compañero.

## Conceptos clave

### Anatomía de un playbook Ansible

Un playbook YAML es **una lista de plays**. Cada play ata un grupo de hosts con tareas:

```yaml
- hosts: stapp01           # ← Qué hosts (alias o grupo del inventario)
  tasks:                   # ← Lista de tareas a ejecutar
    - name: Create an empty file
      file:
        path: /tmp/file.txt
        state: touch
```

Bloques estándar de un play:

| Bloque             | Función                                                                 |
| ------------------ | ----------------------------------------------------------------------- |
| `hosts:`           | A qué hosts del inventario aplica el play (obligatorio)                 |
| `become:`          | `true` para ejecutar con sudo (default `false`)                          |
| `become_user:`     | Usuario al que escalar (default `root` si `become: true`)               |
| `gather_facts:`    | `true` (default) — recolecta info del sistema antes de ejecutar tasks   |
| `vars:`            | Variables del play                                                       |
| `vars_files:`      | Archivos externos con variables                                          |
| `tasks:`           | Lista de tareas a ejecutar en orden                                      |
| `handlers:`        | Tareas que solo corren si una task las "notifica"                        |
| `pre_tasks:`       | Tareas que corren **antes** de los roles                                |
| `post_tasks:`      | Tareas que corren **después** de los roles                              |
| `roles:`           | Lista de roles a aplicar                                                 |

Para este lab solo se usan `hosts:` y `tasks:`.

### Anatomía de una task

```yaml
- name: Descripción legible de la task   # ← Aparece en el log como "TASK [Descripción]"
  <module_name>:                          # ← Nombre del módulo
    <param1>: <value1>                    # ← Parámetros del módulo
    <param2>: <value2>
  when: <condición>                       # ← Opcional: ejecutar solo si...
  register: <variable>                    # ← Opcional: capturar el resultado
  notify: <handler_name>                  # ← Opcional: disparar handler si changed
  tags: [<tag1>, <tag2>]                  # ← Opcional: para correr selectivamente
```

| Campo         | Función                                                                        |
| ------------- | ------------------------------------------------------------------------------ |
| `name:`       | Descripción legible — aparece en el log. **Buena práctica**: siempre ponerlo  |
| `<module>:`   | Nombre del módulo a invocar (`file`, `apt`, `service`, `copy`, ...)            |
| `when:`       | Ejecutar solo si la condición es verdadera                                     |
| `register:`   | Capturar el output de la task en una variable                                  |
| `notify:`     | Si la task termina como `changed`, dispara el handler especificado             |
| `tags:`       | Para correr solo tasks con cierto tag: `ansible-playbook ... --tags=deploy`    |
| `loop:`       | Iterar sobre una lista de valores                                              |
| `ignore_errors:` | `true` para que la task no aborte el play en caso de fallar                  |

### El módulo `file` — qué hace cada `state`

El módulo `file` gestiona archivos, directorios, y links. La acción depende del valor de `state:`:

| `state`        | Comportamiento                                                                |
| -------------- | ----------------------------------------------------------------------------- |
| `file` (default) | El archivo **debe existir** — verifica + ajusta permisos. **No lo crea**.   |
| `touch`        | Crea si no existe; si existe, actualiza `mtime` (siempre reporta `changed`)    |
| `directory`    | Crea el directorio si no existe; ajusta permisos                              |
| `absent`       | **Elimina** el archivo/directorio/link                                         |
| `link`         | Crea un symlink (soft link)                                                   |
| `hard`         | Crea un hard link                                                              |

Para este lab se usa **`state: touch`** porque hay que **crear** un archivo nuevo.

Parámetros adicionales útiles del módulo `file`:

| Parámetro       | Función                                                                  |
| --------------- | ------------------------------------------------------------------------ |
| `path:`         | Path del archivo/directorio (obligatorio)                                |
| `owner:`        | Cambiar el dueño del archivo (`chown`)                                   |
| `group:`        | Cambiar el grupo (`chgrp`)                                               |
| `mode:`         | Permisos en formato `0644` o `u+rwx,g+r,o+r`                              |
| `recurse:`      | `true` para aplicar `chown`/`chgrp` recursivo a un directorio            |
| `src:`          | Path de origen (para `state: link` o `hard`)                              |

Ejemplo completo:

```yaml
- name: Create empty file with specific permissions
  file:
    path: /tmp/file.txt
    state: touch
    owner: tony
    group: tony
    mode: '0644'
```

### `touch` no es idempotente en el sentido estricto

Una propiedad sutil del módulo `file` con `state: touch`: **cada corrida reporta `changed: true`** aunque el archivo ya exista.

Por qué: `touch` semánticamente significa "actualiza el `mtime` del archivo". Si el archivo ya existe, el contenido no cambia pero el timestamp sí, por lo que Ansible marca la task como `changed`.

Esto importa cuando:

- Los `changed` disparan handlers (ej. restart de servicio) — un touch innecesario causa un restart innecesario
- Se quiere monitorear si "algo realmente cambió" entre runs

Alternativas más estrictas para idempotencia real:

```yaml
# Opción A — state: file (no crea, solo verifica)
- name: Ensure file exists
  file:
    path: /tmp/file.txt
    state: file

# Opción B — command con creates:
- name: Create file only if it doesn't exist
  command: touch /tmp/file.txt
  args:
    creates: /tmp/file.txt   # ← skipea si el archivo ya existe
```

Para este lab `state: touch` está bien (es la forma más directa de crear un archivo vacío).

### `Gathering Facts` — la task implícita que siempre aparece

Antes de ejecutar las tasks del play, Ansible corre **una task implícita** llamada `Gathering Facts`:

```
TASK [Gathering Facts] ******************************************************
ok: [stapp01]
```

Lo que hace:

1. Conecta al host
2. Ejecuta el módulo `setup`
3. Recolecta ~200+ variables del host (OS, IP, kernel, RAM, mount points, etc.)
4. Las hace disponibles como `ansible_facts.*` para las tasks siguientes

Variables comunes recolectadas:

| Variable                                       | Contenido típico                                  |
| ---------------------------------------------- | ------------------------------------------------- |
| `ansible_facts.os_family`                      | `RedHat`, `Debian`, `Suse`, ...                   |
| `ansible_facts.distribution`                   | `CentOS`, `Ubuntu`, `Fedora`, ...                 |
| `ansible_facts.distribution_version`           | `9.4`, `22.04`, ...                                |
| `ansible_facts.kernel`                         | `5.14.0-...`                                       |
| `ansible_facts.architecture`                   | `x86_64`, `aarch64`, ...                          |
| `ansible_facts.hostname`                       | hostname del host                                  |
| `ansible_facts.default_ipv4.address`           | IP primaria del host                               |
| `ansible_facts.memtotal_mb`                    | RAM total en MB                                    |
| `ansible_facts.processor_vcpus`                | Cantidad de CPUs                                   |
| `ansible_facts.mounts`                         | Lista de mount points                              |

Útil para condicionales:

```yaml
- name: Install nginx (Debian)
  apt:
    name: nginx
  when: ansible_facts.os_family == "Debian"

- name: Install nginx (RHEL)
  yum:
    name: nginx
  when: ansible_facts.os_family == "RedHat"
```

### Deshabilitar gathering facts — cuándo y por qué

Recolectar facts toma **1-3 segundos por host**. Para flotas chicas no importa; para 100+ hosts puede sumar minutos.

Si las tasks no usan facts, deshabilitar:

```yaml
- hosts: stapp01
  gather_facts: false           # ← skipea Gathering Facts
  tasks:
    - name: Create file
      file:
        path: /tmp/file.txt
        state: touch
```

Para este lab no importa la performance — gather_facts default está bien.

### El `PLAY RECAP` — las 7 columnas

Al terminar el playbook, Ansible imprime un resumen por host:

```
PLAY RECAP ***************************************
stapp01    : ok=2  changed=1  unreachable=0  failed=0  skipped=0  rescued=0  ignored=0
```

| Columna       | Significado                                                                |
| ------------- | -------------------------------------------------------------------------- |
| `ok`          | Tareas que corrieron sin error (incluye changed)                            |
| `changed`     | Tareas que aplicaron cambios (subconjunto de ok)                            |
| `unreachable` | Hosts inalcanzables (SSH falló, network issue)                              |
| `failed`      | Tareas que fallaron con error                                               |
| `skipped`     | Tareas saltadas por `when:` que evaluó false                                |
| `rescued`     | Tareas recuperadas por `block:` con `rescue:` (try/catch de Ansible)        |
| `ignored`     | Tareas fallidas con `ignore_errors: yes` (no abortan el play)               |

Lectura del recap del lab `ok=2 changed=1`:

- **`ok=2`**: dos tasks corrieron — `Gathering Facts` + `Create an empty file`
- **`changed=1`**: solo una aplicó cambios — `Create an empty file` (gathering no cambia nada)
- **`unreachable=0`**: el host respondió
- **`failed=0`**: ninguna task falló

Este es el patrón canónico de un play exitoso: `ok >= 1`, `unreachable=0`, `failed=0`.

### `ansible_ssh_common_args` — args extras para SSH

El inventario incluye:

```
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

| Arg                              | Función                                                              |
| -------------------------------- | -------------------------------------------------------------------- |
| `-o StrictHostKeyChecking=no`    | No pregunta al primer contacto si "aceptar host key (yes/no)"        |
| `-o UserKnownHostsFile=/dev/null` | No persiste la host key en `~/.ssh/known_hosts`                      |
| `-o ConnectTimeout=10`           | Timeout de conexión en segundos                                       |
| `-o ServerAliveInterval=60`      | Mandar keepalive cada 60s para evitar timeouts                       |

`StrictHostKeyChecking=no` es conveniente para labs (evita prompts), pero en **producción** es **anti-pattern de seguridad** — permite man-in-the-middle attacks. Lo correcto en producción: aceptar manualmente la host key una vez y dejar que SSH valide en runs futuros.

## Pasos

1. Login al jump host como `thor`
2. `cd /home/thor/ansible/`
3. Corregir el inventario: cambiar `stapp03` → `stapp01`, `banner` → `tony`, password placeholder → real
4. Validar inventario con `ansible all -m ping -i inventory`
5. Crear `playbook.yml` con un play que use el módulo `file` con `state: touch`
6. Correr `ansible-playbook -i inventory playbook.yml`
7. Validar SSH al server y `ls /tmp/file.txt`

## Comandos / Código

### 1. Estado inicial del inventario (incorrecto)

```bash
cat /home/thor/ansible/inventory
# stapp03 ansible_user=banner ansible_ssh_pass=$pwd ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

Problemas:

- `stapp03` — debería ser `stapp01`
- `banner` — el user de stapp03; para stapp01 es `tony`
- `$pwd` — placeholder, no es el password real

### 2. Corregir el inventario

```bash
cat > /home/thor/ansible/inventory <<'EOF'
stapp01 ansible_user=tony ansible_ssh_pass=Ir0nM@n ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
```

> **Nota**: el lab usa `ansible_ssh_pass` (alias deprecated). El moderno es `ansible_password`. Para este lab, cualquiera funciona — el alias legacy sigue siendo válido en Ansible 2.x+.

### 3. Validar conectividad

```bash
ansible all -m ping -i /home/thor/ansible/inventory
```

Output esperado:

```
stapp01 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

`"ping": "pong"` confirma:
- DNS / IP resolvió
- SSH autenticó correctamente
- Python existe en el host remoto

### 4. Crear el playbook

```yaml
# /home/thor/ansible/playbook.yml
- hosts: stapp01
  tasks:
    - name: Create an empty file
      file:
        path: /tmp/file.txt
        state: touch
```

Estructura del archivo:

| Nivel                | Significado                                                       |
| -------------------- | ----------------------------------------------------------------- |
| `- hosts: stapp01`   | El play apunta al host `stapp01` del inventario                   |
| `tasks:`             | Lista de tasks del play                                            |
| `- name: ...`        | Una task con descripción                                            |
| `file:`              | El módulo a usar                                                    |
| `path: /tmp/file.txt` | Parámetro del módulo: el path del archivo                         |
| `state: touch`       | Parámetro del módulo: crear si no existe                            |

### 5. Ejecutar el playbook

```bash
ansible-playbook -i /home/thor/ansible/inventory /home/thor/ansible/playbook.yml
```

Output esperado:

```
PLAY [stapp01] **********************************************************

TASK [Gathering Facts] **************************************************
ok: [stapp01]

TASK [Create an empty file] *********************************************
changed: [stapp01]

PLAY RECAP **************************************************************
stapp01    : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

Lectura del output:

| Sección                            | Significado                                                              |
| ---------------------------------- | ------------------------------------------------------------------------ |
| `PLAY [stapp01]`                   | Inicio del play apuntando a stapp01                                       |
| `TASK [Gathering Facts]`           | Task implícita — recolecta info del host                                  |
| `ok: [stapp01]`                    | La task corrió sin cambios                                                |
| `TASK [Create an empty file]`      | El nombre que pusimos en `name:`                                          |
| `changed: [stapp01]`               | La task **creó/modificó** el archivo                                      |
| `PLAY RECAP`                       | Resumen final por host                                                    |

### 6. Validar en el host destino

```bash
ssh tony@stapp01
ls -lhart /tmp/ | grep file
# -rw-r--r--  1 tony tony    0 Jun 15 00:47 file.txt
```

Detalles a notar:

- **Tamaño 0** — archivo vacío como pide el lab
- **Owner: tony:tony** — el user que ejecutó la task vía SSH
- **Permisos: 0644** — default del módulo `file`

### 7. Probar idempotencia — re-correr el playbook

```bash
ansible-playbook -i /home/thor/ansible/inventory /home/thor/ansible/playbook.yml
```

Output esperado:

```
TASK [Create an empty file] *********************************************
changed: [stapp01]                           ← changed=1 de nuevo!

PLAY RECAP **************************************************************
stapp01    : ok=2    changed=1    ...
```

**Sigue marcando `changed`**. Esto es el comportamiento documentado de `state: touch` — no es bug.

Para idempotencia real con `changed=0` en re-runs, usar:

```yaml
- name: Create file only if missing
  copy:
    content: ''
    dest: /tmp/file.txt
    force: false
```

`copy` con `force: false` solo crea el archivo si no existe — segundas corridas marcan `ok=0 changed=0`.

## Variantes del playbook (referencia)

### Variante con permisos explícitos

```yaml
- hosts: stapp01
  tasks:
    - name: Create empty file with specific permissions
      file:
        path: /tmp/file.txt
        state: touch
        owner: tony
        group: tony
        mode: '0644'
```

### Variante con multiple files (loop)

```yaml
- hosts: stapp01
  tasks:
    - name: Create multiple empty files
      file:
        path: "{{ item }}"
        state: touch
      loop:
        - /tmp/file.txt
        - /tmp/another.txt
        - /tmp/third.txt
```

### Variante con become (sudo)

Si el archivo destino es en un directorio que requiere root:

```yaml
- hosts: stapp01
  become: true            # Activar sudo para todo el play
  tasks:
    - name: Create file in /etc
      file:
        path: /etc/file.txt
        state: touch
```

`/tmp/` es world-writable, no requiere `become`. Para escribir en `/etc/`, `/var/log/`, etc., sí.

### Variante con tags

```yaml
- hosts: stapp01
  tasks:
    - name: Create empty file
      file:
        path: /tmp/file.txt
        state: touch
      tags: [setup, files]
```

Correr solo tasks con tag:

```bash
ansible-playbook -i inventory playbook.yml --tags=setup
ansible-playbook -i inventory playbook.yml --skip-tags=files
```

## Anatomía — qué pasa internamente

```
[ansible-playbook -i inventory playbook.yml]
              │
              ▼
1. Parsear inventory → identificar hosts del play (stapp01)
              │
              ▼
2. Conectar via SSH a stapp01 con user tony + password Ir0nM@n
              │
              ▼
3. [Task implícita: Gathering Facts]
   - Copia el módulo `setup` al remoto
   - Lo ejecuta (Python en el remoto)
   - Recibe JSON con ~200 facts
              │
              ▼
4. [Task: Create an empty file]
   - Copia el módulo `file` al remoto (~/.ansible/tmp/)
   - Lo ejecuta con args path=/tmp/file.txt state=touch
   - Recibe JSON con resultado: {"changed": true, "dest": "/tmp/file.txt"}
              │
              ▼
5. Imprimir PLAY RECAP con totales
              │
              ▼
6. Limpiar archivos temporales del remoto
```

> **Detalle importante**: Ansible **no copia el módulo como un script**. Lo serializa con sus args como JSON, lo manda al remoto, y el Python remoto ejecuta el módulo. Por eso **el remoto necesita Python** — sin él, Ansible no puede ejecutar módulos. Las pocas excepciones: módulos `raw` y `script` que ejecutan comandos crudos vía SSH sin Python.

## Módulos comunes que vale conocer (referencia para próximos labs)

| Módulo          | Para qué                                                                |
| --------------- | ----------------------------------------------------------------------- |
| `file`          | Gestionar archivos, directorios, links (lo de hoy)                     |
| `copy`          | Copiar archivos desde el control node al remoto                         |
| `template`      | Renderizar templates Jinja2 y copiar al remoto                          |
| `lineinfile`    | Asegurar que una línea está/no está en un archivo                        |
| `blockinfile`   | Insertar/actualizar un bloque de líneas marcadas en un archivo           |
| `replace`       | Reemplazar texto con regex                                               |
| `apt`           | Gestionar paquetes en Debian/Ubuntu                                      |
| `yum` / `dnf`   | Gestionar paquetes en RHEL/CentOS/Fedora                                 |
| `package`       | Wrapper genérico (detecta apt/yum/dnf automáticamente)                  |
| `service`       | Manage servicios (start/stop/restart/enable)                            |
| `systemd`       | Igual que service pero más opciones específicas de systemd               |
| `user`          | Crear/modificar/eliminar usuarios                                        |
| `group`         | Crear/modificar grupos                                                   |
| `cron`          | Gestionar cron jobs                                                      |
| `git`           | Clone/pull de repos Git                                                  |
| `command`       | Ejecutar comandos arbitrarios (sin shell — sin pipes, redirects)         |
| `shell`         | Ejecutar comandos arbitrarios (con shell — soporta pipes, redirects)     |
| `debug`         | Imprimir variables/mensajes para debugging                              |
| `setup`         | Gathering Facts (se ejecuta implícitamente al inicio)                   |

Cada módulo tiene su doc completa en `ansible-doc <module>` o en la doc oficial.

## Deep dive — referencia transversal

Para una referencia completa de inventarios (formatos, dynamic, vault, troubleshooting) fuera del scope de este lab, ver:

- [`tools/ansible/README.md`](../../tools/ansible/README.md) — guía general de Ansible (conceptos, vocabulario, comandos)
- [`tools/ansible/inventories.md`](../../tools/ansible/inventories.md) — inventarios en profundidad

## Conexión con días anteriores

- **Día 82 (Ansible Inventory)**: el lab que dio la base — sin inventario válido, este playbook no podría correr. Hoy es la siguiente capa: el playbook usando ese inventario.
- **Día 1-5 (Ansible journal original)**: los primeros pasos con Ansible (días 1-5 en la sección ansible-journal). Hoy retoma esa secuencia con un playbook básico.
- **Día 8 (Install Ansible con pip3)**: el setup que permite que `ansible-playbook` exista en el jump host.
- **Día 7 (passwordless SSH)**: la alternativa al password en el inventario — SSH keys en lugar de `ansible_ssh_pass`.
- **Días 71-81 (Jenkins Pipelines)**: el paralelo conceptual — un Jenkinsfile es a Jenkins lo que un playbook es a Ansible. Ambos describen una secuencia de tareas declarativa.
- **Día 75 (Slave Nodes)**: misma idea conceptual — un "nodo gestionado" en Jenkins (agent) ↔ un "managed node" en Ansible (host del inventory). La diferencia: Jenkins requiere agent.jar corriendo; Ansible requiere solo SSH + Python.

## Reflexión: el modelo declarativo de Ansible vs imperativo de scripts shell

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- El módulo `file` con `state: touch` vs hacer `ssh tony@stapp01 'touch /tmp/file.txt'`: ¿la diferencia operacional es solo "más verboso" o hay algo conceptual? ¿En qué casos conviene Ansible sobre un script shell con SSH?
- `Gathering Facts` automático: ¿útil o overhead innecesario para playbooks simples? El trade-off de 1-3 segundos por host vs tener `ansible_facts.*` disponibles.
- El "changed" de touch que siempre marca true: ¿es un bug de Ansible o un trade-off consciente? Compará con el patrón "command + creates:" más estricto.
- Playbook YAML vs Jenkinsfile Groovy: ambos son declarativos pero el primero es más constraint (solo módulos predefinidos) y el segundo más flexible (Groovy puro). ¿Cuándo conviene cada uno?
- El paralelo Ansible managed node ↔ Jenkins agent: ¿es útil mentalizarlo así? La diferencia clave: Ansible es push (sin agente residente), Jenkins es pull (agente persistente).
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `ERROR! the playbook ... could not be found`                            | Path del playbook incorrecto o no existe                                                              | Verificar `ls /home/thor/ansible/playbook.yml`                                                    |
| `ERROR! Syntax Error while loading YAML`                                | Indentación incorrecta o caracteres invisibles en el YAML                                            | Usar `yamllint playbook.yml` o copiar/pegar desde un editor que respete spaces                    |
| `unreachable` en el PLAY RECAP                                           | SSH falló — password incorrecto, host no resuelve, puerto bloqueado                                  | `ansible all -m ping -i inventory` para aislar el problema                                        |
| `Permission denied` al crear el archivo                                  | Path destino requiere permisos root y no se usó `become: true`                                       | Agregar `become: true` al play o usar un path world-writable como `/tmp/`                         |
| `changed: true` en cada re-run aunque el archivo exista                  | Comportamiento documentado de `state: touch` — actualiza mtime                                       | Usar `state: file` (no crea) o `command: touch ... creates:` para idempotencia estricta          |
| `failed=1` con mensaje "module not found"                                | Python en el remoto no encuentra el módulo (raro — viene built-in)                                   | Verificar versión de Ansible: `ansible --version`; actualizar si es muy vieja                     |
| Validación del lab falla aunque el playbook pasó                         | El validador busca específicamente `/tmp/file.txt` pero el playbook lo creó en otro path             | Verificar el path exacto que pide el lab                                                          |
| Playbook funciona desde un user pero no desde otro                       | Cada user tiene su propio `~/.ansible/` y `~/.ssh/`                                                  | Usar `-i` con path absoluto al inventory; no asumir `~/.ansible/`                                |
| `ansible_facts` no disponibles en una task                              | `gather_facts: false` está en el play                                                                | Cambiar a `gather_facts: true` o llamar explícitamente al módulo `setup`                          |
| `ssh: Host key verification failed`                                     | known_hosts no tiene la host key                                                                      | El `StrictHostKeyChecking=no` del inventario lo resuelve. Sin ese arg, aceptar manualmente       |
| Task con `name:` igual a otra y ambas corren pero log confunde            | Ansible permite nombres duplicados — no es bug pero confunde la lectura                              | Usar nombres únicos descriptivos en `name:`                                                       |

## Recursos

- [Playbook basics (oficial)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html)
- [`file` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [`setup` module (Gathering Facts)](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/setup_module.html)
- [Idempotency in Ansible](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_strategies.html)
- [Module index — ansible.builtin](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/index.html)
- [`ansible-doc <module>`](https://docs.ansible.com/ansible/latest/cli/ansible-doc.html) — doc local de cualquier módulo
- [YAML linting](https://yamllint.readthedocs.io/)
