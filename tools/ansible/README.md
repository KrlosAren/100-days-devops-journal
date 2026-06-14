# Ansible — Guía de referencia

Ansible es una herramienta de **automatización agentless** que ejecuta tareas en servidores remotos vía SSH. A diferencia de Jenkins (CI/CD orquestador) o Kubernetes (orquestador de containers), Ansible se enfoca en **configurar y mantener el estado** de servidores existentes.

Los comandos principales:

```
ansible <hosts> -m <module> [-a 'args']      # Comando ad-hoc en N hosts
ansible-playbook -i <inventory> playbook.yml # Ejecutar un playbook
ansible-inventory -i <inventory> --list      # Validar inventario
ansible-vault encrypt/decrypt <file>         # Encriptar secrets
ansible-galaxy install <role>                # Gestionar roles de la comunidad
```

Esta guía está organizada en secciones temáticas. Cada una cubre una pregunta operacional que aparece todo el tiempo al trabajar con Ansible.

## Índice

| Sección                                      | Cubre                                                                                                |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| [Inventories](inventories.md)                | Formatos (INI, YAML, JSON, TOML), variables de conexión, grupos, dynamic inventory, validación      |

> Más secciones se irán agregando a medida que aparezcan los temas en el journal (playbooks, roles, modules, vault, etc.).

## Conceptos fundamentales — vocabulario base

| Término          | Definición                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------ |
| **Control node** | Máquina donde Ansible se ejecuta (típicamente el jump host del usuario)                          |
| **Managed node** | Servidor remoto donde Ansible aplica cambios — requiere SSH + Python                              |
| **Inventory**    | Catálogo de managed nodes + cómo conectarse a cada uno                                            |
| **Playbook**     | Archivo YAML con la secuencia de tareas a ejecutar — la "receta" de Ansible                       |
| **Play**         | Bloque dentro de un playbook que ata hosts (de inventory) con tasks                              |
| **Task**         | Acción individual — invoca un módulo con argumentos                                               |
| **Module**       | Unidad ejecutable que hace una cosa específica (`apt`, `copy`, `service`, `template`, ...)        |
| **Role**         | Conjunto reutilizable de tasks, vars, handlers, templates — el "package" de Ansible              |
| **Handler**      | Task que solo corre si otra task la notifica (típico: restart de servicio)                       |
| **Fact**         | Variable autorrecolectada del managed node (OS, IP, RAM, etc.) — disponible vía `setup` module   |
| **Variable**     | Valor parametrizable definido en inventory, playbook, role, o pasado por CLI con `-e`            |
| **Vault**        | Sistema de encriptación de secrets — archivos YAML encriptados con master key                    |
| **Collection**   | Bundle distribuible de modules + roles + plugins (reemplaza a los "Ansible modules" históricos)  |

## Filosofía de Ansible — qué la distingue

### 1. Agentless

Ansible **no instala nada** en los managed nodes. Solo requiere:

- SSH abierto desde el control node al managed node
- Python instalado en el managed node (default en casi cualquier Linux moderno)

Comparado con Chef (cliente local en cada nodo) o Puppet (agente persistente), Ansible es más simple de adoptar pero más lento (cada ejecución abre/cierra conexiones SSH).

### 2. Declarativo + idempotente

Las tareas describen **el estado deseado**, no la secuencia de comandos:

```yaml
- name: Ensure nginx is installed
  apt:
    name: nginx
    state: present     # Idempotente — si ya está, no hace nada
```

Al re-correr el playbook, las tareas que ya están en el estado deseado no hacen nada (no error, no cambio). Esto hace los playbooks **seguros de re-ejecutar**.

### 3. Push-based

Ansible "empuja" cambios desde el control node a los managed nodes. Es el opuesto del "pull-based" de Puppet/Chef donde el agente del nodo consulta al server por updates.

Trade-off:

| Push (Ansible)                                    | Pull (Puppet/Chef)                                |
| ------------------------------------------------- | ------------------------------------------------- |
| Despliegues sincrónicos — se sabe cuándo terminan  | Despliegues asincrónicos — el agente decide       |
| Sin agente en el nodo (más simple)                | Agente local + cache → más rápido en re-corridas |
| Escala con muchos nodos requiere paralelismo      | Escala "naturalmente" (cada agente independiente) |

