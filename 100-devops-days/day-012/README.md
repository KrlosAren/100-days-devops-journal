# Dia 12 - Troubleshooting de Apache: Puerto ocupado por otro proceso

## Problema / Desafio

El sistema de monitoreo reporta que el servicio Apache en `stapp01` no es accesible en el puerto **5004**. Se necesita diagnosticar la causa raiz y restaurar el servicio Apache en ese puerto, asegurandose de que sea accesible desde el jump host sin comprometer la seguridad del servidor.

Verificacion final: `curl http://stapp01:5004` desde el jump host.

## Conceptos clave

### Metodologia de troubleshooting de puertos

Cuando un servicio no responde en el puerto esperado, hay tres posibles causas:

| Causa | Como verificar |
|-------|---------------|
| El servicio no esta corriendo | `systemctl status httpd` |
| Otro proceso ocupa el puerto | `netstat -tunlp` o `ss -tunlp` |
| El firewall bloquea el puerto | `iptables -L -n` o `firewall-cmd --list-all` |

El orden de diagnostico recomendado es: **puerto → servicio → firewall**.

### Herramientas de diagnostico

| Herramienta | Uso | Ejemplo |
|-------------|-----|---------|
| `netstat -tunlp` | Ver que proceso escucha en cada puerto | `netstat -tunlp \| grep 5004` |
| `ss -tunlp` | Alternativa moderna a netstat | `ss -tunlp \| grep 5004` |
| `telnet` | Probar conectividad a un puerto | `telnet localhost 5004` |
| `curl` | Probar respuesta HTTP | `curl http://localhost:5004` |
| `systemctl status` | Ver estado de un servicio | `systemctl status httpd` |

### sendmail

Sendmail es un agente de transferencia de correo (MTA) que usa el protocolo SMTP. En este caso, sendmail estaba configurado para escuchar en el puerto 5004, que es el mismo puerto que necesita Apache. La respuesta `220 ... ESMTP Sendmail` al hacer `telnet` o `curl` confirma que el servicio en ese puerto es sendmail, no Apache.

## Pasos

1. Diagnosticar que proceso ocupa el puerto 5004
2. Detener el proceso que ocupa el puerto (sendmail)
3. Verificar la configuracion de Apache para que use el puerto 5004
4. Iniciar el servicio Apache
5. Verificar que Apache responde en el puerto 5004
6. Verificar que el firewall permite el trafico en el puerto 5004
7. Validar desde el jump host con `curl`

## Comandos / Codigo

### 1. Diagnostico inicial

Verificar que proceso esta escuchando en el puerto 5004:

```bash
sudo netstat -tunlp
```

```
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 127.0.0.1:5004          0.0.0.0:*               LISTEN      502/sendmail: accep
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      313/sshd
```

El puerto 5004 esta ocupado por **sendmail** (PID 502), no por Apache.

Confirmar con `curl` y `telnet`:

```bash
curl localhost:5004
```

```
220 stapp01.stratos.xfusioncorp.com ESMTP Sendmail 8.15.2/8.15.2
421 4.7.0 stapp01.stratos.xfusioncorp.com Rejecting open proxy localhost [127.0.0.1]
```

```bash
telnet localhost 5004
```

```
Trying 127.0.0.1...
Connected to localhost.
220 stapp01.stratos.xfusioncorp.com ESMTP Sendmail 8.15.2/8.15.2
```

La respuesta `220 ... ESMTP Sendmail` confirma que es sendmail, no Apache.

### 2. Detener sendmail y liberar el puerto

```bash
# Detener el servicio sendmail
sudo systemctl stop sendmail

# Deshabilitar para que no inicie al arrancar
sudo systemctl disable sendmail

# Verificar que el puerto quedo libre
sudo netstat -tunlp | grep 5004
```

No deberia mostrar nada, indicando que el puerto 5004 esta libre.

**Alternativa:** si sendmail no es un servicio de systemd, matar el proceso directamente:

```bash
# Matar el proceso por PID
sudo kill 502

# O matar todos los procesos de sendmail
sudo pkill sendmail

# Verificar que murio
sudo netstat -tunlp | grep 5004
```

### 3. Verificar la configuracion de Apache

Antes de iniciar Apache, confirmar que esta configurado para escuchar en el puerto 5004:

```bash
# Buscar la directiva Listen en la configuracion de Apache
sudo grep -i "Listen" /etc/httpd/conf/httpd.conf
```

