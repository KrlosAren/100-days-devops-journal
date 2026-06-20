# Día 88 - Ansible Blockinfile Module (httpd + bloque marcado + owner/group/mode en un task)

## Problema / Desafío

El equipo de Nautilus necesita un servidor web `httpd` simple en **todos** los app servers de Stratos DC, con una página de muestra desplegada únicamente con Ansible. La tarea:

1. Crear `/home/thor/ansible/playbook.yml` (el inventario `inventory` ya existe en `/home/thor/ansible`)
2. Instalar `httpd` en todos los app servers y dejar el servicio **arrancado y corriendo**
3. Usando el módulo **`blockinfile`**, escribir este contenido en `/var/www/html/index.html`:

   ```
   Welcome to XfusionCorp!

   This is  Nautilus sample file, created using Ansible!

   Please do not modify this file manually!
   ```

4. El archivo `index.html` debe tener owner y group **`apache`** en todos los app servers
5. Los permisos deben ser **`0655`**

Restricciones de validación:

- Se corre con `ansible-playbook -i inventory playbook.yml` — **sin argumentos extra**. El `become` debe vivir dentro del playbook.
- **No usar marker custom ni vacío** en `blockinfile` — hay que dejar los marcadores por defecto.

Cierra la línea de Ansible (Días 82-87). Si el Día 87 instalaba un paquete suelto, hoy se hace el flujo completo de provisioning: **instalar servicio + arrancarlo + desplegar contenido con permisos**, todo en un solo playbook.

## Conceptos clave

### El módulo `blockinfile` — insertar/gestionar un bloque de líneas

`lineinfile` (Día relacionado) gestiona **una** línea. `blockinfile` gestiona un **bloque** de varias líneas como una sola unidad, delimitado por marcadores que el propio módulo inserta:

```yaml
- name: write content
  ansible.builtin.blockinfile:
    path: /var/www/html/index.html
    create: yes
    block: |
      Welcome to XfusionCorp!
      This is  Nautilus sample file, created using Ansible!
      Please do not modify this file manually!
```

Resultado en el archivo:

```
# BEGIN ANSIBLE MANAGED BLOCK
Welcome to XfusionCorp!
This is  Nautilus sample file, created using Ansible!
Please do not modify this file manually!
# END ANSIBLE MANAGED BLOCK
```

| Parámetro     | Función                                                                       |
| ------------- | ----------------------------------------------------------------------------- |
| `path:`       | Archivo a editar (antes `dest:`)                                               |
| `block:`      | El contenido multilínea a insertar (se usa `\|` para bloque YAML literal)      |
| `create:`     | Si el archivo no existe, **créalo** (default `no` → falla si no existe)        |
| `marker:`     | Plantilla de los comentarios delimitadores (default `# {mark} ANSIBLE MANAGED BLOCK`) |
| `insertafter:`/`insertbefore:` | Dónde colocar el bloque (regex, `EOF`, `BOF`)                  |
| `state:`      | `present` (default, inserta/actualiza) o `absent` (borra el bloque)            |
| `owner:`/`group:`/`mode:` | Heredados del módulo `file` — fijan dueño y permisos en el mismo task |

### Los marcadores: el corazón de la idempotencia

`blockinfile` envuelve el bloque entre dos comentarios:

```
# BEGIN ANSIBLE MANAGED BLOCK   ← marker con {mark} = BEGIN
...contenido...
# END ANSIBLE MANAGED BLOCK     ← marker con {mark} = END
```

En cada corrida, Ansible **busca esos marcadores** en el archivo:

- Si los encuentra → reemplaza lo que hay entre ellos (no duplica)
- Si no los encuentra → inserta el bloque entero

Por eso una segunda corrida da `ok` y no `changed`: el bloque ya está delimitado y su contenido no cambió.

> **La restricción del lab — "no usar marker custom ni vacío"** — existe justamente para no romper esto. Si se pone `marker: ""` o un marker raro, la validación que busca el bloque por defecto no lo encuentra, o el módulo pierde la capacidad de reidentificar su bloque y empieza a duplicar contenido.

