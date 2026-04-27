# Día 38 - Pull de imagen Docker y re-tagging

## Problema / Desafío

El equipo de Nautilus necesita preparar el entorno para pruebas de contenedores en App Server 1 (`stapp01`). Requisitos:

- Descargar la imagen `busybox:musl` desde Docker Hub
- Crear un nuevo tag `busybox:news` apuntando a la misma imagen

## Conceptos clave

### Tags en Docker

Un tag es un **alias con nombre** que apunta a un digest de imagen (hash SHA256 de los layers). No es una copia — múltiples tags pueden apuntar al mismo IMAGE ID.

```
busybox:musl  ──┐
                ├──► IMAGE ID: 0188a8de47ca  (mismos layers en disco)
busybox:news  ──┘
```

Los tags cumplen varias funciones:

| Uso | Ejemplo |
|-----|---------|
| Versionado semántico | `nginx:1.25.3`, `nginx:1.25`, `nginx:1` |
| Variantes de imagen | `busybox:musl`, `busybox:glibc`, `busybox:uclibc` |
| Entornos / pipelines | `app:dev`, `app:staging`, `app:prod` |
| Alias de conveniencia | `nginx:latest` → apunta a la versión más reciente publicada |

> **Nota:** `latest` es solo una convención, no se actualiza automáticamente. Si no se especifica tag, Docker asume `latest`.

### Variantes de busybox

`busybox` es una imagen minimalista (~1.5 MB) que empaqueta múltiples utilidades Unix en un solo binario. El tag indica la librería C utilizada:

| Tag | Librería C | Característica |
|-----|-----------|----------------|
| `musl` | musl libc | Ligera, orientada a seguridad y tamaño |
| `glibc` | GNU libc | Compatibilidad amplia, mayor tamaño |
| `uclibc` | uClibc-ng | Diseñada para sistemas embebidos |

### docker tag

`docker tag` no descarga ni crea datos nuevos. Añade una entrada en el registro local de imágenes que apunta al mismo conjunto de layers. Si se elimina uno de los tags, los layers permanecen mientras otro tag los referencie.

## Pasos

1. Descargar la imagen con `docker pull`
2. Verificar que la imagen existe localmente con `docker image ls`
3. Crear el nuevo tag con `docker tag`
4. Verificar que ambos tags apuntan al mismo IMAGE ID

## Comandos / Código

### 1. Pull de la imagen

```bash
docker pull busybox:musl
```

```
musl: Pulling from library/busybox
5bfa213ad291: Pull complete
Digest: sha256:19b646668802469d968a05342a601e78da4322a414a7c09b1c9ee25165042138
Status: Downloaded newer image for busybox:musl
docker.io/library/busybox:musl
```

### 2. Verificar imagen descargada

```bash
docker image ls
```

```
REPOSITORY   TAG       IMAGE ID       CREATED         SIZE
busybox      musl      0188a8de47ca   19 months ago   1.51MB
```

### 3. Crear nuevo tag

```bash
docker tag busybox:musl busybox:news
```

### 4. Verificar ambos tags

```bash
docker image ls
```

```
REPOSITORY   TAG       IMAGE ID       CREATED         SIZE
busybox      musl      0188a8de47ca   19 months ago   1.51MB
busybox      news      0188a8de47ca   19 months ago   1.51MB
```

Mismo IMAGE ID confirma que ambos tags apuntan a los mismos layers — sin duplicación de datos.

## Comportamiento al eliminar tags

```bash
# Elimina solo el tag, no los layers (mientras otro tag los referencie)
docker rmi busybox:musl

# Para eliminar los layers del disco hay que eliminar todos los tags
docker rmi busybox:musl busybox:news
# o forzar por IMAGE ID (elimina todos los tags a la vez)
docker rmi 0188a8de47ca
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `Error response from daemon: pull access denied` | La imagen no existe en Docker Hub o el nombre está mal escrito |
| `tag does not exist` | El tag especificado no está publicado — verificar en hub.docker.com |
| Al hacer `docker rmi` solo desaparece un tag | Normal: si hay múltiples tags al mismo IMAGE ID, hay que eliminarlos todos para liberar el disco |

## Recursos

- [docker pull - documentación oficial](https://docs.docker.com/engine/reference/commandline/pull/)
- [docker tag - documentación oficial](https://docs.docker.com/engine/reference/commandline/tag/)
- [busybox en Docker Hub](https://hub.docker.com/_/busybox)