```
Listen 5004
```

Si el puerto no es 5004, cambiarlo:

```bash
sudo sed -i 's/Listen [0-9]*/Listen 5004/' /etc/httpd/conf/httpd.conf

# Verificar el cambio
sudo grep -i "Listen" /etc/httpd/conf/httpd.conf
```

### 4. Iniciar Apache

```bash
# Iniciar el servicio
sudo systemctl start httpd

# Habilitar inicio automatico
sudo systemctl enable httpd

# Verificar estado
sudo systemctl status httpd
```

```
● httpd.service - The Apache HTTP Server
   Active: active (running)
```

### 5. Verificar que Apache responde localmente

```bash
# Verificar que Apache escucha en el puerto 5004
sudo netstat -tunlp | grep 5004
```

```
tcp   0   0   0.0.0.0:5004   0.0.0.0:*   LISTEN   1234/httpd
```

**Importante:** Apache debe escuchar en `0.0.0.0:5004` (todas las interfaces), no en `127.0.0.1:5004` (solo localhost). Si escucha en `127.0.0.1`, no sera accesible desde otros servidores.

```bash
# Probar la respuesta HTTP
curl http://localhost:5004
```

### 6. Verificar y corregir el firewall (iptables)

Este es el paso mas critico. Aunque Apache funcione localmente, si iptables bloquea el trafico entrante, el jump host recibira `No route to host`.

```bash
# Ver reglas con numeros de linea
sudo iptables -L -n --line-numbers
```

```
Chain INPUT (policy ACCEPT)
num  target     prot opt source               destination
1    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0            state RELATED,ESTABLISHED
2    ACCEPT     icmp --  0.0.0.0/0            0.0.0.0/0
3    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0
4    ACCEPT     tcp  --  0.0.0.0/0            0.0.0.0/0            state NEW tcp dpt:22
5    REJECT     all  --  0.0.0.0/0            0.0.0.0/0            reject-with icmp-host-prohibited
6    ACCEPT     tcp  --  0.0.0.0/0            0.0.0.0/0            tcp dpt:5000
```

**Dos problemas encontrados:**

1. La regla ACCEPT para el puerto esta en la **linea 6**, despues del REJECT en la **linea 5**. Las reglas de iptables se evaluan en orden — el REJECT matchea todo el trafico antes de que llegue al ACCEPT, por eso el jump host recibe `No route to host`
2. La regla apunta al puerto **5000**, no al **5004** que necesita Apache

#### Como funciona el orden en iptables

```
Paquete TCP al puerto 5004 llega →
  Regla 1: RELATED,ESTABLISHED? → No (es conexion nueva) → siguiente
  Regla 2: ICMP? → No (es TCP) → siguiente
  Regla 3: loopback? → No (viene de otra maquina) → siguiente
  Regla 4: TCP dpt:22? → No (es puerto 5004) → siguiente
  Regla 5: REJECT all → SI → ❌ Paquete rechazado (nunca llega a regla 6)
```

#### Solucion: insertar la regla ANTES del REJECT

```bash
# Insertar regla para puerto 5004 en posicion 5 (empuja el REJECT a la 6)
sudo iptables -I INPUT 5 -p tcp --dport 5004 -j ACCEPT
```

Eliminar la regla vieja incorrecta (puerto 5000, ahora en posicion 7):

```bash
sudo iptables -D INPUT 7
```

Verificar que quedo correcto:

```bash
sudo iptables -L -n --line-numbers
```

```
Chain INPUT (policy ACCEPT)
num  target     prot opt source               destination
1    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0            state RELATED,ESTABLISHED
2    ACCEPT     icmp --  0.0.0.0/0            0.0.0.0/0
3    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0
4    ACCEPT     tcp  --  0.0.0.0/0            0.0.0.0/0            state NEW tcp dpt:22
5    ACCEPT     tcp  --  0.0.0.0/0            0.0.0.0/0            tcp dpt:5004
6    REJECT     all  --  0.0.0.0/0            0.0.0.0/0            reject-with icmp-host-prohibited
```

Ahora el flujo es:

```
Paquete TCP al puerto 5004 llega →
  Regla 1-4: No matchean → siguiente
  Regla 5: TCP dpt:5004? → SI → ✅ Paquete aceptado
```

#### Diferencia entre `-A` (append) e `-I` (insert)

