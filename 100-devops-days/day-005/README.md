# Día 05 - SELinux

## Problema / Desafío

Instalar los paquetes necesarios de SELinux en el servidor, y luego deshabilitarlo de forma permanente. No se requiere reiniciar el servidor manualmente ya que hay un reinicio de mantenimiento programado para esta noche. El estado actual de SELinux en la línea de comandos no es relevante; lo importante es que después del reinicio el estado final sea `disabled`.

## Conceptos clave

- **SELinux (Security-Enhanced Linux)**: Es un módulo de seguridad del kernel de Linux que proporciona un mecanismo de control de acceso obligatorio (MAC - Mandatory Access Control). Fue desarrollado originalmente por la NSA y está integrado en distribuciones como RHEL, CentOS, Fedora y Rocky Linux.
- **Modos de SELinux**:

| Modo | Descripción |
|------|-------------|
| `enforcing` | SELinux está activo y **aplica** las políticas de seguridad. Los accesos no autorizados son **bloqueados y registrados** |
| `permissive` | SELinux está activo pero **no bloquea** accesos. Solo **registra** las violaciones en los logs |
| `disabled` | SELinux está completamente **desactivado**. No se aplican ni registran políticas |

- **`getenforce`**: Muestra el modo actual de SELinux (`Enforcing`, `Permissive` o `Disabled`).
- **`sestatus`**: Muestra el estado detallado de SELinux, incluyendo modo actual, modo en el archivo de configuración, y la política cargada.
- **`setenforce`**: Cambia el modo de SELinux **temporalmente** (solo entre `Enforcing` y `Permissive`, no puede establecer `Disabled`). El cambio se pierde al reiniciar.
- **`/etc/selinux/config`**: Archivo de configuración principal de SELinux. Los cambios aquí son **permanentes** y se aplican después de un reinicio.

## Pasos

1. Instalar los paquetes requeridos de SELinux
2. Verificar el estado actual de SELinux
3. Modificar la configuración para deshabilitar SELinux permanentemente
4. Confirmar que la configuración quedó correcta (el cambio se aplicará tras el reinicio programado)

## Comandos / Código

### 1. Instalar los paquetes de SELinux

```bash
sudo yum install -y selinux-policy selinux-policy-targeted
```

Estos son los paquetes principales:

| Paquete | Descripción |
|---------|-------------|
| `selinux-policy` | Políticas base de SELinux |
| `selinux-policy-targeted` | Política targeted que protege procesos específicos del sistema |

### 2. Verificar el estado actual de SELinux

```bash
getenforce
```

Salida posible:

```
Enforcing
```

Para ver el estado detallado:

```bash
sestatus
```

Salida esperada:

```
SELinux status:                 enabled
SELinuxfs mount:                /sys/fs/selinux
SELinux root directory:         /etc/selinux
Loaded policy name:             targeted
Current mode:                   enforcing
Mode from config file:          enforcing
Policy MLS status:              enabled
Policy deny_unknown status:     allowed
Memory protection checking:     actual (secure)
Max kernel policy version:      33
```

### 3. Deshabilitar SELinux permanentemente

Editar el archivo de configuración:

```bash
sudo vi /etc/selinux/config
```

Cambiar la línea `SELINUX=` de su valor actual a `disabled`:

```
# Antes
SELINUX=enforcing

# Después
SELINUX=disabled
```

Alternativamente, con `sed`:

```bash
sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
```

> **Nota**: No se ejecuta `setenforce 0` ni se reinicia el servidor. El reinicio de mantenimiento programado para esta noche aplicará el cambio. El comando `getenforce` seguirá mostrando el modo actual hasta que el servidor se reinicie.

### 4. Confirmar la configuración

```bash
grep '^SELINUX=' /etc/selinux/config
```

Salida esperada:

```
SELINUX=disabled
```

### Por qué no usar `setenforce 0`

`setenforce 0` cambia SELinux a modo `permissive` de forma **temporal**, pero:

- No puede establecer el modo `disabled`, solo alterna entre `enforcing` y `permissive`
- El cambio se pierde al reiniciar si no se modificó `/etc/selinux/config`
- En este caso no es necesario porque hay un reinicio programado que aplicará la configuración permanente

### Diferencia entre `permissive` y `disabled`

| Aspecto | `permissive` | `disabled` |
|---------|-------------|------------|
| Políticas cargadas | Sí | No |
| Bloquea accesos | No | No |
| Registra violaciones | Sí (en `/var/log/audit/audit.log`) | No |
| Etiquetado de archivos | Se mantiene | Se pierde (requiere re-etiquetado al reactivar) |
| Requiere reinicio para activar | No (`setenforce 1`) | Sí |

### Estado después del reinicio

Después del reinicio de mantenimiento:

```bash
getenforce
```

Salida esperada:

```
Disabled
```

```bash
sestatus
```

Salida esperada:

```
SELinux status:                 disabled
```

## Por qué la configuración vive en `/etc`

`/etc` es el directorio estándar de Linux para **configuración del sistema**. Su nombre viene de "et cetera" históricamente, pero en la práctica se interpreta como **"Editable Text Configuration"**.

Esta organización es parte del **FHS (Filesystem Hierarchy Standard)**, que define qué va en cada directorio:

| Directorio | Propósito | Ejemplo |
|-----------|-----------|---------|
| `/etc` | Configuración **específica del host** (lo que hace único a este servidor) | `/etc/selinux/config`, `/etc/hostname` |
| `/usr` | Programas y datos **compartibles y de solo lectura** (lo que viene con el software) | `/usr/bin/getenforce`, `/usr/share/selinux/` |
| `/var` | Datos **variables** que cambian durante la operación | `/var/log/audit/audit.log` |
| `/proc` y `/sys` | Estado del **kernel en runtime** (virtual, vive en memoria) | `/proc/cpuinfo`, `/sys/fs/selinux/enforce` |

La separación es intencional:

- Los **binarios** del programa van en `/usr` — son los mismos en cualquier servidor con ese paquete instalado
- La **configuración** va en `/etc` — es lo que hace que *este* servidor se comporte diferente a otro con el mismo software
- El **estado en runtime** vive en `/proc` y `/sys` — es lo que el kernel tiene cargado en memoria ahora mismo

Por eso cuando instalamos `selinux-policy`, los archivos del paquete van a `/usr/share/selinux/`, pero la configuración de *cómo queremos que funcione en este servidor* va a `/etc/selinux/config`. Y cuando el kernel lee esa configuración al arrancar, el estado "vivo" queda expuesto en `/sys/fs/selinux/`.

Es el mismo patrón de runtime vs persistente: `/sys` y `/proc` son el reflejo en memoria, `/etc` es lo que está en disco.

## Configuración en runtime vs configuración persistente en Linux

En Linux existen dos niveles donde vive la configuración de un servicio o del sistema:

| Nivel | Dónde vive | Cuándo se aplica | Persiste tras reinicio |
|-------|-----------|-------------------|------------------------|
| **Runtime (memoria)** | Kernel / proceso en ejecución | Inmediatamente | No |
| **Persistente (disco)** | Archivos en `/etc/` | Al próximo arranque o recarga del servicio | Sí |

Cuando ejecutamos un comando como `setenforce 0`, estamos modificando el estado **en memoria del kernel**. El kernel ya está corriendo y acepta el cambio al instante, pero no toca ningún archivo en disco. Al reiniciar, el kernel vuelve a leer `/etc/selinux/config` y el cambio se pierde.

Cuando editamos `/etc/selinux/config`, estamos escribiendo en disco. El kernel **no lee ese archivo mientras está corriendo** — solo lo lee durante el arranque. Por eso el cambio no se refleja hasta el próximo reinicio.

### Este patrón se repite en todo Linux

| Servicio / Subsistema | Cambio en runtime (temporal) | Configuración persistente (disco) |
|------------------------|------------------------------|-----------------------------------|
| SELinux | `setenforce 0` | `/etc/selinux/config` |
| Hostname | `hostname nuevo-nombre` | `/etc/hostname` |
| Parámetros del kernel | `sysctl -w param=valor` | `/etc/sysctl.conf` |
| Firewall (iptables) | `iptables -A ...` | `/etc/sysconfig/iptables` o `iptables-save` |
| Rutas de red | `ip route add ...` | `/etc/sysconfig/network-scripts/` o NetworkManager |
| DNS resolver | — | `/etc/resolv.conf` |

### Por qué importa entender esto

- **Diagnosticar problemas**: Si un cambio "funciona" pero se pierde al reiniciar, es porque solo se aplicó en runtime. Si un cambio "no funciona" inmediatamente después de editar un archivo, es porque falta reiniciar o recargar el servicio.
- **Evitar sorpresas en producción**: Un servidor puede llevar meses sin reiniciar. Configuraciones en runtime que nunca se persistieron se perderán en el próximo reinicio.
- **Entender el flujo de arranque**: Al encender el sistema, el kernel y los servicios leen sus archivos de configuración en disco. Después de eso, cualquier modificación en runtime no actualiza esos archivos automáticamente.

> **Regla general**: Si modificas algo en runtime, asegúrate de que también esté reflejado en el archivo de configuración correspondiente. Si modificas un archivo de configuración, el cambio no aplica hasta que el servicio se recargue o el sistema se reinicie.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `getenforce` sigue mostrando `Enforcing` después de editar el config | Es normal. El cambio en `/etc/selinux/config` requiere un reinicio para aplicarse |
| `setenforce: SELinux is disabled` al intentar cambiar el modo | SELinux ya está deshabilitado. No se puede usar `setenforce` en modo `disabled` |
| Error al instalar paquetes: `No package selinux-policy available` | Verificar que los repositorios base están habilitados con `yum repolist` |
| Después de reactivar SELinux los servicios fallan | Se necesita re-etiquetar el sistema de archivos con `touch /.autorelabel && reboot` |
| `Permission denied` al editar `/etc/selinux/config` | Se requiere `sudo` o acceso root para modificar este archivo |

## Recursos

- [SELinux - Red Hat Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/using_selinux/index)
- [sestatus - Manual de Linux](https://man7.org/linux/man-pages/man8/sestatus.8.html)
- [SELinux Wiki](https://selinuxproject.org/page/Main_Page)
- [SELinux modes - Fedora Docs](https://docs.fedoraproject.org/en-US/quick-docs/selinux-changing-states-and-modes/)
