# Dia 15 - Instalar y configurar Nginx con SSL (Self-Signed Certificate)

## Problema / Desafio

Preparar App Server 3 (`stapp03`) para desplegar una aplicacion:

1. Instalar y configurar Nginx
2. Mover los certificados SSL self-signed de `/tmp/nautilus.crt` y `/tmp/nautilus.key` a una ubicacion apropiada y configurarlos en Nginx
3. Crear un `index.html` con contenido `Welcome!` en el document root de Nginx
4. Verificar acceso HTTPS desde el jump host con `curl -Ik https://<app-server-ip>/`

## Conceptos clave

### Nginx

Nginx es un servidor web de alto rendimiento que tambien funciona como reverse proxy, load balancer y cache HTTP. Es mas ligero que Apache y maneja mejor las conexiones concurrentes.

| | Nginx | Apache (httpd) |
|---|-------|----------------|
| Arquitectura | Event-driven (asincrono) | Process/thread por conexion |
| Concurrencia | Muy alta con bajo consumo de memoria | Mayor consumo por conexion |
| Configuracion | `/etc/nginx/nginx.conf` | `/etc/httpd/conf/httpd.conf` |
| Modulos | Se compilan con el binario | Se cargan dinamicamente |
| Caso de uso tipico | Reverse proxy, static files, load balancer | Aplicaciones dinamicas (PHP, etc.) |

### Estructura de directorios de Nginx

```
/etc/nginx/
├── nginx.conf              # Configuracion principal
├── conf.d/                 # Configuraciones adicionales (*.conf se incluyen automaticamente)
├── default.d/              # Configuraciones del server block por defecto
└── ssl/                    # Certificados SSL (creado manualmente)
    ├── nautilus.crt
    └── nautilus.key

/usr/share/nginx/html/      # Document root por defecto
├── index.html              # Pagina principal
├── 404.html
└── 50x.html
```

### SSL/TLS y certificados self-signed

**SSL/TLS** encripta la comunicacion entre cliente y servidor. Para habilitar HTTPS se necesitan:

| Archivo | Que es | Permisos |
|---------|--------|----------|
| `.crt` (certificado) | Contiene la clave publica y la identidad del servidor. Se comparte con los clientes | 644 (lectura publica) |
| `.key` (clave privada) | Clave secreta del servidor. **Nunca** debe ser accesible por otros | **600** (solo root) |

**Self-signed** significa que el certificado fue firmado por el propio servidor, no por una CA (Certificate Authority) como Let's Encrypt o DigiCert. Los navegadores y `curl` no confian en certificados self-signed por defecto.

```
Certificado firmado por CA:
Cliente → Verifica con CA → ✅ Confiado automaticamente

Certificado self-signed:
Cliente → No encuentra CA → ❌ "SSL certificate problem: self-signed certificate"
Cliente → curl -k (ignorar SSL) → ✅ Conexion forzada
```

### El comando `tee`

`tee` lee de stdin y escribe simultaneamente en stdout **y** en un archivo. Es util cuando necesitas escribir un archivo con `sudo` porque la redireccion `>` no hereda los privilegios de `sudo`:

```bash
# Esto NO funciona — la redireccion la hace el shell del usuario, no root
sudo echo "Welcome!" > /usr/share/nginx/html/index.html
# bash: /usr/share/nginx/html/index.html: Permission denied

# Esto SI funciona — tee se ejecuta con privilegios de root
echo "Welcome!" | sudo tee /usr/share/nginx/html/index.html
```

`tee` tambien imprime en pantalla. Para silenciar la salida:

```bash
echo "Welcome!" | sudo tee /usr/share/nginx/html/index.html > /dev/null
```

### Symlinks en el document root

Al inspeccionar `/usr/share/nginx/html/`, el `index.html` por defecto es un **symlink**:

```
lrwxrwxrwx 1 root root 25 index.html -> ../../testpage/index.html
```

Al usar `tee` o `echo >` sobre un symlink, se **sobreescribe el archivo al que apunta**, no el symlink. Pero en este caso funciona correctamente porque queremos reemplazar el contenido.

## Pasos

