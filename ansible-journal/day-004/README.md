# Día 04 - Copiar archivos a servidores de aplicación con Ansible

## Problema / Desafío

Copiar el archivo `/usr/src/data/index.html` a la ruta `/opt/data` en todos los servidores de aplicación usando Ansible. Se debe crear un inventario con los tres servidores y un playbook que realice la copia y valide el resultado.

## Conceptos clave

- **Módulo `copy`**: Copia archivos desde el nodo de control hacia los hosts remotos, o copia archivos localmente dentro de los hosts remotos. Cuando `src` es una ruta absoluta en el host remoto y se usa con `remote_src: yes`, copia archivos dentro del mismo servidor remoto. Sin `remote_src`, Ansible busca el archivo en el nodo de control.
- **Módulo `slurp`**: Lee el contenido de un archivo remoto y lo devuelve codificado en base64. Es útil para validar que un archivo fue copiado correctamente sin necesidad de conectarse manualmente al servidor.
- **Filtro `b64decode`**: Decodifica contenido en base64 a texto legible. Se usa en combinación con `slurp` para mostrar el contenido real del archivo.
- **Inventory (Inventario)**: Archivo que define los hosts y grupos sobre los que Ansible ejecuta tareas. Puede escribirse en diferentes formatos: INI, YAML y JSON.
- **Variables de conexión**: Parámetros como `ansible_user`, `ansible_password` y `ansible_host` que definen cómo Ansible se conecta a cada host.

## Pasos

1. Crear el archivo de inventario con los tres servidores de aplicación
2. Crear el playbook con las tareas de copia y validación
3. Ejecutar el playbook apuntando al inventario
4. Verificar que el archivo fue copiado correctamente en todos los servidores

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
- name: Copy file to apps servers
  hosts: all
  become: yes

  vars:
    file_src: "/usr/src/data/index.html"
    file_dst: "/opt/data"

  tasks:

    - name: copy file
      copy:
        src: "{{ file_src }}"
        dest: "{{ file_dst }}"

    - name: validate file
      slurp:
        src: "/opt/data/index.html"
      register: file_content

    - name: content file
      debug:
        msg: "{{ file_content.content | b64decode }}"
```

**Desglose del playbook:**

- `hosts: all`: Ejecuta en todos los hosts del inventario (los tres servidores de aplicación).
- `become: yes`: Escala privilegios con `sudo` para poder escribir en `/opt/data`.
- `vars`: Define variables reutilizables para las rutas origen y destino.

Tareas:

1. **copy file**: Usa el módulo `copy` para copiar el archivo desde `file_src` hacia `file_dst` en cada servidor remoto.
2. **validate file**: Usa `slurp` para leer el contenido del archivo copiado y guardarlo en la variable `file_content`.
3. **content file**: Decodifica el contenido base64 y lo muestra en la salida de Ansible con `debug`.

### Ejecución

```bash
ansible-playbook -i inventory playbook.yml
```

Salida esperada (resumida):

```
PLAY [Copy file to apps servers] **********************************************

TASK [copy file] **************************************************************
changed: [stapp01]
changed: [stapp02]
changed: [stapp03]

TASK [validate file] **********************************************************
ok: [stapp01]
ok: [stapp02]
ok: [stapp03]

TASK [content file] ***********************************************************
ok: [stapp01] => {
    "msg": "<contenido del archivo index.html>"
}
ok: [stapp02] => {
    "msg": "<contenido del archivo index.html>"
}
ok: [stapp03] => {
    "msg": "<contenido del archivo index.html>"
}

PLAY RECAP ********************************************************************
stapp01 : ok=3  changed=1  unreachable=0  failed=0  skipped=0
stapp02 : ok=3  changed=1  unreachable=0  failed=0  skipped=0
stapp03 : ok=3  changed=1  unreachable=0  failed=0  skipped=0
```

## Formatos de inventario en Ansible

Ansible soporta múltiples formatos para definir inventarios. Cada uno tiene sus ventajas según el caso de uso.

### 1. Formato INI (el más común)

Es el formato por defecto y el más simple. Usa corchetes para grupos y una línea por host.

```ini
[webservers]
web1 ansible_host=192.168.1.10 ansible_user=admin
web2 ansible_host=192.168.1.11 ansible_user=admin

[dbservers]
db1 ansible_host=192.168.1.20 ansible_user=dba

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[production:children]
webservers
dbservers
```

**Características:**
- Grupos definidos con `[nombre_grupo]`
- Variables de grupo con `[nombre_grupo:vars]`
- Grupos de grupos con `[nombre_grupo:children]`
- Una línea por host con variables inline

### 2. Formato YAML

Más legible para inventarios complejos. Usa la extensión `.yml` o `.yaml`.

```yaml
all:
  children:
    webservers:
      hosts:
        web1:
          ansible_host: 192.168.1.10
          ansible_user: admin
        web2:
          ansible_host: 192.168.1.11
          ansible_user: admin
    dbservers:
      hosts:
        db1:
          ansible_host: 192.168.1.20
          ansible_user: dba
  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
