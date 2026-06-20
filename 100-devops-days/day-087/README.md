# Día 87 - Ansible Install Package (módulo yum + gestión de paquetes idempotente)

## Problema / Desafío

El equipo de desarrollo necesita ciertos paquetes pre-instalados en los app servers para probar aplicaciones. La tarea: instalar el paquete `sqlite` en **todos** los app servers usando el módulo `yum` de Ansible.

Requirements:

1. Crear inventario `/home/thor/playbook/inventory` con todos los app servers
2. Crear playbook `/home/thor/playbook/playbook.yml` que instale `sqlite` con el módulo **yum**
3. El user `thor` debe poder correr el playbook desde el jump host
4. La validación corre `ansible-playbook -i inventory playbook.yml` — sin args extra

Continúa la línea de Ansible (Días 82-86). Hoy se pasa de gestionar **archivos** (`file`, `copy`) a gestionar **paquetes del sistema** — la tarea más común en provisioning real.

## Conceptos clave

### El módulo `yum` — gestor de paquetes para RHEL/CentOS

`yum` (Yellowdog Updater Modified) es el gestor de paquetes de la familia Red Hat (RHEL, CentOS, Fedora, Amazon Linux). El módulo de Ansible lo envuelve para hacerlo declarativo:

```yaml
- name: install package
  ansible.builtin.yum:
    name: sqlite        # ← Paquete a gestionar
    state: present      # ← Estado deseado: instalado
```

| Parámetro    | Función                                                                  |
| ------------ | ------------------------------------------------------------------------ |
| `name:`      | Nombre del paquete (o lista de paquetes, o URL/path a un `.rpm`)          |
| `state:`     | Estado deseado: `present`, `latest`, `absent`                            |
| `enablerepo:`| Habilitar un repo específico solo para esta operación                    |
| `disablerepo:`| Deshabilitar un repo                                                     |
| `update_cache:`| Refrescar la metadata de repos antes de instalar                       |
| `exclude:`   | Paquetes a excluir de la operación                                       |

### Los `state` del módulo yum — qué hace cada uno

| `state`    | Comportamiento                                                              | Idempotente |
| ---------- | --------------------------------------------------------------------------- | ----------- |
| `present`  | Instala **si no está**; si ya está, no hace nada                            | Sí          |
| `installed`| Alias de `present`                                                          | Sí          |
| `latest`   | Instala si falta; **actualiza** a la última versión si hay una más nueva    | Parcial*    |
| `absent`   | **Desinstala** el paquete si está presente                                  | Sí          |
| `removed`  | Alias de `absent`                                                          | Sí          |

*`latest` es idempotente solo si no hay actualizaciones disponibles; si aparece una versión nueva, marcará `changed` en el próximo run.

Para este lab se usa **`present`**: garantiza que `sqlite` esté instalado sin forzar una versión específica.

### `present` vs `latest` — la diferencia que importa en producción

```yaml
state: present    # "Que exista" — no toca la versión si ya está instalado
state: latest     # "Que sea la última" — actualiza en cada run si hay versión nueva
```

- **`present`**: estable y predecible. Una vez instalado, runs futuros no lo tocan (`changed=0`). Ideal cuando solo importa que el paquete **exista**.
- **`latest`**: mantiene el paquete actualizado, pero introduce **no-determinismo** — el mismo playbook puede cambiar el sistema entre runs según los repos. Riesgoso para reproducibilidad.

Regla práctica: usar `present` salvo que se necesite explícitamente la última versión. Para versiones exactas: `name: sqlite-3.34.1`.

### Idempotencia del módulo yum

Como el `copy` del Día 84 (y a diferencia del `touch` del Día 83), `yum` es **idempotente de verdad**:

```
# Primera corrida (sqlite no instalado):
stapp01 : ok=2  changed=1   ← lo instaló

# Segunda corrida (ya instalado):
stapp01 : ok=2  changed=0   ← no hizo nada, ya estaba present
```

El módulo consulta la base de datos RPM, ve si el paquete ya está, y solo actúa si falta. El `changed=1` del output del lab confirma que **fue la primera instalación** en los tres servers.

### `become: true` — instalar paquetes requiere root

