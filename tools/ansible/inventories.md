# Ansible · Inventories (formatos + variables de conexión + dynamic)

El inventario es **el catálogo de hosts** donde Ansible va a ejecutar playbooks. Para cada host define:

- Cómo se llama (alias usado en playbooks)
- Cómo conectarse (IP, user, autenticación, puerto, método)
- A qué grupos pertenece (para targeting selectivo)

Es el equivalente Ansible del `kubeconfig` de K8s (lista de clusters + auth) o del `~/.ssh/config` de SSH (lista de hosts + cómo conectarse a cada uno).

## Tabla de decisión: qué formato usar

| Escenario                                              | Tipo recomendado                       |
| ------------------------------------------------------ | -------------------------------------- |
| Lab, demo, ≤ 10 hosts fijos                            | **INI**                                |
| Producción on-prem, ≤ 50 hosts, estructura compleja    | **YAML**                               |
| Producción cloud (AWS/GCP/Azure)                       | **Dynamic inventory plugin**           |
| Inventario generado por otra herramienta (Terraform, CMDB) | **Inventory script** o JSON output |
| Multi-source (parte estático + parte dinámico)         | Directorio con múltiples archivos       |

## Formatos soportados

Ansible soporta **cinco formatos** de inventario, agrupados en dos categorías:

### Categoría 1 — Inventarios estáticos (archivos)

| Formato    | Extensión típica                | Cuándo conviene                                                                  |
| ---------- | ------------------------------- | -------------------------------------------------------------------------------- |
| **INI**    | `inventory`, `hosts`, `*.ini`   | Inventarios chicos (≤ 20 hosts), estructura simple, lectura rápida              |
| **YAML**   | `inventory.yml`, `*.yaml`       | Inventarios grandes, jerarquías de grupos, variables complejas (listas, dicts)   |
| **JSON**   | `*.json`                        | Output de scripts/herramientas que generan inventario; menos común a mano        |
| **TOML**   | `*.toml` (Ansible 2.8+)         | Alternativa estructurada — uso marginal en producción                           |

### Categoría 2 — Inventarios dinámicos (scripts/plugins)

| Tipo                          | Cuándo usar                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| **Dynamic inventory plugin**  | Inventario generado en runtime desde una fuente externa (AWS, GCP, Azure, K8s)       |
| **Inventory script**          | Script ejecutable (Python, Bash, etc.) que devuelve JSON con la estructura esperada  |

## Comparación lado a lado — el mismo host en cada formato

### INI

```ini
[stapp03]
stapp03 ansible_host=stapp03 ansible_user=banner ansible_password=BigGr33n ansible_connection=ssh
```

### YAML equivalente

```yaml
# inventory.yml
all:
  children:
    stapp03:
      hosts:
        stapp03:
          ansible_host: stapp03
          ansible_user: banner
          ansible_password: BigGr33n
          ansible_connection: ssh
```

Estructura YAML jerárquica: `all` → `children` → grupo → `hosts` → host → variables.

### JSON equivalente

```json
{
  "stapp03": {
    "hosts": ["stapp03"],
    "vars": {}
  },
  "_meta": {
    "hostvars": {
      "stapp03": {
        "ansible_host": "stapp03",
        "ansible_user": "banner",
        "ansible_password": "BigGr33n",
        "ansible_connection": "ssh"
      }
    }
  }
}
```

JSON sigue el formato canónico que Ansible espera de un script dinámico. La sección `_meta.hostvars` es la convención para variables por host. Raramente se escribe a mano — sale de tooling automatizado.

### TOML equivalente

```toml
[stapp03]
[stapp03.hosts.stapp03]
ansible_host = "stapp03"
ansible_user = "banner"
ansible_password = "BigGr33n"
ansible_connection = "ssh"
```

TOML es una opción válida pero poco usada en el ecosistema Ansible. La doc oficial lo menciona pero la mayoría de tooling asume INI o YAML.

## Variables de conexión — referencia completa

Las variables que aparecen con prefijo `ansible_` controlan **cómo Ansible se conecta y ejecuta** en el host remoto.