1. Conectarse al servidor por SSH
2. Identificar la distribucion e instalar Nginx
3. Revisar la configuracion de Nginx y el document root
4. Crear el archivo `index.html` con el contenido requerido
5. Mover los certificados SSL a una ubicacion segura
6. Configurar el bloque SSL en Nginx
7. Validar la configuracion, reiniciar Nginx y probar

## Comandos / Codigo

### 1. Conectarse al servidor

```bash
ssh banner@stapp03
```

### 2. Identificar distribucion e instalar Nginx

```bash
# Identificar la distribucion
cat /etc/os-release
```

En CentOS/RHEL:

```bash
sudo yum install -y epel-release
sudo yum install -y nginx
```

En Debian/Ubuntu:

```bash
sudo apt update && sudo apt install -y nginx
```

Habilitar e iniciar el servicio:

```bash
sudo systemctl enable nginx
sudo systemctl start nginx
```

### 3. Revisar la configuracion de Nginx

```bash
cat /etc/nginx/nginx.conf
```

El bloque del server por defecto:

```nginx
server {
    listen       80;
    listen       [::]:80;
    server_name  _;
    root         /usr/share/nginx/html;

    include /etc/nginx/default.d/*.conf;

    error_page 404 /404.html;
    location = /404.html {
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
    }
}
```

El document root es `/usr/share/nginx/html`.

### 4. Crear el index.html

Revisar el contenido actual del document root:

```bash
ls -la /usr/share/nginx/html/
```

```
lrwxrwxrwx 1 root root   25 index.html -> ../../testpage/index.html
-rw-r--r-- 1 root root 3.9K 404.html
-rw-r--r-- 1 root root 4.0K 50x.html
```

El `index.html` es un symlink. Sobreescribimos el contenido usando `tee`:

```bash
echo "Welcome!" | sudo tee /usr/share/nginx/html/index.html
```

Verificar:

```bash
cat /usr/share/nginx/html/index.html
```

```
Welcome!
```

### 5. Mover los certificados SSL

Crear un directorio seguro para los certificados y moverlos:

```bash
# Crear directorio para SSL
sudo mkdir -p /etc/nginx/ssl

# Mover los certificados
sudo mv /tmp/nautilus.crt /etc/nginx/ssl/
sudo mv /tmp/nautilus.key /etc/nginx/ssl/

# Asignar permisos seguros
sudo chmod 600 /etc/nginx/ssl/nautilus.key
sudo chmod 644 /etc/nginx/ssl/nautilus.crt

# Verificar
ls -la /etc/nginx/ssl/
```

```
-rw-r--r-- 1 root root 1234 nautilus.crt
-rw------- 1 root root 1704 nautilus.key
```

**Importante:** la clave privada (`.key`) debe tener permisos **600** (solo lectura para root). Si otros usuarios pueden leerla, la seguridad SSL queda comprometida.

### 6. Configurar el bloque SSL en Nginx

En `/etc/nginx/nginx.conf` ya existe un bloque SSL comentado. Descomentarlo y configurar las rutas de los certificados:

```bash
sudo vi /etc/nginx/nginx.conf
```

Descomentar y modificar el bloque TLS:

```nginx
server {
    listen       443 ssl http2;
    listen       [::]:443 ssl http2;
    server_name  _;
    root         /usr/share/nginx/html;

    ssl_certificate "/etc/nginx/ssl/nautilus.crt";
    ssl_certificate_key "/etc/nginx/ssl/nautilus.key";
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout  10m;
    ssl_ciphers PROFILE=SYSTEM;
    ssl_prefer_server_ciphers on;

    include /etc/nginx/default.d/*.conf;

    error_page 404 /404.html;
        location = /40x.html {
    }

    error_page 500 502 503 504 /50x.html;
        location = /50x.html {
    }
}
```

**Directivas SSL explicadas:**

| Directiva | Funcion |
|-----------|---------|
| `listen 443 ssl http2` | Escuchar en puerto 443 con SSL y HTTP/2 |
| `ssl_certificate` | Ruta al certificado publico (`.crt`) |
| `ssl_certificate_key` | Ruta a la clave privada (`.key`) |
| `ssl_session_cache shared:SSL:1m` | Cache de sesiones SSL compartido (1 MB, ~4000 sesiones) |
| `ssl_session_timeout 10m` | Sesiones SSL validas por 10 minutos (evita renegociacion) |
| `ssl_ciphers PROFILE=SYSTEM` | Usar los ciphers definidos por el sistema operativo |
| `ssl_prefer_server_ciphers on` | El servidor elige el cipher, no el cliente (mas seguro) |

