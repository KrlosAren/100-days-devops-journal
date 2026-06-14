# Día 82 - Ansible Inventory for App Server Testing (formato INI + variables de conexión)

## Problema / Desafío

Después de 13 días de CI/CD con Jenkins (Días 68-81), el journal retoma **Ansible** desde el Día 5. El lab arranca con el concepto más fundamental: el **inventario** — el catálogo de hosts donde los playbooks van a ejecutarse.

Requirements:

1. Crear inventario tipo **INI** en `/home/thor/playbook/inventory` (jump host)
2. Incluir App Server 3 (`stapp03`) con las variables necesarias para conexión
3. El hostname del inventario debe matchear el nombre del wiki (`stapp03`)
4. La validación corre: `ansible-playbook -i inventory playbook.yml` — el inventario debe funcionar sin args extra

Datos del host destino:

| Campo                | Valor                  |
| -------------------- | ---------------------- |
| Hostname / wiki name | `stapp03`              |
| IP                   | `172.16.238.12`        |
| SSH user             | `banner`               |
| SSH password         | `BigGr33n`             |
| Método de conexión   | SSH                    |

## Conceptos clave

### Qué es un inventario Ansible

El inventario es **el catálogo de hosts** donde Ansible va a ejecutar playbooks. Para cada host define:

- Cómo se llama (alias usado en playbooks)
- Cómo conectarse (IP, user, autenticación, puerto, método)
- A qué grupos pertenece (para targeting selectivo)

Es el equivalente Ansible del **`kubeconfig` de K8s** (lista de clusters + auth) o del **`~/.ssh/config`** de SSH (lista de hosts + cómo conectarse a cada uno).

### Tipos de archivo para escribir inventarios en Ansible

Ansible soporta **cinco formatos** de inventario, agrupados en dos categorías:

#### Categoría 1 — Inventarios estáticos (archivos)

| Formato       | Extensión típica                | Cuándo conviene                                                                  |
| ------------- | ------------------------------- | -------------------------------------------------------------------------------- |
| **INI**       | `inventory`, `hosts`, `*.ini`   | Inventarios chicos (≤ 20 hosts), estructura simple, lectura rápida              |
| **YAML**      | `inventory.yml`, `*.yaml`       | Inventarios grandes, jerarquías de grupos, variables complejas (listas, dicts)   |
| **JSON**      | `*.json`                        | Output de scripts/herramientas que generan inventario; menos común a mano        |
| **TOML**      | `*.toml` (Ansible 2.8+)         | Alternativa estructurada — uso marginal, casi no se ve en producción            |

#### Categoría 2 — Inventarios dinámicos (scripts)

| Tipo                       | Cuándo usar                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------ |
| **Dynamic inventory plugin** | Inventario generado en runtime desde una fuente externa (AWS, GCP, Azure, K8s)     |
| **Inventory script**       | Script ejecutable (Python, Bash, etc.) que devuelve JSON con la estructura esperada  |

### Comparación lado a lado — el mismo host en cada formato

El inventario del lab traducido a cada formato:

#### INI (lo del lab)

```ini
[stapp03]
stapp03 ansible_host=stapp03 ansible_user=banner ansible_password=BigGr33n ansible_connection=ssh
```

#### YAML equivalente

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

#### JSON equivalente

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

JSON sigue **el formato canónico** que Ansible espera de un script dinámico. La sección `_meta.hostvars` es la convención para variables por host. Raramente se escribe a mano — sale de tooling automatizado.

#### TOML equivalente

```toml
[stapp03]
[stapp03.hosts.stapp03]
ansible_host = "stapp03"
ansible_user = "banner"
ansible_password = "BigGr33n"
ansible_connection = "ssh"
```

TOML es una opción válida pero **poco usada en el ecosistema Ansible**. La doc oficial lo menciona pero la mayoría de tooling de Ansible asume INI o YAML.

### Inventarios dinámicos — el caso "real" en cloud

En producción cloud, los inventarios estáticos no escalan: las instancias EC2/GCE aparecen y desaparecen constantemente. **Dynamic inventory plugins** consultan el cloud provider en runtime.

#### Ejemplo: AWS EC2 dynamic inventory

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

Al correr `ansible-inventory -i inventory_aws_ec2.yml --list`, Ansible llama a la API de AWS, lista las instancias filtradas, y devuelve un inventario JSON dinámico **generado en runtime**. Cada vez que se ejecuta, el inventario refleja el estado actual del cloud.

Plugins comunes:

| Plugin                          | Para qué                                            |
| ------------------------------- | --------------------------------------------------- |
| `amazon.aws.aws_ec2`            | Instancias EC2 de AWS                                |
| `google.cloud.gcp_compute`      | VMs de GCP                                          |
| `azure.azcollection.azure_rm`   | VMs de Azure                                        |
| `kubernetes.core.k8s`           | Pods de un cluster K8s                              |
| `community.docker.docker_machines` | Containers de Docker                            |
| `theforeman.foreman.foreman`    | Servers gestionados por Foreman/Satellite           |
| `community.vmware.vmware_vm_inventory` | VMs de vSphere/vCenter                        |

#### Inventory script (formato custom)

Un script ejecutable que respeta el contrato:

- Acepta `--list` → devuelve JSON con toda la estructura
- Acepta `--host <hostname>` → devuelve JSON con las variables de ese host

Ejemplo trivial en Bash:

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

### Cuándo usar cada tipo — guía rápida

| Escenario                                              | Tipo recomendado                       |
| ------------------------------------------------------ | -------------------------------------- |
| Lab, demo, ≤ 10 hosts fijos                            | **INI**                                |
| Producción on-prem, ≤ 50 hosts, estructura compleja    | **YAML**                               |
| Producción cloud (AWS/GCP/Azure)                       | **Dynamic inventory plugin**           |
| Inventario generado por otra herramienta (Terraform, CMDB) | **Inventory script** o **JSON output** |
| Multi-source (parte estático + parte dinámico)         | Directorio con múltiples archivos — Ansible los une todos |

### Múltiples inventarios — directorio en lugar de archivo

Una propiedad útil: `-i` puede apuntar a un **directorio** que contiene varios archivos de inventario. Ansible los lee todos y los une:

```
inventories/
├── ini/
│   └── hosts                # INI con hosts on-prem
├── yaml/
│   └── databases.yml         # YAML con grupo dbservers
└── dynamic/
    └── aws_ec2.yml           # Dynamic plugin para EC2
```

```bash
ansible-playbook -i inventories/ playbook.yml
```

Esto une los tres inventarios — útil para entornos híbridos (on-prem + cloud).

### Para el lab — INI es lo correcto

El lab pide INI explícitamente y es el formato más simple para un único host. Los otros formatos son referencia conceptual para días futuros y producción real.

### Variables de conexión — las más usadas

| Variable                          | Significado                                                       |
| --------------------------------- | ----------------------------------------------------------------- |
| `ansible_host`                    | IP o hostname real (puede diferir del alias del inventario)       |
| `ansible_user`                    | Usuario remoto para SSH                                           |
| `ansible_password`                | Password SSH (alias moderno de `ansible_ssh_pass`)                |
| `ansible_ssh_pass`                | Password SSH (alias legacy — todavía funciona)                    |
| `ansible_ssh_private_key_file`    | Path a la clave privada SSH                                       |
| `ansible_port`                    | Puerto SSH (default 22)                                            |
| `ansible_connection`              | Método: `ssh` (default), `local`, `docker`, `winrm`, `kubectl`     |
| `ansible_python_interpreter`      | Path al python del host remoto (útil si no es `/usr/bin/python3`) |
| `ansible_become`                  | `true` para usar sudo                                              |
| `ansible_become_user`             | Usuario al que escalar privilegios (default `root`)               |
| `ansible_become_password`         | Password para sudo (si no NOPASSWD)                                |

> El alias del inventario (`stapp03` en `[stapp03]`) puede ser **cualquier nombre**. `ansible_host` es la IP/hostname real al que Ansible se conecta. Esto permite tener alias amigables (ej. `web-prod-01`) que apuntan a IPs cambiantes.

### Anatomía del archivo INI — sintaxis completa

```ini
# Comentarios con # o ;

# Host simple sin grupo (va al grupo implícito "ungrouped")
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

### Grupos especiales pre-existentes

Ansible crea automáticamente dos grupos:

| Grupo         | Hosts incluidos                                            |
| ------------- | ---------------------------------------------------------- |
| `all`         | **Todos** los hosts del inventario                          |
| `ungrouped`   | Hosts que **no están** en ningún grupo definido por usuario |

Esto permite targeting genérico:

```bash
ansible all -m ping -i inventory
ansible ungrouped -m setup -i inventory
```

### `ansible_password` vs SSH keys — la práctica de seguridad

El password plano en el inventario es **anti-pattern de producción**. Las tres alternativas en orden de preferencia:

#### Opción 1 — SSH keys (lo más usado en producción)

```ini
[stapp03]
stapp03 ansible_host=172.16.238.12 ansible_user=banner \
        ansible_ssh_private_key_file=~/.ssh/banner_key