### `create: yes` — por qué es obligatorio aquí

Un `httpd` recién instalado **no trae** `/var/www/html/index.html`. La página "Testing 123 / It works!" que se ve viene de `/etc/httpd/conf.d/welcome.conf`, no de un index. Es decir: el archivo destino **no existe** cuando corre el task.

```yaml
create: yes    # ← si index.html no existe, créalo; sin esto → "Path does not exist"
```

`blockinfile` con `create: no` (el default) **falla** si el archivo no existe. Con `create: yes`, lo crea y le aplica `owner`/`group`/`mode`. Apenas existe el `index.html`, Apache deja de mostrar el welcome y sirve nuestro contenido.

### owner / group / mode en el mismo task — herencia del módulo `file`

Muchos módulos que tocan archivos (`copy`, `template`, `blockinfile`, `lineinfile`) **heredan los parámetros del módulo `file`**. Eso permite fijar dueño y permisos sin un task `file` aparte:

```yaml
blockinfile:
  path: /var/www/html/index.html
  block: |
    ...
  owner: apache      # ← dueño
  group: apache      # ← grupo
  mode: '0655'       # ← permisos
```

Esto cubre los requisitos 4 y 5 del lab en una sola pasada. El usuario/grupo `apache` es el que crea el paquete `httpd` al instalarse — es el dueño "natural" del docroot.

### Los permisos `0655` — qué significan exactamente

```
0  6   5   5
│  │   │   └── otros: r-x (4+1 = 5)  → leer + ejecutar
│  │   └────── grupo: r-x (4+1 = 5)  → leer + ejecutar
│  └────────── dueño: rw- (4+2 = 6)  → leer + escribir
└───────────── sin bits especiales (setuid/setgid/sticky)
```

`0655` es **inusual**: el dueño puede escribir (`6`) pero no ejecutar, mientras grupo y otros sí pueden ejecutar (`5`) pero no escribir. Para un archivo HTML el bit de ejecución es irrelevante — lo que importa es la **lectura**, presente para los tres. El lab pide exactamente `0655`, así que se respeta al pie de la letra; comillas obligatorias (`'0655'`) para que YAML no lo interprete como número octal/decimal.

### El servicio: `state: started` + `enabled: yes`

```yaml
- name: Start service & enable
  ansible.builtin.service:
    name: httpd
    state: started     # ← arrancado AHORA
    enabled: yes       # ← arranca solo al bootear
```

| Parámetro          | Garantiza                                                  |
| ------------------ | --------------------------------------------------------- |
| `state: started`   | El servicio está **corriendo en este momento**            |
| `enabled: yes`     | El servicio arranca **automáticamente al reiniciar**      |

El lab solo pide "up and running" (→ `state: started`). Agregar `enabled: yes` es buena práctica: sin él, un reboot dejaría el web server caído.

### El playbook completo — anatomía

```yaml
- hosts: all              # ← los 3 app servers del inventario
  become: true            # ← root: instalar y tocar /var/www requiere privilegios
  tasks:
    - name: install packages
      ansible.builtin.yum:
        name: httpd
        state: present

    - name: Start service & enable
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: yes

    - name: write content on /var/www/html/index.html
      ansible.builtin.blockinfile:
        path: /var/www/html/index.html
        create: yes
        block: |
          Welcome to XfusionCorp!
          This is  Nautilus sample file, created using Ansible!
          Please do not modify this file manually!
        owner: apache
        group: apache
        mode: '0655'
```

`become: true` está **en el play**, no en la línea de comando — clave para que la validación corra sin `--become`.

## Pasos

1. Login al jump host como `thor`; `cd /home/thor/ansible`
2. Validar conectividad: `ansible -i inventory all -m ping`
3. Crear `/home/thor/ansible/playbook.yml` con los 3 tasks (yum → service → blockinfile)
4. Correr `ansible-playbook -i inventory playbook.yml`
5. Validar: `curl <app-server>` o revisar permisos/owner del `index.html`

