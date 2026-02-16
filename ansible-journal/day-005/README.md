# Día 05 - Crear archivos con permisos y propietario específico usando Ansible

## Problema / Desafío

Crear un archivo vacío `/tmp/code.txt` en todos los servidores de aplicación usando Ansible. El archivo debe tener permisos `0644` y el propietario (user/group) debe corresponder al usuario específico de cada servidor: `tony` en app1, `steve` en app2 y `banner` en app3.

## Conceptos clave

- **Módulo `file`**: Gestiona archivos y directorios en hosts remotos. Permite crear, eliminar, modificar permisos y cambiar propietarios. Con `state: touch` crea un archivo vacío si no existe, o actualiza su timestamp si ya existe (similar al comando `touch` en Linux).
- **`state: touch` e idempotencia**: A diferencia de otros states como `absent` o `directory`, `touch` siempre reporta `changed` porque actualiza el timestamp del archivo incluso si ya existe. Sin embargo, es seguro ejecutarlo múltiples veces: no elimina contenido existente ni causa errores si el archivo ya está presente. No es necesario verificar previamente si el archivo existe.
- **Variable `ansible_user`**: Es una variable de conexión que define con qué usuario Ansible se conecta al host remoto. Se define en el inventario por host. En este playbook la reutilizamos como valor para `owner` y `group`, lo que permite asignar el propietario correcto en cada servidor sin usar condicionales ni variables adicionales.
- **Módulo `stat`**: Obtiene información detallada de un archivo (permisos, propietario, tamaño, timestamps, etc.). Equivalente al comando `stat` de Linux. Los resultados se almacenan en una variable con `register` para uso posterior.
- **Filtro `regex_replace`**: Transforma cadenas usando expresiones regulares. En este caso se usa para eliminar los ceros iniciales del modo octal (ej: `0100644` → `644`) y hacer la salida más legible.

## Por qué usar `ansible_user` como owner/group

La variable `ansible_user` se define en el inventario para cada host como parte de la configuración de conexión:

```ini
stapp01 ansible_user=tony ...
stapp02 ansible_user=steve ...
stapp03 ansible_user=banner ...
```

Al usar `owner: "{{ ansible_user }}"` y `group: "{{ ansible_user }}"` en la tarea, Ansible resuelve la variable con el valor correspondiente a cada host durante la ejecución. Esto significa que:

- En `stapp01`, el archivo queda con owner/group `tony`
- En `stapp02`, con `steve`
- En `stapp03`, con `banner`

**Ventaja**: No se necesitan condicionales (`when`), bloques `host_vars`, ni variables adicionales. Se reutiliza una variable que ya existe en el inventario, manteniendo el playbook simple y sin duplicación.

**Alternativa sin `ansible_user`**: Si los usuarios de conexión fueran diferentes a los propietarios deseados, se podría usar `host_vars` o una variable personalizada en el inventario:

```ini
stapp01 ansible_user=admin file_owner=tony ...
```

## Pasos

1. Crear el archivo de inventario con los tres servidores y sus usuarios
2. Crear el playbook con la tarea de creación del archivo, permisos y validación
3. Ejecutar el playbook
4. Verificar la salida del `debug` para confirmar owner, group y permisos

## Comandos / Código

### Inventory

```ini
[all]
stapp01 ansible_user=tony ansible_password=xxxx ansible_host=stapp01.stratos.xfusioncorp.com
stapp02 ansible_user=steve ansible_password=xxxx ansible_host=stapp02.stratos.xfusioncorp.com
stapp03 ansible_user=banner ansible_password=xxxx ansible_host=stapp03.stratos.xfusioncorp.com
```

### Playbook

```yaml
---
- name: create empty file
  hosts: all
  become: yes

  vars:
    file_dst: "/tmp/code.txt"

  tasks:

    - name: create file
      file:
        path: "{{ file_dst }}"
        state: touch
        mode: "0644"
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"

    - name: valid file creation
      stat:
        path: "{{ file_dst }}"
      register: file_creation

    - name: output stat
      debug:
        msg: "Owner : {{ file_creation.stat.pw_name }}, Group : {{ file_creation.stat.gr_name }}, Mode : {{ file_creation.stat.mode | string | regex_replace('^0+', '') }}"
```

