# Día 01 - Crear un archivo vacío con Ansible

## Problema / Desafío

Completar el archivo de inventario con los datos de conexión del host y crear un playbook que genere un archivo vacío en el servidor remoto.

## Solución

### Inventory

```ini
[stapp02]
stapp02 ansible_host=172.16.238.11 ansible_user=steve ansible_password='xxxxx' ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

**Desglose del inventory:**

El inventory define los hosts sobre los que Ansible va a ejecutar tareas. Cada línea dentro de un grupo (definido entre corchetes `[stapp02]`) representa un host con sus variables de conexión:

- `ansible_host`: La dirección IP o hostname real del servidor al que conectarse.
- `ansible_user`: El usuario SSH con el que Ansible se autentica.
- `ansible_password`: La contraseña del usuario para la conexión SSH.
- `ansible_ssh_common_args`: Argumentos adicionales para SSH. En este caso `-o StrictHostKeyChecking=no` evita la verificación interactiva de la huella del host, útil en entornos automatizados.

### Playbook

```yaml
---
- name: create empty file
  hosts: all
  become: yes
  tasks:
    - name: create file
      file:
        path: /tmp/empty.txt
        state: touch
```

**Desglose del playbook:**

Un playbook es un archivo YAML que define una lista de plays. Cada play conecta un grupo de hosts con una lista de tareas:

- `name`: Descripción legible del play, aparece en la salida de la ejecución para identificar qué está haciendo Ansible.
- `hosts`: Define sobre qué hosts del inventory se ejecuta. `all` significa todos los hosts definidos en el inventory.
- `become`: Cuando está en `yes`, Ansible escala privilegios (por defecto usa `sudo`) para ejecutar las tareas como root.
- `tasks`: Lista de tareas a ejecutar en orden secuencial.

Dentro de la tarea:

- `file`: Módulo de Ansible para gestionar archivos y directorios en el host remoto.
- `path`: Ruta completa del archivo a crear.
- `state: touch`: Crea el archivo vacío si no existe, o actualiza su timestamp si ya existe (equivalente al comando `touch` de Linux).

### Ejecución y verificación

```bash
# Ejecutar el playbook
ansible-playbook -i inventory playbook.yml

# Verificar que el archivo fue creado
ansible stapp02 -i inventory -m shell -a "ls -l /tmp/empty.txt"
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `Permission denied` al conectar por SSH | Verificar que `ansible_user` y `ansible_password` son correctos |
| `Unreachable` en el host | Confirmar que la IP en `ansible_host` es accesible y que el servicio SSH está activo |
| `Missing sudo password` | Agregar `ansible_become_password` en el inventory o usar `--ask-become-pass` al ejecutar |

## Recursos

- [Documentación de Inventarios](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [Módulo file](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [Introducción a Playbooks](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html)