| Variable                              | Función                                                            |
| ------------------------------------- | ------------------------------------------------------------------ |
| `ansible_host`                        | IP o hostname real (puede diferir del alias del inventario)        |
| `ansible_user`                        | Usuario remoto para SSH                                            |
| `ansible_password`                    | Password SSH (alias moderno de `ansible_ssh_pass`)                 |
| `ansible_ssh_pass`                    | Password SSH (alias legacy — todavía funciona, da deprecation warning) |
| `ansible_ssh_private_key_file`        | Path a la clave privada SSH                                        |
| `ansible_port`                        | Puerto SSH (default 22)                                            |
| `ansible_connection`                  | Método: `ssh` (default), `local`, `docker`, `winrm`, `kubectl`     |
| `ansible_python_interpreter`          | Path al python del host remoto (útil si no es `/usr/bin/python3`)  |
| `ansible_become`                      | `true` para usar sudo (privilege escalation)                       |
| `ansible_become_user`                 | Usuario al que escalar privilegios (default `root`)                |
| `ansible_become_password`             | Password para sudo (si no NOPASSWD)                                |
| `ansible_become_method`               | `sudo` (default), `su`, `doas`, `pbrun`, etc.                      |
| `ansible_ssh_common_args`             | Args extra para SSH (ej. `-o StrictHostKeyChecking=no`)            |
| `ansible_shell_type`                  | Tipo de shell en el remoto: `sh` (default), `csh`, `fish`          |
| `ansible_winrm_*`                     | Variables específicas para Windows via WinRM                       |

> El alias del inventario (`stapp03` en `[stapp03]`) puede ser **cualquier nombre**. `ansible_host` es la IP/hostname real al que Ansible se conecta. Esto permite tener alias amigables (ej. `web-prod-01`) que apuntan a IPs cambiantes.

## Anatomía del archivo INI

```ini
# Comentarios con # o ;

# Host suelto sin grupo (va al grupo implícito "ungrouped")
hostA ansible_host=10.0.0.1

# Grupo de hosts
[webservers]
web1 ansible_host=10.0.0.10
web2 ansible_host=10.0.0.11
web3 ansible_host=10.0.0.12

# Otro grupo
[dbservers]
db1 ansible_host=10.0.1.10
db2 ansible_host=10.0.1.11

# Variables aplicables a TODOS los hosts del grupo
[webservers:vars]
ansible_user=deploy
ansible_port=22
http_port=8080

# Grupo de grupos (composición)
[stratos:children]
webservers
dbservers

# Variables aplicables al grupo compuesto
[stratos:vars]
datacenter=stratos
environment=production
```

Tres secciones especiales:

| Sección                | Función                                                                         |
| ---------------------- | ------------------------------------------------------------------------------- |
| `[group_name]`         | Hosts que pertenecen al grupo                                                   |
| `[group_name:vars]`    | Variables que aplican a todos los hosts del grupo                                |
| `[group_name:children]` | Grupos que pertenecen a este grupo padre (composición jerárquica)                |

## Grupos automáticos

Ansible crea dos grupos automáticamente:

| Grupo         | Hosts incluidos                                            |
| ------------- | ---------------------------------------------------------- |
| `all`         | **Todos** los hosts del inventario                          |
| `ungrouped`   | Hosts que **no están** en ningún grupo definido por usuario |

Esto permite targeting genérico:

```bash
ansible all -m ping -i inventory
ansible ungrouped -m setup -i inventory
```

## Inventarios dinámicos — el caso "real" en cloud

En producción cloud, los inventarios estáticos no escalan: las instancias EC2/GCE aparecen y desaparecen constantemente. **Dynamic inventory plugins** consultan el cloud provider en runtime.

### Ejemplo: AWS EC2 dynamic inventory

`inventory_aws_ec2.yml`:

```yaml
plugin: amazon.aws.aws_ec2
regions:
  - us-east-1
filters:
  tag:Environment: production
  instance-state-name: running
keyed_groups:
  - key: tags.Role
    prefix: role
  - key: placement.availability_zone
    prefix: az
hostnames:
  - tag:Name
  - dns-name
```

Al correr `ansible-inventory -i inventory_aws_ec2.yml --list`, Ansible llama a la API de AWS, lista las instancias filtradas, y devuelve un inventario JSON dinámico **generado en runtime**.

### Plugins comunes

| Plugin                                | Para qué                                              |
| ------------------------------------- | ----------------------------------------------------- |
| `amazon.aws.aws_ec2`                  | Instancias EC2 de AWS                                  |
| `google.cloud.gcp_compute`            | VMs de GCP                                            |
| `azure.azcollection.azure_rm`         | VMs de Azure                                          |
| `kubernetes.core.k8s`                 | Pods de un cluster K8s                                |
| `community.docker.docker_machines`    | Containers de Docker                                  |
| `theforeman.foreman.foreman`          | Servers gestionados por Foreman/Satellite             |
| `community.vmware.vmware_vm_inventory` | VMs de vSphere/vCenter                                |

