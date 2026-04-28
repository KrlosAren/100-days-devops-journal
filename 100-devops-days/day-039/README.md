# Día 39 - Crear imagen Docker desde un contenedor

## Problema / Desafío

Un desarrollador de Nautilus realizó cambios dentro de un contenedor en App Server 3 (`stapp03`) y necesita un respaldo de esos cambios como imagen. El equipo DevOps debe crear la imagen `cluster:datacenter` a partir del contenedor `ubuntu_latest` en ejecución.

## Conceptos clave

### docker commit

`docker commit` captura el estado actual del filesystem de un contenedor y lo guarda como una nueva imagen. Internamente, Docker calcula la diferencia entre el contenedor y su imagen base y la almacena como un nuevo layer encima de los existentes.

```bash
docker commit <container_id|name> <imagen:tag>
```

Es el equivalente manual a lo que hace un `Dockerfile` con cada instrucción `RUN`: cada cambio genera un layer. La diferencia es que con `commit` ese layer se crea a partir de un estado en runtime, no de instrucciones declarativas.

### Por qué este lab requiere docker commit y no docker tag

El enunciado dice: *"crear una imagen a partir del contenedor"* y *"mantener un respaldo de los cambios"*. Eso describe explícitamente `docker commit`.

`docker tag` **no sirve para este caso** porque:

- Opera sobre una **imagen**, no sobre un contenedor
- Solo crea un alias — apunta al IMAGE ID de la imagen base (`ubuntu:latest`)
- No captura nada de lo que ocurrió dentro del contenedor en runtime

Si el desarrollador instaló paquetes o modificó archivos dentro del contenedor, `docker tag` produciría una imagen sin esos cambios. `docker commit` los preserva.

### Casos de uso de cada comando

| Comando | Cuándo usarlo |
|---------|--------------|
| `docker commit` | Respaldar el estado de un contenedor en ejecución, incluyendo cambios en runtime (paquetes instalados, archivos modificados, datos generados) |
| `docker tag` | Renombrar una imagen existente, crear un alias de versión (`app:1.2` → `app:stable`), preparar una imagen para push a otro registro |

La distinción clave: `docker tag` trabaja con el punto de partida (la imagen), `docker commit` trabaja con el punto de llegada (el estado actual del contenedor).

## Pasos

1. Verificar el contenedor en ejecución
2. Inspeccionar los cambios del contenedor con `docker diff`
3. Crear la imagen con `docker commit`
4. Asignar el tag si no se especificó al momento del commit
5. Verificar que la imagen fue creada con un IMAGE ID propio

## Comandos / Código

### 1. Verificar el contenedor en ejecución

```bash
docker ps
docker image ls
```

```
CONTAINER ID   IMAGE     COMMAND       CREATED         STATUS         PORTS     NAMES
91ca344b077e   ubuntu    "/bin/bash"   6 minutes ago   Up 6 minutes             ubuntu_latest

REPOSITORY   TAG          IMAGE ID       CREATED         SIZE
cluster      datacenter   0b1ebe5dd426   2 weeks ago     78.1MB
ubuntu       latest       0b1ebe5dd426   2 weeks ago     78.1MB
```

### 2. Inspeccionar los cambios del contenedor

```bash
docker diff ubuntu_latest
```

```
C /var
C /var/lib
C /var/lib/apt
C /var/lib/apt/lists
A /var/lib/apt/lists/auxfiles
A /var/lib/apt/lists/security.ubuntu.com_ubuntu_dists_noble-security_multiverse_binary-amd64_Packages.lz4
A /var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_noble-backports_multiverse_binary-amd64_Packages.lz4
...
A /usr/src/welcome.txt
```

`docker diff` muestra las diferencias entre el contenedor y su imagen base:
- `A` — archivo agregado
- `C` — archivo modificado
- `D` — archivo eliminado

