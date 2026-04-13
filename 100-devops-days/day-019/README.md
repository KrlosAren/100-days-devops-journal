# Dia 19 - Configurar Apache para servir multiples sitios con Alias

## Problema / Desafio

Preparar un servidor Apache en app server 2 para hospedar dos sitios web estaticos:

1. Instalar `httpd` y dependencias en app server 2
2. Apache debe servir en el puerto **3004**
3. Copiar los backups `/home/thor/media` y `/home/thor/cluster` desde el jump host al app server
4. Configurar Apache para que `http://localhost:3004/media/` sirva el sitio media y `http://localhost:3004/cluster/` sirva el sitio cluster
5. Verificar con `curl` que ambos sitios respondan correctamente

## Conceptos clave

### Directiva Alias en Apache

`Alias` permite mapear una URL a un directorio fuera (o dentro) del `DocumentRoot`. Apache sirve archivos desde esa ruta cuando el cliente accede a la URL especificada:

```apache
Alias /ruta-url "/ruta/en/el/filesystem"
```

```
Sin Alias:
  http://localhost/page.html → /var/www/html/page.html (DocumentRoot)

Con Alias:
  http://localhost/media/    → /var/www/html/media/index.html
  http://localhost/cluster/  → /var/www/html/cluster/index.html
```

### Alias vs VirtualHost

| Metodo | Uso | Ejemplo |
|--------|-----|---------|
| `Alias` | Multiples rutas en el **mismo** servidor/puerto | `/media/`, `/cluster/` en `:3004` |
| `VirtualHost` | Multiples dominios o puertos **separados** | `site1.com:80`, `site2.com:80` |

Para este caso `Alias` es la solucion correcta porque ambos sitios comparten el mismo puerto y dominio, solo cambia la ruta.

### Bloque Directory

Cada `Alias` necesita un bloque `<Directory>` que defina los permisos de acceso al directorio mapeado:

```apache
<Directory "/var/www/html/media">
    AllowOverride None
    Require all granted
</Directory>
```

| Directiva | Funcion |
|-----------|---------|
| `AllowOverride None` | No permite que archivos `.htaccess` sobreescriban la configuracion |
| `Require all granted` | Permite acceso a todos los clientes |
| `Require all denied` | Bloquea acceso a todos |
| `Require ip 192.168.1.0/24` | Solo permite acceso desde un rango de IPs |

Sin el bloque `<Directory>` con `Require all granted`, Apache devuelve `403 Forbidden`.

### scp — Secure Copy

`scp` copia archivos entre hosts usando SSH. Es la forma mas directa de transferir archivos entre servidores:

```bash
scp -r /origen usuario@host:/destino
```

| Flag | Funcion |
|------|---------|
| `-r` | Copia recursiva (directorios completos) |
| `-P 2222` | Puerto SSH diferente al default (22) |
| `-i key.pem` | Usar llave SSH especifica |

## Pasos

1. Conectarse al app server 2
2. Instalar Apache (`httpd`)
3. Cambiar el puerto de Apache a 3004
4. Copiar los backups desde el jump host con `scp`
5. Configurar los `Alias` en Apache para servir ambos sitios
6. Iniciar Apache y verificar con `curl`

## Comandos / Codigo

### 1. Instalar Apache en app server 2

```bash
ssh steve@stapp02
```

```bash
sudo yum install -y httpd
```

### 2. Cambiar el puerto a 3004

```bash
sudo sed -i 's/Listen 80$/Listen 3004/' /etc/httpd/conf/httpd.conf

# Verificar
grep '^Listen' /etc/httpd/conf/httpd.conf
```

```
Listen 3004
```

### 3. Copiar los backups desde el jump host

Desde el jump host, copiar los directorios al app server 2:

```bash
# Desde el jump host
scp -r /home/thor/media steve@stapp02:/tmp/
scp -r /home/thor/cluster steve@stapp02:/tmp/
```

Luego en el app server, mover a la ubicacion correcta:

```bash
# En stapp02
sudo cp -r /tmp/media /var/www/html/
sudo cp -r /tmp/cluster /var/www/html/
```

Alternativa directa (si tienes permisos):

```bash
scp -r /home/thor/media steve@stapp02:/var/www/html/
scp -r /home/thor/cluster steve@stapp02:/var/www/html/
```

### 4. Configurar Apache para servir ambos sitios

