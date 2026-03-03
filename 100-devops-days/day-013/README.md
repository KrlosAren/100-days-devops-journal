# Dia 13 - Implementar iptables para restringir acceso a Apache

## Problema / Desafio

El equipo de seguridad ha detectado que el servidor Apache esta expuesto a todo el rango de IPs (`0.0.0.0/0`) porque no existen reglas de firewall configuradas. Se necesita implementar iptables para:

1. Instalar iptables en el servidor
2. Bloquear el acceso al puerto **8082** (Apache) para todo el mundo **excepto** el LBR host (Load Balancer)
3. Asegurar que las reglas persistan despues de un reboot

## Conceptos clave

### Por que restringir el acceso

Sin firewall, cualquier IP en la red puede acceder al servidor Apache directamente. En una arquitectura con Load Balancer, el trafico debe fluir asi:

```
SIN FIREWALL (inseguro):
Cliente → Apache:8082     ← Cualquiera puede acceder directamente
Cliente → LBR → Apache:8082

CON FIREWALL (seguro):
Cliente → Apache:8082     ← BLOQUEADO
Cliente → LBR → Apache:8082  ← Solo el LBR puede llegar
```

Restringir el acceso al puerto 8082 solo desde el LBR host garantiza que:
- Todo el trafico pasa por el Load Balancer
- El LBR puede aplicar rate limiting, SSL termination, health checks
- El servidor Apache no esta expuesto directamente a internet

### iptables vs firewalld

| | iptables | firewalld |
|---|----------|-----------|
| Tipo | Herramienta de bajo nivel | Frontend de alto nivel |
| Configuracion | Reglas directas con flags | Zonas y servicios |
| Persistencia | Requiere `iptables-save` o `iptables-persistent` | Persistente con `--permanent` |
| Disponible en | Todas las distros Linux | CentOS/RHEL 7+, Fedora |
| Control | Granular y preciso | Mas simple pero menos flexible |

En servidores donde se necesita control granular, iptables es la opcion preferida.

### Estrategia de reglas: whitelist vs blacklist

| Estrategia | Enfoque | Seguridad |
|------------|---------|-----------|
| **Whitelist** (recomendada) | Bloquear todo, permitir solo lo necesario | Alta — solo lo explicito esta permitido |
| **Blacklist** | Permitir todo, bloquear lo peligroso | Baja — lo que olvides queda abierto |

Para este ejercicio usamos **whitelist**: bloqueamos el puerto 8082 para todos y solo permitimos el LBR host.

## Pasos

1. Instalar iptables y el servicio de persistencia
2. Verificar las reglas actuales (deberian estar vacias)
3. Agregar regla para permitir acceso al puerto 8082 solo desde el LBR host
4. Agregar regla para bloquear el puerto 8082 para todos los demas
5. Guardar las reglas para que persistan despues de reboot
6. Verificar las reglas y probar el acceso

## Comandos / Codigo

### 1. Instalar iptables

En CentOS/RHEL:

```bash
# Instalar iptables y el servicio de persistencia
sudo yum install -y iptables-services

# Habilitar e iniciar el servicio
sudo systemctl enable iptables
sudo systemctl start iptables

# Verificar que esta activo
sudo systemctl status iptables
```

```
● iptables.service - IPv4 firewall with iptables
   Active: active (exited)
```

En Debian/Ubuntu:

```bash
sudo apt install -y iptables iptables-persistent
```

**Nota:** si `firewalld` esta activo, puede haber conflicto. Detenerlo antes de usar iptables:

```bash
# Verificar si firewalld esta corriendo
sudo systemctl status firewalld

# Si esta activo, detenerlo y deshabilitarlo
sudo systemctl stop firewalld
sudo systemctl disable firewalld
```

### 2. Verificar las reglas actuales

```bash
sudo iptables -L -n --line-numbers
```

```
Chain INPUT (policy ACCEPT)
num  target  prot opt source       destination

Chain FORWARD (policy ACCEPT)
num  target  prot opt source       destination

Chain OUTPUT (policy ACCEPT)
num  target  prot opt source       destination
```

Sin reglas — todo el trafico esta permitido. Esto confirma el problema reportado por el equipo de seguridad.

### 3. Permitir acceso al puerto 8082 desde el LBR host

Primero identificar la IP del LBR host:

```bash
# Obtener la IP del LBR host
getent hosts lbr-host
# o
ping -c 1 lbr-host
```

Supongamos que la IP del LBR host es `172.16.238.14`:

```bash
# Permitir trafico TCP al puerto 8082 SOLO desde el LBR host
sudo iptables -A INPUT -p tcp -s 172.16.238.14 --dport 8082 -j ACCEPT
```

**Importante:** esta regla debe ir **ANTES** de la regla de bloqueo. Las reglas de iptables se evaluan en orden.

### 4. Bloquear el puerto 8082 para todos los demas

```bash
# Rechazar trafico TCP al puerto 8082 desde cualquier otro origen
sudo iptables -A INPUT -p tcp --dport 8082 -j DROP
```

### 5. Verificar las reglas

```bash
sudo iptables -L -n --line-numbers
```

```
Chain INPUT (policy ACCEPT)
num  target  prot opt source          destination
1    ACCEPT  tcp  --  172.16.238.14   0.0.0.0/0    tcp dpt:8082
2    DROP    tcp  --  0.0.0.0/0       0.0.0.0/0    tcp dpt:8082
```

El flujo de evaluacion:

```
Paquete TCP al puerto 8082 llega →
  Regla 1: Viene del LBR (172.16.238.14)? → SI → ✅ ACCEPT
  Regla 1: Viene del LBR (172.16.238.14)? → NO → siguiente
  Regla 2: TCP al puerto 8082? → SI → ❌ DROP (silencioso)
```

### 6. Persistir las reglas despues de reboot

Las reglas de iptables se almacenan en memoria. Si el servidor se reinicia, **se pierden**. Hay que guardarlas:

#### En CentOS/RHEL (con iptables-services):

```bash
# Guardar las reglas actuales al archivo de configuracion
sudo service iptables save
```

```
iptables: Saving firewall rules to /etc/sysconfig/iptables: [  OK  ]
```

Esto escribe las reglas en `/etc/sysconfig/iptables`. El servicio `iptables` las carga automaticamente al iniciar.

Verificar el archivo guardado:

```bash
cat /etc/sysconfig/iptables
```

```
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p tcp -s 172.16.238.14 --dport 8082 -j ACCEPT
-A INPUT -p tcp --dport 8082 -j DROP
COMMIT
```

#### En Debian/Ubuntu (con iptables-persistent):

```bash
# Guardar las reglas
sudo netfilter-persistent save
```

Las reglas se guardan en `/etc/iptables/rules.v4` y `/etc/iptables/rules.v6`.

#### Alternativa manual (cualquier distro):

```bash
# Guardar
sudo iptables-save > /etc/iptables.rules

# Para restaurar manualmente
sudo iptables-restore < /etc/iptables.rules
```

Para cargar automaticamente al boot, agregar en `/etc/rc.local` o crear un servicio systemd.

### 7. Verificar la persistencia

```bash
# Simular un reboot reiniciando el servicio
sudo systemctl restart iptables

# Verificar que las reglas siguen
sudo iptables -L -n --line-numbers
```

Las reglas deben seguir intactas despues del reinicio.

### 8. Probar el acceso

```bash
# Desde el LBR host — debe funcionar
curl http://stapp01:8082
# Respuesta: HTML de Apache

# Desde cualquier otro host — debe fallar (timeout por DROP)
curl http://stapp01:8082
# curl: (7) Failed to connect... (timeout)
```

## Reglas adicionales recomendadas

En un servidor de produccion, ademas de restringir el puerto 8082, se recomienda:

```bash
# 1. Permitir trafico de loopback (localhost)
sudo iptables -I INPUT 1 -i lo -j ACCEPT

# 2. Permitir conexiones ya establecidas (respuestas a conexiones salientes)
sudo iptables -I INPUT 2 -m state --state ESTABLISHED,RELATED -j ACCEPT

# 3. Permitir SSH (para no perder acceso al servidor)
sudo iptables -I INPUT 3 -p tcp --dport 22 -j ACCEPT

# 4. Permitir ping (ICMP) para monitoreo
sudo iptables -I INPUT 4 -p icmp -j ACCEPT

# 5. Regla del LBR (ya creada)
# 6. DROP al puerto 8082 (ya creada)

# Guardar todo
sudo service iptables save
```

Resultado final:

```
Chain INPUT (policy ACCEPT)
num  target     prot opt source          destination
1    ACCEPT     all  --  0.0.0.0/0       0.0.0.0/0        (loopback)
2    ACCEPT     all  --  0.0.0.0/0       0.0.0.0/0        state ESTABLISHED,RELATED
3    ACCEPT     tcp  --  0.0.0.0/0       0.0.0.0/0        tcp dpt:22
4    ACCEPT     icmp --  0.0.0.0/0       0.0.0.0/0
5    ACCEPT     tcp  --  172.16.238.14   0.0.0.0/0        tcp dpt:8082
6    DROP       tcp  --  0.0.0.0/0       0.0.0.0/0        tcp dpt:8082
```

## DROP vs REJECT en este contexto

Para este ejercicio se usa `DROP` en vez de `REJECT`:

| Target | Comportamiento | El atacante ve |
|--------|---------------|---------------|
| `DROP` | Descarta el paquete silenciosamente | Timeout — no sabe si el servidor existe |
| `REJECT` | Envia respuesta ICMP de rechazo | `Connection refused` — sabe que el servidor existe |

`DROP` es mas seguro para puertos que no deben ser visibles al exterior, porque no revela informacion sobre el servidor.

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| LBR no puede acceder al puerto 8082 | Verificar que la IP del LBR es correcta. Verificar que la regla ACCEPT esta antes del DROP con `iptables -L -n --line-numbers` |
| Reglas desaparecen despues de reboot | Ejecutar `sudo service iptables save` o `sudo netfilter-persistent save` |
| Se perdio acceso SSH al servidor | Siempre agregar una regla ACCEPT para el puerto 22 antes de cualquier DROP general. Si ya se perdio acceso, usar consola fisica o IPMI |
| `iptables: No chain/target/match by that name` | El modulo de kernel no esta cargado. Ejecutar `sudo modprobe ip_tables` |
| Conflicto con firewalld | Detener firewalld: `sudo systemctl stop firewalld && sudo systemctl disable firewalld` |
| `service iptables save` no funciona | Instalar `iptables-services`: `sudo yum install -y iptables-services` |

## Recursos

- [iptables - Arch Wiki](https://wiki.archlinux.org/title/Iptables)
- [iptables Essentials - DigitalOcean](https://www.digitalocean.com/community/tutorials/iptables-essentials-common-firewall-rules-and-commands)
- [Linux Firewalls Using iptables](https://www.netfilter.org/documentation/)
- [iptables-persistent - Debian Wiki](https://wiki.debian.org/iptables)
