# Dia 16 - Configurar Nginx como Load Balancer

## Problema / Desafio

El trafico de un sitio web ha aumentado y el equipo ha decidido desplegar la aplicacion en alta disponibilidad usando los 3 app servers de Stratos DC. La migracion esta casi completa, solo falta configurar el servidor LBR (Load Balancer):

1. Instalar Nginx en el servidor LBR
2. Configurar load balancing en el contexto `http` usando los 3 app servers
3. Solo modificar `/etc/nginx/nginx.conf`
4. No cambiar el puerto de Apache (3001) en los app servers
5. Asegurar que Apache este corriendo en los 3 app servers

## Conceptos clave

### Load Balancer

Un Load Balancer distribuye el trafico entrante entre multiples servidores para:

- **Alta disponibilidad** — si un servidor cae, los otros siguen atendiendo
- **Escalabilidad** — distribuir la carga entre multiples servidores
- **Rendimiento** — ningun servidor se satura con todo el trafico

```
Sin Load Balancer:
Cliente → stapp01:3001     ← Todo el trafico va a un solo servidor

Con Load Balancer:
                    ┌→ stapp01:3001
Cliente → LBR:80 ──┼→ stapp02:3001
                    └→ stapp03:3001
```

### Nginx como reverse proxy / load balancer

Nginx no solo sirve paginas web — tambien puede actuar como **reverse proxy** que recibe peticiones y las reenvia a servidores backend:

| Rol | Funcion |
|-----|---------|
| Web server | Sirve archivos estaticos directamente |
| Reverse proxy | Reenvia peticiones a otro servidor |
| Load balancer | Reverse proxy que distribuye entre **multiples** servidores |

### Directiva `upstream`

El bloque `upstream` en Nginx define un grupo de servidores backend entre los cuales se distribuye el trafico:

```nginx
upstream backend {
    server stapp01:3001;
    server stapp02:3001;
    server stapp03:3001;
}
```

Nginx usa este grupo como destino en `proxy_pass`.

### Algoritmos de balanceo

| Algoritmo | Directiva | Comportamiento |
|-----------|-----------|---------------|
| **Round Robin** (default) | (ninguna) | Distribuye peticiones secuencialmente: 1→2→3→1→2→3... |
| **Least Connections** | `least_conn;` | Envia al servidor con menos conexiones activas |
| **IP Hash** | `ip_hash;` | El mismo cliente siempre va al mismo servidor (session persistence) |
| **Weighted** | `server host weight=3;` | Servidores con mayor peso reciben mas trafico |

Para este ejercicio usamos **Round Robin** (default) que es el mas simple y funciona bien cuando los servidores tienen capacidad similar.

### Diferencia entre proxy_pass y root

| Directiva | Funcion | Ejemplo |
|-----------|---------|---------|
| `root` | Nginx sirve archivos **locales** del filesystem | `root /usr/share/nginx/html;` |
| `proxy_pass` | Nginx reenvia la peticion a **otro servidor** | `proxy_pass http://backend;` |

En modo load balancer, Nginx no tiene archivos locales — solo reenvia trafico.

## Pasos

1. Verificar que Apache esta corriendo en los 3 app servers
2. Instalar Nginx en el servidor LBR
3. Configurar Nginx como load balancer en `/etc/nginx/nginx.conf`
4. Validar la configuracion y reiniciar Nginx
5. Probar el acceso al sitio web

## Comandos / Codigo

### 1. Verificar Apache en los app servers

Desde el jump host, verificar que los 3 app servers responden en el puerto 3001:

```bash
for host in stapp01 stapp02 stapp03; do
  echo -n "$host: "
  curl -s -o /dev/null -w "%{http_code}" $host:3001
  echo
done
```

```
stapp01: 200
stapp02: 200
stapp03: 200
```

Si alguno no responde, conectarse por SSH y levantar Apache:

```bash
sudo systemctl start httpd
sudo systemctl enable httpd
```

### 2. Instalar Nginx en el LBR

```bash
ssh lbr_user@lbr

# Instalar Nginx
sudo yum install -y epel-release
sudo yum install -y nginx

# Habilitar e iniciar
sudo systemctl enable nginx
sudo systemctl start nginx
```

### 3. Configurar el load balancing

Editar el archivo de configuracion principal:

```bash
sudo vi /etc/nginx/nginx.conf
```

Configuracion completa:

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

