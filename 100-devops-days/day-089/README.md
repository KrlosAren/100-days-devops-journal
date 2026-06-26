# Día 89 - Ansible Manage Services (módulo `service`: started vs restarted, enabled, idempotencia)

## Problema / Desafío

Los desarrolladores necesitan dependencias instaladas y **corriendo** en los app servers de Stratos DC. Como ahora la instalación de paquetes y la gestión de servicios se hace con Ansible, hay que crear y probar el playbook. La tarea:

1. Crear `/home/thor/ansible/playbook.yml` que instale `httpd` en **todos** los app servers
2. Tras la instalación, **arrancar y habilitar** el servicio `httpd` en todos
3. El inventario `/home/thor/ansible/inventory` ya existe
4. El user `thor` debe poder correr el playbook desde el jump host

Restricción de validación: se corre con `ansible-playbook -i inventory playbook.yml` — **sin argumentos extra**. El `become` debe vivir dentro del playbook.

> **Nota sobre el solape con el Día 88**: este lab es casi un subconjunto del anterior (instalar `httpd` + arrancar servicio), pero **sin** el paso de `blockinfile`. Por eso este día se enfoca en el módulo **`service`** en profundidad — el verdadero protagonista de la tarea. El `curl localhost` de la verificación devuelve la **página de prueba por defecto de Apache** (`<!DOCTYPE html>...`) justamente porque hoy no se crea ningún `index.html` — eso es lo que hacía el `blockinfile` del Día 88.

## Conceptos clave

### El módulo `service` — gestionar el ciclo de vida de un servicio

El módulo `ansible.builtin.service` controla el estado de un servicio del sistema de forma **declarativa e idempotente**:

```yaml
- name: start & enabled
  ansible.builtin.service:
    name: httpd
    state: started
    enabled: yes
```

| Parámetro    | Función                                                                       |
| ------------ | ----------------------------------------------------------------------------- |
| `name:`      | Nombre del servicio (`httpd`, `nginx`, `sshd`, …)                             |
| `state:`     | Estado deseado: `started`, `stopped`, `restarted`, `reloaded`                 |
| `enabled:`   | `yes`/`no` — si arranca automáticamente al bootear                            |
| `daemon_reload:` | Recargar systemd antes de actuar (tras cambiar un unit file)              |

### Los `state` del módulo service — qué hace cada uno

| `state`     | Acción                                                          | ¿Idempotente?                          |
| ----------- | -------------------------------------------------------------- | -------------------------------------- |
| `started`   | Arranca el servicio **si no está corriendo**                  | **Sí** — no toca uno ya corriendo      |
| `stopped`   | Detiene el servicio **si está corriendo**                     | **Sí**                                 |
| `restarted` | **Siempre** detiene y vuelve a arrancar                       | **No** — bouncea en cada corrida       |
| `reloaded`  | Recarga la config **sin** matar el proceso (si el servicio lo soporta) | No (siempre actúa)            |

La distinción clave del día:

```yaml
state: started      # "que esté corriendo" — declarativo, idempotente
state: restarted    # "reinícialo" — imperativo, corre SIEMPRE
```

- **`started`**: el correcto para "asegurar que el servicio esté arriba". En un segundo run, si ya corre, da `ok` (no `changed`). No interrumpe el servicio.
- **`restarted`**: bouncea el servicio en **cada** ejecución del playbook — útil tras un cambio de config, pero un error si solo se quería garantizar que esté arriba (causa downtime innecesario en cada run).

> Regla práctica: usar `started` para garantizar disponibilidad; reservar `restarted` para cuando una config cambió y el servicio **debe** releer (idealmente vía **handler**, ver más abajo).

### `state` vs `enabled` — dos ejes ortogonales

Son dos preguntas independientes:

```
state: started   →  ¿está corriendo AHORA (este boot)?
enabled: yes     →  ¿arrancará SOLO en el PRÓXIMO boot?
```

| `state`   | `enabled` | Resultado                                                        |
| --------- | --------- | --------------------------------------------------------------- |
| `started` | `yes`     | Corre ahora **y** sobrevive reboots ← lo que pide el lab        |
| `started` | `no`      | Corre ahora pero **muere** tras un reboot                        |
| `stopped` | `yes`     | Apagado ahora, pero arrancará en el próximo boot                 |
| `stopped` | `no`      | Apagado ahora y no arranca al bootear                            |

El lab pide explícitamente "start **and** enable" → ambos en el mismo task. Olvidar `enabled: yes` es un bug silencioso: pasa la validación inicial pero el servidor queda caído tras el primer reinicio.

### Idempotencia: la prueba está en el segundo run

```
# Primera corrida (httpd recién instalado, servicio parado):
TASK [start & enabled]
changed: [stapp01]      ← lo arrancó + habilitó

# Segunda corrida (ya corre + ya habilitado):
TASK [start & enabled]
ok: [stapp01]           ← no hizo nada, ya estaba en el estado deseado
```