### Inventory script (formato custom)

Un script ejecutable que respeta el contrato:

- Acepta `--list` → devuelve JSON con toda la estructura
- Acepta `--host <hostname>` → devuelve JSON con las variables de ese host

Ejemplo en Bash:

```bash
#!/bin/bash
# /usr/local/bin/my_inventory.sh
case "$1" in
  --list)
    cat <<EOF
{
  "stapp03": { "hosts": ["stapp03"] },
  "_meta": { "hostvars": { "stapp03": { "ansible_host": "stapp03", "ansible_user": "banner" } } }
}
EOF
    ;;
  --host)
    echo '{}'
    ;;
esac
```

```bash
chmod +x /usr/local/bin/my_inventory.sh
ansible-playbook -i /usr/local/bin/my_inventory.sh playbook.yml
```

Ansible detecta que el archivo es **ejecutable** y lo trata como inventory script en lugar de archivo estático.

## Múltiples inventarios — directorio en lugar de archivo

Una propiedad útil: `-i` puede apuntar a un **directorio** que contiene varios archivos de inventario. Ansible los lee todos y los une:

```
inventories/
├── ini/
│   └── hosts                # INI con hosts on-prem
├── yaml/
│   └── databases.yml        # YAML con grupo dbservers
└── dynamic/
    └── aws_ec2.yml          # Dynamic plugin para EC2
```

```bash
ansible-playbook -i inventories/ playbook.yml
```

Esto une los tres inventarios — útil para entornos híbridos (on-prem + cloud).

## Variables de inventory — orden de precedencia

Cuando un host obtiene variables de varias fuentes, Ansible resuelve los conflictos por **precedencia** (menor a mayor prioridad):

```
1. role defaults                        ← más bajo
2. inventory file / inventory script
3. inventory group_vars/all
4. inventory group_vars/<group_name>
5. inventory host_vars/<host>
6. playbook group_vars / host_vars
7. host facts (gathered)
8. play vars
9. task vars
10. extra vars (-e en la CLI)           ← más alto, gana sobre todo
```

Para inventarios simples, todas las variables viven en el inventory file (nivel 2). Para inventarios complejos, separar en `group_vars/` y `host_vars/`.

### Estructura típica con vars separadas

```
inventories/production/
├── hosts                       # INI con grupos
├── group_vars/
│   ├── all.yml                  # Variables para todos
│   ├── webservers.yml           # Variables del grupo webservers
│   └── dbservers/
│       ├── vars.yml             # Variables planas
│       └── vault.yml            # Variables encriptadas con ansible-vault
└── host_vars/
    ├── web1.yml                 # Específicas de web1
    └── web2.yml                 # Específicas de web2
```

## Validación de un inventario

Tres comandos canónicos para validar:

```bash
# 1. Listar estructura JSON completa
ansible-inventory -i inventory --list

# 2. Visualización en árbol (grupos y hosts)
ansible-inventory -i inventory --graph

# 3. Ping a todos los hosts (smoke test canónico)
ansible all -i inventory -m ping
```

El `ansible -m ping` no solo testea ICMP — testea que **Ansible puede ejecutar Python en el host remoto**, que es el requisito mínimo para que cualquier playbook funcione.

Output esperado del ping:

```
stapp03 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

## Variables sensibles — el problema del password en plain text

Tener `ansible_password=BigGr33n` en el archivo es **anti-pattern de producción**. Tres alternativas, ordenadas de mejor a peor:

### Opción 1 — SSH keys (lo más usado)

```ini
[stapp03]
stapp03 ansible_host=stapp03 ansible_user=banner \
        ansible_ssh_private_key_file=~/.ssh/banner_key