http {
    # Grupo de servidores backend
    upstream backend {
        server stapp01.stratos.xfusioncorp.com:3001;
        server stapp02.stratos.xfusioncorp.com:3001;
        server stapp03.stratos.xfusioncorp.com:3001;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://backend;
        }
    }
}
```

**Explicacion de cada bloque:**

```
nginx.conf
├── worker_processes auto       # Numero de workers (auto = 1 por CPU)
├── events
│   └── worker_connections 1024 # Conexiones simultaneas por worker
└── http
    ├── upstream backend        # Define los 3 app servers como grupo
    │   ├── stapp01:3001
    │   ├── stapp02:3001
    │   └── stapp03:3001
    └── server
        ├── listen 80           # LBR escucha en puerto 80
        └── location /
            └── proxy_pass http://backend  # Reenvia a los app servers
```

### 4. Validar y reiniciar

```bash
# Validar configuracion
sudo nginx -t
```

```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

```bash
# Reiniciar Nginx
sudo systemctl restart nginx
```

### 5. Verificar el load balancing

```bash
# Acceder al LBR — debe responder con el contenido de los app servers
curl http://lbr:80
```

Para verificar que el round robin funciona, hacer multiples peticiones y ver los logs de cada app server:

```bash
# Multiples peticiones
for i in $(seq 1 6); do curl -s http://lbr:80 > /dev/null; done

# Revisar logs en cada app server
ssh tony@stapp01 "sudo tail -3 /var/log/httpd/access_log"
ssh steve@stapp02 "sudo tail -3 /var/log/httpd/access_log"
ssh banner@stapp03 "sudo tail -3 /var/log/httpd/access_log"
```

Deberia verse trafico distribuido entre los 3 servidores.

## Configuraciones adicionales para produccion

### Headers del proxy

En produccion, los app servers necesitan saber la IP real del cliente (no la del LBR):

