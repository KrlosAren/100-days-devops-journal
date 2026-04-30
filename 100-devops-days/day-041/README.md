# Día 41 - Escribir un Dockerfile

## Problema / Desafío

El equipo de desarrollo de Nautilus necesita una imagen personalizada en App Server 3 (`stapp03`). Requisitos:

- Crear `/opt/docker/Dockerfile` con `D` mayúscula
- Imagen base: `ubuntu:24.04`
- Instalar `apache2` y configurarlo para escuchar en el puerto `6100`
- No modificar otras configuraciones de Apache (document root, etc.)

## Conceptos clave

### Dockerfile

Un Dockerfile es el plano de construcción de una imagen Docker. Define, instrucción por instrucción, cómo construir una imagen que luego puede ejecutarse como contenedor. Cada instrucción genera un **layer** (capa) en la imagen final.

### Instrucciones utilizadas

| Instrucción | Función |
|-------------|---------|
| `FROM` | Define la imagen base desde la que se parte |
| `RUN` | Ejecuta un comando durante la construcción de la imagen |
| `EXPOSE` | Documenta en qué puerto escucha el contenedor (no abre el puerto por sí solo) |
| `CMD` | Define el proceso principal que se ejecuta al iniciar el contenedor |

### CMD: exec form vs shell form

`CMD` acepta dos formas:

```dockerfile
# Exec form (recomendada): array JSON con comillas dobles
CMD ["apache2ctl", "-D", "FOREGROUND"]

# Shell form: string, ejecutado vía /bin/sh -c
CMD apache2ctl -D FOREGROUND
```

La diferencia clave está en quién ocupa **PID 1** (el proceso principal del contenedor):

| Forma | PID 1 | Recibe señales del OS (SIGTERM, SIGKILL) |
|-------|-------|------------------------------------------|
| Exec form | El proceso definido directamente | ✅ Sí |
| Shell form | `/bin/sh` (el proceso definido es hijo) | ❌ No directamente |

La exec form es preferible para procesos de larga duración como servidores: garantiza que el proceso reciba señales del sistema (por ejemplo, `docker stop` envía SIGTERM para un shutdown limpio).

> **Error común:** usar comillas simples en exec form. Docker espera un array JSON — las comillas simples no son JSON válido y causan un error al iniciar el contenedor:
> ```dockerfile
> CMD ['apache2ctl','-D','FOREGROUND']   # ❌ SyntaxError: no es JSON válido
> CMD ["apache2ctl","-D","FOREGROUND"]   # ✅ correcto
> ```

### Layers y caché

Cada instrucción `RUN`, `COPY`, `ADD` genera un layer independiente. Docker cachea los layers: si nada cambia en una instrucción ni en las anteriores, reutiliza el layer sin reconstruirlo (`CACHED` en el output del build).

Por eso el orden importa:
- Instrucciones que cambian con poca frecuencia (instalar dependencias) → al inicio
- Instrucciones que cambian frecuentemente (configuración, código) → al final

Esto maximiza los layers cacheados en rebuilds.

### Limpieza de apt en el mismo RUN

```dockerfile
RUN apt-get update && \
    apt-get install -y apache2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
```

La limpieza del cache de apt debe estar **en el mismo `RUN`** que el install. Si se separa en otro `RUN`, los archivos de `apt/lists/` ya quedaron guardados en el layer anterior y no se pueden eliminar retroactivamente — la imagen seguirá siendo grande.

## Pasos

1. Crear la carpeta `/opt/docker/` y el archivo `Dockerfile`
2. Escribir el Dockerfile con las instrucciones requeridas
3. Construir la imagen con `docker build`
4. Verificar que la imagen fue creada correctamente

## Comandos / Código

### Dockerfile

```dockerfile
FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y apache2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN sed -i 's/Listen 80/Listen 6100/' /etc/apache2/ports.conf

RUN sed -i 's/<VirtualHost \*:80>/<VirtualHost *:6100>/' /etc/apache2/sites-enabled/000-default.conf

EXPOSE 6100

CMD ["apache2ctl", "-D", "FOREGROUND"]
```

### Construir la imagen

```bash
# Con tag personalizado
docker build -t apache-server .

# Especificando el Dockerfile explícitamente
docker build -f /opt/docker/Dockerfile -t apache-server .
```

