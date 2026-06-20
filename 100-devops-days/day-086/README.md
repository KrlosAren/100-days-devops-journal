# Día 86 - Ansible Ping Module Usage (passwordless SSH + módulo ping)

## Problema / Desafío

Antes de correr playbooks, el equipo DevOps necesita un **pre-requisito**: conexión SSH **sin password** entre el Ansible controller (jump host) y los managed nodes. El ticket pide configurar las llaves SSH y verificar con el módulo `ping`.

Requirements:

1. El jump host es el **Ansible controller**; los playbooks corren desde el user `thor`
2. Existe el inventario `/home/thor/ansible/inventory`
3. Usando ese inventario, el `ansible ping` desde el jump host a **App Server 3** debe funcionar

Estado inicial del inventario (solo passwords, sin user):

```ini
stapp01 ansible_ssh_pass=Ir0nM@n
stapp02 ansible_ssh_pass=Am3ric@
stapp03 ansible_ssh_pass=BigGr33n
```

Objetivo: reemplazar la **autenticación por password** por **autenticación por llave SSH**, dejando el inventario sin secretos.

Continúa la línea del Día 7 (passwordless SSH) y de los Días 82-85 (inventarios y módulos), pero el foco hoy es la **capa de conexión** que hace posible todo lo demás.

## Conceptos clave

### El módulo `ping` NO es el `ping` de la red (ICMP)

El error mental más común. El `ping` de Ansible **no manda paquetes ICMP** ni mide latencia:

| `ping` de red (`/bin/ping`)              | Módulo `ping` de Ansible                          |
| ---------------------------------------- | ------------------------------------------------- |
| Manda paquetes **ICMP** capa 3           | Abre una conexión **SSH** completa                |
| Mide latencia / reachability de red      | Verifica el stack completo de Ansible             |
| No autentica                             | **Autentica** (SSH key o password)                |
| No necesita Python en el destino         | **Verifica que hay Python** en el destino         |
| Responde aunque SSH esté caído           | Falla si SSH o Python no están                    |

Lo que hace el módulo `ping` internamente:

1. **Conecta por SSH** al host (con las credenciales del inventario)
2. **Verifica que Python existe** en el remoto (lo necesita para ejecutar módulos)
3. Devuelve `"ping": "pong"` si todo el camino funciona

```json
stapp03 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

Por eso `pong` confirma **tres cosas a la vez**: red OK + SSH autenticó + Python disponible. Es el smoke test canónico antes de correr cualquier playbook.

> El campo `discovered_interpreter_python` muestra que Ansible **auto-detectó** el intérprete Python del remoto (`/usr/bin/python3`). Sin Python, el módulo falla con `/bin/sh: python: not found`.

### Por qué passwordless SSH — el problema con `ansible_ssh_pass`

El inventario inicial guarda passwords en **texto plano**:

```ini
stapp01 ansible_ssh_pass=Ir0nM@n      # ← secreto visible en el archivo
```

Problemas:

- **Secretos en texto plano** — cualquiera que lea el archivo ve los passwords
- **Termina en git** si el inventario se versiona
- **No escala** — rotar un password obliga a editar el inventario
- Requiere `sshpass` instalado para que Ansible lo use

La solución estándar: **autenticación por llave pública SSH**. El controller prueba su identidad con una llave privada; el remoto confía en la pública previamente instalada. Sin passwords en ningún lado.

### Anatomía de la autenticación por llave SSH

```
[Jump host - thor]                          [App Server - tony]
  ~/.ssh/id_rsa      (privada, NUNCA sale)
  ~/.ssh/id_rsa.pub  (pública)  ──ssh-copy-id──►  ~/.ssh/authorized_keys
                                                    (la pública vive aquí)