```nginx
location / {
    proxy_pass http://backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

| Header | Funcion |
|--------|---------|
| `Host` | Nombre del host original que el cliente solicito |
| `X-Real-IP` | IP real del cliente |
| `X-Forwarded-For` | Cadena de IPs por las que paso la peticion (cliente → proxies) |
| `X-Forwarded-Proto` | Protocolo original (http o https) |

Sin estos headers, los app servers ven todas las peticiones como si vinieran del LBR.

### Health checks pasivos

Nginx detecta automaticamente servidores caidos y deja de enviarles trafico:

```nginx
upstream backend {
    server stapp01:3001 max_fails=3 fail_timeout=30s;
    server stapp02:3001 max_fails=3 fail_timeout=30s;
    server stapp03:3001 max_fails=3 fail_timeout=30s;
}
```

| Parametro | Funcion |
|-----------|---------|
| `max_fails=3` | Despues de 3 intentos fallidos, marca el servidor como caido |
| `fail_timeout=30s` | Espera 30 segundos antes de reintentar con el servidor caido |

### Servidor de backup

```nginx
upstream backend {
    server stapp01:3001;
    server stapp02:3001;
    server stapp03:3001;
    server stapp04:3001 backup;    # Solo recibe trafico si los otros 3 caen
}
```

### Weighted round robin

Si un servidor tiene mas capacidad que los otros:

```nginx
upstream backend {
    server stapp01:3001 weight=3;   # Recibe 3x mas trafico
    server stapp02:3001 weight=1;
    server stapp03:3001 weight=1;
}
```

### Session persistence con ip_hash

Si la aplicacion usa sesiones (login, carrito de compras), el mismo cliente debe ir siempre al mismo servidor:

```nginx
upstream backend {
    ip_hash;
    server stapp01:3001;
    server stapp02:3001;
    server stapp03:3001;
}
```

## Configuraciones tipicas de Nginx

### Rate limiting

Limitar el numero de peticiones por segundo para prevenir abuso o DDoS:

```nginx
http {
    # Definir zona de rate limiting: 10 peticiones por segundo por IP
    limit_req_zone $binary_remote_addr zone=mylimit:10m rate=10r/s;

    server {
        location / {
            # Aplicar el rate limit con burst de 20 (cola de espera)
            limit_req zone=mylimit burst=20 nodelay;
            proxy_pass http://backend;
        }
    }
}
```

| Parametro | Funcion |
|-----------|---------|
| `rate=10r/s` | Maximo 10 peticiones por segundo por IP |
| `burst=20` | Permite rafagas de hasta 20 peticiones (las excedentes se encolan) |
| `nodelay` | Procesa las peticiones del burst inmediatamente (sin delay artificial) |
| `zone=mylimit:10m` | 10 MB de memoria compartida para tracking (~160,000 IPs) |

### Timeouts

Configurar timeouts para evitar conexiones colgadas:

```nginx
http {
    # Timeouts del proxy hacia los backend servers
    proxy_connect_timeout 5s;      # Timeout para establecer conexion con backend
    proxy_send_timeout 10s;        # Timeout para enviar datos al backend
    proxy_read_timeout 30s;        # Timeout para recibir respuesta del backend

    # Timeouts del cliente
    client_body_timeout 10s;       # Timeout para recibir el body del cliente
    client_header_timeout 5s;      # Timeout para recibir los headers del cliente
    send_timeout 10s;              # Timeout para enviar respuesta al cliente

    # Keepalive
    keepalive_timeout 65s;         # Tiempo que mantiene la conexion abierta
}
```

### Limitar tamano de uploads

```nginx
http {
    # Tamano maximo de body en peticiones (uploads)
    client_max_body_size 10M;      # Default: 1M
}
```

Si se excede el limite, Nginx devuelve `413 Request Entity Too Large`.

### Gzip compression

Comprimir las respuestas para reducir el ancho de banda:

```nginx
http {
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    gzip_min_length 1000;          # No comprimir archivos menores a 1KB
    gzip_comp_level 6;             # Nivel de compresion (1-9, 6 es buen balance)
    gzip_vary on;                  # Agregar header Vary: Accept-Encoding
}
```

### Caching de archivos estaticos

```nginx
server {
    # Cache de archivos estaticos por 30 dias
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
```

### Logs personalizados

```nginx
http {
    # Formato de log personalizado
    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'upstream: $upstream_addr response_time: $upstream_response_time';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
}
```

Variables utiles para logs de load balancer:

| Variable | Valor |
|----------|-------|
| `$upstream_addr` | IP del backend que atendio la peticion |
| `$upstream_response_time` | Tiempo de respuesta del backend |
| `$upstream_status` | HTTP status del backend |
| `$request_time` | Tiempo total de la peticion (cliente → nginx → backend → cliente) |

### Seguridad basica

```nginx
server {
    # Ocultar version de Nginx en headers y paginas de error
    server_tokens off;

    # Bloquear acceso a archivos ocultos (.git, .env, .htaccess)
    location ~ /\. {
        deny all;
        return 404;
    }

    # Bloquear acceso a archivos de backup
    location ~ ~$ {
        deny all;
    }
}
```

`server_tokens off` cambia el header de `nginx/1.20.1` a solo `nginx`, ocultando la version exacta.

### Ejemplo de nginx.conf completo para produccion

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logs
    log_format main '$remote_addr [$time_local] "$request" '
                    '$status $body_bytes_sent '
                    'upstream=$upstream_addr time=$upstream_response_time';
    access_log /var/log/nginx/access.log main;

    # Performance
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    # Seguridad
    server_tokens off;
    client_max_body_size 10M;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=mylimit:10m rate=10r/s;

    # Backend servers
    upstream backend {
        server stapp01:3001 max_fails=3 fail_timeout=30s;
        server stapp02:3001 max_fails=3 fail_timeout=30s;
        server stapp03:3001 max_fails=3 fail_timeout=30s;
    }

    server {
        listen 80;
        server_name _;

        location / {
            limit_req zone=mylimit burst=20 nodelay;
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 5s;
            proxy_read_timeout 30s;
        }

        location ~ /\. {
            deny all;
            return 404;
        }
    }
}
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `502 Bad Gateway` | Los app servers no responden. Verificar que Apache esta corriendo en los 3 con `curl stapp0X:3001` |
| `nginx -t` falla | Verificar sintaxis de `nginx.conf`. Los bloques `upstream` deben estar dentro de `http {}` |
| Solo responde un servidor | Verificar que los 3 servers estan listados en `upstream`. Revisar que no haya `ip_hash` activo |
| Timeout al acceder al LBR | Verificar que Nginx esta corriendo: `systemctl status nginx`. Verificar firewall del LBR |
| App servers ven IP del LBR en logs | Agregar `proxy_set_header X-Real-IP $remote_addr` en la configuracion de `location` |
| `upstream` fuera de `http` causa error | El bloque `upstream` debe estar **dentro** del bloque `http {}`, no fuera |

## Recursos

- [Nginx - HTTP Load Balancing](https://nginx.org/en/docs/http/load_balancing.html)
- [Nginx - upstream module](https://nginx.org/en/docs/http/ngx_http_upstream_module.html)
- [Nginx - proxy_pass](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass)
- [Nginx Reverse Proxy Guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
