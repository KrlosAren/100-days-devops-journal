# Día 03 - Cambiar la configuración default de Ansible para definir un usuario remoto

## Problema / Desafío

Modificar la configuración por defecto de Ansible para que el usuario `james` sea utilizado como `remote_user` en todos los hosts, sin crear un nuevo archivo de configuración. La idea es localizar el archivo de configuración existente y editarlo directamente.

## Conceptos clave

- **ansible-config dump**: Comando que muestra toda la configuración activa de Ansible, incluyendo valores por defecto y los que fueron modificados. Los valores modificados aparecen en color diferente (verde = default, amarillo = modificado).
- **ansible.cfg**: Archivo de configuración principal de Ansible. Puede existir en varias ubicaciones con diferente prioridad:
  1. `ANSIBLE_CONFIG` (variable de entorno)
  2. `./ansible.cfg` (directorio actual)
  3. `~/.ansible.cfg` (home del usuario)
  4. `/etc/ansible/ansible.cfg` (configuración global del sistema)
- **remote_user**: Parámetro en la sección `[defaults]` de `ansible.cfg` que define el usuario SSH por defecto para conectarse a los hosts remotos. Si no se define, Ansible usa el usuario actual del sistema.
- **CONFIG_FILE**: Variable que aparece en la salida de `ansible-config dump` indicando la ruta del archivo de configuración que Ansible está usando actualmente.

## Pasos

1. Ejecutar `ansible-config dump` para listar toda la configuración activa
2. Buscar la línea `CONFIG_FILE` para identificar la ruta del archivo de configuración en uso
3. Editar el archivo de configuración con permisos elevados (`sudo`)
4. Agregar `remote_user = james` en la sección `[defaults]`
5. Verificar que el cambio se aplicó correctamente

## Comandos / Código

### Listar la configuración activa

```bash
ansible-config dump
```

La salida muestra todas las configuraciones. Buscamos la línea que indica qué archivo de configuración está en uso:

```
CONFIG_FILE() = /etc/ansible/ansible.cfg
```

### Buscar la ruta del archivo de configuración

Se puede filtrar directamente la línea relevante:

```bash
ansible-config dump | grep CONFIG_FILE
```

Salida esperada:

```
CONFIG_FILE() = /etc/ansible/ansible.cfg
```

### Editar la configuración

Con la ruta identificada, editamos el archivo con permisos elevados:

```bash
sudo vi /etc/ansible/ansible.cfg
```

Dentro del archivo, en la sección `[defaults]`, agregar la siguiente línea:

```ini
[defaults]
remote_user = james
```

Si la sección `[defaults]` ya existe con otros parámetros, simplemente agregar la línea `remote_user = james` dentro de ella.

### Verificar el cambio

```bash
ansible-config dump | grep REMOTE_USER
```

Salida esperada (el valor debe aparecer como modificado, no como default):

```
DEFAULT_REMOTE_USER(/etc/ansible/ansible.cfg) = james
```

La presencia de la ruta entre paréntesis confirma que el valor fue leído desde el archivo de configuración y no es el valor por defecto.

## Otros parámetros útiles de configuración

Además de `remote_user`, el archivo `ansible.cfg` permite configurar muchos otros comportamientos. Estos son los más prácticos organizados por sección:

### Sección `[defaults]`

| Parámetro | Ejemplo | Qué hace |
|-----------|---------|----------|
| `remote_user` | `james` | Usuario SSH por defecto |
| `host_key_checking` | `False` | Desactiva la verificación de fingerprint SSH (útil en labs) |
| `inventory` | `/etc/ansible/hosts` | Ruta al inventory por defecto, evita usar `-i` cada vez |
| `forks` | `10` | Cantidad de hosts que Ansible maneja en paralelo (default: 5) |
| `timeout` | `30` | Timeout de conexión SSH en segundos |
| `log_path` | `/var/log/ansible.log` | Habilita logging de todas las ejecuciones |
| `roles_path` | `/etc/ansible/roles` | Dónde buscar roles |
| `retry_files_enabled` | `False` | Desactiva la creación de archivos `.retry` |
| `gathering` | `smart` | Controla cuándo se recopilan facts (`implicit`, `explicit`, `smart`) |

### Sección `[privilege_escalation]`

| Parámetro | Ejemplo | Qué hace |
|-----------|---------|----------|
| `become` | `True` | Activa escalación de privilegios por defecto |
| `become_method` | `sudo` | Método de escalación (`sudo`, `su`, `pbrun`, etc.) |
| `become_user` | `root` | Usuario al que se escala |
| `become_ask_pass` | `False` | Si pide contraseña de sudo al ejecutar |

### Sección `[ssh_connection]`

| Parámetro | Ejemplo | Qué hace |
|-----------|---------|----------|
| `pipelining` | `True` | Reduce la cantidad de conexiones SSH (mejora rendimiento) |
| `ssh_args` | `-o ControlMaster=auto` | Argumentos extra para SSH |

### Comandos útiles para explorar la configuración

```bash
# Ver toda la configuración activa
ansible-config dump

# Ver solo los valores que fueron modificados (no default)
ansible-config dump --only-changed

# Ver la configuración en formato de archivo ansible.cfg
ansible-config init

# Ver la configuración de un plugin específico
ansible-config list
```

El comando `ansible-config init` es especialmente útil porque genera un `ansible.cfg` comentado con **todos** los parámetros disponibles, sirve como referencia completa.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `Permission denied` al editar `/etc/ansible/ansible.cfg` | Usar `sudo` para editar el archivo, ya que es propiedad de root |
| El cambio no se refleja en `ansible-config dump` | Verificar que la línea está dentro de la sección `[defaults]` y no tiene errores de sintaxis |
| Ansible usa otro archivo de configuración | Revisar si existe un `ansible.cfg` en el directorio actual o en `~/.ansible.cfg` que tenga mayor prioridad |
| `REMOTE_USER` sigue mostrando el valor default | Asegurarse de que no hay espacios extra ni caracteres invisibles en la línea agregada |

## Recursos

- [Documentación de ansible-config](https://docs.ansible.com/ansible/latest/cli/ansible-config.html)
- [Configuración de Ansible](https://docs.ansible.com/ansible/latest/reference_appendices/config.html)
- [Parámetro remote_user](https://docs.ansible.com/ansible/latest/reference_appendices/config.html#default-remote-user)