## Comandos / Código

### 1. Validar conectividad

```bash
ansible -i inventory all -m ping
```

```
stapp01 | SUCCESS => { ... "ping": "pong" }
stapp02 | SUCCESS => { ... "ping": "pong" }
stapp03 | SUCCESS => { ... "ping": "pong" }
```

### 2. El playbook (solución utilizada)

```yaml
# /home/thor/ansible/playbook.yml
- hosts: all
  become: true
  tasks:
    - name: install packages
      ansible.builtin.yum:
        name: httpd
        state: present

    - name: Start service & enable
      service:
        name: httpd
        state: started
        enabled: yes

    - name: write content on /var/www/html/index.html
      ansible.builtin.blockinfile:
        path: /var/www/html/index.html
        create: yes
        block: |
          Welcome to XfusionCorp!
          This is  Nautilus sample file, created using Ansible!
          Please do not modify this file manually!
        owner: apache
        group: apache
        mode: '0655'
```

### 3. Ejecutar el playbook

```bash
ansible-playbook -i inventory playbook.yml
```

Output real del lab (recortado):

```
TASK [install packages] ********************************
ok: [stapp02]
ok: [stapp01]
ok: [stapp03]

TASK [Start service & enable] **************************
changed: [stapp02]
changed: [stapp01]
changed: [stapp03]

TASK [write content on /var/www/html/index.html] *******
ok: [stapp02]
ok: [stapp03]
ok: [stapp01]

PLAY RECAP *********************************************
stapp01  : ok=6  changed=2  unreachable=0  failed=0
stapp02  : ok=6  changed=2  unreachable=0  failed=0
stapp03  : ok=6  changed=2  unreachable=0  failed=0
```

> `httpd` salió `ok` (ya estaba `present` en la imagen del lab); el servicio salió `changed` (lo arrancó). El bloque salió `ok` porque ya se había escrito en una corrida previa — si fuera la primera vez sería `changed`.

### 4. Verificación

Opción A — desde un task de debug dentro del propio playbook (como en el lab):

```yaml
- name: test service
  ansible.builtin.shell: curl localhost
  register: server_content

- name: server ok
  ansible.builtin.debug:
    var: server_content.stdout
```

```
"server_content.stdout": "# BEGIN ANSIBLE MANAGED BLOCK\nWelcome to XfusionCorp!\nThis is  Nautilus sample file, created using Ansible!\nPlease do not modify this file manually!\n# END ANSIBLE MANAGED BLOCK"
```

Opción B — ad-hoc, verificar permisos y owner en los 3 hosts:

```bash
ansible -i inventory all -m shell -a "ls -l /var/www/html/index.html" --become
# esperado: -rw-r-xr-x. 1 apache apache ... index.html
```

Opción C — confirmar contenido servido:

```bash
ansible -i inventory all -m uri -a "url=http://localhost return_content=yes" --become
```

## Variantes (referencia)

### Controlar dónde se inserta el bloque

```yaml
- name: insertar bloque al inicio del archivo
  ansible.builtin.blockinfile:
    path: /etc/motd
    insertbefore: BOF        # Beginning Of File (también: EOF, o un regex)
    block: |
      Acceso monitoreado.
```

### Múltiples bloques en el mismo archivo (requiere marker distinto)

Cuando se necesita más de un bloque gestionado en un mismo archivo, **sí** se usa `marker` custom — pero ojo, este lab lo prohíbe:

```yaml
- ansible.builtin.blockinfile:
    path: /etc/ssh/sshd_config
    marker: "# {mark} BLOQUE HARDENING"
    block: |
      PermitRootLogin no
```

### Borrar un bloque gestionado

```yaml
- ansible.builtin.blockinfile:
    path: /var/www/html/index.html
    state: absent          # elimina el bloque entre marcadores
```

### `blockinfile` vs `copy`/`template` — cuándo cada uno

