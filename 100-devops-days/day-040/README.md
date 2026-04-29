# Día 40 - Docker EXEC: instalar y configurar Apache dentro de un contenedor

## Problema / Desafío

Un miembro del equipo DevOps dejó trabajo pendiente en el contenedor `kkloud` en App Server 2 (`stapp02`). Se debe:

- Instalar `apache2` dentro del contenedor usando `apt`
- Configurar Apache para escuchar en el puerto `6300` (en lugar del `80` por defecto)
- El servidor debe escuchar en todas las interfaces (localhost, 127.0.0.1, IP del contenedor), no solo en una específica
- Dejar Apache corriendo y el contenedor en estado activo

## Conceptos clave

### docker exec

`docker exec` ejecuta un comando dentro de un contenedor en ejecución sin crear un nuevo proceso principal.

```bash
docker exec -it <container_id|name> <comando>
#            │└─ tty: asigna una terminal
#            └── interactive: mantiene stdin abierto
```

Con `/bin/bash` se obtiene una shell completa dentro del contenedor para ejecutar múltiples comandos en secuencia.

### service vs systemctl en contenedores

En un contenedor, PID 1 es el proceso definido en la imagen (en este caso `/bin/bash`), no `systemd`. Como `systemctl` requiere que systemd esté corriendo como PID 1, el comando falla en la mayoría de contenedores.

`service` es un wrapper que invoca directamente los scripts en `/etc/init.d/` sin depender de init, por lo que funciona dentro de contenedores:

```bash
service apache2 start    # ✅ funciona en contenedores
systemctl start apache2  # ❌ falla sin systemd
```

### Configuración de puertos en Apache

Cambiar el puerto en Apache requiere modificar dos archivos para que sean consistentes:

| Archivo | Qué define |
|---------|-----------|
| `/etc/apache2/ports.conf` | En qué puerto(s) escucha el daemon de Apache |
| `/etc/apache2/sites-enabled/000-default.conf` | El VirtualHost que recibe las conexiones en ese puerto |

Si solo se cambia `ports.conf`, Apache escucha en el nuevo puerto pero no tiene VirtualHost configurado para él — las conexiones llegan pero no se procesan. Ambos deben coincidir.

### Listen sin IP específica

La directiva `Listen 6300` (sin IP) hace que Apache escuche en todas las interfaces de red disponibles.

```
Listen 6300          # escucha en todas las interfaces ✅
Listen 127.0.0.1:6300  # solo localhost ❌ (no cumple el requisito)
Listen 0.0.0.0:6300    # equivalente a sin IP, pero explícito
```

## Pasos

1. Verificar el contenedor en ejecución
2. Entrar al contenedor con `docker exec`
3. Instalar `apache2` y `vim` con `apt`
4. Editar `/etc/apache2/ports.conf`: cambiar `Listen 80` → `Listen 6300`
5. Editar `/etc/apache2/sites-enabled/000-default.conf`: cambiar `<VirtualHost *:80>` → `<VirtualHost *:6300>`
6. Iniciar Apache con `service apache2 start`
7. Verificar que Apache está corriendo y escucha en el puerto correcto

## Comandos / Código

### 1. Verificar el contenedor

```bash
docker ps
```

```
CONTAINER ID   IMAGE          COMMAND       CREATED         STATUS         PORTS     NAMES
d4771693a8b1   ubuntu:18.04   "/bin/bash"   2 minutes ago   Up 2 minutes             kkloud
```

### 2. Entrar al contenedor

```bash
docker exec -it d4771693a8b1 /bin/bash
```

### 3. Instalar apache2 y vim

```bash
apt update && apt install -y apache2 vim
```

### 4. Editar ports.conf

```bash
vim /etc/apache2/ports.conf
```

Cambiar:
```
Listen 80
```
Por:
```
Listen 6300
```

### 5. Editar el VirtualHost

```bash
vim /etc/apache2/sites-enabled/000-default.conf
```

Cambiar:
```
<VirtualHost *:80>
```
Por:
```
<VirtualHost *:6300>
```

### 6. Iniciar Apache

```bash
service apache2 start
```

```
 * Starting Apache httpd web server apache2   [ OK ]
```

### 7. Verificar

```bash
service apache2 status
curl localhost:6300
```

### Alternativa: editar los archivos con sed (sin vim)

```bash
# Cambiar el puerto en ports.conf
sed -i 's/Listen 80/Listen 6300/' /etc/apache2/ports.conf

# Cambiar el VirtualHost en 000-default.conf
sed -i 's/*:80/*:6300/' /etc/apache2/sites-enabled/000-default.conf
```

`sed -i` edita el archivo in-place (sin crear un archivo temporal). Es preferible a `vim` en scripts o aprovisionamiento remoto donde no hay terminal interactiva.

> **Nota sobre el `*` en sed:** En GNU sed (Linux), `*` al inicio de un patrón se trata como literal. Para mayor portabilidad se puede escapar: `sed -i 's/\*:80/\*:6300/'`. En contextos de scripting o si el comando falla, usar la versión escapada.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `systemctl: command not found` o `Failed to connect to bus` | El contenedor no tiene systemd — usar `service apache2 start` |
| Apache inicia pero no responde en el puerto nuevo | Verificar que `000-default.conf` también fue actualizado a `*:6300` |
| `curl: (7) Failed to connect` | Apache no está corriendo — revisar con `service apache2 status` y los logs en `/var/log/apache2/error.log` |
| `apt update` falla con errores de GPG o repositorio | La imagen `ubuntu:18.04` tiene repos desactualizados — puede requerir `apt update --allow-insecure-repositories` o actualizar los sources |

## Recursos

- [docker exec - documentación oficial](https://docs.docker.com/engine/reference/commandline/exec/)
- [Apache - directiva Listen](https://httpd.apache.org/docs/2.4/bind.html)
- [service vs systemctl en contenedores](https://jpetazzo.github.io/2014/06/23/docker-ssh-considered-evil/)