**Desglose del playbook:**

- `hosts: all`: Ejecuta en todos los hosts del inventario.
- `become: yes`: Escala privilegios para poder cambiar el owner/group del archivo.
- `vars`: Define la ruta del archivo como variable para evitar repetición.

Tareas:

1. **create file**: Usa el módulo `file` con `state: touch` para crear el archivo vacío. Aplica permisos `0644` y asigna owner/group usando `ansible_user`.
2. **valid file creation**: Usa `stat` para obtener los metadatos del archivo creado y los guarda en `file_creation`.
3. **output stat**: Muestra owner, group y permisos del archivo usando `debug`. El filtro `regex_replace` limpia los ceros iniciales del modo.

### Ejecución

```bash
ansible-playbook -i inventory playbook.yml
```

Salida esperada (resumida):

```
PLAY [create empty file] ******************************************************

TASK [create file] ************************************************************
changed: [stapp01]
changed: [stapp02]
changed: [stapp03]

TASK [valid file creation] ****************************************************
ok: [stapp01]
ok: [stapp02]
ok: [stapp03]

TASK [output stat] ************************************************************
ok: [stapp01] => {
    "msg": "Owner : tony, Group : tony, Mode : 644"
}
ok: [stapp02] => {
    "msg": "Owner : steve, Group : steve, Mode : 644"
}
ok: [stapp03] => {
    "msg": "Owner : banner, Group : banner, Mode : 644"
}

PLAY RECAP ********************************************************************
stapp01 : ok=3  changed=1  unreachable=0  failed=0  skipped=0
stapp02 : ok=3  changed=1  unreachable=0  failed=0  skipped=0
stapp03 : ok=3  changed=1  unreachable=0  failed=0  skipped=0
```

## Tips y notas adicionales

### No es necesario verificar si el archivo existe antes de usar `touch`

El módulo `file` con `state: touch` ya maneja ambos escenarios:
- Si el archivo **no existe**, lo crea.
- Si el archivo **ya existe**, actualiza su timestamp sin modificar el contenido.

Agregar una tarea previa con `stat` + `when: not file.stat.exists` es innecesario y agrega complejidad sin beneficio. El módulo `file` ya es seguro para ejecutar múltiples veces.

### `mode` como string vs número

Siempre definir los permisos como string entre comillas (`"0644"`), no como número (`0644`). En YAML, un número que empieza con `0` se interpreta como octal, lo que puede causar resultados inesperados dependiendo del parser. Usar string garantiza que Ansible reciba el valor correcto.

### `become: yes` es necesario para cambiar owner/group

Aunque el archivo se crea en `/tmp` (donde cualquier usuario puede escribir), cambiar el `owner` y `group` a un usuario diferente al que ejecuta la tarea requiere privilegios de root. Sin `become: yes`, la tarea fallaría con `Permission denied` al intentar hacer `chown`.

### Cuidado al reutilizar variables `ansible_*` como datos del playbook

Las variables que empiezan con `ansible_` son **variables especiales de conexión**. Ansible las usa internamente para establecer la conexión SSH. `ansible_user` define con qué usuario conectarse, `ansible_password` la contraseña, `ansible_host` la dirección del servidor, etc.

En este playbook reutilizamos `ansible_user` para un segundo propósito: asignar el propietario del archivo. Funciona porque **el usuario de conexión y el propietario deseado son el mismo**. Pero si en algún momento se cambia el usuario de conexión (por ejemplo, usar un usuario genérico `deploy` para todos los servidores), el owner del archivo también cambiaría, rompiendo el comportamiento esperado:

```ini
# Si cambias la conexión a un usuario genérico...
stapp01 ansible_user=deploy ansible_host=stapp01.stratos.xfusioncorp.com
```