| Módulo        | Para                                                                 |
| ------------- | ------------------------------------------------------------------- |
| `blockinfile` | Insertar/gestionar **un fragmento** dentro de un archivo existente  |
| `lineinfile`  | Gestionar **una sola línea** (regex match + replace)                |
| `copy`        | Poner un archivo **completo** desde el control node                 |
| `template`    | Archivo **completo** con variables Jinja2 (`{{ }}`)                 |

Para un `index.html` que **es** todo el contenido, `copy`/`template` serían más naturales; el lab pide `blockinfile` específicamente para practicar la gestión de fragmentos marcados.

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `Path /var/www/html/index.html does not exist`                  | `httpd` no crea `index.html`; falta `create: yes`                              | Agregar `create: yes` al task de `blockinfile`                                  |
| El bloque se **duplica** en cada corrida                        | Marker custom/vacío rompe la reidentificación del bloque                        | Dejar el marker por defecto (la restricción del lab)                            |
| `chown failed: failed to look up user apache`                   | `httpd` aún no instalado → el usuario `apache` no existe                        | Asegurar que el task `yum` corre **antes** que el `blockinfile`                 |
| `mode: 655` interpretado mal / permisos raros                   | YAML lee `0655` sin comillas como número                                        | Usar comillas: `mode: '0655'`                                                   |
| Servicio instalado pero `curl` no responde                      | Falta `state: started` o firewall                                              | `state: started` en el task `service`; revisar `firewalld`                      |
| Funciona con `--become` pero no sin args                        | La validación corre sin `--become`                                            | Poner `become: true` **dentro del play**, no en la CLI                          |
| `failed to transfer file ... curl: command not found`           | El task de verificación usa `curl` y el host no lo tiene                        | Usar el módulo `uri` en vez de `shell: curl` para verificar                     |
| Segunda corrida da `changed` en el bloque sin haber tocado nada | El `block:` tiene espacios/saltos distintos al archivo                          | Mantener el `block:` idéntico; revisar trailing whitespace                      |

## Conexión con días anteriores

- **Día 87 (`yum`)**: ahí se instalaba un paquete suelto; hoy `yum` es solo el primer paso de un flujo completo instalar → arrancar → desplegar.
- **Días 84-85 (`copy`, `file`)**: `blockinfile` hereda los parámetros `owner`/`group`/`mode` del módulo `file` — el mismo patrón de permisos, ahora en un módulo de edición.
- **Día 86 (passwordless SSH)**: el pre-requisito que deja correr el playbook sin password; el `ping` de hoy confirma que sigue funcionando.
- **Día 68 (Install Jenkins a mano)**: el contraste imperativo — ahí se instaló y arrancó un servicio web por SSH manual sobre un host; hoy Ansible hace instalar + arrancar + configurar contenido declarativamente sobre toda la flota.

## Reflexión: gestión de fragmentos vs archivos completos

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- blockinfile (fragmento marcado dentro de un archivo) vs copy/template (archivo completo): para este index.html que ES todo el contenido, ¿blockinfile fue la herramienta correcta o el lab lo pidió solo para practicar? ¿En qué caso real preferirías cada uno?
- Los marcadores ANSIBLE MANAGED BLOCK son lo que da idempotencia: ¿qué pasa conceptualmente si dos playbooks distintos editan el mismo archivo con el marker por defecto? ¿Por qué entonces existen los markers custom?
- create: yes resuelve "el archivo no existe", pero ¿es buena idea que un módulo de "edición" también cree archivos? ¿O mezcla responsabilidades que deberían ser dos tasks (file + blockinfile)?
- mode '0655': permisos que el dueño puede escribir pero no ejecutar, y otros pueden ejecutar pero no escribir. Para un HTML da igual el bit de ejecución, pero ¿copiar un mode "raro" sin cuestionarlo es un riesgo? ¿Cuándo importaría?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`blockinfile` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/blockinfile_module.html)
- [`lineinfile` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/lineinfile_module.html)
- [`service` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)
- [`uri` module (verificar HTTP)](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html)
- [Managing files with Ansible](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html)