El `.` al final es el **contexto de build**: el directorio desde donde Docker resuelve rutas para instrucciones como `COPY` o `ADD`. En este caso no hay archivos que copiar, pero el contexto es obligatorio.

### Output del build

```
[+] Building 0.3s (8/8) FINISHED
 => [1/4] FROM docker.io/library/ubuntu:24.04                     0.0s
 => CACHED [2/4] RUN apt-get update && apt-get install -y apache2  0.0s
 => CACHED [3/4] RUN sed -i 's/Listen 80/Listen 6100/' ...         0.0s
 => CACHED [4/4] RUN sed -i 's/<VirtualHost \*:80>/...'            0.0s
 => exporting to image                                             0.0s
 => writing image sha256:bc86a7361ea8...                           0.0s
 => naming to docker.io/library/apache-server                      0.0s
```

Los tres `CACHED` confirman que Docker reutilizó layers de una construcción previa — solo el export tardó tiempo real.

### Verificar la imagen

```bash
docker image ls
```

```
REPOSITORY      TAG       IMAGE ID       CREATED              SIZE
apache-server   latest    bc86a7361ea8   About a minute ago   199MB
ubuntu          24.04     602eb6fb314b   12 months ago        78.1MB
```

### Ejecutar el contenedor

```bash
docker run -d -p 6100:6100 apache-server
```

```
cb375bb29dcd52e4918db919c9710bf7f69c2de0c52ffcab9f203245723a5452
```

```bash
docker ps
```

```
CONTAINER ID   IMAGE           COMMAND                  CREATED         STATUS        PORTS                                       NAMES
cb375bb29dcd   apache-server   "apache2ctl -D FOREG…"   2 seconds ago   Up 1 second   0.0.0.0:6100->6100/tcp, :::6100->6100/tcp   sad_lamarr
```

| Flag | Efecto |
|------|--------|
| `-d` | Detached — el contenedor corre en background, libera la terminal |
| `-p 6100:6100` | Publica el puerto: `<puerto_host>:<puerto_contenedor>` |

La columna `COMMAND` muestra `"apache2ctl -D FOREG…"` — es exactamente el `CMD` definido en el Dockerfile ejecutándose como PID 1.

La columna `PORTS` confirma el mapeo: `0.0.0.0:6100->6100/tcp` significa que cualquier IP del host en el puerto 6100 redirige al puerto 6100 del contenedor.

### Sobreescribir CMD para inspección

Cuando la imagen está construida pero queremos explorar su contenido antes de que el servidor arranque, se puede reemplazar el `CMD` desde `docker run`:

```bash
# El comando al final reemplaza el CMD del Dockerfile
docker run -it apache-server bash
```

Esto abre una shell interactiva dentro del contenedor sin iniciar Apache — útil para verificar que los archivos de configuración quedaron correctamente modificados.

## ENTRYPOINT vs CMD

| | `CMD` | `ENTRYPOINT` |
|-|-------|-------------|
| Se puede sobreescribir al ejecutar | ✅ `docker run imagen otro-comando` | ❌ No directamente (requiere `--entrypoint`) |
| Uso típico | Comando por defecto, fácil de reemplazar | Proceso principal fijo del contenedor |
| Se pueden combinar | Sí — `ENTRYPOINT` define el ejecutable, `CMD` define sus argumentos por defecto | |

```dockerfile
# Usando ambos juntos
ENTRYPOINT ["apache2ctl"]
CMD ["-D", "FOREGROUND"]

# docker run imagen                   → apache2ctl -D FOREGROUND
# docker run imagen -D OTHER_FLAG     → apache2ctl -D OTHER_FLAG  (CMD se sobreescribe)
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `unknown instruction` o contenedor no inicia | `CMD` con comillas simples no es JSON válido — usar comillas dobles: `CMD ["comando"]` |
| `EXPOSE` declarado pero el puerto no es accesible | `EXPOSE` solo documenta el puerto — para publicarlo usar `-p 6100:6100` en `docker run` |
| Layer grande aunque se limpió apt | La limpieza de `apt/lists/` debe estar en el **mismo `RUN`** que el install |
| `sed` falla con "no such file" | El archivo de Apache no existe hasta que `apt-get install apache2` corre — verificar el orden de instrucciones |

## Recursos

- [Dockerfile reference](https://docs.docker.com/engine/reference/builder/)
- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [docker build - documentación oficial](https://docs.docker.com/engine/reference/commandline/build/)