### 4. YAML como lenguaje universal

Todo en Ansible (excepto el inventory INI opcional) se escribe en YAML:

- Playbooks
- Roles
- Inventarios (variante YAML)
- Vault (YAML encriptado)

Esto facilita el code review y versionado en git — todo es texto plano legible.

## Comparación con otras herramientas del journal

| Herramienta   | Para qué sirve                                  | Modelo                                   |
| ------------- | ----------------------------------------------- | ---------------------------------------- |
| **Jenkins** (Días 68-81) | CI/CD — pipelines, builds, deploys     | Server centralizado con jobs              |
| **Kubernetes** (Días 48-67) | Orquestación de containers en producción | Declarativo, controllers + reconciliation |
| **Ansible** (este área) | Configuración y mantenimiento de servers | Push declarativo, agentless                |
| **Docker** (Días 35-47) | Empaquetado de aplicaciones en containers | Imágenes inmutables                       |
| **Git** (Días 21-34)   | Control de versiones                            | DAG de commits                            |

Las herramientas son **complementarias**, no excluyentes. Una stack típica usa Git para versionado, Jenkins para CI/CD, Docker para empaquetado, Ansible para provisioning del host, y Kubernetes para correr containers en runtime.

## Cheatsheet rápido

```bash
# === ESTRUCTURA TÍPICA DE UN PROYECTO ===
project/
├── inventory                 # INI o YAML con hosts
├── ansible.cfg               # Config local de Ansible
├── playbook.yml              # Playbook principal
├── group_vars/
│   ├── all.yml               # Variables para TODOS los hosts
│   └── webservers.yml        # Variables del grupo webservers
├── host_vars/
│   └── web1.yml              # Variables específicas de web1
└── roles/
    └── nginx/                # Role reutilizable
        ├── tasks/main.yml
        ├── handlers/main.yml
        ├── templates/
        └── defaults/main.yml

# === COMANDOS BÁSICOS ===

# Ping a todos los hosts del inventario
ansible all -i inventory -m ping

# Ejecutar comando ad-hoc en un grupo
ansible webservers -i inventory -m shell -a 'uptime'

# Correr un playbook
ansible-playbook -i inventory playbook.yml

# Correr solo tasks con tag específico
ansible-playbook -i inventory playbook.yml --tags=deploy

# Modo dry-run (no aplica cambios, solo simula)
ansible-playbook -i inventory playbook.yml --check

# Mostrar qué cambiaría (diff de archivos)
ansible-playbook -i inventory playbook.yml --check --diff

# Pasar variables extras desde CLI
ansible-playbook -i inventory playbook.yml -e "version=1.2.3"

# Verbose para debugging
ansible-playbook -i inventory playbook.yml -vvv

# Limitar a un host específico del inventario
ansible-playbook -i inventory playbook.yml --limit web1

# === INVENTORY ===
ansible-inventory -i inventory --list           # JSON completo
ansible-inventory -i inventory --graph          # Visualización ASCII

# === VAULT ===
ansible-vault create secrets.yml                # Crear archivo encriptado
ansible-vault edit secrets.yml                  # Editar (descifra, edita, recifra)
ansible-vault encrypt_string 'password' --name 'db_password'  # String inline
ansible-playbook ... --ask-vault-pass           # Pedir password al correr

# === GALAXY ===
ansible-galaxy install geerlingguy.nginx        # Instalar role de la comunidad
ansible-galaxy list                              # Listar roles instalados
ansible-galaxy collection install community.general
```

## Recursos generales

- [Ansible documentation (oficial)](https://docs.ansible.com/)
- [Module index](https://docs.ansible.com/ansible/latest/collections/index_module.html)
- [Ansible Galaxy](https://galaxy.ansible.com/) — marketplace de roles/collections
- [Best practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [`ansible-lint`](https://ansible.readthedocs.io/projects/lint/) — linter para playbooks
- [`molecule`](https://ansible.readthedocs.io/projects/molecule/) — framework de testing para roles
