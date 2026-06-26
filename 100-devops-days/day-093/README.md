# Día 93 - Using Ansible Conditionals (`when` + `ansible_nodename` + facts)

## Problema / Desafío

El equipo Nautilus quiere ejercitar **todas** las formas que ofrece Ansible para una misma tarea. Hoy toca usar **condicionales `when`**. El inventario ya existe. La tarea:

Crear `/home/thor/ansible/playbook.yml` usando `when` para:

1. Copiar `/usr/src/devops/blog.txt` (del jump host) a **App Server 1** en `/opt/devops/` → owner `tony:tony`, permisos `0777`
2. Copiar `/usr/src/devops/story.txt` a **App Server 2** → owner `steve:steve`, permisos `0777`
3. Copiar `/usr/src/devops/media.txt` a **App Server 3** → owner `banner:banner`, permisos `0777`

Restricciones del lab:

- Usar la variable **`ansible_nodename`** (de los facts) en los `when`
- Usar **`- hosts: all`** (correr el play sobre todos los hosts)
- Validación: `ansible-playbook -i inventory playbook.yml` — **sin args extra**; `become` dentro del playbook

> Mismo objetivo que el Día 90 (cada archivo a un host distinto), pero por una **tercera** vía: un solo play sobre `all` + `when` por task. El lab obliga este enfoque para enseñar condicionales.

## Conceptos clave

### `when` — ejecutar una task solo si se cumple una condición

`when` es el condicional de Ansible: la task corre **solo si** la expresión es verdadera para ese host. Si es falsa, la task se **salta** (`skipped`):

```yaml
- name: copy blog.txt
  copy:
    src: /usr/src/devops/blog.txt
    dest: /opt/devops/blog.txt
  when: ansible_nodename == "stapp01"      # ← solo en stapp01
```

Como el play corre sobre `all`, los **tres** hosts evalúan **las tres** tasks; cada `when` deja pasar solo la que le toca. El resultado neto es idéntico a tres plays separados, pero con un único play.

| Detalle de `when`                            | Comportamiento                                          |
| -------------------------------------------- | ------------------------------------------------------- |
| Expresión verdadera                          | La task se ejecuta (`ok`/`changed`)                     |
| Expresión falsa                              | La task se **salta** (`skipped`)                        |
| `when:` sin `{{ }}`                          | Se evalúa como expresión Jinja2 **directamente** (sin llaves) |
| Lista de condiciones                         | Se combinan con **AND** implícito                       |

> **Gotcha sutil**: en `when` **no** se ponen las `{{ }}`. Se escribe `when: ansible_nodename == "stapp01"`, no `when: "{{ ansible_nodename }}" == ...`. `when` ya espera una expresión Jinja2, así que las llaves sobran (y dan warning).

### ★ `ansible_nodename` — el tercer "nombre del host"

El lab pide `ansible_nodename` específicamente. Es la **tercera** variable tipo-hostname del journal, y conviene tener clara la diferencia:

| Variable                  | Origen                                              | ¿Necesita facts? | Equivalente shell      |
| ------------------------- | --------------------------------------------------- | ---------------- | ---------------------- |
| `inventory_hostname`      | Nombre **en el inventario** (Día 92)                | **No** (magic)   | —                      |
| `ansible_hostname`        | Hostname **corto** del SO (Día 92)                  | Sí (fact)        | `hostname -s`          |
| `ansible_nodename`        | **Node name** de la red (hoy)                       | Sí (fact)        | `uname -n` / `hostname`|
| `ansible_fqdn`            | Nombre completo con dominio                          | Sí (fact)        | `hostname -f`          |

`ansible_nodename` es un **fact**: sale del `Gathering Facts` (internamente `uname -n`). En estos labs coincide con `stapp01`, pero conceptualmente es lo que el **kernel** reporta como nombre del nodo.

### ★ La consecuencia: NO deshabilitar `gather_facts`

Como `ansible_nodename` es un fact, **debe** recolectarse antes de evaluar el `when`. Si se pone `gather_facts: no`, la variable queda **indefinida** y **todos** los `when` fallan (o dan error de variable undefined) → no se copia nada.

```yaml
- hosts: all
  become: true
  # gather_facts: yes   ← es el DEFAULT, no hace falta ponerlo
```

Por defecto `gather_facts` está en `yes`, así que dejarlo implícito es correcto. La lección: **un `when` basado en un fact crea una dependencia obligatoria con el fact-gathering**. Si se usara `inventory_hostname` (magic var), no habría esa dependencia — pero el lab pidió `ansible_nodename`.

### `copy` con `src` local — push desde el control node

Los `.txt` están en el **jump host** (control node). El módulo `copy` toma el archivo de ahí y lo **empuja** al remoto:

```yaml
copy:
  src: /usr/src/devops/blog.txt    # ← ruta en el CONTROL NODE (jump host)
  dest: /opt/devops/blog.txt       # ← ruta en el host REMOTO
```

