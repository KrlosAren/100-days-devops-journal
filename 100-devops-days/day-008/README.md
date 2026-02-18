# Día 08 - Instalar Ansible con pip3 disponible para todos los usuarios

## Problema / Desafío

Instalar Ansible versión `4.10.0` usando `pip3` y asegurar que el binario de Ansible esté disponible globalmente en todo el sistema, de manera que todos los usuarios puedan ejecutar el comando `ansible`.

## Conceptos clave

### pip3 install --user vs instalación global

Por defecto, `pip3 install` sin privilegios instala paquetes en el directorio del usuario (`~/.local/lib/pythonX.X/site-packages/`), y los binarios quedan en `~/.local/bin/`. Esto significa que solo el usuario que ejecutó la instalación puede usar el comando.

Para que **todos los usuarios** del sistema puedan ejecutar `ansible`, se necesita una instalación global con `sudo`, que coloca los archivos en rutas del sistema:

| Tipo de instalación | Paquetes en | Binarios en | Quién puede usarlo |
|---------------------|-------------|-------------|---------------------|
| `pip3 install ansible` (sin sudo) | `~/.local/lib/` | `~/.local/bin/` | Solo el usuario actual |
| `sudo pip3 install ansible` | `/usr/local/lib/` o `/usr/lib/` | `/usr/local/bin/` | Todos los usuarios |

### Versión específica con pip

Para instalar una versión exacta de un paquete se usa la sintaxis `paquete==versión`:

```bash
pip3 install ansible==4.10.0
```

El doble `==` es importante. Un solo `=` da error de sintaxis en pip.

### Ansible: paquete vs ansible-core

A partir de Ansible 2.10, el proyecto se dividió en dos paquetes:

| Paquete | Qué incluye |
|---------|-------------|
| `ansible` | Paquete completo: `ansible-core` + colecciones de la comunidad (módulos para AWS, Azure, Docker, etc.) |
| `ansible-core` | Solo el motor de Ansible y los módulos built-in básicos |

`ansible==4.10.0` instala el paquete completo, que internamente incluye `ansible-core` 2.11.x.

## Pasos

1. Verificar que `pip3` está disponible en el sistema
2. Instalar Ansible 4.10.0 con `pip3 install` como root para instalación global
3. Verificar que el binario está en `/usr/local/bin/`
4. Verificar la versión instalada
5. Confirmar que otros usuarios pueden ejecutar `ansible`
6. Si algún usuario no encuentra el binario, crear symlink en `/usr/bin/`

## Comandos / Código

### Verificar pip3

```bash
pip3 --version
```

```
pip 21.x.x from /usr/lib/python3.x/site-packages/pip (python 3.x)
```

Si `pip3` no está instalado:

```bash
# En CentOS/RHEL
sudo yum install python3-pip -y

# En Ubuntu/Debian
sudo apt install python3-pip -y
```

### Instalar Ansible globalmente

```bash
sudo pip3 install ansible==4.10.0
```

El `sudo` es clave: sin él, la instalación queda solo para el usuario actual y no cumple el requisito de disponibilidad global.

### Verificar la instalación

```bash
# Verificar la versión
ansible --version
```

```
ansible [core 2.11.x]
  config file = None
  configured module search path = ['/root/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/local/lib/python3.x/dist-packages/ansible
  executable location = /usr/local/bin/ansible
  python version = 3.x.x
```

Lo importante es verificar que `executable location` apunte a `/usr/local/bin/ansible` (ruta del sistema) y no a `~/.local/bin/ansible` (ruta del usuario).

```bash
# Verificar dónde quedó el binario
which ansible
```

```
/usr/local/bin/ansible
```

```bash
# Verificar que /usr/local/bin está en el PATH del sistema
echo $PATH
```

`/usr/local/bin` generalmente está incluido en el PATH por defecto en la mayoría de distribuciones Linux. Sin embargo, **algunos usuarios como root pueden no tenerlo** (ver sección siguiente).

### Problema encontrado: root no encuentra ansible

Al cambiar a root con `sudo su`, el comando `ansible` no se encuentra:

```bash
thor@jumphost ~$ sudo su
root@jumphost /home/thor# ansible --version
bash: ansible: command not found
```

Esto ocurre porque el PATH de root no incluye `/usr/local/bin`:

```bash
root@jumphost /home/thor# echo $PATH
/root/.local/bin:/root/bin:/sbin:/bin:/usr/sbin:/usr/bin
```

El binario existe y funciona si se invoca con ruta completa:

```bash
root@jumphost /home/thor# /usr/local/bin/ansible --version
ansible [core 2.11.12]
  ...
  executable location = /usr/local/bin/ansible
```

### Solución: crear symlink en /usr/bin

Para que el binario esté disponible en una ruta que **todos** los usuarios tienen en su PATH (`/usr/bin`):

```bash
ln -s /usr/local/bin/ansible /usr/bin/ansible
```

Verificar:

```bash
root@jumphost /home/thor# ansible --version
ansible [core 2.11.12]
```

### Por qué `sudo su` tiene un PATH diferente

`sudo su` (sin guion) hereda un PATH restringido que no incluye `/usr/local/bin`. La diferencia:

| Comando | PATH incluye `/usr/local/bin` | Tipo de shell |
|---------|-------------------------------|---------------|
| `sudo su` | No | Shell sin login (hereda entorno parcial) |
| `sudo su -` | Depende de la distribución | Shell con login (carga `/etc/profile`) |
| `sudo -i` | Depende de la distribución | Shell con login |

La solución con symlink en `/usr/bin` es la más robusta porque `/usr/bin` está en el PATH de **todas** las variantes.

### Verificar la versión exacta del paquete

```bash
pip3 show ansible
```

```
Name: ansible
Version: 4.10.0
Summary: Radically simple IT automation
Location: /usr/local/lib/python3.x/dist-packages
Requires: ansible-core
```

## Alternativas de instalación

### Opción 1: pip3 con sudo (solución utilizada)

```bash
sudo pip3 install ansible==4.10.0
```

Instalación directa en las rutas del sistema. Simple y efectiva.

### Opción 2: pip3 sin sudo + symlink manual

Si no se quiere o puede usar `sudo pip3`:

```bash
# Instalar como usuario
pip3 install ansible==4.10.0

# Crear symlink en ruta del sistema
sudo ln -s ~/.local/bin/ansible /usr/local/bin/ansible
sudo ln -s ~/.local/bin/ansible-playbook /usr/local/bin/ansible-playbook
```

Desventaja: hay que crear un symlink por cada binario de Ansible (`ansible`, `ansible-playbook`, `ansible-galaxy`, `ansible-vault`, etc.).

### Opción 3: Instalar con el gestor de paquetes del sistema

```bash
# CentOS/RHEL (puede no tener la versión exacta)
sudo yum install ansible -y

# Ubuntu/Debian
sudo apt install ansible -y
```

Desventaja: no siempre está disponible la versión específica requerida.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `ansible: command not found` después de instalar sin sudo | La instalación quedó en `~/.local/bin/`. Reinstalar con `sudo pip3 install ansible==4.10.0` |
| `pip3: command not found` | Instalar pip3: `sudo yum install python3-pip -y` (CentOS) o `sudo apt install python3-pip -y` (Ubuntu) |
| `ERROR: Could not find a version that satisfies the requirement ansible==4.10.0` | Verificar conectividad a internet. Si pip está desactualizado, actualizar con `sudo pip3 install --upgrade pip` |
| Otro usuario no puede ejecutar `ansible` | Verificar que el binario está en `/usr/local/bin/` con `which ansible`. Si `/usr/local/bin` no está en el PATH del usuario, crear symlink: `ln -s /usr/local/bin/ansible /usr/bin/ansible` |
| `ansible: command not found` como root con `sudo su` | El PATH de root no incluye `/usr/local/bin`. Crear symlink en `/usr/bin/`: `ln -s /usr/local/bin/ansible /usr/bin/ansible` |
| `WARNING: Running pip as the 'root' user` | Es un warning, no un error. Aparece al usar `sudo pip3`. En este caso es el comportamiento esperado |
| Conflicto de versiones con Ansible ya instalado | Desinstalar primero: `sudo pip3 uninstall ansible -y && sudo pip3 install ansible==4.10.0` |

## Recursos

- [Installing Ansible - Ansible Docs](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [pip install - pip Docs](https://pip.pypa.io/en/stable/cli/pip_install/)
- [Ansible package vs ansible-core](https://docs.ansible.com/ansible/latest/reference_appendices/release_and_maintenance.html)