| Flag | Accion | Cuando usar |
|------|--------|-------------|
| `-A` (append) | Agrega la regla **al final** de la cadena | Cuando no hay regla REJECT/DROP antes |
| `-I` (insert) | Inserta la regla en una **posicion especifica** | Cuando existe un REJECT/DROP que bloquea todo |

**Error comun:** usar `-A` cuando hay un REJECT. La regla se agrega despues del REJECT y nunca se evalua. Siempre verificar el orden con `--line-numbers`.

**Nota importante sobre seguridad:** no se deben deshabilitar `iptables` completamente. El desafio dice "sin comprometer la seguridad", asi que la solucion correcta es **insertar una regla especifica** para el puerto 5004, no eliminar el REJECT ni abrir todo.

### 7. Validar desde el jump host

```bash
curl http://stapp01:5004
```

La respuesta debe ser el contenido HTML servido por Apache.

## Resumen del flujo de diagnostico

```
1. netstat -tunlp → Puerto 5004 ocupado por sendmail (no Apache)
2. curl/telnet    → Confirma respuesta ESMTP (sendmail)
3. systemctl stop sendmail → Libera el puerto
4. grep Listen httpd.conf  → Confirma config de Apache en puerto 5004
5. systemctl start httpd   → Levanta Apache
6. netstat -tunlp → Confirma Apache en 0.0.0.0:5004
7. iptables -L   → Verifica firewall abierto
8. curl stapp01:5004 → Validacion final desde jump host
```

## Guia de iptables

### Estructura de un comando iptables

```
iptables -[accion] [cadena] [condiciones] -j [target]
```

```
iptables -A INPUT -p tcp -s 192.168.1.10 --dport 5004 -j ACCEPT
         │  │      │       │               │             │
         │  │      │       │               │             └─ Que hacer (ACCEPT/DROP/REJECT)
         │  │      │       │               └─ Puerto destino
         │  │      │       └─ IP origen
         │  │      └─ Protocolo (tcp/udp/icmp)
         │  └─ Cadena (INPUT/OUTPUT/FORWARD)
         └─ Accion (-A append / -I insert / -D delete)
```

### Acciones principales

| Flag | Accion | Descripcion | Ejemplo |
|------|--------|-------------|---------|
| `-A` | Append | Agrega la regla **al final** de la cadena | `iptables -A INPUT ...` |
| `-I` | Insert | Inserta en una **posicion especifica** | `iptables -I INPUT 3 ...` |
| `-D` | Delete | Elimina una regla por numero o por definicion | `iptables -D INPUT 5` |
| `-R` | Replace | Reemplaza una regla en una posicion | `iptables -R INPUT 3 ...` |
| `-F` | Flush | Elimina **todas** las reglas de una cadena | `iptables -F INPUT` |
| `-L` | List | Lista las reglas | `iptables -L -n --line-numbers` |
| `-P` | Policy | Cambia la politica por defecto de la cadena | `iptables -P INPUT DROP` |

### Cadenas (chains)

Las cadenas determinan en que punto del trafico se evalua la regla:

| Cadena | Trafico que evalua | Ejemplo de uso |
|--------|-------------------|----------------|
| `INPUT` | Paquetes que **llegan** al servidor | Permitir/bloquear acceso a servicios |
| `OUTPUT` | Paquetes que **salen** del servidor | Restringir conexiones salientes |
| `FORWARD` | Paquetes que **pasan a traves** del servidor (routing) | Servidores que actuan como gateway/router |

```
                    ┌─────────┐
Trafico entrante →  │  INPUT  │ → Procesos locales (Apache, SSH, etc.)
                    └─────────┘
                    ┌─────────┐
Procesos locales →  │ OUTPUT  │ → Trafico saliente
                    └─────────┘
                    ┌─────────┐
Trafico entrante →  │ FORWARD │ → Trafico saliente (sin pasar por procesos locales)
                    └─────────┘
```

### Targets (que hacer con el paquete)

| Target | Comportamiento | El cliente ve |
|--------|---------------|---------------|
| `ACCEPT` | Permite el paquete | Conexion exitosa |
| `DROP` | Descarta silenciosamente | Timeout (sin respuesta) |
| `REJECT` | Rechaza y envia respuesta ICMP | `No route to host` o `Connection refused` |
| `LOG` | Registra en syslog y continua evaluando | Nada (solo logging) |

**DROP vs REJECT:** `DROP` es mas seguro (no revela que el servidor existe), pero `REJECT` es mas amigable para diagnostico porque el cliente recibe una respuesta inmediata en vez de esperar un timeout.