```

Sin password en el archivo. La key privada vive en disco, protegida por permisos del filesystem (`chmod 600`).

#### Opción 2 — `ansible-vault` para encriptar el password

```bash
# Crear archivo de vault con el password
ansible-vault encrypt_string 'BigGr33n' --name 'ansible_password'
# Output: ansible_password: !vault | $ANSIBLE_VAULT;1.1;AES256\n<encrypted>

# Pegar en group_vars/stapp03/vault.yml
# Correr playbook con --ask-vault-pass o --vault-password-file
ansible-playbook -i inventory playbook.yml --ask-vault-pass
```

El password está cifrado at-rest pero descifrable con la master password del vault.

#### Opción 3 — Lookup desde secret manager externo

```yaml
ansible_password: "{{ lookup('community.hashi_vault.vault_kv2_get', 'secret/data/stapp03')['data']['password'] }}"
```

El secret nunca toca disco — se lee en runtime desde Vault/AWS Secrets Manager/etc.

> Para este lab: password plano es lo que pide el lab y funciona. Pero para producción real, **SSH keys** es la base y **ansible-vault** para los secretos restantes.

### Validar el inventario antes de correr playbooks

Tres comandos útiles para validar:

```bash
# 1. Listar todos los hosts y su estructura de grupos
ansible-inventory -i inventory --list

# 2. Listar solo los hosts (formato más simple)
ansible-inventory -i inventory --graph

# 3. Hacer ping a todos los hosts (test de conectividad)
ansible all -i inventory -m ping
```

El `ansible -m ping` no solo testea ICMP — testea que **Ansible puede ejecutar Python en el host remoto**, que es el requisito mínimo para que cualquier playbook funcione. Es el test de salud canónico.

### Por qué el playbook se ejecuta con `-i inventory` (path relativo)

El comando de validación del lab:

```bash
ansible-playbook -i inventory playbook.yml
```

Esto solo funciona si:

1. El archivo `inventory` está en el directorio de trabajo (o relativo a él)
2. `playbook.yml` también está en el mismo directorio
3. El usuario tiene permisos de lectura sobre los dos

Por eso el lab pide específicamente `/home/thor/playbook/inventory` — porque el playbook va a estar en `/home/thor/playbook/` y el comando se va a ejecutar desde ahí.

## Pasos

1. Conectarse al jump host como `thor`
2. Verificar que existe el directorio `/home/thor/playbook/`
3. Crear el archivo `/home/thor/playbook/inventory` con el formato INI
4. Definir el host `stapp03` con sus variables de conexión
5. Validar con `ansible-inventory -i /home/thor/playbook/inventory --list`
6. Validar conectividad con `ansible all -i /home/thor/playbook/inventory -m ping`

## Comandos / Código

### 1. Conectarse al jump host

```bash
ssh thor@jump_host
cd /home/thor/playbook
ls
# (debería haber playbooks ya colocados por el lab)
```

### 2. Crear el archivo inventory

```bash
cat > /home/thor/playbook/inventory <<'EOF'
[stapp03]
stapp03 ansible_host=stapp03 ansible_user=banner ansible_password=BigGr33n ansible_connection=ssh
EOF
```

Dos detalles a notar en esta versión:

| Decisión                                  | Por qué                                                                                  |
| ----------------------------------------- | ---------------------------------------------------------------------------------------- |
| `ansible_host=stapp03` (no IP)            | Usa **resolución DNS interna** del lab. Si la IP cambia, el inventario sigue funcionando |
| `ansible_password` (no `ansible_ssh_pass`) | Alias moderno (canónico desde Ansible 2.x), evita warning de deprecation                |

> El nombre del grupo `[stapp03]` es **opcional** acá — el host podría ir directamente al grupo `ungrouped` si se omite el header. Convención: nombrar el grupo para poder targetear "todos los app servers" más adelante.

### Versión con IP literal (alternativa)

Si el DNS interno no es confiable o se quiere fijar la IP explícitamente:

```ini
[stapp03]
stapp03 ansible_host=172.16.238.12 ansible_user=banner ansible_password=BigGr33n ansible_connection=ssh
```

Trade-off: la versión con DNS es **más portable** (sobrevive cambios de IP), la versión con IP es **más determinística** (no depende de resolución DNS). Para labs como este, cualquiera funciona; para producción, suele preferirse DNS interno con un service discovery confiable.

### 3. Versión equivalente sin `ansible_connection` (default es ssh)

```ini
[stapp03]
stapp03 ansible_host=172.16.238.12 ansible_user=banner ansible_ssh_pass=BigGr33n
```

`ansible_connection=ssh` es el default — solo se especifica cuando el método es distinto.

### 4. Validar la estructura del inventario

```bash
ansible-inventory -i /home/thor/playbook/inventory --list
```

Output esperado:

```json
{
    "_meta": {
        "hostvars": {
            "stapp03": {
                "ansible_connection": "ssh",
                "ansible_host": "172.16.238.12",
                "ansible_ssh_pass": "BigGr33n",
                "ansible_user": "banner"
            }
        }
    },
    "all": {
        "children": [
            "stapp03",
            "ungrouped"
        ]
    },
    "stapp03": {
        "hosts": [
            "stapp03"
        ]
    }
}
```

Detalles a notar:

| Bloque                          | Significado                                                                |
| ------------------------------- | -------------------------------------------------------------------------- |
| `_meta.hostvars.stapp03.<var>`  | Variables del host (lo que aparece después del nombre en el INI)            |
| `all.children`                  | Grupos hijos del grupo `all` — siempre incluye `ungrouped`                  |
| `stapp03.hosts`                 | Hosts del grupo `stapp03` (solo uno en este caso)                          |

### 5. Validar conectividad — el "smoke test" del inventario

```bash
ansible all -i /home/thor/playbook/inventory -m ping
```

Output esperado:

```
stapp03 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