Instalar software es una operación privilegiada — modifica `/usr/bin`, la base de datos RPM, etc. Sin `become`, falla con permisos:

```yaml
- hosts: all
  become: true        # ← sudo para que yum pueda instalar
```

Este es el tercer lab seguido donde `become` es necesario (Días 84, 85, 87) — patrón claro: **toda operación que modifica el sistema** (no solo `/tmp`) lo necesita.

### `yum` vs `dnf` vs `package` vs `apt` — elegir el módulo correcto

| Módulo     | Para                                            | Distros                          |
| ---------- | ----------------------------------------------- | -------------------------------- |
| `yum`      | Gestor clásico RHEL                             | RHEL/CentOS 7, Amazon Linux      |
| `dnf`      | Sucesor de yum (más rápido, mejor resolución)   | RHEL/CentOS 8+, Fedora           |
| `apt`      | Gestor Debian                                   | Debian, Ubuntu                   |
| `package`  | **Genérico** — detecta el gestor automáticamente| Cualquiera (portable)            |

El lab pide explícitamente `yum`. En RHEL 8+, `yum` es en realidad un **symlink a `dnf`** — el módulo `yum` de Ansible funciona igual y delega en `dnf` por debajo.

Para playbooks portables entre distros, `package` es más robusto:

```yaml
- name: install sqlite (portable)
  ansible.builtin.package:
    name: sqlite
    state: present
```

### `ansible.builtin.yum` — el FQCN

`ansible.builtin.yum` es el **Fully Qualified Collection Name**: `<namespace>.<collection>.<module>`. Desde Ansible 2.10, los módulos viven en **collections**. `ansible.builtin` es la collection core que siempre está disponible.

```yaml
ansible.builtin.yum:    # FQCN explícito (recomendado, evita ambigüedad)
yum:                    # Forma corta (funciona, resuelve a ansible.builtin.yum)
```

Ambas funcionan; el FQCN es la **buena práctica** moderna porque evita colisiones si dos collections definen un módulo con el mismo nombre.

## Pasos

1. Login al jump host como `thor`
2. Crear `/home/thor/playbook/inventory` con los 3 app servers
3. Validar conectividad: `ansible -i inventory all -m ping`
4. Crear `/home/thor/playbook/playbook.yml` con `hosts: all`, `become: true` y el módulo `yum`
5. Correr `ansible-playbook -i inventory playbook.yml`
6. Validar la instalación en los hosts

## Comandos / Código

### 1. Crear el inventario

```bash
cat > /home/thor/playbook/inventory <<'EOF'
stapp01 ansible_user=tony ansible_ssh_pass=Ir0nM@n ansible_ssh_common_args='-o StrictHostKeyChecking=no'
stapp02 ansible_user=steve ansible_ssh_pass=Am3ric@ ansible_ssh_common_args='-o StrictHostKeyChecking=no'
stapp03 ansible_user=banner ansible_ssh_pass=BigGr33n ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
```

> Si ya se configuró passwordless SSH (Día 86), el inventario puede ser solo `stappNN ansible_user=...` sin passwords.

### 2. Crear el playbook

```yaml
# /home/thor/playbook/playbook.yml
- hosts: all
  become: true
  tasks:
    - name: install package
      ansible.builtin.yum:
        name: sqlite
        state: present
```

### 3. Ejecutar el playbook

```bash
ansible-playbook -i inventory playbook.yml
```

Output real del lab:

```
PLAY [all] *****************************************************************

TASK [Gathering Facts] *****************************************************
ok: [stapp03]
ok: [stapp02]
ok: [stapp01]

TASK [install package] *****************************************************
changed: [stapp03]
changed: [stapp01]
changed: [stapp02]

PLAY RECAP *****************************************************************
stapp01    : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
stapp02    : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
stapp03    : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`changed=1` en los tres → sqlite se instaló (primera vez). Una segunda corrida mostraría `changed=0`.

### 4. Validar la instalación

```bash
# Vía Ansible — verificar en los 3 de una vez
ansible -i inventory all -m shell -a "rpm -q sqlite" --become

# Output esperado por host:
# stapp01: sqlite-3.x.x-x.el8.x86_64
```

O con el módulo `command`:

```bash
ansible -i inventory all -m command -a "sqlite3 --version" --become
```

## Variantes (referencia)

### Instalar múltiples paquetes (lista)

```yaml
- name: install varios paquetes
  ansible.builtin.yum:
    name:
      - sqlite
      - git
      - vim
    state: present
