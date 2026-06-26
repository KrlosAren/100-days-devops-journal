# Día 91 - Ansible Lineinfile Module (gestión de una línea + `insertbefore`/`regexp` + `touch` no trunca)

## Problema / Desafío

El equipo Nautilus quiere un `httpd` simple en **todos** los app servers, con una página de muestra desplegada con Ansible. La tarea:

1. Crear `/home/thor/ansible/playbook.yml` (el inventario ya existe)
2. Instalar `httpd` en todos los app servers y dejar el servicio **arrancado y corriendo**
3. Crear `/var/www/html/index.html` con el contenido:
   ```
   This is a Nautilus sample file, created using Ansible!
   ```
4. Usando el módulo **`lineinfile`**, añadir esta línea **al inicio** del archivo:
   ```
   Welcome to xFusionCorp Industries!
   ```
5. El archivo debe ser propiedad de `apache:apache` en todos los app servers
6. Los permisos deben ser **`0744`**

Restricción de validación: se corre con `ansible-playbook -i inventory playbook.yml` — **sin argumentos extra**. El `become` debe vivir dentro del playbook.

> Es el contrapunto del Día 88: si `blockinfile` gestiona un **bloque** de líneas, `lineinfile` gestiona **una sola línea**. Y este lab esconde una lección sobre por qué `state: touch` **no** borra el contenido previo (ver el cuadro más abajo).

## Conceptos clave

### El módulo `lineinfile` — asegurar que **una** línea esté (o no) en un archivo

```yaml
- name: add welcome line at the top
  ansible.builtin.lineinfile:
    path: /var/www/html/index.html
    line: 'Welcome to xFusionCorp Industries!'
    insertbefore: BOF
```

| Parámetro       | Función                                                                       |
| --------------- | ----------------------------------------------------------------------------- |
| `path:`         | Archivo a editar                                                              |
| `line:`         | La línea exacta que debe existir                                              |
| `regexp:`       | Patrón para **buscar** una línea existente y reemplazarla (el uso más potente)|
| `insertbefore:` | Dónde insertar si la línea es nueva: `BOF` o un regex                         |
| `insertafter:`  | Dónde insertar: `EOF` (default) o un regex                                    |
| `state:`        | `present` (default, asegura la línea) / `absent` (la borra)                   |
| `create:`       | `yes` → crear el archivo si no existe                                         |
| `backrefs:`     | Usar grupos capturados del `regexp` en el `line`                             |

### Idempotencia: `lineinfile` matchea la **línea completa**

Esta es la clave para entender el output del lab. `lineinfile` con `state: present`:

1. Busca si la `line` (o el `regexp`) ya existe en el archivo.
2. **Si existe** → no hace nada (`ok`, no `changed`). **No la mueve ni la duplica**, aunque haya un `insertbefore`/`insertafter`.
3. **Si no existe** → la inserta en la posición indicada.

> El punto sutil: `insertbefore`/`insertafter` **solo aplican cuando la línea se está agregando**. Si la línea ya está en el archivo, su posición actual se respeta.

### `insertbefore` / `insertafter` — dónde cae la línea nueva

| Valor             | Posición                                                  |
| ----------------- | --------------------------------------------------------- |
| `insertbefore: BOF` | **B**eginning **O**f **F**ile — al inicio                |
| `insertafter: EOF`  | **E**nd **O**f **F**ile — al final (default)             |
| `insertbefore: '^ServerName'` | Justo antes de la primera línea que matchea el regex |
| `insertafter: '^\[main\]'`    | Justo después de la línea que matchea               |

**Gotcha de orden (LIFO en BOF)**: si dos tasks insertan con `insertbefore: BOF`, la que corre **última** queda arriba, porque cada inserción empuja a la anterior hacia abajo. En este lab, "add welcome" corre después de "add base content", por eso `Welcome...` termina en el tope — justo lo que pide el requisito.

### ★ Por qué sobrevive `This is KodeKloud Ansible Lab !` — `state: touch` NO trunca

El `curl` del lab muestra **tres** líneas, pero el playbook solo añade dos:

```
Welcome to xFusionCorp Industries!     ← añadida por lineinfile (insertbefore BOF)
This is KodeKloud Ansible Lab !        ← ¿de dónde salió esto?
This is a Nautilus sample file, created using Ansible!   ← preexistente
```

La línea de KodeKloud **no la añade nadie** en el playbook. El lab **pre-siembra** el `index.html`, y el task de creación usa `state: touch`:

```yaml
- name: create file
  ansible.builtin.file:
    path: /var/www/html/index.html
    state: touch         # ← solo actualiza el mtime; NO borra el contenido
    owner: apache
    group: apache
    mode: '0744'
```

`state: touch` sobre un archivo que ya existe **solo cambia el timestamp** — no lo vacía. Por eso el contenido pre-existente sobrevive. La reconstrucción del archivo inicial:

```
# Archivo pre-sembrado por el lab:
This is KodeKloud Ansible Lab !
This is a Nautilus sample file, created using Ansible!
```

