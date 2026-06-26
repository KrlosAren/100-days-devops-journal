# Día 92 - Managing Jinja2 Templates Using Ansible (módulo `template` + roles + `inventory_hostname`)

## Problema / Desafío

Un miembro del equipo Nautilus está desarrollando un **role** para instalar y configurar `httpd`. Falta agregar un template Jinja2 para `index.html` y la task que lo despliega. El inventario `~/ansible/inventory` ya existe. La tarea:

a. Actualizar `~/ansible/playbook.yml` para correr el role `httpd` en **App Server 1** (`stapp01`)
b. Crear un template `index.html.j2` en `/home/thor/ansible/role/httpd/templates/` con la línea:
   ```
   This file was created using Ansible on <servidor respectivo>
   ```
   **No hardcodear** el nombre del server — usar la variable **`inventory_hostname`**
c. Agregar una task en `/home/thor/ansible/role/httpd/tasks/main.yml` que copie el template a `/var/www/html/index.html` con permisos **`0777`**
d. El owner (user/group) de `/var/www/html/index.html` debe ser el **sudo user respectivo** del server (ej. `tony` en `stapp01`)

Restricción de validación: se corre con `ansible-playbook -i inventory playbook.yml` — **sin argumentos extra**. El `become` ya está en el playbook.

> Día clave: es el **primer role** del journal y el primer uso del módulo **`template`** (renderiza Jinja2). Reúne todo lo de Ansible visto hasta ahora dentro de la estructura formal de un role.

## Conceptos clave

### Qué es un role — Ansible organizado por convención

Hasta ahora los playbooks eran un archivo plano con tasks. Un **role** es la forma estándar de **empaquetar y reutilizar** automatización: directorios con nombres fijos que Ansible carga automáticamente.

```
role/httpd/
├── tasks/        → main.yml: las tareas del role (punto de entrada)
├── templates/    → archivos .j2 (Jinja2); el módulo template busca aquí por defecto
├── files/        → archivos estáticos; el módulo copy busca aquí por defecto
├── handlers/     → handlers (notify)
├── defaults/     → variables por defecto (prioridad más baja)
├── vars/         → variables del role (prioridad alta)
├── meta/         → dependencias del role + metadata Galaxy
├── tests/        → playbook de prueba del role
└── README.md     → documentación del role
```

La magia es la **convención sobre configuración**: no se le dice a Ansible dónde buscar el template — al usar `template: src: index.html.j2`, Ansible **automáticamente** lo busca en `templates/` del role. Lo mismo `copy` con `files/`, los handlers en `handlers/main.yml`, etc.

> En este lab el directorio se llama `role/` (singular) en vez del convencional `roles/` (plural). Funciona porque el playbook referencia la ruta explícita `role/httpd`; Ansible respeta el path dado. La convención de Galaxy es `roles/`, pero el path se puede sobreescribir.

### El módulo `template` — `copy` que renderiza Jinja2

```yaml
- name: Copy index from template
  ansible.builtin.template:
    src: index.html.j2            # ← buscado en templates/ del role
    dest: /var/www/html/index.html
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0777'
```

| Módulo     | Qué hace con el contenido                                          |
| ---------- | ----------------------------------------------------------------- |
| `copy`     | Transfiere el archivo **tal cual** (texto literal)                |
| `template` | **Renderiza** Jinja2 (`{{ }}`, `{% %}`) **antes** de transferir   |

Si se usara `copy` con `index.html.j2`, el archivo destino contendría literalmente `{{ inventory_hostname }}`. `template` evalúa esa expresión y escribe `stapp01`. Por eso el lab pide `template`, no `copy`.

### Jinja2 — el motor de templates

Jinja2 es el motor de templates de Python (Django, Flask) que Ansible usa para interpolar variables y lógica:

```jinja
This file was created using Ansible on {{ inventory_hostname }}
{% if ansible_distribution == "CentOS" %}Running on CentOS{% endif %}
{% for user in app_users %}{{ user }}{% endfor %}
```

