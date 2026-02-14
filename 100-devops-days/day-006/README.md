# Día 06 - Crear un Cron Job con Cronie

## Problema / Desafío

Instalar el paquete `cronie` en todos los app servers, iniciar el servicio `crond` y crear un cron job para el usuario `root` que ejecute `echo hello > /tmp/cron_text` cada 5 minutos.

## Conceptos clave

- **Cron**: Es el programador de tareas de Linux. Permite ejecutar comandos o scripts de forma automática en horarios definidos.
- **Cronie**: Es la implementación moderna de cron usada en distribuciones basadas en RHEL (CentOS, Rocky Linux, Fedora). Reemplaza a `vixie-cron`.
- **crond**: Es el daemon (servicio) de cron. Se ejecuta en segundo plano y lee las tablas de cron para ejecutar tareas programadas.
- **crontab**: Es el archivo donde se definen las tareas programadas de un usuario. Cada usuario puede tener su propio crontab.
- **Sintaxis de cron**:

```
┌───────────── minuto (0-59)
│ ┌───────────── hora (0-23)
│ │ ┌───────────── día del mes (1-31)
│ │ │ ┌───────────── mes (1-12)
│ │ │ │ ┌───────────── día de la semana (0-7, 0 y 7 = domingo)
│ │ │ │ │
* * * * * comando
```

- **`*/5`**: La barra (`/`) indica un intervalo. `*/5` en el campo de minutos significa "cada 5 minutos".
- **`crontab -e`**: Edita el crontab del usuario actual.
- **`crontab -l`**: Lista las entradas del crontab del usuario actual.
- **`crontab -u usuario -e`**: Edita el crontab de un usuario específico (requiere root).

## Pasos

1. Instalar el paquete `cronie` en cada app server
2. Iniciar y habilitar el servicio `crond`
3. Crear el cron job para el usuario `root`
4. Verificar que el cron job quedó registrado

## Comandos / Código

### 1. Instalar cronie

```bash
sudo yum install -y cronie
```

`cronie` incluye el daemon `crond` y la utilidad `crontab`.

### 2. Iniciar el servicio crond

```bash
sudo systemctl start crond
sudo systemctl enable crond
```

Verificar que está corriendo:

```bash
sudo systemctl status crond
```

Salida esperada:

```
● crond.service - Command Scheduler
   Loaded: loaded (/usr/lib/systemd/system/crond.service; enabled)
   Active: active (running)
```

### 3. Crear el cron job para root

```bash
crontab -l -u root
```

Si no hay crontab existente, mostrará:

```
no crontab for root
```

Agregar el cron job:

```bash
echo "*/5 * * * * echo hello > /tmp/cron_text" | crontab -u root -
```

> **Nota**: El guion (`-`) al final de `crontab -` le indica que lea la entrada desde stdin. Si root ya tiene entradas en su crontab y se quieren conservar, se debe usar un enfoque diferente (ver sección de alternativas).

### 4. Verificar el cron job

```bash
crontab -l -u root
```

Salida esperada:

```
*/5 * * * * echo hello > /tmp/cron_text
```

### Alternativa: Preservar crontab existente

Si el usuario root ya tiene cron jobs configurados, usar `echo ... | crontab -` los sobreescribiría. Para agregar sin perder las entradas existentes:

```bash
(crontab -l -u root 2>/dev/null; echo "*/5 * * * * echo hello > /tmp/cron_text") | crontab -u root -
```

Esto concatena las entradas existentes con la nueva línea antes de pasarlas a `crontab -`.

### Alternativa: Usar crontab -e

```bash
sudo crontab -e -u root
```

Esto abre el editor para agregar manualmente la línea:

```
*/5 * * * * echo hello > /tmp/cron_text
```

### Ejecutar en todos los app servers

Si se tiene acceso SSH a múltiples app servers, se puede ejecutar todo en un solo flujo:

```bash
ssh app_server "sudo yum install -y cronie && sudo systemctl start crond && sudo systemctl enable crond && echo '*/5 * * * * echo hello > /tmp/cron_text' | sudo crontab -u root -"
```

### Desglose del cron job

| Campo | Valor | Significado |
|-------|-------|-------------|
| Minuto | `*/5` | Cada 5 minutos (0, 5, 10, 15, ..., 55) |
| Hora | `*` | Todas las horas |
| Día del mes | `*` | Todos los días |
| Mes | `*` | Todos los meses |
| Día de la semana | `*` | Todos los días de la semana |
| Comando | `echo hello > /tmp/cron_text` | Escribe "hello" en `/tmp/cron_text` |

### Dónde se almacenan los crontabs