Luego:

1. `add base content` (`This is a Nautilus...`, insertbefore BOF) → **la línea ya existe** → no-op idempotente, queda donde estaba (abajo).
2. `add welcome` (`Welcome...`, insertbefore BOF) → línea nueva → se inserta arriba de todo.

Resultado final = el output del `curl`. **Si se quisiera un archivo limpio** (sin la línea de KodeKloud), `touch` es la herramienta equivocada — habría que usar `copy`/`content`, o borrar la línea con `lineinfile state=absent`, o `template`.

### El verdadero superpoder de `lineinfile`: `regexp` (editar config files)

El caso de uso real de `lineinfile` no es "añadir una línea de bienvenida" — es **buscar y reemplazar una directiva en un archivo de configuración**:

```yaml
- name: forzar PermitRootLogin no en sshd_config
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PermitRootLogin'        # ← matchea la línea exista o esté comentada
    line: 'PermitRootLogin no'          # ← la reemplaza por esta
```

Aquí `regexp` localiza la línea (esté como `PermitRootLogin yes`, comentada, o ausente) y la deja exactamente como `line`. Sin `regexp`, cada cambio de valor crearía una línea **nueva** en vez de reemplazar la vieja — `regexp` es lo que hace a `lineinfile` idempotente sobre directivas que cambian de valor.

### `lineinfile` vs `blockinfile` vs `copy`/`template` — cuándo cada uno

| Módulo        | Para                                                                 |
| ------------- | ------------------------------------------------------------------- |
| `lineinfile`  | **Una** línea: añadir o reemplazar una directiva (regexp)            |
| `blockinfile` | **Un bloque** de varias líneas marcado (Día 88)                     |
| `copy`        | Archivo **completo** desde el control node                          |
| `template`    | Archivo **completo** con variables Jinja2                           |

Regla: para 1 directiva → `lineinfile`; para N líneas que van juntas → `blockinfile`; para el archivo entero → `copy`/`template`.

### El playbook completo — anatomía

```yaml
- hosts: all
  become: true
  tasks:
    - name: install httpd        # Día 87
      ansible.builtin.yum:
        name: httpd
        state: present
    - name: manage service       # Día 89
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: yes
    - name: create file          # Día 85 (touch + owner/group/mode)
      ansible.builtin.file:
        path: /var/www/html/index.html
        owner: apache
        group: apache
        state: touch
        mode: '0744'
    - name: add base content     # protagonista de hoy
      ansible.builtin.lineinfile:
        path: /var/www/html/index.html
        line: 'This is a Nautilus sample file, created using Ansible!'
        insertbefore: BOF
    - name: add welcome line at the top
      ansible.builtin.lineinfile:
        path: /var/www/html/index.html
        line: 'Welcome to xFusionCorp Industries!'
        insertbefore: BOF        # corre último → queda arriba
```

Los permisos `0744` (`rwxr--r--`): owner puede leer/escribir/ejecutar, grupo y otros solo leer. El bit de ejecución del owner es irrelevante para un HTML, pero el lab lo pide literal → comillas `'0744'` para que YAML no lo lea como octal.

## Pasos

1. Login al jump host como `thor`; `cd /home/thor/ansible`
2. Validar conectividad: `ansible -i inventory all -m ping`
3. Crear `/home/thor/ansible/playbook.yml`: `yum` → `service` → `file` (touch + perms) → `lineinfile` x2
4. Correr `ansible-playbook -i inventory playbook.yml`
5. Validar con `curl http://stappNN` y revisando owner/perms

## Comandos / Código

### Playbook (solución utilizada)

```yaml
# /home/thor/ansible/playbook.yml
- hosts: all
  become: true
  tasks:
    - name: install httpd
      ansible.builtin.yum:
        name: httpd
        state: present
    - name: manage service
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: yes
    - name: create file
      file:
        path: /var/www/html/index.html
        owner: apache
        group: apache
        state: touch
        mode: '0744'
    - name: add base content
      lineinfile:
        path: /var/www/html/index.html
        line: 'This is a Nautilus sample file, created using Ansible!'
        insertbefore: BOF
    - name: add welcome line at the top
      lineinfile:
        path: /var/www/html/index.html
        line: 'Welcome to xFusionCorp Industries!'
        insertbefore: BOF
```

### Verificación

```bash
# El contenido servido (desde el jump host)
curl http://stapp01
```

Output real del lab:

```
Welcome to xFusionCorp Industries!
This is KodeKloud Ansible Lab !
This is a Nautilus sample file, created using Ansible!
```

> `Welcome...` arriba (lo que pide el lab). La línea de KodeKloud es contenido pre-sembrado que `state: touch` no borró. La línea Nautilus quedó abajo porque ya existía y `lineinfile` no la movió.

```bash
# Owner y permisos en los 3 hosts
ansible -i inventory all -m shell -a "ls -l /var/www/html/index.html" --become
# esperado: -rwxr--r--. 1 apache apache ... index.html
```

## Variantes (referencia)