Editar la configuracion de Apache:

```bash
sudo vi /etc/httpd/conf/httpd.conf
```

Agregar al final del archivo los `Alias` y bloques `Directory`:

```apache
Alias /media "/var/www/html/media"
Alias /cluster "/var/www/html/cluster"

<Directory "/var/www/html/media">
    AllowOverride None
    Require all granted
</Directory>

<Directory "/var/www/html/cluster">
    AllowOverride None
    Require all granted
</Directory>
```

**Nota:** Como los directorios estan dentro de `/var/www/html/` (que es el `DocumentRoot` por defecto), en este caso los `Alias` pueden no ser estrictamente necesarios ya que Apache serviria los subdirectorios automaticamente. Sin embargo, agregarlos es una buena practica porque:
- Hace explicita la configuracion
- Funciona igual si los directorios estuvieran fuera de `DocumentRoot`
- Los bloques `<Directory>` aseguran los permisos correctos

### 5. Iniciar Apache y verificar

```bash
# Habilitar e iniciar Apache
sudo systemctl enable httpd
sudo systemctl start httpd
```

### 6. Verificar ambos sitios

```bash
curl http://localhost:3004/media/
```

```bash
curl http://localhost:3004/cluster/
```

Ambos deben devolver el contenido HTML de sus respectivos `index.html`.

## Cuando usar Alias vs DocumentRoot con subdirectorios

```
Caso 1: Directorios dentro de DocumentRoot
  /var/www/html/media/     → http://localhost/media/    (funciona sin Alias)
  /var/www/html/cluster/   → http://localhost/cluster/  (funciona sin Alias)

Caso 2: Directorios fuera de DocumentRoot (requiere Alias)
  /opt/sites/media/        → Alias /media "/opt/sites/media"
  /srv/apps/cluster/       → Alias /cluster "/srv/apps/cluster"
```

Si los archivos estan **dentro** de `DocumentRoot`, Apache los sirve automaticamente sin necesidad de `Alias`. Si estan **fuera**, `Alias` es obligatorio.

## Otras formas de servir multiples sitios

### VirtualHost por puerto

Si cada sitio necesita su propio puerto:

```apache
Listen 3004
Listen 3005

<VirtualHost *:3004>
    DocumentRoot "/var/www/html/media"
</VirtualHost>

<VirtualHost *:3005>
    DocumentRoot "/var/www/html/cluster"
</VirtualHost>
```

### VirtualHost por nombre (Name-based)

Si se tienen diferentes dominios apuntando al mismo servidor:

```apache
<VirtualHost *:80>
    ServerName media.example.com
    DocumentRoot "/var/www/html/media"
</VirtualHost>

<VirtualHost *:80>
    ServerName cluster.example.com
    DocumentRoot "/var/www/html/cluster"
</VirtualHost>
```

### Comparacion

| Metodo | Mismo puerto | Mismo dominio | Caso de uso |
|--------|:------------:|:-------------:|-------------|
| `Alias` | Si | Si | Multiples rutas bajo un dominio |
| VirtualHost por puerto | No | Si | Cada sitio en puerto diferente |
| VirtualHost por nombre | Si | No | Cada sitio con dominio propio |

## Apache como Reverse Proxy

Apache puede actuar como reverse proxy usando `mod_proxy`, reenviando peticiones a servidores backend:

```apache
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_http_module modules/mod_proxy_http.so

<VirtualHost *:80>
    ServerName app.example.com

    ProxyPass "/" "http://localhost:8080/"
    ProxyPassReverse "/" "http://localhost:8080/"
</VirtualHost>
```

```
Cliente → Apache:80 (proxy) → App Backend:8080
                ↑                      │
                └──────────────────────┘
                  ProxyPassReverse reescribe
                  headers de respuesta
```

| Directiva | Funcion |
|-----------|---------|
| `ProxyPass` | Reenvia peticiones del cliente al backend |
| `ProxyPassReverse` | Reescribe headers de respuesta (`Location`, `Content-Location`) para que el cliente vea la URL del proxy, no del backend |

### Excluir rutas del proxy

```apache
# No hacer proxy de archivos estaticos — servirlos directo
ProxyPass "/static/" "!"
ProxyPass "/" "http://localhost:8080/"
```

El `"!"` indica que esa ruta **no** se reenvia al backend. El orden importa: las exclusiones deben ir **antes** de la regla general.