```

Al conectar:

1. El controller presenta que tiene la **llave privada**
2. El remoto verifica contra las **públicas** en su `authorized_keys`
3. Si matchea → acceso sin password

| Archivo                        | Dónde vive | Función                                              |
| ------------------------------ | ---------- | ---------------------------------------------------- |
| `~/.ssh/id_rsa`                | controller | Llave **privada** — secreta, nunca se copia          |
| `~/.ssh/id_rsa.pub`            | controller | Llave **pública** — se distribuye a los remotos      |
| `~/.ssh/authorized_keys`       | remoto     | Lista de públicas autorizadas a conectar             |
| `~/.ssh/known_hosts`           | controller | Host keys de servers ya visitados (anti-MITM)        |

### `ssh-keygen` y `ssh-copy-id`

```bash
ssh-keygen -t rsa       # Genera el par de llaves
ssh-copy-id user@host   # Copia la pública al authorized_keys del remoto
```

`ssh-keygen -t rsa`:
- Genera `id_rsa` (privada) + `id_rsa.pub` (pública) en `~/.ssh/`
- Pregunta passphrase — para Ansible **se deja vacía** (Enter), si no, cada conexión pediría la passphrase y rompería la automatización

`ssh-copy-id`:
- Pide el password del remoto **una sola vez** (la última vez que se usa password)
- Appendea la pública al `~/.ssh/authorized_keys` del remoto
- Setea permisos correctos automáticamente (`700` en `.ssh`, `600` en `authorized_keys`)

### El detalle clave: qué user en `ssh-copy-id`

El inventario inicial **no tiene `ansible_user`**, así que Ansible se conectaría como `thor` (el user del controller). Pero los app servers usan `tony`/`steve`/`banner`. Hay que:

1. Copiar la llave al **user correcto** de cada server (`ssh-copy-id tony@stapp01`)
2. Declarar ese user en el inventario (`ansible_user=tony`)

| Host      | User    | Password (solo para el `ssh-copy-id` inicial) |
| --------- | ------- | --------------------------------------------- |
| `stapp01` | `tony`  | `Ir0nM@n`                                     |
| `stapp02` | `steve` | `Am3ric@`                                     |
| `stapp03` | `banner`| `BigGr33n`                                    |

## Pasos

1. Generar el par de llaves SSH en el jump host (passphrase vacía)
2. Copiar la pública a cada app server con `ssh-copy-id` (usa el password una última vez)
3. Editar el inventario: agregar `ansible_user`, quitar `ansible_ssh_pass`
4. Verificar con `ansible -i inventory all -m ping`

## Comandos / Código

### 1. Generar la llave SSH

```bash
ssh-keygen -t rsa
# Enter en todas las preguntas (passphrase vacía para automatización)
```

Output:

```
Generating public/private rsa key pair.
Enter file in which to save the key (/home/thor/.ssh/id_rsa): [Enter]
Enter passphrase (empty for no passphrase): [Enter]
Enter same passphrase again: [Enter]
Your identification has been saved in /home/thor/.ssh/id_rsa
Your public key has been saved in /home/thor/.ssh/id_rsa.pub
```

### 2. Copiar la llave pública a cada server

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub tony@stapp01     # password: Ir0nM@n
ssh-copy-id -i ~/.ssh/id_rsa.pub steve@stapp02    # password: Am3ric@
ssh-copy-id -i ~/.ssh/id_rsa.pub banner@stapp03   # password: BigGr33n
```

El lab solo exige App Server 3, pero configurar los tres deja el controller listo para cualquier playbook futuro.

> Si aparece el prompt `Are you sure you want to continue connecting (yes/no)?`, responder `yes` (primer contacto, host key nueva).

### 3. Editar el inventario — quitar passwords, agregar users

Antes (auth por password):

```ini
stapp01 ansible_ssh_pass=Ir0nM@n
stapp02 ansible_ssh_pass=Am3ric@
stapp03 ansible_ssh_pass=BigGr33n
```

Después (auth por llave SSH):

```ini
stapp01 ansible_user=tony
stapp02 ansible_user=steve
stapp03 ansible_user=banner
```

El `ansible_ssh_pass` desaparece — la llave SSH reemplaza al password. Solo queda **qué user** usar en cada host.

### 4. Verificar con el módulo ping

```bash
ansible -i inventory all -m ping
```

Output esperado:

```
stapp01 | SUCCESS => {
    "ansible_facts": { "discovered_interpreter_python": "/usr/bin/python3" },
    "changed": false,
    "ping": "pong"
}
stapp02 | SUCCESS => { ... "ping": "pong" }
stapp03 | SUCCESS => { ... "ping": "pong" }
```

`pong` en los tres = passwordless SSH funcionando. **Sin pedir password** = la llave hizo su trabajo.

Para verificar solo App Server 3 (lo que pide el lab):

```bash
ansible -i inventory stapp03 -m ping
```

### Desglose del comando `ansible ... -m ping`

```
ansible -i inventory all -m ping
        │          │      │  │
        │          │      │  └── ping: el módulo a ejecutar
        │          │      └───── -m: especifica un módulo (ad-hoc command)
        │          └──────────── all: patrón de hosts (todos)
        └─────────────────────── -i: archivo de inventario
```

Esto es un **ad-hoc command**: ejecutar un módulo sin escribir un playbook. Útil para tareas únicas y verificaciones rápidas.