### Condiciones de filtrado

#### Por protocolo (`-p`)

```bash
# Solo trafico TCP
iptables -A INPUT -p tcp --dport 5004 -j ACCEPT

# Solo trafico UDP
iptables -A INPUT -p udp --dport 53 -j ACCEPT

# Solo ICMP (ping)
iptables -A INPUT -p icmp -j ACCEPT
```

#### Por IP origen (`-s`)

```bash
# Permitir desde una IP especifica
iptables -A INPUT -p tcp -s 172.16.238.3 --dport 5004 -j ACCEPT

# Bloquear una IP especifica
iptables -A INPUT -s 10.0.0.50 -j DROP
```

#### Por rango de IPs (notacion CIDR)

```bash
# Permitir toda la subred 172.16.238.0/24 (256 IPs: 172.16.238.0 - 172.16.238.255)
iptables -A INPUT -p tcp -s 172.16.238.0/24 --dport 5004 -j ACCEPT

# Permitir la red 10.0.0.0/8 (todo el rango 10.x.x.x)
iptables -A INPUT -p tcp -s 10.0.0.0/8 --dport 5004 -j ACCEPT

# Permitir un rango mas reducido /28 (16 IPs: 192.168.1.0 - 192.168.1.15)
iptables -A INPUT -p tcp -s 192.168.1.0/28 --dport 5004 -j ACCEPT
```

**Referencia rapida de CIDR:**

| CIDR | IPs | Mascara | Ejemplo |
|------|-----|---------|---------|
| `/32` | 1 | 255.255.255.255 | Host unico |
| `/24` | 256 | 255.255.255.0 | Red tipica |
| `/16` | 65,536 | 255.255.0.0 | Red grande |
| `/8` | 16,777,216 | 255.0.0.0 | Red muy grande |

#### Por hostname/dominio (`-s`)

```bash
# Permitir por hostname (resuelve a IP al momento de crear la regla)
iptables -A INPUT -p tcp -s jump_host.stratos.xfusioncorp.com --dport 5004 -j ACCEPT
```

**Advertencia:** iptables resuelve el hostname a IP **una sola vez** al crear la regla. Si la IP del host cambia (DHCP, DNS dinamico), la regla queda apuntando a la IP vieja. En produccion siempre preferir IPs.

#### Por IP destino (`-d`)

```bash
# Solo para trafico dirigido a una IP especifica del servidor
iptables -A INPUT -p tcp -d 172.16.238.10 --dport 5004 -j ACCEPT
```

Util cuando el servidor tiene multiples interfaces de red.

#### Por puerto (`--dport` / `--sport`)

```bash
# Puerto destino (el mas comun)
iptables -A INPUT -p tcp --dport 5004 -j ACCEPT

# Puerto origen (poco comun)
iptables -A INPUT -p tcp --sport 443 -j ACCEPT

# Rango de puertos
iptables -A INPUT -p tcp --dport 5000:5010 -j ACCEPT

# Multiples puertos (requiere -m multiport)
iptables -A INPUT -p tcp -m multiport --dports 80,443,5004 -j ACCEPT
```

#### Por interfaz de red (`-i` / `-o`)

```bash
# Solo trafico que entra por eth0
iptables -A INPUT -i eth0 -p tcp --dport 5004 -j ACCEPT

# Solo trafico de loopback (localhost)
iptables -A INPUT -i lo -j ACCEPT

# Trafico saliente por eth1
iptables -A OUTPUT -o eth1 -p tcp --dport 443 -j ACCEPT
```

#### Por estado de conexion (`-m state`)

```bash
# Permitir conexiones ya establecidas y relacionadas
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Solo conexiones nuevas al puerto 5004
iptables -A INPUT -p tcp -m state --state NEW --dport 5004 -j ACCEPT
```

| Estado | Significado |
|--------|------------|
| `NEW` | Primer paquete de una conexion nueva |
| `ESTABLISHED` | Paquete de una conexion ya establecida |
| `RELATED` | Relacionado con una conexion existente (ej: FTP data) |
| `INVALID` | Paquete que no pertenece a ninguna conexion conocida |

### Negar condiciones (`!`)

```bash
# Aceptar de todos EXCEPTO una IP
iptables -A INPUT -p tcp ! -s 10.0.0.50 --dport 5004 -j ACCEPT

# Aceptar en todos los puertos EXCEPTO el 22
iptables -A INPUT -p tcp ! --dport 22 -j ACCEPT
```