## Apache como Load Balancer

Con `mod_proxy_balancer`, Apache puede distribuir trafico entre multiples backends:

```apache
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_http_module modules/mod_proxy_http.so
LoadModule proxy_balancer_module modules/mod_proxy_balancer.so
LoadModule lbmethod_byrequests_module modules/mod_lbmethod_byrequests.so

<Proxy "balancer://backend">
    BalancerMember "http://stapp01:8080"
    BalancerMember "http://stapp02:8080"
    BalancerMember "http://stapp03:8080"
    ProxySet lbmethod=byrequests
</Proxy>

<VirtualHost *:80>
    ProxyPass "/" "balancer://backend/"
    ProxyPassReverse "/" "balancer://backend/"
</VirtualHost>
```

```
                    ┌→ stapp01:8080
Cliente → Apache ───┼→ stapp02:8080
                    └→ stapp03:8080
```

### Algoritmos de balanceo

| Algoritmo | Modulo | Comportamiento |
|-----------|--------|----------------|
| `byrequests` | `mod_lbmethod_byrequests` | Round Robin — distribuye por cantidad de peticiones |
| `bytraffic` | `mod_lbmethod_bytraffic` | Por cantidad de bytes transferidos |
| `bybusyness` | `mod_lbmethod_bybusyness` | Al servidor con menos peticiones activas |
| `heartbeat` | `mod_lbmethod_heartbeat` | Basado en heartbeat reportado por el backend |

### Opciones avanzadas de BalancerMember

```apache
<Proxy "balancer://backend">
    BalancerMember "http://stapp01:8080" loadfactor=3
    BalancerMember "http://stapp02:8080" loadfactor=1
    BalancerMember "http://stapp03:8080" loadfactor=1 status=+H
</Proxy>
```

| Parametro | Funcion |
|-----------|---------|
| `loadfactor=3` | Peso del servidor — recibe 3x mas trafico |
| `status=+H` | Hot standby — solo recibe trafico si los otros caen |
| `retry=60` | Segundos antes de reintentar un servidor caido |
| `timeout=10` | Timeout de conexion al backend |

### Comparacion Apache vs Nginx como proxy/LB

| Aspecto | Apache | Nginx |
|---------|--------|-------|
| Configuracion | Mas verbosa (modulos explicitos) | Mas concisa (`upstream` + `proxy_pass`) |
| Rendimiento | Bueno, pero mas pesado por proceso/hilo | Mejor en conexiones concurrentes (event-driven) |
| Modulos | Dinamicos (`LoadModule`) | Compilados generalmente |
| Caso de uso tipico | Ya tienes Apache y necesitas proxy | Proxy/LB dedicado |
| Hot reload | `graceful` restart | `nginx -s reload` |

## Otras configuraciones utiles de Apache

### mod_rewrite — Reescritura de URLs

```apache
LoadModule rewrite_module modules/mod_rewrite.so

<VirtualHost *:80>
    RewriteEngine On

    # Redirigir HTTP a HTTPS
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]

    # URL amigable: /producto/123 → /index.php?id=123
    RewriteRule ^/producto/([0-9]+)$ /index.php?id=$1 [L]
</VirtualHost>
```

| Flag | Significado |
|------|-------------|
| `[R=301]` | Redirect con codigo 301 (permanente) |
| `[L]` | Last — no procesar mas reglas |
| `[QSA]` | Query String Append — mantener parametros existentes |
| `[NC]` | No Case — ignorar mayusculas/minusculas |

### mod_headers — Manipulacion de headers

```apache
LoadModule headers_module modules/mod_headers.so

# Seguridad
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

# Cache
Header set Cache-Control "max-age=86400, public"

# CORS
Header set Access-Control-Allow-Origin "*"
```

| Header | Funcion |
|--------|---------|
| `X-Frame-Options` | Previene que la pagina se cargue en un iframe (clickjacking) |
| `X-Content-Type-Options` | Evita que el navegador adivine el tipo MIME |
| `X-XSS-Protection` | Activa filtro XSS del navegador |
| `Strict-Transport-Security` | Fuerza HTTPS por el tiempo indicado |

### mod_expires — Cache de archivos estaticos