### Crear un archivo limpio (sin contenido pre-existente)

Si se quisiera que el archivo tenga **solo** las líneas del lab, `touch` no sirve. Opciones:

```yaml
# Opción A: copy con content (reemplaza todo el archivo)
- ansible.builtin.copy:
    dest: /var/www/html/index.html
    content: |
      Welcome to xFusionCorp Industries!
      This is a Nautilus sample file, created using Ansible!
    owner: apache
    group: apache
    mode: '0744'
```

```yaml
# Opción B: lineinfile con create (sin tocar mtime de un archivo que ya existe)
- ansible.builtin.lineinfile:
    path: /var/www/html/index.html
    line: 'This is a Nautilus sample file, created using Ansible!'
    create: yes
    owner: apache
    group: apache
    mode: '0744'
```

### Reemplazar una directiva con `regexp`

```yaml
- ansible.builtin.lineinfile:
    path: /etc/httpd/conf/httpd.conf
    regexp: '^Listen '
    line: 'Listen 8080'
```

### Borrar una línea

```yaml
- ansible.builtin.lineinfile:
    path: /var/www/html/index.html
    line: 'This is KodeKloud Ansible Lab !'
    state: absent          # quita esa línea exacta
```

### Insertar después de un patrón

```yaml
- ansible.builtin.lineinfile:
    path: /etc/hosts
    insertafter: '^127\.0\.0\.1'
    line: '127.0.0.1 myapp.local'
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Aparecen líneas que no añadí (ej. "KodeKloud Lab")              | `state: touch` no trunca; el archivo tenía contenido pre-existente             | Usar `copy`/`content` o `lineinfile state=absent` para limpiar lo no deseado    |
| La línea no se mueve al top pese a `insertbefore: BOF`          | La línea ya existía → `lineinfile` es idempotente y no la reubica              | Normal; `insertbefore` solo aplica al **agregar** una línea nueva               |
| `Welcome` no quedó arriba                                       | Orden de tasks: la última inserción en BOF gana el top                          | Poner el task de la línea que va arriba **al final** (o usar un solo task)      |
| Cada corrida crea una línea duplicada con valor distinto        | Se omitió `regexp` al editar una directiva variable                            | Usar `regexp:` para matchear y reemplazar la línea existente                    |
| `Destination does not exist` en el task `lineinfile`            | El archivo no existe y falta `create: yes`                                     | Asegurar el task `file`/`copy` antes, o `create: yes` en `lineinfile`           |
| El task `file` sale `changed` siempre                           | `state: touch` no es idempotente (toca mtime cada run)                         | Normal; usar `state: present` (sin touch) si no se quiere modificar el mtime    |
| Funciona con `--become` pero no sin args                        | La validación corre sin `--become`                                            | Poner `become: true` **dentro del play**                                        |

## Conexión con días anteriores

- **Día 88 (`blockinfile`)**: el par conceptual — bloque vs línea única. `blockinfile` usa marcadores para reidentificar su bloque; `lineinfile` matchea la línea completa (o un `regexp`).
- **Día 85 (`file` + `touch` + `mode`)**: el task de creación reusa exactamente eso (touch + owner/group/mode con comillas). Hoy se ve el lado oscuro de `touch`: no trunca.
- **Días 87-89 (`yum` + `service`)**: los dos primeros tasks son el stack httpd ya conocido; hoy se le añade la gestión fina del contenido línea por línea.
- **Idempotencia (Días 84, 87)**: `lineinfile` es idempotente sobre la línea/regexp; `state: touch` **no** lo es (mtime). Conviven en el mismo playbook — útil para distinguir qué task saldrá `changed` siempre.

## Reflexión: gestión quirúrgica de archivos vs reescribir el archivo entero

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- lineinfile/blockinfile (editar in-place, preservando lo demás) vs copy/template (reemplazar todo): editar in-place es menos destructivo pero deja contenido ajeno (la línea de KodeKloud). ¿Cuándo prefieres "no tocar lo que no es mío" vs "el archivo debe quedar EXACTAMENTE así"? ¿Qué enfoque da más garantías en producción?
- el regexp es lo que hace útil a lineinfile (reemplazar directivas), pero hoy no se usó. ¿Añadir una línea sin regexp es un anti-patrón que en el próximo run podría duplicar, o está bien para contenido que nunca cambia de valor?
- state: touch no trunca y por eso sobrevivió la línea de KodeKloud. El playbook "pasó" la validación igual. ¿Es otro caso de "el test verde no garantiza el estado que yo creía"? ¿Cómo lo detectarías antes de que sea un problema?
- el gotcha del orden (último insertbefore BOF gana): el resultado correcto dependió del orden de los tasks. ¿Es frágil depender del orden, o es comportamiento predecible que está bien explotar?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`lineinfile` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/lineinfile_module.html)
- [`blockinfile` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/blockinfile_module.html)
- [`copy` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [`replace` module (regex en todo el archivo)](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/replace_module.html)
- [Managing files with Ansible](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html)