El `changed=3` del output del lab confirma que **fue la primera vez** que se arrancó en los tres servers. Un `started` idempotente nunca causa downtime en runs repetidos — a diferencia de `restarted`.

### `service` vs `systemd` vs `systemd_service` — elegir el módulo

| Módulo                      | Para                                                                    |
| --------------------------- | ----------------------------------------------------------------------- |
| `ansible.builtin.service`   | **Genérico** — detecta el init system (systemd, SysV, upstart, BSD)     |
| `ansible.builtin.systemd_service` (alias `systemd`) | Específico systemd — expone `daemon_reload`, `masked`, scopes |

`service` es el wrapper portable: en un host con systemd (RHEL 7+), delega en systemd por debajo. Se usa `service` cuando solo se necesita start/stop/enable básico; se baja a `systemd` cuando hace falta algo específico de systemd:

```yaml
- name: recargar unit + reiniciar
  ansible.builtin.systemd:
    name: httpd
    state: restarted
    daemon_reload: true     # ← releer unit files tras editarlos (solo systemd)
```

### El patrón idiomático que falta hoy: **handlers** (`notify`)

Hoy se arranca el servicio en un task normal. Pero el patrón **correcto** para "reiniciar un servicio cuando su config cambió" es el **handler**:

```yaml
tasks:
  - name: desplegar config de httpd
    ansible.builtin.copy:
      src: httpd.conf
      dest: /etc/httpd/conf/httpd.conf
    notify: restart httpd        # ← solo dispara si este task hizo 'changed'

handlers:
  - name: restart httpd
    ansible.builtin.service:
      name: httpd
      state: restarted
```

Diferencia clave:

- Un task con `state: restarted` **siempre** reinicia.
- Un **handler** con `notify` solo reinicia **si el task que lo notifica cambió algo**, y corre **una sola vez al final** del play (aunque lo notifiquen varios tasks).

Esto evita el downtime innecesario de reiniciar en cada run. El lab de hoy no lo requiere (solo "start + enable"), pero es la evolución natural de la gestión de servicios — vale tenerlo en el radar.

### El playbook completo — anatomía

```yaml
- hosts: all              # los 3 app servers
  become: true            # root: instalar y gestionar servicios requiere privilegios
  tasks:
    - name: install packages
      ansible.builtin.yum:        # ← Día 87
        name: httpd
        state: present

    - name: start & enabled
      ansible.builtin.service:    # ← protagonista de hoy
        name: httpd
        state: started
        enabled: yes
```

`become: true` está **en el play** — clave para que la validación corra sin `--become`. Gestionar servicios (start/stop/enable) es una operación privilegiada igual que instalar paquetes.

## Pasos

1. Login al jump host como `thor`; `cd /home/thor/ansible`
2. Validar conectividad: `ansible -i inventory all -m ping`
3. Crear `/home/thor/ansible/playbook.yml` con dos tasks: `yum` (instalar) → `service` (arrancar + habilitar)
4. Correr `ansible-playbook -i inventory playbook.yml`
5. Validar que el servicio está `active` y `enabled` en los 3 hosts

## Comandos / Código

### Playbook (solución utilizada)

```yaml
# /home/thor/ansible/playbook.yml
- hosts: all
  become: true
  tasks:
    - name: install packages
      ansible.builtin.yum:
        name: httpd
        state: present

    - name: start & enabled
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: yes

    - name: probe httpd
      ansible.builtin.shell: |
        curl localhost
      register: server_content

    - name: server ok
      ansible.builtin.debug:
        var: server_content.stdout[:30]
```

### Ejecutar el playbook

```bash
ansible-playbook -i inventory playbook.yml
```

Output real del lab (recortado):

```
TASK [install packages] ********************************
changed: [stapp01]
changed: [stapp02]
changed: [stapp03]

TASK [start & enabled] *********************************
changed: [stapp03]
changed: [stapp01]
changed: [stapp02]

TASK [probe httpd] *************************************
changed: [stapp01]
changed: [stapp02]
changed: [stapp03]

TASK [server ok] **************************************
ok: [stapp01] => {
    "server_content.stdout[:30]": "<!DOCTYPE html>\n<html lang=\"en"
}

PLAY RECAP ********************************************
stapp01  : ok=5  changed=3  unreachable=0  failed=0
stapp02  : ok=5  changed=3  unreachable=0  failed=0
stapp03  : ok=5  changed=3  unreachable=0  failed=0
```

`changed=3` (yum + service + probe). El `<!DOCTYPE html>` es la **página de prueba por defecto de Apache** — no hay `index.html` propio (eso era el Día 88).

> El `[:30]` en `server_content.stdout[:30]` es **slicing de Python/Jinja2**: toma los primeros 30 caracteres del output para no inundar el log con todo el HTML. Truco útil para verificaciones de debug.

### Verificación (alternativas)