```apache
LoadModule expires_module modules/mod_expires.so

<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType image/jpeg "access plus 30 days"
    ExpiresByType image/png "access plus 30 days"
    ExpiresByType text/css "access plus 7 days"
    ExpiresByType application/javascript "access plus 7 days"
    ExpiresByType text/html "access plus 1 hour"
</IfModule>
```

### mod_security — WAF (Web Application Firewall)

```apache
LoadModule security2_module modules/mod_security2.so

<IfModule mod_security2.c>
    SecRuleEngine On
    SecRequestBodyLimit 10485760

    # Bloquear SQL injection basico
    SecRule ARGS "@detectSQLi" "id:1,deny,status:403,msg:'SQL Injection detected'"

    # Bloquear XSS basico
    SecRule ARGS "@detectXSS" "id:2,deny,status:403,msg:'XSS detected'"
</IfModule>
```

`mod_security` inspecciona las peticiones entrantes y bloquea patrones maliciosos antes de que lleguen a la aplicacion.

### Autenticacion basica

```apache
# Crear archivo de passwords
# htpasswd -c /etc/httpd/.htpasswd admin

<Directory "/var/www/html/admin">
    AuthType Basic
    AuthName "Area Restringida"
    AuthUserFile /etc/httpd/.htpasswd
    Require valid-user
</Directory>
```

| Comando htpasswd | Funcion |
|------------------|---------|
| `htpasswd -c archivo usuario` | Crear archivo y agregar primer usuario |
| `htpasswd archivo usuario` | Agregar usuario a archivo existente |
| `htpasswd -D archivo usuario` | Eliminar usuario |

### Limitar metodos HTTP

```apache
<Directory "/var/www/html">
    # Solo permitir GET y POST
    <LimitExcept GET POST>
        Require all denied
    </LimitExcept>
</Directory>
```

### Resumen de modulos de Apache

| Modulo | Funcion |
|--------|---------|
| `mod_proxy` | Reverse proxy |
| `mod_proxy_balancer` | Load balancing |
| `mod_rewrite` | Reescritura de URLs |
| `mod_headers` | Manipulacion de headers HTTP |
| `mod_expires` | Cache por tipo de contenido |
| `mod_security` | WAF — proteccion contra ataques web |
| `mod_ssl` | Soporte HTTPS/TLS |
| `mod_alias` | Mapeo de URLs a directorios (`Alias`) |
| `mod_auth_basic` | Autenticacion basica HTTP |
| `mod_deflate` | Compresion gzip de respuestas |

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `403 Forbidden` al acceder a `/media/` o `/cluster/` | Verificar que existe el bloque `<Directory>` con `Require all granted`. Verificar permisos del directorio: `ls -la /var/www/html/media/` |
| `404 Not Found` | Verificar que los directorios existen y contienen archivos. Verificar que el `Alias` apunta a la ruta correcta |
| `curl: (7) Failed to connect` | Apache no esta corriendo o no escucha en el puerto 3004. Verificar con `systemctl status httpd` y `ss -tunlp \| grep 3004` |
| `scp: Permission denied` | Copiar a `/tmp/` primero y luego mover con `sudo cp -r`. O usar `sudo` en el destino |
| Apache no inicia despues de cambiar puerto | Verificar sintaxis: `httpd -t`. Verificar que no haya otro proceso en el puerto 3004 |
| Archivos copiados pero sin acceso | Verificar owner: `sudo chown -R apache:apache /var/www/html/media /var/www/html/cluster` |

## Recursos

- [Apache - Alias Directive](https://httpd.apache.org/docs/2.4/mod/mod_alias.html#alias)
- [Apache - Directory Directive](https://httpd.apache.org/docs/2.4/mod/core.html#directory)
- [Apache - VirtualHost Examples](https://httpd.apache.org/docs/2.4/vhosts/examples.html)
- [scp man page](https://man7.org/linux/man-pages/man1/scp.1.html)
- [Apache - mod_proxy](https://httpd.apache.org/docs/2.4/mod/mod_proxy.html)
- [Apache - mod_proxy_balancer](https://httpd.apache.org/docs/2.4/mod/mod_proxy_balancer.html)
- [Apache - mod_rewrite](https://httpd.apache.org/docs/2.4/mod/mod_rewrite.html)
- [Apache - mod_headers](https://httpd.apache.org/docs/2.4/mod/mod_headers.html)
- [Apache - mod_security](https://modsecurity.org/)
