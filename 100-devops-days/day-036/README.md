# Día 36 - Desplegar contenedor Nginx con Docker

## Problema / Desafío

El equipo DevOps de Nautilus necesita desplegar un contenedor Nginx en el App Server 3 (`stapp03`). Requisitos:

- Crear un contenedor llamado `nginx_3`
- Usar la imagen `nginx` con el tag `alpine`
- El contenedor debe estar en estado `running`

## Conceptos clave

### Imagen vs Contenedor

```
Imagen (nginx:alpine)     →   Contenedor (nginx_3)
  plantilla de solo        →   instancia en ejecución
  lectura                      con su propio filesystem,
                               red y proceso
```

Una imagen puede generar múltiples contenedores. El tag `alpine` especifica qué variante de la imagen usar.

### nginx:alpine vs nginx:latest

| | `nginx:alpine` | `nginx:latest` |
|--|----------------|----------------|
| Base OS | Alpine Linux | Debian |
| Tamaño | ~40 MB | ~190 MB |
| Uso en producción | Muy común | Menos preferido |
| Superficie de ataque | Mínima | Mayor |

### Flags de docker run

| Flag | Significado |
|------|-------------|
| `-d` | Detached — libera la terminal, el contenedor corre en background |
| `--name` | Nombre propio del contenedor (sin esto Docker asigna uno random) |
| `-p <host>:<container>` | Mapea un puerto del host a un puerto del contenedor |

### daemon off en Nginx

El proceso principal de Nginx normalmente se lanza en background (daemon). En Docker, el proceso principal debe correr en **foreground** — si termina, el contenedor se detiene. Por eso la imagen oficial usa `nginx -g "daemon off;"` como CMD.

```
docker run nginx:alpine
    ↓
/docker-entrypoint.sh  (inicializa config)
    ↓
nginx -g "daemon off;"  (proceso principal, foreground)
    ↓
contenedor vivo mientras nginx corra
```

## Pasos

1. Verificar que Docker está instalado en App Server 3
2. Ejecutar el contenedor con los parámetros correctos
3. Verificar que está en estado `running`
4. Probar conectividad con `curl localhost`

## Comandos / Código

### 1. Verificar Docker

```bash
docker --version
```

```
Docker version 26.1.3, build b72abbb
```

### 2. Ejecutar el contenedor

```bash
docker run -d -p 80:80 --name nginx_3 nginx:alpine
```

```
9f781b2ce076c046f6b07d5e087fa20efb1030361849f48b6677831d457fe0ee
```

Docker imprime el ID completo del contenedor al crearlo.

### 3. Verificar estado

```bash
docker ps
```

```
CONTAINER ID   IMAGE          COMMAND                  CREATED              STATUS              PORTS                               NAMES
9f781b2ce076   nginx:alpine   "/docker-entrypoint.…"   About a minute ago   Up About a minute   0.0.0.0:80->80/tcp, :::80->80/tcp   nginx_3
```

`STATUS: Up` confirma que el contenedor está `running`.

### 4. Probar conectividad

```bash
curl localhost
```

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
</html>
```

Nginx respondiendo en el puerto 80 del host.

### 5. Inspeccionar el contenedor

```bash
docker inspect 9f781b2ce076
```

```json
{
    "Id": "9f781b2ce076c046f6b07d5e087fa20efb1030361849f48b6677831d457fe0ee",
    "Created": "2026-04-23T10:34:08.947626464Z",
    "Path": "/docker-entrypoint.sh",
    "Args": ["nginx", "-g", "daemon off;"],
    "State": {
        "Status": "running",
        "Running": true,
        "Paused": false,
        "Restarting": false,
        "OOMKilled": false,
        "ExitCode": 0,
        "StartedAt": "2026-04-23T10:34:09.474779414Z"
    }
}
```

`inspect` devuelve todos los metadatos del contenedor en JSON: estado, red, volúmenes, variables de entorno, entrypoint, etc.

## Referencia rápida de comandos Docker útiles

```bash
docker ps                        # contenedores en ejecución
docker ps -a                     # todos los contenedores (incluye detenidos)
docker ps -aq                    # solo los IDs de todos los contenedores
docker logs nginx_3              # logs del contenedor
docker logs $(docker ps -aq -f "name=nginx_3")   # logs filtrando por nombre
docker inspect <id|name>         # metadata completa del contenedor
docker stop nginx_3              # detener el contenedor
docker rm nginx_3                # eliminar el contenedor (debe estar detenido)
docker exec -it nginx_3 sh       # abrir shell dentro del contenedor
```

### Filtros útiles con docker ps -f

```bash
docker ps -f "name=nginx_3"      # filtrar por nombre
docker ps -f "status=running"    # filtrar por estado
docker ps -f "ancestor=nginx"    # filtrar por imagen base
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `port is already allocated` al hacer `-p 80:80` | El puerto 80 del host está ocupado — cambiar el puerto host: `-p 8080:80` |
| `Conflict. The container name "nginx_3" is already in use` | Eliminar el contenedor existente: `docker rm -f nginx_3` |
| Contenedor se detiene inmediatamente | El proceso principal terminó — revisar con `docker logs nginx_3` |
| `docker: permission denied` | Agregar el usuario al grupo docker: `sudo usermod -aG docker $USER` |

## Recursos

- [Docker run - documentación oficial](https://docs.docker.com/engine/reference/commandline/run/)
- [nginx - Docker Hub](https://hub.docker.com/_/nginx)
- [Alpine Linux](https://alpinelinux.org/)