```

**Características:**
- Estructura jerárquica clara
- Ideal cuando hay muchas variables por host
- Más fácil de versionar y revisar en diffs de Git

### 3. Formato JSON

Menos usado manualmente, pero útil cuando el inventario se genera de forma programática.

```json
{
  "all": {
    "children": {
      "webservers": {
        "hosts": {
          "web1": {
            "ansible_host": "192.168.1.10",
            "ansible_user": "admin"
          },
          "web2": {
            "ansible_host": "192.168.1.11",
            "ansible_user": "admin"
          }
        }
      },
      "dbservers": {
        "hosts": {
          "db1": {
            "ansible_host": "192.168.1.20",
            "ansible_user": "dba"
          }
        }
      }
    },
    "vars": {
      "ansible_ssh_common_args": "-o StrictHostKeyChecking=no"
    }
  }
}
```

**Características:**
- Ideal para inventarios generados por scripts o APIs
- Fácil de integrar con herramientas que exportan JSON
- Verboso para editar manualmente

### 4. Inventario dinámico (scripts)

En lugar de un archivo estático, Ansible puede ejecutar un script que genere el inventario en tiempo real. Útil para entornos cloud donde los servidores cambian constantemente.

```bash
#!/bin/bash
# dynamic_inventory.sh
# Debe retornar JSON válido con la estructura de inventario

cat <<EOF
{
  "webservers": {
    "hosts": ["web1.example.com", "web2.example.com"]
  },
  "_meta": {
    "hostvars": {
      "web1.example.com": {
        "ansible_user": "admin"
      },
      "web2.example.com": {
        "ansible_user": "admin"
      }
    }
  }
}
EOF
```

```bash
# El script debe tener permisos de ejecución
chmod +x dynamic_inventory.sh

# Usar con -i apuntando al script
ansible-playbook -i dynamic_inventory.sh playbook.yml
```

**Características:**
- El script debe ser ejecutable y retornar JSON válido
- Debe soportar los flags `--list` (listar todo) y `--host <hostname>` (variables de un host)
- Existen plugins oficiales para AWS, GCP, Azure, Docker, etc.
- Ansible detecta automáticamente si el inventario es un archivo estático o un script ejecutable

### 5. Directorio de inventario

Se puede usar un directorio que contenga múltiples archivos de inventario. Ansible los combina todos automáticamente.

```
inventory/
├── 01-static-hosts     # Archivo INI con hosts fijos
├── 02-dynamic-aws.py   # Script dinámico para AWS
└── group_vars/
    ├── all.yml          # Variables para todos los hosts
    └── webservers.yml   # Variables para el grupo webservers
```

```bash
ansible-playbook -i inventory/ playbook.yml
```

### Comparación de formatos

| Formato | Facilidad de edición | Legibilidad con muchas variables | Generación automática | Caso de uso ideal |
|---------|---------------------|----------------------------------|----------------------|-------------------|
| INI | Alta | Baja (todo en una línea) | Media | Inventarios pequeños y simples |
| YAML | Alta | Alta (estructura jerárquica) | Media | Inventarios medianos con muchas variables |
| JSON | Baja | Media | Alta | Inventarios generados por scripts/APIs |
| Dinámico | N/A | N/A | Nativa | Entornos cloud con infraestructura cambiante |
| Directorio | Alta | Alta | Alta | Entornos mixtos (estático + dinámico) |

### El inventario de este ejercicio en formato YAML

Para comparar, así se vería el inventario de este día en formato YAML:

```yaml
all:
  hosts:
    stapp01:
      ansible_user: tony
      ansible_password: xxxx
      ansible_host: stapp01.stratos.xfusioncorp.com
    stapp02:
      ansible_user: steve
      ansible_password: xxxx
      ansible_host: stapp02.stratos.xfusioncorp.com
    stapp03:
      ansible_user: banner
      ansible_password: xxxx
      ansible_host: stapp03.stratos.xfusioncorp.com
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `Permission denied` al copiar a `/opt/data` | Verificar que `become: yes` está definido en el playbook |
| `Source /usr/src/data/index.html not found` | Confirmar que el archivo existe en el nodo de control. Si está en el host remoto, usar `remote_src: yes` en el módulo `copy` |
| `The destination directory /opt/data does not exist` | Agregar una tarea previa con el módulo `file` para crear el directorio: `file: path=/opt/data state=directory` |
| `Authentication failure` en algún servidor | Verificar usuario y contraseña en el inventario para ese host |
| `slurp` falla con `file not found` | La tarea de copia falló silenciosamente. Revisar la salida de la tarea `copy` para ese host |

## Recursos

- [Módulo copy](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [Módulo slurp](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/slurp_module.html)
- [Guía de inventarios](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [Inventario dinámico](https://docs.ansible.com/ansible/latest/inventory_guide/intro_dynamic_inventory.html)
- [Formatos de inventario](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#inventory-basics-formats-hosts-and-groups)
