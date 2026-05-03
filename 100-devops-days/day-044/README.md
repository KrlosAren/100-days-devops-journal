# Día 44 - Escribir un Docker Compose File

## Problema / Desafío

El equipo de desarrollo de Nautilus comparte contenido estático que debe ser servido desde un contenedor `httpd` en App Server 1 (`stapp01`). Requisitos:

- Crear el archivo `/opt/docker/docker-compose.yml` (nombre exacto)
- Usar la imagen `httpd:latest`
- Nombrar el contenedor `httpd` (el nombre del servicio puede ser cualquiera)
- Mapear el puerto `80` del contenedor al `3000` del host
- Montar `/opt/itadmin` del host en `/usr/local/apache2/htdocs` del contenedor (sin modificar datos)

## Conceptos clave

### ¿Qué es Docker Compose?

Docker Compose es un plugin de Docker para orquestar contenedores. Llega un punto donde un contenedor ya no es un simple `docker run` — necesita volumes, redes, variables de entorno, puertos, configs, comandos de start, dependencias entre servicios, etc. Mantener todo eso en flags de CLI se vuelve frágil y poco reproducible.

Con Compose escribes un archivo YAML que describe el stack completo (uno o varios contenedores + sus redes y volúmenes) y lo levantas con un solo comando. El archivo entra a git, se versiona, y todo el equipo arranca el mismo entorno con `docker compose up`.

### Compose v1 vs Compose v2

| | Compose v1 (legacy) | Compose v2 (actual) |
|---|---|---|
| Binario | `docker-compose` (Python, separado) | `docker compose` (plugin de Docker, en Go) |
| Sintaxis CLI | `docker-compose up` | `docker compose up` (sin guion) |
| Estado | Deprecado | Estándar actual |

Ambos leen el mismo formato de YAML. La diferencia es solo cómo se invocan.

### Anatomía mínima de un docker-compose.yml

```yaml
services:           # bloque raíz: contenedores que forman el stack
  <nombre_servicio>:    # alias interno (DNS dentro de la red de compose)
    image: ...          # imagen a usar
    container_name: ... # nombre del contenedor en docker ps (opcional)
    ports:              # puertos a publicar (formato "host:contenedor")
      - "..."
    volumes:            # bind mounts o named volumes (formato "host:contenedor")
      - "..."
```

**Servicio vs contenedor:** el "servicio" es el alias lógico dentro de Compose (usado para DNS interno entre servicios y para comandos como `docker compose logs <servicio>`). El `container_name` es lo que aparece en `docker ps`. Si no defines `container_name`, Compose genera uno tipo `<proyecto>_<servicio>_1`.

### Bind mount (`/opt/itadmin:/usr/local/apache2/htdocs`)

Cuando el lado izquierdo es una ruta absoluta del host, Docker hace un *bind mount*: el directorio del host se monta directamente sobre la ruta del contenedor. Cualquier cambio en el host se ve inmediatamente dentro del contenedor y viceversa.

```
Host:                          Contenedor:
/opt/itadmin/index1.html  ◄──► /usr/local/apache2/htdocs/index1.html
```

Esto sobrescribe lo que la imagen `httpd` traía en `/usr/local/apache2/htdocs` (la página de bienvenida "It works!"). Por eso el `curl` final muestra el contenido de `/opt/itadmin`, no el default de Apache.

## Pasos

1. Verificar que docker compose está instalado
2. Crear el archivo `/opt/docker/docker-compose.yml`
3. Levantar el stack con `docker compose up -d`
4. Verificar que el contenedor está corriendo
5. Probar el acceso con `curl`

## Comandos / Código

### 1. Verificar instalación de Compose

```bash
docker compose version
```

```
Docker Compose version v5.0.2
```

### 2. Escribir `/opt/docker/docker-compose.yml`

```yaml
services:
  httpd:
    image: httpd:latest
    container_name: httpd
    ports:
      - "3000:80"
    volumes:
      - /opt/itadmin:/usr/local/apache2/htdocs
```

Notas sobre la sintaxis:

- `"3000:80"` se escribe entre comillas para evitar que YAML lo interprete como notación sexagesimal (el problema clásico es `22:22`, que YAML parsea como número en base 60). Con comillas siempre es string.
- El servicio se llama `httpd` por simplicidad, pero podría llamarse `web`, `apache` o cualquier cosa — el lab solo pide que el `container_name` sea `httpd`.

### 3. Levantar el stack

```bash
docker compose up -d
```

`-d` (detached) corre los contenedores en background. Sin `-d`, Compose ocupa la terminal mostrando los logs combinados de todos los servicios y `Ctrl+C` los detiene. Por default Compose busca un archivo llamado `docker-compose.yml` o `compose.yml` en el directorio actual.

### 4. Verificar el contenedor

```bash
docker ps
```