```yaml
# ...el archivo quedaría con owner "deploy" en vez de "tony"
owner: "{{ ansible_user }}"  # resuelve a "deploy", no a "tony"
```

Por esta razón, cuando el propietario del archivo no depende directamente del usuario de conexión, es mejor usar una variable propia. A continuación se documentan las alternativas.

### Alternativas para asignar valores únicos por servidor

#### 1. Variables personalizadas en el inventory (lo más simple)

Se agregan variables propias directamente en la línea de cada host:

```ini
[all]
stapp01 ansible_user=tony ansible_password=xxxx ansible_host=stapp01.stratos.xfusioncorp.com file_owner=tony
stapp02 ansible_user=steve ansible_password=xxxx ansible_host=stapp02.stratos.xfusioncorp.com file_owner=steve
stapp03 ansible_user=banner ansible_password=xxxx ansible_host=stapp03.stratos.xfusioncorp.com file_owner=banner
```

```yaml
owner: "{{ file_owner }}"
group: "{{ file_owner }}"
```

Se pueden agregar cuantas variables se necesiten por host. La desventaja es que la línea se hace larga cuando hay muchas.

#### 2. Diccionario en el playbook

Se define un diccionario en `vars` mapeando cada host a su valor:

```yaml
vars:
  file_dst: "/tmp/code.txt"
  owners:
    stapp01: tony
    stapp02: steve
    stapp03: banner
```

```yaml
owner: "{{ owners[inventory_hostname] }}"
group: "{{ owners[inventory_hostname] }}"
```

`inventory_hostname` es una variable especial de Ansible que contiene el nombre del host actual según el inventario. Se usa como clave para buscar el valor en el diccionario. Útil cuando se quiere mantener toda la lógica en el playbook sin modificar el inventario.

#### 3. Directorio `host_vars/` (lo más organizado)

Se crea un archivo YAML por host en un directorio `host_vars/`:

```
project/
├── inventory
├── playbook.yml
└── host_vars/
    ├── stapp01.yml
    ├── stapp02.yml
    └── stapp03.yml
```

```yaml
# host_vars/stapp01.yml
file_owner: tony
```

```yaml
# host_vars/stapp02.yml
file_owner: steve
```

```yaml
# host_vars/stapp03.yml
file_owner: banner
```

Ansible carga estas variables automáticamente por host sin declararlas en el inventario ni en el playbook. Solo se usa `{{ file_owner }}` en la tarea. Es la mejor práctica cuando el proyecto crece y cada host tiene muchas variables propias.

#### Comparación de enfoques

| Enfoque | Dónde se define | Ventaja | Desventaja |
|---------|----------------|---------|------------|
| Variable en inventory | Línea del host en el inventario | Simple, todo en un archivo | Líneas largas con muchas variables |
| Diccionario en playbook | Sección `vars` del playbook | Lógica centralizada en el playbook | Se debe mantener sincronizado con el inventario |
| `host_vars/` | Archivos separados por host | Organizado, escalable, carga automática | Más archivos que gestionar |
| Reutilizar `ansible_*` | Inventario (ya existe) | Sin variables extra | Acoplamiento entre conexión y lógica de negocio |

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `chown failed: failed to look up user` | El usuario definido en `ansible_user` no existe en el servidor remoto. Verificar que el usuario existe con `id <usuario>` |
| `Permission denied` al crear el archivo | Verificar que `become: yes` está definido en el playbook |
| `touch` siempre reporta `changed` | Es el comportamiento esperado de `state: touch`. No indica un problema, simplemente actualiza el timestamp del archivo |
| `regex_replace` no muestra el modo correcto | Verificar que se usa `file_creation.stat.mode` (string) y no `file_creation.stat.mode` como entero. El filtro `string` antes de `regex_replace` asegura la conversión |
| `Authentication failure` | Verificar usuario y contraseña en el inventario para ese host específico |

## Recursos

- [Módulo file](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [Módulo stat](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/stat_module.html)
- [Variables de conexión](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html#connection-variables)
- [Filtros Jinja2 en Ansible](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_filters.html)