En este caso el contenedor tiene dos tipos de cambios:
- **`/var/lib/apt/lists/`** — se ejecutó `apt update` dentro del contenedor, descargando los índices de paquetes de Ubuntu Noble (~62 MB)
- **`/usr/src/welcome.txt`** — archivo nuevo creado dentro del contenedor

Estos cambios confirman que `docker commit` es necesario: `docker tag` no los capturaría.

### 3. Crear la imagen desde el contenedor

```bash
docker commit ubuntu_latest
```

```
sha256:8c5a5d71604e...
```

Al no especificar nombre, Docker crea la imagen sin tag (`<none>:<none>`):

```bash
docker image ls
```

```
REPOSITORY   TAG          IMAGE ID       CREATED         SIZE
<none>       <none>       8c5a5d71604e   5 seconds ago   140MB
cluster      datacenter   0b1ebe5dd426   2 weeks ago     78.1MB
ubuntu       latest       0b1ebe5dd426   2 weeks ago     78.1MB
```

La imagen de 140 MB (vs 78.1 MB de la base) refleja exactamente los archivos que mostró `docker diff`.

### 4. Asignar el tag a la imagen creada

```bash
docker tag 8c5a5d71604e cluster:datacenter
docker image ls
```

```
REPOSITORY   TAG          IMAGE ID       CREATED          SIZE
cluster      datacenter   8c5a5d71604e   22 seconds ago   140MB
ubuntu       latest       0b1ebe5dd426   2 weeks ago      78.1MB
```

El IMAGE ID de `cluster:datacenter` ahora es `8c5a5d71604e`, distinto al de `ubuntu:latest`. El tag anterior (que apuntaba a `0b1ebe5dd426`) fue reemplazado.

### Alternativa: commit y tag en un solo paso

```bash
docker commit ubuntu_latest cluster:datacenter
```

Equivalente al flujo anterior pero sin crear una imagen sin nombre intermedia.

## Nota sobre el tamaño

El salto de 78.1 MB → 140 MB (~62 MB extra) viene del `apt update`: descargó los índices de paquetes de los repositorios de Ubuntu a `/var/lib/apt/lists/`. Esos archivos son el catálogo de paquetes disponibles, no paquetes instalados.

Este es un patrón común de image bloat. En un Dockerfile se evita limpiando la cache en la misma instrucción `RUN`:

```dockerfile
RUN apt update && apt install -y <paquete> && rm -rf /var/lib/apt/lists/*
```

Si se separa en varias instrucciones `RUN`, los archivos de apt quedan en un layer y no se pueden eliminar en layers posteriores.

## docker commit vs docker tag — comparación directa

| | `docker commit` | `docker tag` |
|-|----------------|-------------|
| Opera sobre | Contenedor (estado en runtime) | Imagen existente |
| Captura cambios del contenedor | ✅ Sí | ❌ No |
| IMAGE ID resultante | Nuevo (layer adicional) | Mismo que la imagen base |
| Cuándo es suficiente | Siempre que se quiera preservar el estado del contenedor | Solo cuando no hay cambios que preservar |

## Troubleshooting

| Problema | Solución |
|----------|----------|
| La nueva imagen tiene el mismo IMAGE ID que la base | Verificar con `docker diff` si el contenedor tiene cambios; si no hay, los IMAGE IDs pueden coincidir |
| `docker commit` crea imagen `<none>:<none>` | No se especificó nombre — asignar con `docker tag <image_id> <nombre:tag>` o repetir con `docker commit <container> <nombre:tag>` |
| `No such container` | El nombre o ID del contenedor es incorrecto — verificar con `docker ps -a` |
| La imagen pesa mucho más de lo esperado | Revisar `docker diff` — probablemente hay archivos de cache (`/var/lib/apt/lists/`) que no se limpiaron |

## Recursos

- [docker commit - documentación oficial](https://docs.docker.com/engine/reference/commandline/commit/)
- [docker diff - documentación oficial](https://docs.docker.com/engine/reference/commandline/diff/)
- [docker tag - documentación oficial](https://docs.docker.com/engine/reference/commandline/tag/)