| Parámetro          | Significado                                                        |
| ------------------ | ----------------------------------------------------------------- |
| `src` (default)    | Archivo en el **control node** → se empuja al remoto              |
| `remote_src: yes`  | El `src` ya está **en el host remoto** (copia local allá)         |

Aquí **no** se usa `remote_src` porque el origen está en el jump host, no en los app servers. (Día 84 ya usó `copy` así.)

### `ansible_user` para el owner — el sudo user por host

El inventario define `ansible_user` por host (`tony`/`steve`/`banner`). Igual que el Día 85/92, `owner: "{{ ansible_user }}"` da el dueño correcto por host sin hardcodear:

```yaml
owner: "{{ ansible_user }}"
group: "{{ ansible_user }}"
```

Detalle elegante: cuando la task de `blog.txt` corre en stapp01, `ansible_user` ya es `tony` — así que el `when` selecciona el host **y** el `ansible_user` da el owner correcto, ambos de la misma fuente.

### `when` vs multi-play vs host_vars+loop — tres formas, mismo resultado

| Enfoque                          | Cómo                                                | Día  | Mejor para                          |
| -------------------------------- | --------------------------------------------------- | ---- | ----------------------------------- |
| **Multi-play**                   | Un play `hosts: stappNN` por host                   | 90   | Pocos hosts, config muy distinta    |
| **`host_vars` + loop**           | `hosts: all` + datos en `host_vars` + un solo task | 90 (variante) | Muchos hosts, misma forma de task  |
| **`when` conditionals**          | `hosts: all` + N tasks filtradas por `when`         | 93   | Lógica condicional explícita        |

`when` brilla cuando la decisión **es** condicional ("haz X solo si el SO es CentOS", "instala Y solo si la versión < Z"). Para puro routing de "archivo→host", multi-play o host_vars suelen ser más limpios — pero el lab usa `when` para enseñar el mecanismo.

## Pasos

1. Login al jump host como `thor`; `cd ~/ansible`
2. Revisar el inventario (`cat inventory`) y que los `.txt` existan en `/usr/src/devops/`
3. Crear `playbook.yml` con `hosts: all`, `become: true` y 3 tasks `copy` filtradas por `when: ansible_nodename == ...`
4. Correr `ansible-playbook -i inventory playbook.yml`
5. Validar en cada host

## Comandos / Código

### Inventario (referencia)

```ini
stapp01 ansible_host=stapp01 ansible_ssh_pass=Ir0nM@n ansible_user=tony
stapp02 ansible_host=stapp02 ansible_ssh_pass=Am3ric@ ansible_user=steve
stapp03 ansible_host=stapp03 ansible_ssh_pass=BigGr33n ansible_user=banner
```

### Playbook (solución utilizada)

```yaml
# /home/thor/ansible/playbook.yml
- hosts: all
  become: true
  tasks:
    - name: copy blog.txt
      copy:
        src: /usr/src/devops/blog.txt
        dest: /opt/devops/blog.txt
        mode: '0777'
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"
      when: ansible_nodename == "stapp01"

    - name: copy story.txt
      copy:
        src: /usr/src/devops/story.txt
        dest: /opt/devops/story.txt
        mode: '0777'
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"
      when: ansible_nodename == "stapp02"

    - name: copy media.txt
      copy:
        src: /usr/src/devops/media.txt
        dest: /opt/devops/media.txt
        mode: '0777'
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"
      when: ansible_nodename == "stapp03"
```

### Ejecutar

```bash
ansible-playbook -i inventory playbook.yml
```

Output real del lab (cada host evalúa las 3 tasks, ejecuta 1 y salta 2):

```
TASK [Gathering Facts] *****************************************
ok: [stapp01]
ok: [stapp03]
ok: [stapp02]

TASK [copy blog.txt] *******************************************
skipping: [stapp02]
skipping: [stapp03]
changed: [stapp01]

TASK [copy story.txt] ******************************************
skipping: [stapp01]
skipping: [stapp03]
changed: [stapp02]

TASK [copy media.txt] ******************************************
skipping: [stapp01]
skipping: [stapp02]
changed: [stapp03]

PLAY RECAP *****************************************************
stapp01 : ok=2  changed=1  skipped=2  unreachable=0  failed=0
stapp02 : ok=2  changed=1  skipped=2  unreachable=0  failed=0
stapp03 : ok=2  changed=1  skipped=2  unreachable=0  failed=0
```

> `skipped=2` por host es la **firma visible** de los condicionales: cada host saltó las dos tasks que no le tocaban. `ok=2` = Gathering Facts + la task que sí corrió.

### Verificación

```bash
ansible all -i inventory -b -m shell -a "ls -l /opt/devops/"
```

Output real del lab:

```
stapp01 | CHANGED | rc=0 >>
-rwxrwxrwx 1 tony   tony   35 ... blog.txt
stapp02 | CHANGED | rc=0 >>
-rwxrwxrwx 1 steve  steve  27 ... story.txt
stapp03 | CHANGED | rc=0 >>
-rwxrwxrwx 1 banner banner 22 ... media.txt
```

Cada host tiene **solo** su archivo, con el owner correcto (de `ansible_user`) y `0777` (`-rwxrwxrwx`). Los tres requisitos cumplidos.

## Variantes (referencia)

### Combinar condiciones (AND / OR)

```yaml
# AND: lista de condiciones (todas deben cumplirse)
when:
  - ansible_nodename == "stapp01"
  - ansible_distribution == "CentOS"

# OR: con 'or' explícito
when: ansible_nodename == "stapp01" or ansible_nodename == "stapp02"
```

### Condicionales sobre el resultado de otra task (`register`)

```yaml
- name: chequear si existe el archivo
  ansible.builtin.stat:
    path: /opt/devops/blog.txt
  register: blog

- name: copiar solo si no existe
  copy: { src: ..., dest: ... }
  when: not blog.stat.exists
```

### Condicional por número de fact

```yaml
- name: solo en RHEL 8+
  when: ansible_distribution_major_version | int >= 8
```

### Condicional con `in` (pertenencia)

```yaml
when: ansible_nodename in ["stapp01", "stapp02"]
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Todas las tasks se saltan; no se copia nada                     | `gather_facts: no` → `ansible_nodename` indefinido                            | Dejar `gather_facts` en su default (`yes`)                                      |
| `'ansible_nodename' is undefined`                                | Facts deshabilitados o `when` sobre un host sin facts                          | No deshabilitar facts; o usar `ansible_nodename is defined` como guarda         |
| Warning `delimiters ... when statements should not include {{ }}`| Se escribió `when: "{{ ansible_nodename }}" == ...`                            | Quitar las `{{ }}`: `when: ansible_nodename == "stapp01"`                       |
| `src ... could not be found`                                     | El `.txt` no está en el control node, o ruta mal                               | Verificar que existe en `/usr/src/devops/` del jump host                        |
| Copia local en el remoto en vez de push                         | Se puso `remote_src: yes` por error                                            | Sin `remote_src` — el origen está en el control node                            |
| Owner queda `root`                                               | No se usó `ansible_user` o se hardcodeó                                        | `owner: "{{ ansible_user }}"`                                                   |
| `Destination /opt/devops not writable`                           | Falta `become` o el directorio no existe                                       | `become: true` en el play; crear el dir con `file` si hace falta                |
| Funciona con `--become` pero no sin args                        | La validación corre sin `--become`                                            | `become: true` dentro del play                                                  |

## Conexión con días anteriores

- **Día 90 (multi-play ACLs)**: mismo objetivo "cada archivo a un host distinto", resuelto con plays separados. Hoy es la **tercera forma** (un play + `when`) — útil comparar los tres enfoques.
- **Día 92 (`inventory_hostname`)**: hoy aparece `ansible_nodename`, otro "nombre del host" pero **fact** (no magic var). Completa la trilogía inventory_hostname / ansible_hostname / ansible_nodename.
- **Día 84 (`copy`)**: mismo módulo `copy` con `src` local empujando al remoto; hoy se le suma el filtro `when`.
- **Día 85 (`ansible_user` por host)**: el owner por host vía magic var, exactamente el mismo patrón.
- **Patrón "traducir requisito literal" (Días 65, 67, 90, 92)**: el lab pide `ansible_nodename` y `hosts: all` explícitamente — cumplir la instrucción exacta aunque haya alternativas equivalentes.

## Reflexión: condicionales vs separar por host

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- tres formas de hacer lo mismo (multi-play día 90 / host_vars+loop / when hoy): ¿cuál elegirías para esto en producción y por qué? ¿El when es la herramienta correcta para "routing archivo→host", o brilla más cuando la decisión es genuinamente condicional (SO, versión, estado)?
- ansible_nodename (fact) vs inventory_hostname (magic var): el lab te ata a un fact, lo que obliga gather_facts. ¿Es buena idea condicionar sobre facts cuando una magic var haría lo mismo sin la dependencia? ¿Cuándo el fact es la elección correcta?
- skipped=2 en cada host: ejecutar 3 tasks para que 2 se salten. ¿Es "desperdicio" o el costo natural y aceptable de la legibilidad? ¿Escala a 50 hosts?
- when sin {{ }}: una excepción a la regla general de Jinja2 en Ansible. ¿Ayuda u confunde que algunos campos esperen expresión cruda y otros interpolación?
- el patrón "el mismo when selecciona host Y el ansible_user da el owner": ambos datos salen del contexto del host. ¿Es elegante o frágil acoplar selección y configuración en la misma fuente?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [Conditionals — Ansible docs](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)
- [`copy` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [Discovering variables: facts (`ansible_nodename`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html)
- [Special (magic) variables](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
- [Tests y filtros en `when`](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tests.html)
