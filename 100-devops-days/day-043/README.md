# Día 43 - Docker Port Mapping

## Problema / Desafío

El equipo de Nautilus necesita exponer una aplicación nginx en App Server 3 (`stapp03`). Requisitos:

- Descargar la imagen `nginx:alpine`
- Crear un contenedor llamado `cluster`
- Mapear el puerto `5004` del host al puerto `80` del contenedor
- Mantener el contenedor en ejecución

## Conceptos clave

### Port mapping (-p)

Por defecto un contenedor está aislado — sus puertos no son accesibles desde el host ni desde la red. El flag `-p` publica un puerto del contenedor en el host:

```bash
docker run -p <puerto_host>:<puerto_contenedor> imagen
```

```
Host (stapp03)                  Contenedor
:5004  ──────────────────────►  :80 (nginx)
```

El orden importa: siempre es `host:contenedor`. Invertirlo es el error más común — `5004:80` expone el 80 del contenedor en el 5004 del host, no al revés.

### -d (detached mode)

Sin `-d`, `docker run` ocupa la terminal mostrando stdout del proceso del contenedor. Al presionar Ctrl+C, el contenedor se detiene.

```bash
# Sin -d: bloquea la terminal, Ctrl+C detiene el contenedor
docker run -p 5004:80 --name cluster nginx:alpine

# Con -d: corre en background, devuelve el container ID
docker run -p 5004:80 --name cluster -d nginx:alpine
```

En modo detached, los logs se acceden con `docker logs`.

### docker logs

Reemplaza la lectura directa de archivos de log cuando el contenedor corre en modo detached:

```bash
docker logs <container_id|name>         # todos los logs
docker logs -f <container_id|name>      # seguir logs en tiempo real (como tail -f)
docker logs --tail 20 <container_id>    # últimas 20 líneas
```

### docker inspect

Muestra la configuración completa de un contenedor en formato JSON: estado, red, puertos, volúmenes, variables de entorno, comando de inicio, etc.

```bash
docker inspect <container_id|name>
```

Para extraer un campo específico sin parsear el JSON completo se usan Go templates con `--format`:

```bash
# IP del contenedor en la red bridge
docker inspect --format "{{ .NetworkSettings.Networks.bridge.IPAddress }}" cluster
# 172.17.0.2

# Estado del contenedor
docker inspect --format "{{ .State.Status }}" cluster
# running

# Puertos publicados (NetworkSettings.Ports — muestra host + contenedor)
docker inspect --format "{{ .NetworkSettings.Ports }}" cluster
# map[80/tcp:[{0.0.0.0 5004} {:: 5004}]]

# Configuración de port bindings (HostConfig.PortBindings)
docker inspect --format "{{ .HostConfig.PortBindings }}" cluster
# map[80/tcp:[{invalid IP 5004}]]
```

> **Nota sobre "invalid IP":** En `HostConfig.PortBindings`, el campo `HostIp` está vacío cuando el puerto está publicado en todas las interfaces (`0.0.0.0`). Go templates intenta renderizar esa cadena vacía como IP y muestra `invalid IP` — no es un error, significa exactamente "sin IP específica → todas las interfaces". `NetworkSettings.Ports` es más legible para este caso.

### nginx:alpine vs nginx

| Imagen | Base | Tamaño aprox. | libc |
|--------|------|--------------|------|
| `nginx:alpine` | Alpine Linux | ~45 MB | musl |
| `nginx` (latest) | Debian | ~190 MB | glibc |

Alpine es la opción estándar cuando no se necesitan herramientas del sistema Debian. La diferencia de ~145 MB importa cuando la imagen se descarga o distribuye frecuentemente.

## Pasos

1. Descargar la imagen con `docker pull`
2. Ejecutar el contenedor con port mapping y nombre
3. Verificar que el contenedor está corriendo
4. Confirmar accesibilidad con `curl`

## Comandos / Código

### 1. Pull de la imagen

```bash
docker pull nginx:alpine
```

```
alpine: Pulling from library/nginx
6a0ac1617861: Pull complete
```

### 2. Ejecutar el contenedor

```bash
docker run -p 5004:80 --name cluster -d nginx:alpine
```

```
aa9b041a1854221c871dac19e67706bd29af809a9658d7f16c1f9dada8770e2e
```

### 3. Verificar el contenedor

```bash
docker ps
```

```
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS         PORTS                                   NAMES
aa9b041a1854   nginx:alpine   "/docker-entrypoint.…"   3 seconds ago   Up 2 seconds   0.0.0.0:5004->80/tcp, :::5004->80/tcp   cluster
```

La columna `PORTS` confirma el mapeo: `0.0.0.0:5004->80/tcp` (IPv4) y `:::5004->80/tcp` (IPv6).

### 4. Ver logs del contenedor

```bash
docker logs aa9b041a1854
```

```
/docker-entrypoint.sh: Configuration complete; ready for start up
2026/05/02 12:51:33 [notice] 1#1: nginx/1.29.8
2026/05/02 12:51:33 [notice] 1#1: start worker processes
...
```

El `1#1` en los logs de nginx indica `worker_id#master_pid` — el master process corre con PID 1, directamente como proceso principal del contenedor.

### 5. Probar el acceso

```bash
curl localhost:5004
```

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
</html>
```

Respuesta HTTP confirma que el mapeo de puertos funciona correctamente.

### 6. Inspeccionar el contenedor

```bash
docker inspect aa9b041a1854
```

El campo `Args` en el output muestra cómo nginx fue iniciado:

```json
"Path": "/docker-entrypoint.sh",
"Args": ["nginx", "-g", "daemon off;"]
```

`daemon off;` indica a nginx que no haga fork al background. Sin esta flag, nginx normalmente se convierte en daemon: el proceso padre termina y los workers quedan como hijos. En un contenedor, si PID 1 (el proceso padre) termina, el contenedor se detiene — por eso todos los servidores en contenedores deben correr en foreground.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `docker: Error response from daemon: Conflict. The container name "/cluster" is already in use` | Ya existe un contenedor con ese nombre — eliminarlo con `docker rm cluster` o usar `docker rm -f cluster` si está corriendo |
| `curl: (7) Failed to connect to localhost port 5004` | El contenedor no está corriendo — verificar con `docker ps -a` y revisar logs con `docker logs cluster` |
| El contenedor se detiene inmediatamente | El proceso principal terminó — revisar con `docker logs cluster` para ver el error |
| Puerto 5004 ya en uso en el host | Otro proceso usa ese puerto — identificarlo con `ss -tlnp \| grep 5004` |

## Recursos

- [docker run - documentación oficial](https://docs.docker.com/engine/reference/commandline/run/)
- [docker logs - documentación oficial](https://docs.docker.com/engine/reference/commandline/logs/)
- [docker inspect - documentación oficial](https://docs.docker.com/engine/reference/commandline/inspect/)
- [nginx:alpine en Docker Hub](https://hub.docker.com/_/nginx)