```

Sin password en el archivo. La key privada vive en disco con `chmod 600`. Sin password de SSH, la única forma de impersonar es robar la clave (que vive solo en el control node).

### Opción 2 — ansible-vault para encriptar el password

```bash
# Crear archivo de vault con el password
ansible-vault encrypt_string 'BigGr33n' --name 'ansible_password'
# Output:
# ansible_password: !vault |
#   $ANSIBLE_VAULT;1.1;AES256
#   <encrypted bytes>
```

Pegar en `group_vars/stapp03/vault.yml` y correr el playbook con `--ask-vault-pass` (o `--vault-password-file <path>` para CI).

El password está cifrado at-rest, descifrable con la **master password del vault**. Se puede versionar el archivo en git sin exponer el secret.

### Opción 3 — Lookup desde secret manager externo

```yaml
ansible_password: "{{ lookup('community.hashi_vault.vault_kv2_get', 'secret/data/stapp03')['data']['password'] }}"
```

El secret nunca toca disco — se lee en runtime desde HashiCorp Vault, AWS Secrets Manager, etc. Para producción crítica es lo correcto.

## INI vs `/etc/hosts` del SO — la diferencia conceptual

| Aspecto                       | `/etc/hosts` del SO                                     | Inventario Ansible                                          |
| ----------------------------- | ------------------------------------------------------- | ----------------------------------------------------------- |
| Para qué sirve                | Resolución DNS local (hostname → IP)                    | Catálogo de hosts + metadata de conexión + grupos           |
| Contenido por host            | Solo IP + alias                                          | IP, user, password/key, port, vars custom                   |
| Estructura                    | Plano                                                    | Jerarquía de grupos con composición                          |
| Quién lo usa                  | Cualquier proceso del SO via libnss                      | Solo Ansible (otros tools tienen sus propios formatos)     |

El paralelo conceptual existe — ambos son "lo primero que se consulta para resolver un host". Ansible inventory es la versión enriquecida con metadata operacional.

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `ansible-playbook -i inventory ...` no encuentra el inventario           | Path relativo y el comando se corre desde otro directorio                                            | Usar path absoluto en `-i` o `cd` al directorio del inventory primero                              |
| `ansible all -m ping` devuelve `unreachable`                             | (a) IP/hostname incorrecta; (b) puerto SSH bloqueado; (c) credenciales mal                            | Probar SSH manual: `ssh -p <port> <user>@<host>`                                                  |
| `Failed to connect ... Permission denied (publickey,password)`           | Password incorrecto o `PasswordAuthentication no` en el destino                                       | Verificar `/etc/ssh/sshd_config` del destino                                                      |
| `sshpass: not found`                                                     | Falta `sshpass` en el control node — requerido para `ansible_password`                               | `sudo yum install -y sshpass` o `sudo apt install -y sshpass`                                     |
| `[WARNING]: provided hosts list is empty`                                | El inventario está vacío, mal formateado, o el grupo target no existe                                | `ansible-inventory --list` para validar la estructura                                              |
| Variables del inventory no aplican                                       | Typo en el nombre de la variable                                                                      | Validar nombres exactos contra la doc oficial                                                     |
| `ansible_ssh_pass` da warning de deprecation                             | Es alias deprecated desde 2.x — sigue funcionando pero conviene migrar                                | Reemplazar por `ansible_password`                                                                  |
| Playbook funciona en `stapp03` pero falla en otro host                   | Las variables son por-host; cada host necesita sus propias credenciales                              | Mover lo común a `[group:vars]`, mantener por-host solo lo específico                            |
| `Host key verification failed`                                           | Primera conexión al host — known_hosts no tiene la host key                                          | `host_key_checking=False` en `ansible.cfg` o aceptar manualmente                                  |
| Dynamic plugin devuelve "no hosts matched"                               | Filtros del plugin no matchean ningún recurso real                                                   | Correr `ansible-inventory --list` para ver qué devuelve el plugin antes de correr el playbook    |

## Días del journal donde aparece este tema

| Día     | Cubre                                                                       |
| ------- | --------------------------------------------------------------------------- |
| Día 82  | Primer lab de Ansible en el journal principal — inventario INI con `stapp03` |
| Día 83  | Troubleshoot de inventario incorrecto + primer playbook con módulo `file` apuntando a `stapp01` |
| Día 84  | Inventario multi-host (3 app servers, credenciales por línea) + `hosts: all` con módulo `copy` |
| Día 85  | Variable de conexión `{{ ansible_user }}` reusada en el playbook para setear owner por host |

> Más días se agregarán a medida que aparezcan en el journal.

## Recursos

- [Build your inventory (oficial)](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [INI inventory format](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#inventory-basics-formats-hosts-and-groups)
- [YAML inventory format](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#inventory-basics-formats-hosts-and-groups)
- [Connection variables (lista completa)](https://docs.ansible.com/ansible/latest/inventory_guide/connection_details.html)
- [`ansible-inventory` command](https://docs.ansible.com/ansible/latest/cli/ansible-inventory.html)
- [Dynamic inventory plugins](https://docs.ansible.com/ansible/latest/plugins/inventory.html)
- [Ansible Vault (encriptar secrets)](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
- [Variable precedence (orden de prioridad)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence)
- [`sshpass` para password auth](https://linux.die.net/man/1/sshpass)
