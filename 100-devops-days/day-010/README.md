# Dia 10 - Script de backup para sitio web estatico

## Problema / Desafio

El equipo de soporte de produccion necesita un script bash llamado `blog_backup.sh` que:

1. Cree un archivo zip del directorio `/var/www/html/blog`
2. Guarde el zip en `/backup/` en el App Server 3
3. Copie el archivo al Nautilus Backup Server en `/backup/`
4. No pida password al copiar el archivo
5. No use `sudo` dentro del script

El script debe ubicarse en `/scripts/` en App Server 3.

## Conceptos clave

### scp (Secure Copy)

`scp` permite copiar archivos entre servidores de forma segura sobre SSH. Si se configura autenticacion por llave SSH, la transferencia no requiere password.

```bash
scp archivo_local usuario@servidor_remoto:/ruta/destino/
```

### Autenticacion SSH sin password

Para que `scp` (o `ssh`) no pida password, se debe configurar autenticacion por llave publica:

1. **Generar la llave** en el servidor origen
2. **Copiar la llave publica** al servidor destino
3. El servidor destino valida la llave automaticamente en cada conexion

```
App Server 3                    Backup Server
┌──────────────┐               ┌──────────────┐
│ ~/.ssh/      │               │ ~/.ssh/       │
│  id_ed25519  │──── scp ────→│  authorized_  │
│  id_ed25519  │  (sin pass)  │  keys         │
│  .pub        │               │               │
└──────────────┘               └──────────────┘
```

### zip

Utilidad para crear archivos comprimidos en formato `.zip`. El flag `-r` comprime directorios de forma recursiva.

## Pasos

1. Conectarse a App Server 3
2. Instalar el paquete `zip` (requisito previo, fuera del script)
3. Verificar que exista el directorio `/backup/`
4. Generar llave SSH y copiarla al Backup Server
5. Crear el script en `/scripts/blog_backup.sh`
6. Dar permisos de ejecucion al script
7. Ejecutar y verificar

## Comandos / Codigo

### Conectarse a App Server 3

```bash
ssh banner@stapp03
```

### Instalar zip

```bash
sudo yum install -y zip
# o en distribuciones basadas en Debian:
# sudo apt install -y zip
```

### Verificar directorio de backup

```bash
ls -ld /backup/
```

### Configurar SSH sin password

```bash
# Generar llave SSH
ssh-keygen -t ed25519

# Copiar la llave publica al Backup Server
ssh-copy-id clint@stbkp01.stratos.xfusioncorp.com
```

Verificar que funcione sin pedir password:

```bash
ssh clint@stbkp01.stratos.xfusioncorp.com "echo conexion exitosa"
```

### Crear el script

```bash
#!/bin/bash

echo "Backup script"

zip -r /backup/xfusioncorp_blog.zip /var/www/html/blog

echo "finish zip created"

echo "copy file into server"

scp /backup/xfusioncorp_blog.zip clint@stbkp01.stratos.xfusioncorp.com:/backup/

echo "finished backup"
```

### Opciones de set en bash scripts

Al crear scripts en bash, el comando `set` permite activar opciones que controlan como se comporta el interprete. Estas opciones ayudan a detectar errores y hacer los scripts mas robustos.

#### Opciones principales

| Opcion | Nombre | Que hace |
|--------|--------|----------|
| `set -e` | errexit | Detiene el script si cualquier comando falla (exit code != 0) |
| `set -u` | nounset | Detiene el script si se usa una variable no definida |
| `set -o pipefail` | pipefail | Un pipeline falla si **cualquier** comando en la cadena falla, no solo el ultimo |
| `set -x` | xtrace | Imprime cada comando antes de ejecutarlo (modo debug) |

#### set -e (errexit)

```bash
set -e
cp archivo_que_no_existe.txt /tmp/   # Script se detiene aqui
echo "Esto nunca se ejecuta"
```

#### set -u (nounset)

Atrapa variables con typos. Sin `set -u`, bash usa una cadena vacia silenciosamente:

```bash
set -u
BACKUP_DIR="/backup"
echo $BAKCUP_DIR   # Error: BAKCUP_DIR no esta definida (typo)
```

Sin `-u` esto podria ser desastroso:

```bash
rm -rf $BAKCUP_DIR/   # Se convierte en rm -rf / (borra todo)
```

#### set -o pipefail

Detecta errores en pipelines. Sin esta opcion, bash solo evalua el exit code del ultimo comando:

```bash
set -o pipefail
cat archivo_inexistente | grep "algo"   # Falla correctamente
# Sin pipefail, grep retorna 0 y el error de cat se ignora
```

#### set -x (xtrace)

Modo debug. Imprime cada linea con un `+` antes de ejecutarla:

```bash
set -x
NAME="backup"
zip -r /backup/${NAME}.zip /var/www/html/blog
```

Salida:

```
+ NAME=backup
+ zip -r /backup/backup.zip /var/www/html/blog
```

#### Combinacion estandar en produccion (modo estricto)

En la mayoria de scripts profesionales se usa esta combinacion al inicio:

```bash
#!/bin/bash
set -euo pipefail
```

Esto combina `-e`, `-u` y `-o pipefail` en una sola linea y atrapa la mayoria de errores comunes.

#### Desactivar una opcion

Se usa `+` en lugar de `-` para desactivar una opcion temporalmente:

```bash
set -e              # Activa errexit
# ... codigo critico ...
set +e              # Desactiva errexit
comando_que_puede_fallar   # No detiene el script
set -e              # Reactiva errexit
```

#### Otras opciones menos comunes

| Opcion | Que hace |
|--------|----------|
| `set -n` | Lee el script pero no ejecuta nada (validacion de sintaxis) |
| `set -f` | Desactiva globbing (expansion de `*`, `?`, etc.) |
| `set -C` | Previene sobreescribir archivos con `>` (obliga a usar `>\|`) |

### Dar permisos de ejecucion

```bash
chmod +x /scripts/blog_backup.sh
```

### Ejecutar el script

```bash
./blog_backup.sh
```

```
Backup script
updating: var/www/html/blog/ (stored 0%)
updating: var/www/html/blog/.gitkeep (stored 0%)
updating: var/www/html/blog/index.html (stored 0%)
finish zip created
copy file into server
xfusioncorp_blog.zip                           100%  588     1.1MB/s   00:00
finished backup
```

## Observacion importante

En el script, el zip debe crearse directamente en `/backup/`:

```bash
# Correcto - guarda el zip en /backup/
zip -r /backup/xfusioncorp_blog.zip /var/www/html/blog

# Incorrecto - guarda el zip en el directorio actual (/scripts/)
zip -r xfusioncorp_blog.zip /var/www/html/blog
```

La tarea indica que el archivo debe guardarse en `/backup/` en el App Server antes de copiarlo al Backup Server.

## Tips y mejoras para produccion

### 1. Timestamp en el nombre del backup

Si el script se ejecuta multiples veces, el zip se sobreescribe. Agregar la fecha y hora al nombre evita esto y permite mantener un historial:

```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
zip -r /backup/xfusioncorp_blog_${TIMESTAMP}.zip /var/www/html/blog
```

Esto genera nombres como `xfusioncorp_blog_20260221_143000.zip`.

### 2. Validacion de errores con set -e

El script actual no se detiene si un comando falla. Por ejemplo, si `zip` falla, el `scp` se ejecuta de todas formas (copiando un archivo corrupto o inexistente). Agregar `set -e` al inicio del script hace que se detenga ante cualquier error:

```bash
#!/bin/bash
set -e

# Si zip falla, el script se detiene aqui
zip -r /backup/xfusioncorp_blog.zip /var/www/html/blog

# Este comando solo se ejecuta si el zip fue exitoso
scp /backup/xfusioncorp_blog.zip clint@stbkp01.stratos.xfusioncorp.com:/backup/
```

Otra opcion es validar cada comando individualmente con `$?`:

```bash
zip -r /backup/xfusioncorp_blog.zip /var/www/html/blog
if [ $? -ne 0 ]; then
    echo "ERROR: Fallo al crear el zip"
    exit 1
fi
```

### 3. Verificacion de integridad del zip

Antes de copiar el archivo al servidor remoto, se puede validar que el zip no este corrupto con `unzip -t`:

```bash
unzip -t /backup/xfusioncorp_blog.zip
```