### Ejemplos practicos combinados

```bash
# Permitir SSH solo desde la red interna
iptables -A INPUT -p tcp -s 172.16.238.0/24 --dport 22 -j ACCEPT

# Permitir HTTP/HTTPS desde cualquier lugar
iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT

# Permitir Apache en 5004 solo desde el jump host
iptables -I INPUT 5 -p tcp -s 172.16.238.3 --dport 5004 -j ACCEPT

# Bloquear todo el trafico de una IP sospechosa
iptables -I INPUT 1 -s 203.0.113.50 -j DROP

# Permitir ping pero limitar a 1 por segundo (anti flood)
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT

# Loguear y despues dropear trafico sospechoso
iptables -A INPUT -p tcp --dport 5004 -s 203.0.113.0/24 -j LOG --log-prefix "BLOCKED: "
iptables -A INPUT -p tcp --dport 5004 -s 203.0.113.0/24 -j DROP
```

### Persistencia de reglas

Las reglas de iptables se pierden al reiniciar el servidor. Para hacerlas persistentes:

```bash
# En CentOS/RHEL: guardar reglas actuales
sudo iptables-save > /etc/sysconfig/iptables

# O usando el servicio
sudo service iptables save

# En Debian/Ubuntu: instalar iptables-persistent
sudo apt install iptables-persistent
sudo netfilter-persistent save
```

### Ver y limpiar reglas

```bash
# Listar reglas con numeros y sin resolver DNS
sudo iptables -L -n --line-numbers

# Listar con contadores de paquetes (util para debug)
sudo iptables -L -n -v

# Ver reglas en formato "comando" (util para backup/restore)
sudo iptables -S

# Eliminar una regla por numero
sudo iptables -D INPUT 5

# Eliminar todas las reglas de INPUT
sudo iptables -F INPUT

# Eliminar TODAS las reglas de TODAS las cadenas
sudo iptables -F
```

## Diferencia entre `127.0.0.1` y `0.0.0.0`

| Direccion | Accesible desde | Uso |
|-----------|----------------|-----|
| `127.0.0.1` (localhost) | Solo la misma maquina | Servicios internos |
| `0.0.0.0` (todas las interfaces) | Cualquier maquina en la red | Servicios que deben ser accesibles externamente |

Sendmail estaba escuchando en `127.0.0.1:5004`, lo que significaba que aunque se identificara como SMTP, solo era accesible localmente. Apache debe escuchar en `0.0.0.0:5004` para ser alcanzable desde el jump host.

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| Puerto 5004 sigue ocupado despues de `stop sendmail` | Verificar con `ps aux \| grep sendmail` si quedo algun proceso zombie. Usar `kill -9 <PID>` |
| Apache no inicia: `Address already in use` | Otro proceso aun ocupa el puerto. Verificar con `netstat -tunlp \| grep 5004` |
| Apache inicia pero no responde desde jump host | Verificar que escucha en `0.0.0.0:5004` (no `127.0.0.1`). Verificar reglas de firewall con `iptables -L -n` |
| `curl: (7) No route to host` desde jump host | El firewall esta rechazando la conexion. Verificar con `iptables -L -n --line-numbers` que la regla ACCEPT para el puerto 5004 este **antes** de cualquier regla REJECT. Usar `-I INPUT <pos>` en vez de `-A INPUT` |
| Regla de iptables agregada pero sigue sin funcionar | La regla puede estar despues de un REJECT. Verificar posicion con `--line-numbers` y usar `-I` para insertar en la posicion correcta |
| `curl` responde pero con error 403 Forbidden | Revisar permisos del `DocumentRoot` y configuracion de `<Directory>` en `httpd.conf` |
| `httpd.conf` no tiene `Listen 5004` | Buscar en archivos de configuracion adicionales: `grep -r "Listen" /etc/httpd/` |
| `systemctl start httpd` falla con error de sintaxis | Verificar la configuracion con `apachectl configtest` antes de iniciar |

## Recursos

- [Apache HTTP Server - Listen Directive](https://httpd.apache.org/docs/2.4/bind.html)
- [netstat command](https://man7.org/linux/man-pages/man8/netstat.8.html)
- [iptables tutorial](https://www.frozentux.net/iptables-tutorial/iptables-tutorial.html)
- [Troubleshooting Apache](https://httpd.apache.org/docs/2.4/misc/perf-tuning.html)