```
CONTAINER ID   IMAGE          COMMAND              CREATED         STATUS          PORTS                                   NAMES
60d1791c2fec   httpd:latest   "httpd-foreground"   2 minutes ago   Up 21 seconds   0.0.0.0:3000->80/tcp, :::3000->80/tcp   httpd
```

El comando `httpd-foreground` confirma que Apache corre en foreground (sin daemonizarse) — necesario para que el contenedor no termine al iniciar.

### 5. Probar el acceso

```bash
curl localhost:3000
```

```html
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
 <head>
  <title>Index of /</title>
 </head>
 <body>
<h1>Index of /</h1>
<ul><li><a href="index1.html"> index1.html</a></li>
</ul>
</body></html>
```

El listado de directorio (`Index of /`) confirma dos cosas:

1. El bind mount funciona: Apache está sirviendo el contenido de `/opt/itadmin` (que solo tiene `index1.html`).
2. No existe un `index.html` por default, así que `mod_autoindex` genera el listado automáticamente. Si hubiera un `index.html`, Apache lo serviría en lugar del listado.

## Comparación: `docker run` vs `docker compose`

El compose file de arriba es equivalente a un `docker run` con varios flags. Escribir ambos uno al lado del otro ayuda a entender qué hace cada línea del YAML.

```bash
docker run -p 3000:80 --name httpd -v /opt/itadmin:/usr/local/apache2/htdocs -d httpd:latest
```

Mapeo línea por línea con el YAML:

| Compose | docker run |
|---|---|
| `image: httpd:latest` | `httpd:latest` (último argumento) |
| `container_name: httpd` | `--name httpd` |
| `ports: - "3000:80"` | `-p 3000:80` |
| `volumes: - /opt/itadmin:/usr/local/apache2/htdocs` | `-v /opt/itadmin:/usr/local/apache2/htdocs` |
| (Compose `up -d`) | `-d` |

Verificación de que el `docker run` produce el mismo resultado que el compose:

```bash
docker run -p 3000:80 --name httpd -v /opt/itadmin:/usr/local/apache2/htdocs -d httpd:latest
# 011db3d972e43c4a3da9015269b2ba7ecacadfc413b114c1063df580d9027447

curl localhost:3000
```

```html
<h1>Index of /</h1>
<ul><li><a href="index2.html"> index2.html</a></li></ul>
```

Apache sirve el contenido de `/opt/itadmin` (en este host hay un `index2.html` en lugar de `index1.html`), confirmando que el bind mount funciona idéntico al de Compose.

| Aspecto | `docker run` | `docker compose` |
|---|---|---|
| Configuración | Flags en la línea de comando | Archivo YAML versionable |
| Múltiples contenedores | Un comando por contenedor | Todos en el mismo archivo |
| Reproducibilidad | Hay que recordar/scriptear los flags | El archivo es la fuente de verdad |
| Red entre contenedores | Crear red manual + `--network` | Compose crea una red default automáticamente |
| Reinicio del stack | Cada contenedor por separado | `docker compose down && up` |

## Comandos útiles del ciclo de vida

```bash
docker compose up -d            # levantar en background
docker compose ps               # listar contenedores del stack actual
docker compose logs -f httpd    # seguir logs de un servicio
docker compose stop             # detener sin eliminar
docker compose down             # detener y eliminar contenedores + red
docker compose down -v          # también elimina los volumes nombrados
docker compose restart httpd    # reiniciar un solo servicio
docker compose config           # validar y mostrar el YAML resuelto
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `yaml: line X: mapping values are not allowed in this context` | Indentación inconsistente (mezcla tabs y espacios, o niveles desalineados). YAML solo acepta espacios — usar 2 espacios por nivel |
| `Bind for 0.0.0.0:3000 failed: port is already allocated` | Otro contenedor o proceso usa el puerto 3000 — `docker ps` o `ss -tlnp \| grep 3000` para identificarlo |
| El contenedor arranca pero `curl` devuelve la página default de Apache | El bind mount no se aplicó — verificar que la ruta del host existe (`ls /opt/itadmin`) y que la sintaxis del volumen es `host:contenedor` (no al revés) |
| `network <proyecto>_default ... has active endpoints` al hacer `docker compose down` | Hay contenedores fuera de Compose conectados a la red — desconectarlos manualmente o usar `docker compose down --remove-orphans` |
| Cambios al YAML no se aplican | `docker compose up -d` solo recrea contenedores cuya config cambió. Si modificaste algo y Compose no lo nota, forzar con `docker compose up -d --force-recreate` |

## Recursos

- [Compose file reference](https://docs.docker.com/compose/compose-file/)
- [docker compose CLI](https://docs.docker.com/compose/reference/)
- [Migrar de v1 a v2](https://docs.docker.com/compose/migrate/)
- [httpd en Docker Hub](https://hub.docker.com/_/httpd)