```

Pasar una lista a `name:` es más eficiente que un `loop:` — yum resuelve todas las dependencias en **una sola transacción**.

### Asegurar la última versión + refrescar cache

```yaml
- name: install latest sqlite con cache fresca
  ansible.builtin.yum:
    name: sqlite
    state: latest
    update_cache: true
```

### Desinstalar un paquete

```yaml
- name: remove sqlite
  ansible.builtin.yum:
    name: sqlite
    state: absent
```

### Versión portable con `package`

```yaml
- name: install sqlite en cualquier distro
  ansible.builtin.package:
    name: sqlite
    state: present
```

## Troubleshooting

| Problema                                                         | Causa                                                                       | Solución                                                                            |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `You need to be root to perform this command`                    | Falta `become: true` — instalar requiere privilegios                        | Agregar `become: true` al play                                                      |
| `No package sqlite available`                                    | El repo no tiene el paquete o la cache está vieja                           | `update_cache: true` o verificar repos con `yum repolist`                           |
| `Failed to download metadata for repo`                           | El host no tiene acceso a internet / repos mal configurados                 | Verificar conectividad y `/etc/yum.repos.d/`                                        |
| `changed=0` y se esperaba `changed=1`                            | El paquete ya estaba instalado — comportamiento idempotente normal          | Confirmar con `rpm -q sqlite`; no es error                                          |
| `This command has to be run under the root user` con sudo password| El user necesita password de sudo y no se proveyó                          | En los labs suele haber sudo NOPASSWD; si no, romper la regla "sin args" no es opción |
| `The Python 2 yum module is needed for this module`              | El host usa Python sin el binding de yum/dnf                                | Fijar `ansible_python_interpreter` al Python que tiene el módulo del gestor         |
| `unreachable` en un host                                         | Credenciales/SSH incorrectos                                                | `ansible all -m ping -i inventory` para aislar                                      |
| Playbook funciona con `--become` pero no sin args                | La validación corre sin `--become`; el `become` debe estar **en el play**   | Poner `become: true` dentro del playbook, no en la línea de comando                 |

## Conexión con días anteriores

- **Días 84-85 (`copy`, `file`)**: gestionaban archivos. Hoy se sube un nivel — gestionar **paquetes del sistema**, la base de cualquier provisioning.
- **Día 86 (passwordless SSH)**: el pre-requisito que hace que este playbook corra sin pedir password. El inventario de hoy puede aprovechar las llaves ya instaladas.
- **Idempotencia (Día 84)**: `yum` con `state: present` es idempotente igual que `copy` — re-runs dan `changed=0`. Contrasta con el `touch` del Día 83 (siempre `changed`).
- **Día 68 (Install Jenkins)**: el paralelo manual — ahí se instaló Jenkins con `apt` a mano sobre un solo server; hoy Ansible hace lo mismo declarativamente sobre toda la flota.

## Reflexión: gestión de paquetes declarativa vs imperativa

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- yum state: present (declarativo: "que exista") vs un `ssh host 'yum install -y sqlite'` (imperativo: "instalalo"): la diferencia operacional al correr 10 veces. ¿Por qué importa que yum consulte el estado antes de actuar?
- present vs latest: el trade-off entre "reproducible" y "actualizado". ¿Cuál elegirías para un server de producción y por qué? ¿El no-determinismo de latest es aceptable en algún contexto?
- yum vs package (genérico): el lab pidió yum explícito, atando el playbook a RHEL. ¿Vale la pena escribir siempre portable con package, o es over-engineering si sé que toda mi flota es RHEL?
- become en 3 labs seguidos (84, 85, 87): el patrón "modificar el sistema = root". ¿Hay un riesgo en normalizar become: true a nivel de play completo en vez de por-task?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`yum` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/yum_module.html)
- [`dnf` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/dnf_module.html)
- [`package` module (genérico)](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/package_module.html)
- [Managing packages with Ansible](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html)
- [FQCN y collections](https://docs.ansible.com/ansible/latest/collections_guide/collections_using.html)