| Sintaxis    | Función                                          |
| ----------- | ------------------------------------------------ |
| `{{ var }}` | Interpolar el valor de una variable              |
| `{% ... %}` | Lógica de control: `if`, `for`, `set`           |
| `{# ... #}` | Comentario (no se renderiza)                     |
| `\| filter` | Filtros: `{{ name \| upper }}`, `{{ x \| default(5) }}` |

### ★ `inventory_hostname` vs `ansible_hostname` — la distinción que pide el lab

El requisito dice explícitamente: usar **`inventory_hostname`**. Hay varias variables que parecen "el nombre del host" pero **no son lo mismo**:

| Variable                  | De dónde sale                                              | Necesita facts | Valor en stapp01 |
| ------------------------- | ---------------------------------------------------------- | -------------- | ---------------- |
| `inventory_hostname`      | El nombre **tal como está escrito en el inventario**       | **No**         | `stapp01`        |
| `ansible_hostname`        | **Fact gathered** — el `hostname` corto real de la máquina | **Sí**         | `stapp01`        |
| `ansible_fqdn`            | Fact — el FQDN completo                                    | Sí             | `stapp01.…`      |
| `inventory_hostname_short`| `inventory_hostname` cortado en el primer `.`              | No             | `stapp01`        |

- **`inventory_hostname`** es una **magic variable** (Día 85): Ansible siempre la conoce, sin `gather_facts`. Refleja la identidad **lógica** del host en el inventario.
- **`ansible_hostname`** es un **fact**: requiere el `Gathering Facts`, y refleja lo que la máquina cree que es su nombre (`hostname`).

En los labs de KodeKloud ambos coinciden (`stapp01`), así que un template con `ansible_hostname` produce **la misma salida** y "pasa". Pero conceptualmente son distintos: si la máquina tuviera un `hostname` configurado diferente al nombre del inventario, divergirían. **El requisito pide `inventory_hostname`** → se usa ese, que además es más robusto (no depende de facts ni del hostname real del SO).

> Patrón recurrente (Días 65, 67, 90): traducir el requisito **literal** al campo correcto. "Use `inventory_hostname`" es una instrucción exacta, no una sugerencia genérica de "pon el nombre del host".

### `ansible_user` para el owner — el sudo user por host

El requisito (d) pide que el owner sea el "sudo user respectivo" (`tony` en stapp01, `steve` en stapp02, …). Ese valor vive en el inventario como `ansible_user` (la variable de conexión, Día 85):

```yaml
owner: "{{ ansible_user }}"
group: "{{ ansible_user }}"
```

Como cada host define su propio `ansible_user` en el inventario, esto da el owner correcto **por host** sin `when:` ni hardcodear — el mismo patrón "owner por host vía magic var" del Día 85.

### ★ Templating perezoso (lazy) — cuándo se resuelven los `{{ }}`

Clave conceptual: Jinja2 **no** se evalúa al cargar el playbook, sino **por host, justo antes de ejecutar la task**. El flujo real de Ansible:

1. **Carga/parseo YAML**: Ansible lee el archivo como YAML puro. Las `{{ }}` son todavía **texto**, no se tocan.
2. **Compilación**: se arma el plan de tareas. Sigue sin resolver variables (lazy).
3. **Ejecución por host**: cuando la task corre contra `stapp01`, Ansible toma el **contexto de variables de ese host** y recién ahí evalúa los `{{ }}` con Jinja2.
4. **Dispatch del módulo**: `template` recibe los valores **ya resueltos** (`owner=tony`, contenido con `stapp01`, etc.).

Consecuencia práctica: el **mismo** template y la **misma** task producen contenido distinto por host, porque el contexto de variables cambia. Por eso un solo `index.html.j2` sirve para toda la flota.

### El playbook — apuntar el role a App Server 1

El playbook original tenía `hosts:` vacío. Hay que apuntarlo a `stapp01`:

```yaml
---
- hosts: stapp01            # ← App Server 1 (estaba vacío)
  become: yes
  become_user: root
  roles:
    - role/httpd            # ← path explícito al role
```

`become: yes` + `become_user: root` para que el role pueda instalar paquetes y escribir en `/var/www/html`.

## Pasos

1. Login al jump host como `thor`; `cd ~/ansible`
2. Inspeccionar el role: `ls -lhart role/httpd/` y `cat role/httpd/tasks/main.yml`
3. Editar `playbook.yml` → `hosts: stapp01`
4. Crear `role/httpd/templates/index.html.j2` con la línea + `{{ inventory_hostname }}`
5. Agregar la task `template` en `role/httpd/tasks/main.yml`
6. Correr `ansible-playbook -i inventory playbook.yml`
7. Validar contenido + owner + permisos en `stapp01`

## Comandos / Código

### 1. El playbook

```yaml
# ~/ansible/playbook.yml
---
- hosts: stapp01
  become: yes
  become_user: root
  roles:
    - role/httpd
```

### 2. El template Jinja2

```jinja
{# ~/ansible/role/httpd/templates/index.html.j2 #}
This file was created using Ansible on {{ inventory_hostname }}
```

> Una sola línea. `{{ inventory_hostname }}` se resuelve a `stapp01` al ejecutar contra ese host.

### 3. La task dentro del role

```yaml
# ~/ansible/role/httpd/tasks/main.yml
---
- name: install the latest version of HTTPD
  yum:
    name: httpd
    state: latest

- name: Start service httpd
  service:
    name: httpd
    state: started

- name: Copy index from template
  template:
    src: index.html.j2                # ← Ansible lo busca en templates/
    dest: /var/www/html/index.html
    owner: "{{ ansible_user }}"       # ← tony en stapp01 (sudo user del host)
    group: "{{ ansible_user }}"
    mode: '0777'
```

### 4. Ejecutar

```bash
ansible-playbook -i inventory playbook.yml
```

Output real del lab:

```
PLAY [stapp01] *************************************************

TASK [Gathering Facts] *****************************************
ok: [stapp01]

TASK [role/httpd : install the latest version of HTTPD] ********
changed: [stapp01]

TASK [role/httpd : Start service httpd] ************************
changed: [stapp01]

TASK [role/httpd : Copy index from template] *******************
changed: [stapp01]

PLAY RECAP *****************************************************
stapp01 : ok=4  changed=3  unreachable=0  failed=0
```

> Las tasks aparecen prefijadas con `role/httpd :` — así Ansible indica que vienen de un role.

### 5. Verificación

```bash
ansible stapp01 -i inventory -b -m shell \
  -a "cat /var/www/html/index.html; ls -l /var/www/html/index.html"
```

```
This file was created using Ansible on stapp01
-rwxrwxrwx 1 tony tony 47 ... /var/www/html/index.html
```

`stapp01` (de `inventory_hostname`), owner `tony tony` (de `ansible_user`), `-rwxrwxrwx` = `0777`. Los tres requisitos cumplidos.

## Variantes (referencia)

### Correr el role en todos los hosts (no solo stapp01)

```yaml
- hosts: all
  become: yes
  roles:
    - role/httpd
```

Cada host renderizaría su propio `index.html` con su `inventory_hostname` y su `ansible_user` — sin cambiar el template ni la task. Ese es el poder del templating lazy.

### Sintaxis alternativa de roles (con parámetros)

```yaml
roles:
  - role: role/httpd
    vars:
      http_port: 8080
```

### Template con lógica Jinja2

```jinja
This file was created using Ansible on {{ inventory_hostname }}
{% if ansible_default_ipv4 is defined %}
Server IP: {{ ansible_default_ipv4.address }}
{% endif %}
Generated for: {{ ansible_user }}
```

### `validate` — chequear sintaxis antes de escribir (configs críticas)