### 7. Validar, reiniciar y probar

Validar la configuracion antes de reiniciar:

```bash
sudo nginx -t
```

```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

**Siempre** ejecutar `nginx -t` antes de reiniciar. Si hay un error de sintaxis y se reinicia sin validar, Nginx no levanta y el servicio queda caido.

Reiniciar Nginx:

```bash
sudo systemctl restart nginx
```

Probar localmente:

```bash
# HTTP (puerto 80)
curl stapp03.stratos.xfusioncorp.com
```

```
Welcome!
```

```bash
# HTTPS sin flag -k — falla porque es self-signed
curl https://stapp03.stratos.xfusioncorp.com
```

```
curl: (60) SSL certificate problem: self-signed certificate
```

```bash
# HTTPS con -Ik — ignora el error SSL y muestra headers
curl -Ik https://stapp03.stratos.xfusioncorp.com
```

```
HTTP/2 200
server: nginx/1.20.1
date: Tue, 03 Mar 2026 01:17:58 GMT
content-type: text/html
content-length: 9
last-modified: Tue, 03 Mar 2026 01:09:04 GMT
```

### Flags de curl para SSL

| Flag | Funcion |
|------|---------|
| `-k` / `--insecure` | Ignora errores de certificado SSL (self-signed, expirado, etc.) |
| `-I` / `--head` | Solo muestra los headers de respuesta, no el body |
| `-v` / `--verbose` | Muestra el handshake SSL completo (util para debug) |
| `--cacert /path/to/ca.crt` | Especifica un CA personalizado para verificar el certificado |

```bash
# Ver el handshake SSL completo
curl -Ikv https://stapp03.stratos.xfusioncorp.com
```

En la salida verbose se puede ver:
- La version de TLS negociada
- El cipher utilizado
- Los detalles del certificado (issuer, subject, expiracion)

## Resumen del flujo

```
1. SSH a stapp03
2. yum install nginx → instalar Nginx
3. echo "Welcome!" | sudo tee .../index.html → crear pagina
4. mkdir /etc/nginx/ssl → crear directorio seguro
5. mv /tmp/nautilus.* /etc/nginx/ssl/ → mover certificados
6. chmod 600 nautilus.key → permisos seguros
7. vi nginx.conf → descomentar bloque SSL, apuntar a certificados
8. nginx -t → validar configuracion
9. systemctl restart nginx → aplicar cambios
10. curl -Ik https://stapp03 → verificar HTTPS funciona
```

## Self-Signed vs Let's Encrypt vs CA comercial

En este ejercicio usamos un certificado **self-signed**. En produccion hay mejores opciones:

| Tipo | Costo | Confianza | Renovacion | Caso de uso |
|------|-------|-----------|------------|-------------|
| **Self-signed** | Gratis | No (browsers muestran advertencia) | Manual | Labs, desarrollo, servicios internos |
| **Let's Encrypt** | Gratis | Si (CA reconocida) | Automatica (90 dias) | Sitios web publicos |
| **CA comercial** (DigiCert, Comodo) | $10-$1000+/ano | Si | Manual (1-2 anos) | Enterprise, EV certificates |

### Let's Encrypt con Certbot

[Let's Encrypt](https://letsencrypt.org/) es una CA gratuita y automatizada. **Certbot** es el cliente oficial para obtener y renovar certificados:

```bash
# Instalar Certbot en CentOS/RHEL
sudo yum install -y epel-release
sudo yum install -y certbot python3-certbot-nginx

# En Debian/Ubuntu
sudo apt install -y certbot python3-certbot-nginx
```

#### Obtener un certificado

```bash
# Certbot configura Nginx automaticamente
sudo certbot --nginx -d midominio.com -d www.midominio.com
```

Certbot:
1. Verifica que el dominio apunta al servidor (challenge HTTP o DNS)
2. Obtiene el certificado de Let's Encrypt
3. Modifica `nginx.conf` para agregar el bloque SSL automaticamente
4. Recarga Nginx

#### Renovacion automatica

Los certificados de Let's Encrypt duran **90 dias**. Certbot instala un cron/timer para renovar automaticamente:

```bash
# Verificar que la renovacion automatica esta configurada
sudo systemctl status certbot-renew.timer