> `"ping": "pong"` confirma que:
> 1. La resolución DNS / IP funcionó
> 2. El SSH se autenticó correctamente
> 3. Python existe en el host remoto y Ansible puede ejecutar módulos

### 6. Variantes del inventario (referencia, no aplica al lab estricto)

#### Variante con grupo más descriptivo

```ini
[app_servers]
stapp03 ansible_host=172.16.238.12 ansible_user=banner ansible_ssh_pass=BigGr33n

[app_servers:vars]
http_port=8080
```

Permite agregar más app servers después sin duplicar variables comunes.

#### Variante con SSH keys (producción)

```ini
[app_servers]
stapp03 ansible_host=172.16.238.12 ansible_user=banner

[app_servers:vars]
ansible_ssh_private_key_file=~/.ssh/banner_key
```

Sin password en el archivo — la key vive aparte con `chmod 600`.

#### Variante YAML equivalente

```yaml
# inventory.yml
all:
  children:
    app_servers:
      hosts:
        stapp03:
          ansible_host: 172.16.238.12
          ansible_user: banner
          ansible_ssh_pass: BigGr33n
      vars:
        http_port: 8080
```

## Anatomía — orden de precedencia de variables

Ansible busca variables en este orden (de menor a mayor prioridad):

```
1. role defaults
2. inventory file (este lab) / inventory script
3. inventory group_vars/all
4. inventory group_vars/<group_name>
5. inventory host_vars/<host>
6. playbook group_vars / host_vars
7. host facts (gathered)
8. play vars
9. task vars
10. extra vars (-e en la línea de comando) ← gana sobre todo
```

Para el lab, todas las variables están en el inventory file (nivel 2) — el más bajo. Si más adelante se agregan `group_vars/app_servers.yml`, esas variables sobreescriben.

## Inventario INI vs hosts file de Linux

| Aspecto                       | `/etc/hosts` del SO                                     | Inventario Ansible                                          |
| ----------------------------- | ------------------------------------------------------- | ----------------------------------------------------------- |
| Para qué sirve                | Resolución DNS local (hostname → IP)                    | Catálogo de hosts + metadata de conexión + grupos           |
| Contenido por host            | Solo IP + alias                                          | IP, user, password/key, port, vars custom                   |
| Estructura                    | Plano                                                    | Jerarquía de grupos con composición                          |
| Quién lo usa                  | Cualquier proceso del SO via libnss                      | Solo Ansible (otros tools tienen sus propios formatos)     |

El paralelo conceptual existe: ambos son "lo primero que se consulta para resolver un host". Ansible inventory es la versión enriquecida con metadata operacional.

## Conexión con días anteriores

- **Día 1-5 (Ansible journal original)**: los primeros pasos con Ansible. Hoy retoma esa sección después de 77 días — el inventario es el primer prerequisito para todo lo que sigue.
- **Día 7 (passwordless SSH)**: la alternativa al password en el inventario. En producción, el inventario apunta a una key privada, no a un password literal.
- **Día 8 (Install Ansible con pip3)**: el setup de Ansible. Hoy se asume que está instalado en el jump host.
- **Día 75 (Slave Nodes de Jenkins)**: paralelo conceptual — Jenkins inventory = lista de nodes con sus labels y credentials; Ansible inventory = lista de hosts con sus variables. Mismo problema, distinto stack.
- **Día 71 (Jenkins job con SSH a server)**: en Jenkins el SSH se configura via Credentials Manager + `agent { label }`. En Ansible se configura via `ansible_user` + `ansible_password` en el inventory. La diferencia: Ansible es **declarativo** (todo en el archivo), Jenkins distribuye entre UI/credentials/labels.