| Ubicación | Descripción |
|-----------|-------------|
| `/var/spool/cron/` | Crontabs de usuarios individuales (un archivo por usuario) |
| `/etc/crontab` | Crontab del sistema (requiere especificar usuario en cada línea) |
| `/etc/cron.d/` | Archivos de cron adicionales del sistema |
| `/etc/cron.daily/` | Scripts que se ejecutan una vez al día |
| `/etc/cron.hourly/` | Scripts que se ejecutan una vez por hora |
| `/etc/cron.weekly/` | Scripts que se ejecutan una vez por semana |
| `/etc/cron.monthly/` | Scripts que se ejecutan una vez al mes |

Cuando usamos `crontab -e` o `crontab -`, el archivo se guarda en `/var/spool/cron/<usuario>`. Para root sería `/var/spool/cron/root`.

## Redirección de file descriptors: `2>/dev/null` y `2>&1`

En el comando de la sección "Preservar crontab existente" se usa `2>/dev/null`. Para entender por qué, hay que conocer los **file descriptors** (descriptores de archivo) que Linux asigna a todo proceso:

| FD | Nombre | Descripción |
|----|--------|-------------|
| `0` | `stdin` | Entrada estándar (lo que el proceso lee) |
| `1` | `stdout` | Salida estándar (output normal) |
| `2` | `stderr` | Salida de errores |

Por defecto, tanto `stdout` como `stderr` se imprimen en la terminal, pero son flujos separados y se pueden redirigir de forma independiente.

### `2>/dev/null` — Descartar errores

Redirige **stderr** (FD 2) a `/dev/null`, un archivo especial que descarta todo lo que recibe (un "agujero negro").

En el contexto de este día:

```bash
(crontab -l -u root 2>/dev/null; echo "*/5 * * * * echo hello > /tmp/cron_text") | crontab -u root -
```

Si root no tiene crontab, `crontab -l` imprime `no crontab for root` por **stderr**. Sin `2>/dev/null`, ese mensaje de error se mezclaría con la salida del subshell y terminaría como una línea dentro del nuevo crontab. Al descartarlo con `2>/dev/null`, solo pasa la nueva línea del `echo`.

### `2>&1` — Fusionar stderr con stdout

Redirige **stderr** (FD 2) al **mismo destino** que stdout (FD 1). El `&` indica que `1` es un file descriptor, no un archivo llamado "1".

```bash
# Sin redirección: stdout y stderr van a la terminal por separado
comando

# Con 2>&1: stderr se fusiona con stdout
comando 2>&1
```

Uso común — guardar toda la salida (normal + errores) en un log:

```bash
./script.sh > /tmp/output.log 2>&1
```

Sin `2>&1`, solo stdout iría al archivo y los errores seguirían apareciendo en la terminal.

### Resumen de combinaciones

```bash
comando > archivo          # stdout → archivo, stderr → terminal
comando 2> archivo         # stdout → terminal, stderr → archivo
comando > archivo 2>&1     # stdout → archivo, stderr → mismo archivo
comando 2>/dev/null        # stdout → terminal, stderr → descartado
comando > /dev/null 2>&1   # todo descartado (silencio total)
```

### Por qué `>` y `2>` son operadores diferentes

El número antes de `>` indica **qué file descriptor** se redirige:

| Operador | Equivalente explícito | Qué redirige |
|----------|----------------------|--------------|
| `>` | `1>` | stdout (se asume FD 1 por defecto) |
| `2>` | — | stderr (FD 2 explícito) |
| `&>` | `> archivo 2>&1` | Ambos (shortcut en bash) |

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `crond` no inicia: `Unit crond.service not found` | El paquete `cronie` no está instalado. Ejecutar `yum install -y cronie` |
| `crontab: command not found` | Instalar `cronie` que incluye el binario `crontab` |
| El cron job no se ejecuta | Verificar que `crond` está activo con `systemctl status crond` |
| El archivo `/tmp/cron_text` no aparece | Esperar al menos 5 minutos. Verificar el cron con `crontab -l -u root` |
| `echo ... | crontab -` sobreescribió los cron jobs existentes | Restaurar desde backup si existe, o reconstruir. Usar la alternativa con `(crontab -l; echo ...) | crontab -` |
| Cron ejecuta el comando pero el archivo no tiene el contenido esperado | Verificar que la redirección `>` es correcta (sobreescribe) vs `>>` (agrega) |

## Recursos

- [crontab - Manual de Linux](https://man7.org/linux/man-pages/man5/crontab.5.html)
- [cronie - GitHub](https://github.com/cronie-crond/cronie)
- [Crontab Guru - Editor visual de expresiones cron](https://crontab.guru/)
- [Red Hat - Automating system tasks with cron](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/automating_system_administration_by_using_rhel_system_roles/assembly_automating-system-tasks-using-cron_automating-system-administration-by-using-rhel-system-roles)