```yaml
- name: desplegar httpd.conf validándolo
  ansible.builtin.template:
    src: httpd.conf.j2
    dest: /etc/httpd/conf/httpd.conf
    validate: 'httpd -t -f %s'      # %s = archivo temporal; si falla, no lo instala
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| El archivo destino contiene `{{ inventory_hostname }}` literal    | Se usó `copy` en vez de `template`                                             | Usar el módulo `template` para que renderice Jinja2                            |
| `Could not find or access 'index.html.j2'`                       | El template no está en `templates/` del role, o el nombre no coincide          | Crear el `.j2` en `role/httpd/templates/`; `src` es relativo a esa carpeta     |
| El nombre del server sale mal o vacío                            | Se usó `ansible_hostname` (fact) sin gather_facts, o variable equivocada        | Usar `inventory_hostname` (magic var, no necesita facts) como pide el lab      |
| Owner queda como `root` en vez de `tony`                         | No se usó `ansible_user`, o se hardcodeó                                        | `owner: "{{ ansible_user }}"` — toma el sudo user por host                      |
| `hosts:` vacío → no corre en ningún host                        | El playbook original tenía `hosts:` sin valor                                  | Poner `hosts: stapp01`                                                          |
| Permisos no son 0777                                             | `mode` mal escrito o sin comillas (gotcha octal)                              | `mode: '0777'` con comillas                                                    |
| `the role 'httpd' was not found`                                 | Path del role mal referenciado                                                | Usar el path que existe: `- role/httpd` (no solo `httpd` si no está en `roles/`)|
| Funciona con `--become` pero no sin args                        | La validación corre sin `--become`                                            | `become: yes` debe estar **en el playbook**                                     |

## Conexión con días anteriores

- **Día 85 (magic variables)**: `inventory_hostname` y `ansible_user` son magic vars; hoy se usan dentro de un template para renderizar contenido **por host**. Mismo patrón "el dato del host vive en variables, no hardcodeado".
- **Días 88/91 (`blockinfile`/`lineinfile`)**: gestionaban fragmentos de un archivo existente. Hoy `template` genera el **archivo completo** desde una plantilla con variables — el nivel más alto de gestión de contenido.
- **Días 87/89 (`yum`/`service`)**: las dos primeras tasks del role son exactamente ese stack; hoy se ven **empaquetadas dentro de un role** reutilizable.
- **Patrón "traducir requisito literal" (Días 65, 67, 90)**: el lab pide `inventory_hostname` específicamente — usar `ansible_hostname` "funciona" en el lab pero no es lo que se pidió.

## Reflexión: convención sobre configuración (roles + templating lazy)

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- inventory_hostname vs ansible_hostname: en este lab dan el mismo valor, pero el requisito pidió uno específico. ¿Vale la pena entender la diferencia si "funcionan igual"? ¿En qué escenario real divergen y te muerden? (pista: hostname del SO ≠ nombre del inventario)
- templating lazy (las {{ }} se resuelven por host en ejecución, no al cargar): un solo template sirve para 100 servers, cada uno con su valor. ¿Cómo cambia esto tu forma de pensar la automatización vs escribir un archivo por server?
- roles y "convención sobre configuración": Ansible busca templates/ y files/ automáticamente. ¿La magia implícita (no decir dónde buscar) ayuda o esconde lo que pasa? ¿Cuándo preferirías rutas explícitas?
- template vs copy: la diferencia es renderizar o no. ¿Es buena idea usar siempre template "por si acaso", o copy cuando no hay variables comunica mejor la intención?
- el role ya venía con state: latest en el yum (no present). ¿Notaste el no-determinismo que discutimos en el Día 87? ¿Lo cambiarías o respetarías el role tal como está?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`template` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Roles — Ansible docs](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Templating (Jinja2) — Ansible docs](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
- [Special (magic) variables: `inventory_hostname`](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
- [Jinja2 template designer documentation](https://jinja.palletsprojects.com/en/latest/templates/)