```bash
# A. Estado del servicio en los 3 de una vez
ansible -i inventory all -m shell -a "systemctl is-active httpd" --become
ansible -i inventory all -m shell -a "systemctl is-enabled httpd" --become
# esperado: active / enabled

# B. Con el propio módulo service en check mode (no cambia nada, reporta estado)
ansible -i inventory all -m ansible.builtin.service \
  -a "name=httpd state=started enabled=yes" --become --check

# C. Confirmar que responde HTTP
ansible -i inventory all -m uri -a "url=http://localhost" --become
```

## Variantes (referencia)

### Reiniciar solo cuando cambia la config (handler) — el patrón correcto

```yaml
tasks:
  - name: desplegar config
    ansible.builtin.template:
      src: httpd.conf.j2
      dest: /etc/httpd/conf/httpd.conf
    notify: restart httpd

handlers:
  - name: restart httpd
    ansible.builtin.service:
      name: httpd
      state: restarted
```

### Recargar sin downtime (si el servicio lo soporta)

```yaml
- name: reload httpd
  ansible.builtin.service:
    name: httpd
    state: reloaded      # relee config sin matar el proceso (graceful)
```

### Específico de systemd + daemon_reload

```yaml
- name: tras editar un unit file
  ansible.builtin.systemd:
    name: httpd
    state: restarted
    daemon_reload: true
    enabled: true
```

### Gestionar varios servicios con loop

```yaml
- name: arrancar + habilitar varios servicios
  ansible.builtin.service:
    name: "{{ item }}"
    state: started
    enabled: yes
  loop:
    - httpd
    - firewalld
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `Could not find the requested service httpd: host`              | El servicio no existe → `httpd` no está instalado todavía                       | Asegurar que el task `yum` corre **antes** que el `service`                     |
| `Interactive authentication required` / permisos                | Falta `become: true` — gestionar servicios requiere root                        | Agregar `become: true` al play (no en la CLI)                                   |
| El servicio se reinicia en **cada** corrida del playbook         | Se usó `state: restarted` en un task normal                                    | Usar `state: started` (idempotente); reservar `restarted` para handlers         |
| Servidor caído tras un reboot, aunque el playbook pasó           | Falta `enabled: yes` — arrancó pero no quedó habilitado                         | Agregar `enabled: yes` al task `service`                                        |
| `Unable to start service httpd: Job for httpd.service failed`    | Config de httpd inválida o puerto 80 ocupado                                    | `journalctl -u httpd` / `httpd -t` para ver el error real                       |
| `curl localhost` devuelve la página "Testing 123" o el default   | No hay `index.html` propio — es normal en este lab                              | No es error; el contenido propio era el Día 88 (`blockinfile`)                  |
| Funciona con `--become` pero no sin args                        | La validación corre sin `--become`                                            | Poner `become: true` **dentro del play**                                        |
| `daemon-reload` necesario y el servicio no toma cambios          | Se editó un unit file sin recargar systemd                                      | Usar el módulo `systemd` con `daemon_reload: true`                              |

## Conexión con días anteriores

- **Día 88 (blockinfile)**: hoy es casi el mismo stack (`httpd` + `service`) pero **sin** el despliegue de contenido. La verificación lo muestra: `curl` devuelve la página default de Apache porque falta el `index.html` que ayer creaba el `blockinfile`.
- **Día 87 (`yum`)**: el primer task de hoy es idéntico — instalar el paquete. Hoy se construye sobre eso para gestionar su **servicio**.
- **Días 84-85 (`copy`, `file`)**: gestionaban archivos; Día 87 paquetes; hoy **servicios** — la tercera categoría del trío clásico de provisioning: *paquete → archivo de config → servicio*.
- **Día 68 (Install Jenkins a mano)**: el contraste imperativo — ahí se arrancó un servicio con `systemctl start jenkins` por SSH; hoy Ansible declara el estado deseado (`started` + `enabled`) sobre toda la flota, idempotentemente.

## Reflexión: declarar estado vs ejecutar comandos

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- started vs restarted: started es "que esté arriba" (idempotente), restarted es "reinícialo" (corre siempre). ¿Por qué importa en producción la diferencia? ¿Qué pasa si un playbook con restarted corre cada hora por cron sobre 50 servers?
- handlers (notify) vs un task con restarted: el patrón correcto reinicia solo si la config cambió. ¿Vale la complejidad del handler para este lab simple, o es over-engineering hasta que haya una config que cambie?
- state + enabled como dos ejes ortogonales: olvidar enabled: yes pasa la validación pero deja el server caído tras un reboot. ¿Es un buen ejemplo de "el test verde no garantiza correctitud"?
- service genérico vs systemd específico: ¿escribir siempre el genérico portable, o asumir systemd porque toda la flota es RHEL? Mismo dilema que yum vs package (Día 87).
- el solape con Día 88: tres labs casi iguales (87, 88, 89). ¿Qué aporta repetir? ¿Refuerza el patrón paquete→archivo→servicio o es redundante?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`service` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)
- [`systemd` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/systemd_service_module.html)
- [Handlers: running operations on change](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)
- [`yum` module reference](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/yum_module.html)
- [Intro to playbooks](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html)
