# Día 02 - Instalar e iniciar httpd con Ansible

## Problema / Desafío

Crear un archivo de inventario en formato INI en playbook/inventory y ejecutar un playbook que instale el paquete `httpd` e inicie el servicio en el host remoto.

## Solución

### Inventory

```ini
[stapp01]
stapp01 ansible_user=tony ansible_password=xxxx ansible_host=172.16.238.10 ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

**Desglose del inventory:**

El inventory en formato INI organiza los hosts en grupos definidos entre corchetes. Cada línea dentro del grupo representa un host con sus variables de conexión:

- `[stapp01]`: Nombre del grupo. Permite referenciar este conjunto de hosts en el playbook mediante `hosts: stapp01` o incluirlo cuando se usa `hosts: all`.
- `stapp01`: Alias del host dentro del inventory. Ansible lo usa como identificador en la salida de ejecución.
- `ansible_user`: Usuario SSH para la conexión al servidor remoto.
- `ansible_password`: Contraseña del usuario SSH. En producción se recomienda usar `ansible-vault` o claves SSH en lugar de contraseñas en texto plano.
- `ansible_host`: Dirección IP o hostname real del servidor destino.

### Playbook

```yaml
---
- hosts: all
  become: yes
  become_user: root
  tasks:
    - name: Install httpd package
      yum:
        name: httpd
        state: installed

    - name: Start service httpd
      service:
        name: httpd
        state: started
```

**Desglose del playbook:**

- `hosts: all`: Ejecuta las tareas en todos los hosts del inventory.
- `become: yes`: Escala privilegios usando `sudo`.
- `become_user: root`: Define que las tareas se ejecutan como el usuario root.

Tareas:

1. **Install httpd package**: Usa el módulo `yum` (gestor de paquetes de RHEL/CentOS) para instalar Apache HTTP Server.
   - `name: httpd`: Nombre del paquete a instalar.
   - `state: installed`: Asegura que el paquete esté instalado. Si ya existe, no hace nada (idempotencia).

2. **Start service httpd**: Usa el módulo `service` para gestionar el servicio.
   - `name: httpd`: Nombre del servicio a gestionar.
   - `state: started`: Asegura que el servicio esté corriendo. Si ya está activo, no hace nada.

### Ejecución y verificación

```bash
# Ejecutar el playbook
ansible-playbook -i inventory playbook.yml

# Verificar que httpd está instalado
ansible stapp01 -i inventory -m shell -a "rpm -qa | grep httpd"

# Verificar que el servicio está corriendo
ansible stapp01 -i inventory -m shell -a "systemctl status httpd"
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `No package matching 'httpd' found` | El módulo `yum` solo funciona en distribuciones RHEL/CentOS. Para Ubuntu/Debian usar el módulo `apt` |
| `Permission denied` al conectar por SSH | Verificar que `ansible_user` y `ansible_password` son correctos en el inventory |
| `Missing sudo password` | Agregar `ansible_become_password` en el inventory o usar `--ask-become-pass` |
| `Failed to start httpd.service` | Verificar que no hay otro servicio usando el puerto 80 con `ss -tlnp \| grep :80` |

## Recursos

- [Documentación de Inventarios INI](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [Módulo yum](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/yum_module.html)
- [Módulo service](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)
