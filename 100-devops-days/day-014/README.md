# Dia 14 - Troubleshooting de Apache: Servicio caido por conflicto de puerto

## Problema / Desafio

El sistema de monitoreo reporta que Apache no esta disponible en uno de los app servers de Stratos DC. Se necesita:

1. Identificar cual de los 3 app servers tiene el problema
2. Diagnosticar y corregir la causa
3. Asegurar que Apache este corriendo en el puerto **8082** en todos los app servers

No se requiere que Apache sirva paginas, solo que el servicio este activo.

## Conceptos clave

### Diagnostico desde el jump host

Cuando hay multiples servidores, el primer paso es identificar cual tiene el problema. Desde el jump host se puede hacer `curl` a cada server para verificar rapidamente:

```
Jump Host
├── curl stapp01:8082 → ❌ Connection refused
├── curl stapp02:8082 → ✅ Responde
└── curl stapp03:8082 → ✅ Responde
```

`Connection refused` significa que **nada esta escuchando** en ese puerto (o el proceso que escucha no es HTTP). Es diferente de `No route to host` (firewall) o `timeout` (servidor inalcanzable).

### Mensajes de error de curl y su significado

| Error | Significado | Causa probable |
|-------|------------|----------------|
| `Connection refused` | El puerto esta cerrado o el servicio no esta corriendo | Servicio caido o puerto incorrecto |
| `No route to host` | Firewall bloquea el trafico | Regla de iptables/firewalld |
| `Timeout` / sin respuesta | El servidor no responde | Servidor apagado, red caida, o DROP en firewall |
| `Could not resolve host` | DNS no encuentra el hostname | Nombre incorrecto o DNS caido |

### Patron recurrente: sendmail ocupando el puerto

Este es un patron que se repite en entornos de laboratorio y produccion: **sendmail** (u otro servicio) se configura para escuchar en el mismo puerto que necesita Apache. Los sintomas son:

1. Apache no puede iniciar (puerto ocupado)
2. O Apache nunca fue iniciado y sendmail tomo el puerto

La solucion es siempre la misma: detener el proceso intruso, liberar el puerto e iniciar Apache.

## Pasos

1. Desde el jump host, hacer `curl` a los 3 app servers para identificar el servidor con problemas
2. Conectarse al servidor afectado via SSH
3. Usar `netstat` para ver que proceso ocupa el puerto 8082
4. Detener y deshabilitar el proceso intruso (sendmail)
5. Iniciar y habilitar Apache (httpd)
6. Verificar que Apache escucha en el puerto 8082
7. Validar desde el jump host con `curl`

## Comandos / Codigo

### 1. Identificar el servidor con problemas

Desde el jump host, verificar cada app server:

```bash
curl stapp01.stratos.xfusioncorp.com:8082 >/dev/null
curl stapp02.stratos.xfusioncorp.com:8082 >/dev/null
curl stapp03.stratos.xfusioncorp.com:8082 >/dev/null
```

```
# stapp01 — FALLO
curl: (7) Failed to connect to stapp01.stratos.xfusioncorp.com port 8082: Connection refused

# stapp02 — OK
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
100 2650k  100 2650k    0     0   107M      0 --:--:-- --:--:-- --:--:--  112M

# stapp03 — OK
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
100 2650k  100 2650k    0     0   136M      0 --:--:-- --:--:-- --:--:--  136M
```

El servidor `stapp01` es el que tiene el problema.

**Tip:** para verificar multiples servers de forma rapida:

```bash
for host in stapp01 stapp02 stapp03; do
  echo -n "$host: "
  curl -s -o /dev/null -w "%{http_code}" $host.stratos.xfusioncorp.com:8082 2>/dev/null || echo "FAILED"
done
```

```
stapp01: FAILED
stapp02: 200
stapp03: 200
```

### 2. Conectarse al servidor y diagnosticar

```bash
ssh tony@stapp01
```

Verificar que proceso esta en el puerto 8082:

```bash
sudo netstat -tunlp
```

```
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      519/sshd
tcp        0      0 127.0.0.1:8082          0.0.0.0:*               LISTEN      772/sendmail: accep
tcp6       0      0 :::22                   :::*                    LISTEN      519/sshd
```

**Dos problemas identificados:**

1. **sendmail** (PID 772) esta ocupando el puerto 8082
2. Escucha en `127.0.0.1:8082` (solo localhost), por eso el jump host recibe `Connection refused` en vez de una respuesta SMTP
3. **Apache (httpd) no esta corriendo** — no aparece en la lista