## Verificación adicional

```bash
# Confirmar que NO pide password al hacer SSH directo
ssh tony@stapp01 'whoami'      # → tony, sin prompt de password

# Ver la pública instalada en el remoto
ssh tony@stapp01 'cat ~/.ssh/authorized_keys'

# Ad-hoc para confirmar conexión sin facts
ansible -i inventory all -m ping -o    # -o = output en una línea por host
```

## Troubleshooting

| Problema                                                          | Causa                                                                         | Solución                                                                              |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `Permission denied (publickey,password)`                          | La pública no quedó en el `authorized_keys` del remoto                        | Re-correr `ssh-copy-id user@host` con el password correcto                            |
| `ping` sigue pidiendo password                                    | El inventario aún tiene `ansible_ssh_pass` o falta `ansible_user`             | Quitar `ansible_ssh_pass`, dejar `ansible_user=...`                                   |
| Ansible conecta como `thor` y falla                               | El inventario no define `ansible_user` y se asume el user del controller      | Agregar `ansible_user=<user>` por host                                                |
| Cada conexión pide passphrase de la llave                         | Se puso passphrase al `ssh-keygen`                                            | Regenerar con passphrase vacía, o usar `ssh-agent` para cachearla                     |
| `Host key verification failed`                                    | El remoto no está en `known_hosts`                                            | Aceptar manualmente (`yes`) o `-o StrictHostKeyChecking=no` en `ansible_ssh_common_args` |
| `/bin/sh: python: not found` / interpreter discovery falla        | El remoto no tiene Python                                                     | Instalar Python en el remoto o fijar `ansible_python_interpreter`                     |
| `ssh-copy-id: command not found`                                  | El paquete `openssh-clients` no está                                          | Instalar `openssh-clients` (o copiar la pública manual a `authorized_keys`)           |
| `pong` funciona pero un playbook con `become` falla               | La llave da acceso SSH pero `become` necesita sudo configurado                | Verificar sudoers / usar `--ask-become-pass` (rompe validación sin args)              |

## Conexión con días anteriores

- **Día 7 (passwordless SSH)**: el lab original que introdujo las llaves SSH. Hoy es la aplicación directa en el contexto de Ansible — el controller necesita SSH sin password para automatizar.
- **Días 82-85 (Ansible)**: todos esos labs usaban `ansible_ssh_pass` en el inventario. Hoy se elimina ese anti-pattern y se reemplaza por llaves — el inventario queda **sin secretos**.
- **Día 75 (Jenkins Slave Nodes)**: paralelo conceptual — "Launch via SSH" en Jenkins también requiere passwordless SSH del controller al agent. Misma capa de conexión, distinta herramienta.
- **`ping` como smoke test**: equivalente al `curl -fsS | grep -q` del Día 81 — una verificación mínima de que el camino completo funciona antes de confiar en él.

## Reflexión: el módulo ping como contrato de conectividad

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- El ping de Ansible verifica SSH + Python + auth, no ICMP. ¿Por qué Ansible necesita Python en el remoto y qué dice eso sobre cómo funciona (agentless pero no "dependency-less")? Comparar con Jenkins agent (agent.jar) vs Ansible (solo SSH+Python).
- Pasar de ansible_ssh_pass a llave SSH: el password desaparece del inventario pero "se mueve" a ~/.ssh/. ¿Realmente es más seguro o solo cambió dónde vive el secreto? ¿Qué protege la llave privada que el password no?
- El ssh-copy-id es la última vez que se usa el password. ¿Qué pasa operacionalmente cuando rotan el password del server después? (la llave sigue funcionando — desacoplé auth de password).
- ping como pre-requisito antes de cualquier playbook: ¿vale la pena correrlo siempre primero, o es ceremonia? ¿Cuándo un pong verde igual no garantiza que el playbook va a correr (ej. become, módulos que faltan)?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`ping` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/ping_module.html)
- [Ansible ad-hoc commands](https://docs.ansible.com/ansible/latest/command_guide/intro_adhoc.html)
- [Connection methods and details](https://docs.ansible.com/ansible/latest/inventory_guide/connection_details.html)
- [`ssh-copy-id` man page](https://man.openbsd.org/ssh-copy-id)
- [SSH key-based authentication](https://www.ssh.com/academy/ssh/public-key-authentication)
- [Interpreter discovery (`ansible_python_interpreter`)](https://docs.ansible.com/ansible/latest/reference_appendices/interpreter_discovery.html)
