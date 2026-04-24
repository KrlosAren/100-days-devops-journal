# Día 37 - Copiar archivos a un contenedor con docker cp

## Problema / Desafío

El equipo DevOps de Nautilus necesita transferir un archivo confidencial cifrado desde el host al contenedor `ubuntu_latest` en App Server 1 (`stapp01`). Requisitos:

- Copiar `/tmp/nautilus.txt.gpg` del host Docker al contenedor `ubuntu_latest`
- Destino dentro del contenedor: `/tmp/`
- El archivo no debe ser modificado durante la operación

## Conceptos clave

### docker cp

`docker cp` copia archivos o directorios entre el filesystem del host y el filesystem de un contenedor en ejecución. Usa la API del daemon de Docker — no requiere SSH ni herramientas de red dentro del contenedor.

```bash
# Host → Contenedor
docker cp <ruta_host> <container_id|name>:<ruta_contenedor>

# Contenedor → Host
docker cp <container_id|name>:<ruta_contenedor> <ruta_host>
```

### docker exec

`docker exec` ejecuta un comando dentro de un contenedor en ejecución sin iniciar un nuevo proceso principal. Es la forma estándar de inspeccionar o interactuar con el interior del contenedor.

```bash
docker exec -it <container> <comando>
#            │└─ tty: asigna una terminal
#            └── interactive: mantiene stdin abierto
```

### Integridad del archivo

`docker cp` transfiere el contenido binario exacto del archivo — no lo modifica. El archivo `.gpg` (cifrado con GPG) llegará al contenedor con los mismos bytes que en el host. Los metadatos (timestamps, permisos) pueden ajustarse según el contexto del daemon.

## Pasos

1. Verificar que el contenedor `ubuntu_latest` está en ejecución
2. Confirmar que el archivo existe en el host
3. Copiar el archivo con `docker cp`
4. Verificar dentro del contenedor que el archivo llegó correctamente

## Comandos / Código

### 1. Verificar el contenedor

```bash
docker ps
```

```
CONTAINER ID   IMAGE     COMMAND       CREATED              STATUS              PORTS     NAMES
7afda3e2ff37   ubuntu    "/bin/bash"   About a minute ago   Up About a minute             ubuntu_latest
```

### 2. Confirmar que el archivo existe en el host

```bash
ls -lhart /tmp/
```

```
-rw-r--r--  1 root root  105 Apr 24 01:54 nautilus.txt.gpg
```

105 bytes, archivo cifrado con GPG.

### 3. Copiar el archivo al contenedor

```bash
docker cp /tmp/nautilus.txt.gpg 7afda3e2ff37:/tmp
```

```
Successfully copied 2.05kB to 7afda3e2ff37:/tmp
```

### 4. Verificar dentro del contenedor

```bash
docker exec -it 7afda3e2ff37 ls -lhart /tmp/
```

```
total 12K
-rw-r--r-- 1 root root  105 Apr 24 01:54 nautilus.txt.gpg
drwxr-xr-x 1 root root 4.0K Apr 24 01:57 ..
drwxrwxrwt 1 root root 4.0K Apr 24 01:57 .
```

El archivo está en `/tmp/` del contenedor con los mismos 105 bytes — contenido íntegro.

## Diferencia entre docker cp y montar un volumen

| | `docker cp` | Volumen (`-v`) |
|--|-------------|----------------|
| Cuándo | Una sola transferencia | Sincronización continua |
| Requiere reiniciar el contenedor | No | Sí (al crear el contenedor) |
| Cambios en el host se reflejan | No | Sí (en tiempo real) |
| Uso típico | Copiar configs, archivos puntuales | Datos persistentes, desarrollo |

## Referencia: sintaxis completa de docker cp

```bash
# Copiar archivo al contenedor
docker cp /ruta/local/archivo.txt contenedor:/ruta/destino/

# Copiar directorio al contenedor
docker cp /ruta/local/directorio/ contenedor:/ruta/destino/

# Extraer archivo del contenedor al host
docker cp contenedor:/ruta/archivo.txt /ruta/local/

# Usando el nombre en vez del ID
docker cp /tmp/nautilus.txt.gpg ubuntu_latest:/tmp
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `No such container` | El contenedor no existe o el ID es incorrecto — verificar con `docker ps` |
| `not running` | El contenedor está detenido — iniciarlo con `docker start <name>` |
| `permission denied` dentro del contenedor | El archivo se copió como root — verificar con `docker exec` quién es el propietario |
| El archivo aparece como directorio | Si el destino no existe, Docker lo crea como directorio — usar la ruta completa: `contenedor:/tmp/nautilus.txt.gpg` |

## Recursos

- [docker cp - documentación oficial](https://docs.docker.com/engine/reference/commandline/cp/)
- [docker exec - documentación oficial](https://docs.docker.com/engine/reference/commandline/exec/)