### 3. Verificar el estado de Apache

```bash
sudo systemctl status httpd
```

```
● httpd.service - The Apache HTTP Server
   Active: inactive (dead)
```

Apache esta instalado pero no esta corriendo. Probablemente no pudo iniciar porque sendmail ya tenia el puerto 8082 ocupado.

### 4. Detener sendmail y liberar el puerto

```bash
# Detener sendmail
sudo systemctl stop sendmail.service

# Deshabilitar para que no inicie al arrancar
sudo systemctl disable sendmail.service
```

```
Removed symlink /etc/systemd/system/multi-user.target.wants/sendmail.service
```

Verificar que el puerto quedo libre:

```bash
sudo netstat -tunlp | grep 8082
```

No deberia mostrar nada.

### 5. Iniciar Apache

```bash
# Iniciar el servicio
sudo systemctl start httpd.service

# Habilitar inicio automatico al boot
sudo systemctl enable httpd.service
```

```
Created symlink /etc/systemd/system/multi-user.target.wants/httpd.service
```

### 6. Verificar que Apache escucha en el puerto 8082

```bash
sudo netstat -tunlp
```

```
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      519/sshd
tcp        0      0 0.0.0.0:8082            0.0.0.0:*               LISTEN      1154/httpd
```

Ahora **httpd** esta escuchando en `0.0.0.0:8082` — accesible desde cualquier interfaz de red.

Notar la diferencia con sendmail:
- sendmail: `127.0.0.1:8082` → solo localhost
- httpd: `0.0.0.0:8082` → todas las interfaces

### 7. Validar desde el jump host

```bash
curl stapp01.stratos.xfusioncorp.com:8082 >/dev/null
```

```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
100  4897  100  4897    0     0   281k      0 --:--:-- --:--:-- --:--:--  281k
```

Apache responde correctamente desde el jump host.

### Verificacion final de los 3 servers

```bash
for host in stapp01 stapp02 stapp03; do
  echo -n "$host: "
  curl -s -o /dev/null -w "%{http_code}" $host.stratos.xfusioncorp.com:8082
  echo
done
```

```
stapp01: 200
stapp02: 200
stapp03: 200
```

Los 3 app servers responden correctamente en el puerto 8082.

## Resumen del flujo

```
1. curl desde jump host a los 3 servers → stapp01 falla (Connection refused)
2. SSH a stapp01 → netstat muestra sendmail en 127.0.0.1:8082
3. systemctl stop/disable sendmail → libera el puerto
4. systemctl start/enable httpd → Apache arranca en 0.0.0.0:8082
5. curl desde jump host → stapp01 responde 200
```

## Diferencia entre `systemctl stop` y `systemctl disable`

| Comando | Efecto | Persistencia |
|---------|--------|-------------|
| `stop` | Detiene el servicio **ahora** | Temporal — se reinicia en el proximo boot |
| `disable` | Remueve del inicio automatico | Permanente — no arranca al boot |
| `stop` + `disable` | Detiene ahora **y** no arranca al boot | Ambos efectos combinados |
| `start` | Inicia el servicio **ahora** | Temporal |
| `enable` | Agrega al inicio automatico | Permanente |
| `start` + `enable` | Inicia ahora **y** arranca al boot | Ambos efectos combinados |

Siempre usar ambos comandos juntos para evitar que el problema reaparezca despues de un reboot.

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `Connection refused` en un app server | Verificar con `netstat -tunlp` que proceso escucha en el puerto. Si no hay ninguno, el servicio no esta corriendo |
| sendmail ocupa el puerto de Apache | `systemctl stop sendmail && systemctl disable sendmail` |
| Apache no inicia: `Address already in use` | Otro proceso ocupa el puerto. Identificar con `netstat -tunlp \| grep 8082` y detenerlo |
| Apache inicia pero no responde externamente | Verificar que escucha en `0.0.0.0` y no en `127.0.0.1`. Revisar `Listen` en `httpd.conf` |
| Despues de reboot sendmail vuelve a aparecer | Falta `systemctl disable sendmail`. Verificar con `systemctl is-enabled sendmail` |
| `httpd.conf` no tiene el puerto correcto | Buscar con `grep -i Listen /etc/httpd/conf/httpd.conf` y corregir |

## Recursos

- [Apache HTTP Server - Binding](https://httpd.apache.org/docs/2.4/bind.html)
- [systemctl - Managing Services](https://www.freedesktop.org/software/systemd/man/systemctl.html)
- [netstat command](https://man7.org/linux/man-pages/man8/netstat.8.html)