# Probar la renovacion (sin renovar de verdad)
sudo certbot renew --dry-run
```

#### Donde guarda los certificados

```
/etc/letsencrypt/live/midominio.com/
├── fullchain.pem    → Certificado completo (cert + chain)
├── privkey.pem      → Clave privada
├── cert.pem         → Solo el certificado
└── chain.pem        → Certificados intermedios
```

En `nginx.conf`:

```nginx
ssl_certificate /etc/letsencrypt/live/midominio.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/midominio.com/privkey.pem;
```

#### Requisitos de Let's Encrypt

| Requisito | Detalle |
|-----------|---------|
| Dominio publico | No funciona con IPs ni dominios internos |
| Puerto 80 abierto | Certbot necesita responder al challenge HTTP |
| DNS apuntando al servidor | El dominio debe resolver a la IP del servidor |

Para dominios internos o sin acceso publico, se sigue usando self-signed o una CA interna.

### Redireccion HTTP → HTTPS

En produccion, todo el trafico HTTP debe redirigirse a HTTPS:

```nginx
# Bloque HTTP — redirige todo a HTTPS
server {
    listen 80;
    server_name midominio.com www.midominio.com;
    return 301 https://$host$request_uri;
}

# Bloque HTTPS — sirve el contenido
server {
    listen 443 ssl http2;
    server_name midominio.com www.midominio.com;

    ssl_certificate /etc/letsencrypt/live/midominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/midominio.com/privkey.pem;

    root /usr/share/nginx/html;
}
```

`return 301` envia una redireccion permanente al navegador. El cliente automaticamente cambia a HTTPS.

### Headers de seguridad recomendados para HTTPS

```nginx
server {
    listen 443 ssl http2;

    # Forzar HTTPS por 1 ano (el browser recuerda y siempre usa HTTPS)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Prevenir clickjacking (no permitir iframes de otros sitios)
    add_header X-Frame-Options "SAMEORIGIN" always;

    # Prevenir MIME type sniffing
    add_header X-Content-Type-Options "nosniff" always;

    # Proteccion XSS basica
    add_header X-XSS-Protection "1; mode=block" always;
}
```

| Header | Proteccion |
|--------|-----------|
| `Strict-Transport-Security` (HSTS) | El browser siempre usa HTTPS, incluso si el usuario escribe `http://` |
| `X-Frame-Options` | Previene que el sitio se cargue en un iframe (anti-clickjacking) |
| `X-Content-Type-Options` | Previene que el browser adivine el tipo de archivo |
| `X-XSS-Protection` | Activa el filtro XSS del browser |

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `nginx -t` falla con error de sintaxis | Revisar llaves `{}` y punto y coma `;` en `nginx.conf`. Cada directiva debe terminar en `;` |
| `nginx: [emerg] cannot load certificate` | Verificar que la ruta al `.crt` y `.key` es correcta y que Nginx (root) tiene permisos de lectura |
| `nginx: [emerg] cannot load certificate key: PEM routines` | El archivo `.key` esta corrupto o no es una clave privada valida |
| Puerto 443 no responde | Verificar que el bloque `listen 443 ssl` esta descomentado. Verificar firewall con `iptables -L -n` |
| `curl: (60) SSL certificate problem` | Esperado con certificados self-signed. Usar `curl -k` para ignorar o `--cacert` con el certificado |
| `Welcome!` no aparece | Verificar que `root` en el bloque SSL apunta a `/usr/share/nginx/html` |
| `sudo echo > archivo` da permiso denegado | La redireccion `>` la hace el shell del usuario, no root. Usar `echo \| sudo tee archivo` |
| `nginx.service failed to start` | Revisar logs con `journalctl -u nginx` o `/var/log/nginx/error.log` |

## Recursos

- [Nginx - Configuring HTTPS servers](https://nginx.org/en/docs/http/configuring_https_servers.html)
- [Nginx - Full Configuration](https://nginx.org/en/docs/ngx_core_module.html)
- [SSL/TLS Strong Encryption - Apache (conceptos aplicables)](https://httpd.apache.org/docs/2.4/ssl/ssl_intro.html)
- [tee command - man page](https://man7.org/linux/man-pages/man1/tee.1.html)