## Reflexión: el inventario como contrato de Ansible

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- Después de tanto Jenkins, ¿el modelo de Ansible (declarativo + push-based agentless) se siente más simple o pierde flexibilidad? Comparación honesta entre ambos paradigmas.
- INI vs YAML para inventarios: ¿cuál se siente más natural? El INI es más compacto pero menos estructurado.
- Password en plain text en el inventario: ¿anti-pattern aceptable para labs o algo que evitarías incluso en demo? ¿Cómo manejarías secrets en producción real con Ansible?
- El paralelo Ansible inventory ↔ Jenkins nodes ↔ kubeconfig: ¿es útil mentalizarlo así para saltar entre herramientas?
- "Inventario como contrato": todo lo que el playbook necesita saber sobre los hosts vive en el inventory. ¿Se siente como una buena separación o un overhead?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `ansible-playbook -i inventory ...` no encuentra el inventario           | Path relativo y el comando se corre desde otro directorio                                            | `cd /home/thor/playbook` antes, o usar path absoluto en `-i`                                       |
| `ansible all -m ping` devuelve `unreachable`                            | (a) IP/hostname incorrecta; (b) puerto SSH bloqueado; (c) credenciales mal                            | Probar SSH manual: `sshpass -p BigGr33n ssh banner@172.16.238.12 hostname`                        |
| `Failed to connect to the host via ssh: Permission denied (publickey,password)` | Password incorrecto o SSH del host destino tiene PasswordAuth disabled                                | Verificar `/etc/ssh/sshd_config` del destino: `PasswordAuthentication yes`                        |
| `sshpass: Failed to run command: No such file or directory`             | Falta `sshpass` en el control node — Ansible lo requiere para usar `ansible_password`                | `sudo yum install -y sshpass` o `sudo apt install -y sshpass`                                     |
| El playbook funciona desde un user pero no desde otro                    | Ansible busca `~/.ansible/`, config local — el otro user no tiene los archivos                       | Usar `-i` con path absoluto, o setear `ANSIBLE_CONFIG=/path/to/ansible.cfg`                       |
| `[WARNING]: provided hosts list is empty`                               | El inventario está vacío, mal formateado, o el grupo target no existe                                | `ansible-inventory --list` para validar la estructura                                              |
| Variables del inventory no aplican                                       | Typo en el nombre de la variable (ej. `ansible_users` en lugar de `ansible_user`)                    | Validar nombres exactos contra la doc oficial                                                     |
| `ansible_ssh_pass` da warning de deprecation                             | Es alias deprecated desde 2.x — sigue funcionando pero conviene migrar                                | Reemplazar por `ansible_password`                                                                  |
| Playbook funciona en `stapp03` pero al agregar otro host falla            | Las variables son por-host; cada host necesita sus propias credenciales                              | Mover a `[group:vars]` lo común; mantener por-host solo lo específico                            |
| `Host key verification failed`                                           | Primera conexión al host — known_hosts no tiene la host key                                          | `ansible all -m ping` con `host_key_checking=False` (en `ansible.cfg`) o aceptar manualmente     |

## Deep dive — referencia transversal de inventories

Para una referencia completa de inventarios fuera del scope de este lab específico (formatos, dynamic plugins, vault, precedencia de variables, troubleshooting), ver:

- [`tools/ansible/inventories.md`](../../tools/ansible/inventories.md) — guía de referencia transversal

Esa guía amplía los temas tocados acá con casos productivos (AWS EC2 plugin, inventario por directorio, ansible-vault para secrets), troubleshooting general, y el orden completo de precedencia de variables.

## Recursos

- [Build your inventory (oficial)](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [INI inventory format](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#inventory-basics-formats-hosts-and-groups)
- [Connection variables](https://docs.ansible.com/ansible/latest/inventory_guide/connection_details.html)
- [`ansible-inventory` command](https://docs.ansible.com/ansible/latest/cli/ansible-inventory.html)
- [Ansible Vault (encriptar secrets)](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
- [Group variable precedence](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence)
- [`sshpass` para password auth](https://linux.die.net/man/1/sshpass)
