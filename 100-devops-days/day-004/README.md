# Día 04 - Permisos de ejecución y propiedad de archivos en Linux

## Problema / Desafío

Hay un script llamado `test.sh` que necesita permisos de ejecución. Además, se debe asegurar que todos los usuarios del sistema puedan ejecutarlo. Para esto es necesario revisar los permisos actuales, entender la notación de permisos, y aplicar los cambios correctos con `chmod`, `chown` y `chgrp`.

## Conceptos clave

- **Permisos en Linux**: Cada archivo tiene tres conjuntos de permisos: para el **propietario** (owner), el **grupo** (group) y **otros** (others). Cada conjunto puede tener permisos de lectura (`r`), escritura (`w`) y ejecución (`x`).
- **Notación de permisos**: Se representan con 10 caracteres, por ejemplo `-rwxr-xr-x`:

| Posición | Significado |
|----------|-------------|
| 1 | Tipo de archivo (`-` archivo regular, `d` directorio, `l` enlace simbólico) |
| 2-4 | Permisos del propietario (owner): `rwx` |
| 5-7 | Permisos del grupo (group): `r-x` |
| 8-10 | Permisos de otros (others): `r-x` |

- **Significado de cada permiso**:

| Permiso | Letra | Valor octal | En archivos | En directorios |
|---------|-------|-------------|-------------|----------------|
| Lectura | `r` | 4 | Leer el contenido | Listar archivos (`ls`) |
| Escritura | `w` | 2 | Modificar el contenido | Crear/eliminar archivos dentro |
| Ejecución | `x` | 1 | Ejecutar como programa | Acceder al directorio (`cd`) |

- **`chmod`**: Cambia los permisos de un archivo o directorio.
- **`chown`**: Cambia el propietario (y opcionalmente el grupo) de un archivo.
- **`chgrp`**: Cambia el grupo de un archivo.
- **`ls -lhr`**: Lista archivos en formato largo (`-l`), con tamaños legibles (`-h`), en orden inverso (`-r`).

## Pasos

1. Crear el script `test.sh`
2. Revisar los permisos actuales con `ls -lhr`
3. Verificar el propietario y grupo del archivo
4. Dar permisos de ejecución con `chmod`
5. Ajustar propietario y grupo si es necesario
6. Verificar que todos los usuarios puedan ejecutar el script

## Comandos / Código

### 1. Revisar permisos actuales

```bash
ls -lhr test.sh
```

Salida esperada (antes de cambiar permisos):

```
-rw-r--r-- 1 usuario grupo 120 feb  9 10:00 test.sh
```

Desglose de `-rw-r--r--`:

| Sección | Permisos | Significado |
|---------|----------|-------------|
| `-` | Tipo | Archivo regular |
| `rw-` | Owner | Lectura y escritura, sin ejecución |
| `r--` | Group | Solo lectura |
| `r--` | Others | Solo lectura |

El script **no tiene permisos de ejecución** para ningún usuario.

### 2. Dar permisos de ejecución

```bash
sudo chmod 755 test.sh
```

**`755`** establece los permisos de forma **absoluta**, garantizando el resultado sin importar los permisos previos:

| Valor | Cálculo | Permisos |
|-------|---------|----------|
| `7` | 4+2+1 | `rwx` (owner: lee, escribe, ejecuta) |
| `5` | 4+0+1 | `r-x` (group: lee y ejecuta) |
| `5` | 4+0+1 | `r-x` (others: lee y ejecuta) |

### Por qué `chmod 755` y no `chmod +x`

`chmod +x` es **relativo**: solo agrega ejecución a los permisos existentes. Si el archivo tiene permisos restrictivos, el resultado puede no cumplir el objetivo:

```bash
# Si el archivo tiene permisos 600 (rw-------)
chmod +x test.sh
# Resultado: 700 (rwx------) → others NO puede ejecutar ni leer
```

`chmod 755` es **absoluto**: define todos los permisos explícitamente, garantizando que group y others tengan lectura y ejecución (`r-x`).

### 3. Verificar los permisos después del cambio

```bash
ls -lhr test.sh
```

Salida esperada:

```
-rwxr-xr-x 1 usuario grupo 120 feb  9 10:00 test.sh
```

Ahora el script tiene permisos de ejecución (`x`) en los tres niveles.

### 4. Verificar propietario y grupo

```bash
ls -lhr test.sh
```

En la salida, la tercera y cuarta columna muestran el **propietario** y el **grupo**:

```
-rwxr-xr-x 1 usuario grupo 120 feb  9 10:00 test.sh
              ^^^^^^^ ^^^^^
              owner   group
```

Si se necesita cambiar el propietario:

```bash
# Cambiar solo el propietario
sudo chown nuevo-usuario test.sh

# Cambiar propietario y grupo al mismo tiempo
sudo chown nuevo-usuario:nuevo-grupo test.sh
```

Si se necesita cambiar solo el grupo:

```bash
sudo chgrp nuevo-grupo test.sh
```

### 5. Ejecutar el script

```bash
./test.sh
```

Salida esperada:

```
Hola, este script tiene permisos de ejecución
Usuario actual: usuario
Fecha: dom feb  9 10:00:00 UTC 2026
```

### Permisos comunes en scripts

| Octal | Simbólico | Uso típico |
|-------|-----------|------------|
| `755` | `rwxr-xr-x` | Scripts ejecutables por todos, editables solo por el owner |
| `700` | `rwx------` | Scripts privados, solo el owner puede leer, escribir y ejecutar |
| `750` | `rwxr-x---` | Ejecutable por el owner y el grupo, sin acceso para otros |
| `644` | `rw-r--r--` | Archivos de configuración legibles por todos, editables solo por el owner |

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `Permission denied` al ejecutar `./test.sh` | Verificar permisos con `ls -l test.sh` y aplicar `chmod 755 test.sh` |
| `bash: ./test.sh: No such file or directory` | Verificar que estás en el directorio correcto con `pwd` y que el archivo existe |
| El script se ejecuta con `bash test.sh` pero no con `./test.sh` | El archivo no tiene el permiso de ejecución (`x`). Usar `chmod 755 test.sh` |
| Solo el propietario puede ejecutar el script | Verificar que `others` tiene permiso `x` con `ls -l`. Si aparece `rwx------`, usar `chmod 755 test.sh` |
| Error de `chown`: `Operation not permitted` | Se requiere `sudo` para cambiar el propietario de archivos |

## Recursos

- [chmod - Manual de Linux](https://man7.org/linux/man-pages/man1/chmod.1.html)
- [chown - Manual de Linux](https://man7.org/linux/man-pages/man1/chown.1.html)
- [Permisos en Linux - Red Hat](https://www.redhat.com/sysadmin/linux-file-permissions-explained)
- [Entendiendo los permisos de archivos](https://wiki.archlinux.org/title/File_permissions_and_attributes)