```
Archive:  /backup/xfusioncorp_blog.zip
    testing: var/www/html/blog/       OK
    testing: var/www/html/blog/.gitkeep   OK
    testing: var/www/html/blog/index.html   OK
No errors detected in compressed data of /backup/xfusioncorp_blog.zip.
```

### 4. Automatizacion con cron

La tarea menciona que los backups se limpian semanalmente. Para automatizar la ejecucion del script se usa `crontab`:

```bash
# Editar el crontab del usuario
crontab -e

# Ejecutar el backup todos los dias a las 2:00 AM
0 2 * * * /scripts/blog_backup.sh >> /var/log/blog_backup.log 2>&1
```

Estructura de cron:

```
┌───────────── minuto (0-59)
│ ┌───────────── hora (0-23)
│ │ ┌───────────── dia del mes (1-31)
│ │ │ ┌───────────── mes (1-12)
│ │ │ │ ┌───────────── dia de la semana (0-6, 0=domingo)
│ │ │ │ │
0 2 * * * /scripts/blog_backup.sh
```

El `>> /var/log/blog_backup.log 2>&1` redirige tanto stdout como stderr al archivo de log para poder revisar si el backup fallo.

### 5. scp esta deprecado: alternativas modernas

Desde OpenSSH 9.0, `scp` esta deprecado porque internamente usa el protocolo SCP (antiguo y con limitaciones de seguridad). Las alternativas recomendadas son:

| Herramienta | Ventaja | Comando equivalente |
|-------------|---------|---------------------|
| **rsync** | Solo transfiere diferencias, mas eficiente para backups recurrentes | `rsync -avz /backup/xfusioncorp_blog.zip clint@stbkp01:/backup/` |
| **sftp** | Protocolo moderno, reemplaza SCP internamente | `sftp clint@stbkp01:/backup/ <<< "put /backup/xfusioncorp_blog.zip"` |
| **scp -s** | Usa el subsistema SFTP en lugar del protocolo SCP legacy | `scp -s /backup/xfusioncorp_blog.zip clint@stbkp01:/backup/` |

`rsync` es especialmente util para backups porque:
- Solo transfiere los bytes que cambiaron (delta transfer)
- Puede reanudar transferencias interrumpidas con `--partial`
- Soporta compresion durante la transferencia con `-z`

### 6. ssh-keygen: ed25519 vs rsa

Se uso `ssh-keygen -t ed25519` para generar la llave SSH. Esta es la opcion recomendada sobre RSA:

| Caracteristica | ed25519 | RSA |
|----------------|---------|-----|
| Tamano de llave | 256 bits (fijo) | 2048-4096 bits |
| Tamano de llave publica | ~68 caracteres | ~400+ caracteres |
| Seguridad | Equivalente a RSA 3072 | Depende del tamano de llave |
| Rendimiento | Mas rapido en firma y verificacion | Mas lento |
| Soporte | OpenSSH 6.5+ (2014) | Universal |

La unica razon para usar RSA es compatibilidad con sistemas muy antiguos (OpenSSH < 6.5).

```bash
# Recomendado
ssh-keygen -t ed25519

# Solo si se necesita compatibilidad con sistemas antiguos
ssh-keygen -t rsa -b 4096
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `zip: command not found` | Instalar con `sudo yum install -y zip` antes de ejecutar el script |
| `scp` pide password | Verificar que la llave SSH fue copiada correctamente con `ssh-copy-id`. Verificar permisos de `~/.ssh/` (700) y `~/.ssh/authorized_keys` (600) en el servidor destino |
| `Permission denied` al crear el zip en `/backup/` | Verificar que el usuario tiene permisos de escritura en `/backup/` con `ls -ld /backup/` |
| `/backup/` no existe en el Backup Server | Crear el directorio en el servidor destino: `ssh clint@stbkp01... "mkdir -p /backup/"` |
| El script no se ejecuta | Verificar permisos con `ls -l /scripts/blog_backup.sh` y agregar con `chmod +x` |

## Recursos

- [scp - Linux man page](https://linux.die.net/man/1/scp)
- [ssh-keygen - Kubernetes Docs](https://man.openbsd.org/ssh-keygen.1)
- [ssh-copy-id - Linux man page](https://linux.die.net/man/1/ssh-copy-id)
- [zip - Linux man page](https://linux.die.net/man/1/zip)
