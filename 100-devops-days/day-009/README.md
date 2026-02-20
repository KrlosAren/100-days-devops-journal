# Día 09 - Troubleshooting: MariaDB no inicia por directorio faltante

## Problema / Desafío

Una aplicación no puede conectarse al servidor de base de datos MariaDB. Se debe identificar la causa raíz del problema y restaurar el servicio.

## Conceptos clave

### Manejadores de servicios en Linux

Existen distintos sistemas de inicio (init systems) que gestionan los servicios en Linux. El manejador disponible depende de la distribución y su versión:

| Sistema | Comando | Distribuciones | Época |
|---------|---------|----------------|-------|
| **systemd** | `systemctl` | RHEL/CentOS 7+, Ubuntu 16.04+, Debian 8+ | 2010 - actual |
| **SysVinit** | `service` / scripts en `/etc/init.d/` | RHEL/CentOS 6, Ubuntu 14.04, Debian 7 y anteriores | 1983 - ~2015 |

#### systemd (systemctl)

Es el estándar actual en la mayoría de distribuciones modernas. Gestiona servicios como **unidades** (units):

| Comando | Descripción |
|---------|-------------|
| `systemctl status <servicio>` | Ver el estado actual del servicio |
| `systemctl start <servicio>` | Iniciar el servicio |
| `systemctl restart <servicio>` | Reiniciar el servicio |
| `systemctl enable <servicio>` | Habilitar el servicio para que inicie con el sistema |

#### SysVinit (service)

Sistema de inicio clásico. Los servicios se gestionan mediante scripts en `/etc/init.d/`:

| Comando | Equivalente en systemctl |
|---------|--------------------------|
| `service mariadb status` | `systemctl status mariadb` |
| `service mariadb start` | `systemctl start mariadb` |
| `service mariadb restart` | `systemctl restart mariadb` |
| `/etc/init.d/mariadb start` | Invocación directa del script de init |
| `chkconfig mariadb on` | `systemctl enable mariadb` |

> **Nota**: En sistemas con systemd, el comando `service` todavía funciona como un wrapper de compatibilidad que redirige las llamadas a `systemctl`.

### Formas de ver logs del sistema

Existen dos enfoques principales para consultar logs en Linux:

#### journalctl (systemd journal)

Logs estructurados y binarios gestionados por systemd. Permiten filtrar por servicio, tiempo, prioridad, etc:

| Comando | Descripción |
|---------|-------------|
| `journalctl -xeu mariadb.service` | Logs del servicio con contexto extra, al final |
| `journalctl -f -u mariadb.service` | Seguir logs en tiempo real (como `tail -f`) |
| `journalctl --since "10 minutes ago"` | Logs de los últimos 10 minutos |
| `journalctl -p err` | Solo mensajes de error o superior |

| Flag | Descripción |
|------|-------------|
| `-x` | Agrega información extra/explicativa a los mensajes |
| `-e` | Salta al final del log (entradas más recientes) |
| `-u <servicio>` | Filtra por unidad/servicio específico |
| `-f` | Sigue los logs en tiempo real |
| `-p <prioridad>` | Filtra por prioridad (`emerg`, `alert`, `crit`, `err`, `warning`, `notice`, `info`, `debug`) |

#### Archivos en /var/log/ (rsyslog / syslog-ng)

Logs tradicionales en texto plano, gestionados por `rsyslog` o `syslog-ng`. Se pueden leer con herramientas estándar como `cat`, `tail`, `less` o `grep`:

| Archivo | Contenido |
|---------|-----------|
| `/var/log/messages` | Logs generales del sistema (RHEL/CentOS) |
| `/var/log/syslog` | Logs generales del sistema (Ubuntu/Debian) |
| `/var/log/mariadb/mariadb.log` | Log específico de MariaDB (si está configurado) |
| `/var/log/mysql/error.log` | Log de errores de MySQL/MariaDB (depende de la configuración) |

```bash
# Ver las últimas líneas del log del sistema
sudo tail -50 /var/log/messages

# Buscar errores relacionados con mariadb en los logs
sudo grep -i mariadb /var/log/messages

# Seguir el log en tiempo real
sudo tail -f /var/log/messages
```

> **Diferencia clave**: `journalctl` almacena logs en formato binario y ofrece filtrado avanzado. Los archivos en `/var/log/` son texto plano, más simples de leer pero menos potentes para filtrar. En sistemas modernos ambos coexisten.

### Directorio de datos de MariaDB

MariaDB almacena sus bases de datos en `/var/lib/mysql/` por defecto. Este directorio debe:

- Existir antes de que el servicio inicie
- Pertenecer al usuario y grupo `mysql` (usuario con el que se ejecuta el proceso de MariaDB)
- Tener los permisos correctos para que el proceso pueda leer y escribir

Si este directorio no existe o tiene permisos incorrectos, el servicio no puede iniciar.

## Pasos

1. Verificar el estado del servicio MariaDB
2. Intentar reiniciar el servicio
3. Revisar los logs con `journalctl` para identificar la causa del fallo
4. Crear el directorio faltante `/var/lib/mysql`
5. Asignar el propietario correcto (`mysql:mysql`)
6. Reiniciar el servicio y verificar la conexión

## Comandos / Código

### Verificar el estado del servicio

```bash
sudo systemctl status mariadb.service
```

El servicio aparece como **inactive** o **failed**.

### Intentar reiniciar el servicio

```bash
sudo systemctl restart mariadb.service
```

El reinicio falla porque el directorio de datos no existe.

### Revisar los logs para identificar la causa

```bash
sudo journalctl -xeu mariadb.service
```

En los logs se identifica que el servicio no puede iniciar porque la carpeta `/var/lib/mysql` no existe.

### Crear el directorio faltante

```bash
sudo mkdir -p /var/lib/mysql
```

### Identificar el usuario de ejecución de MariaDB

Para confirmar con qué usuario se ejecuta el servicio:

```bash
grep -i "user" /etc/my.cnf /etc/my.cnf.d/*.cnf 2>/dev/null
```

O revisar la unidad de systemd:

```bash
systemctl cat mariadb.service | grep User
```

El usuario es `mysql`.

### Asignar el propietario correcto

```bash
sudo chown mysql:mysql /var/lib/mysql
```

### Reiniciar el servicio y verificar

```bash
sudo systemctl restart mariadb.service
sudo systemctl status mariadb.service
```

El servicio debe aparecer como **active (running)**.

### Verificar la conexión a la base de datos

```bash
mysql -u root -p
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| Servicio MariaDB no está corriendo | Verificar con `systemctl status mariadb.service` e intentar reiniciar |
| `systemctl restart` falla sin mensaje claro | Revisar logs con `journalctl -xeu mariadb.service` para ver la causa raíz |
| `/var/lib/mysql` no existe | Crear con `sudo mkdir -p /var/lib/mysql` |
| Servicio falla después de crear el directorio | Verificar que el propietario sea `mysql:mysql` con `ls -ld /var/lib/mysql` y corregir con `chown` |
| Permisos incorrectos en `/var/lib/mysql` | `sudo chown mysql:mysql /var/lib/mysql && sudo chmod 755 /var/lib/mysql` |

## Recursos

- [MariaDB - systemd](https://mariadb.com/kb/en/systemd/)
- [journalctl - Arch Wiki](https://wiki.archlinux.org/title/Systemd/Journal)
- [MariaDB Data Directory](https://mariadb.com/kb/en/server-system-variables/#datadir)
