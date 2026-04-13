# Dia 20 - Configurar Nginx + PHP-FPM para servir una aplicacion PHP

## Problema / Desafio

Desplegar una aplicacion PHP en app server 3 (stapp03) usando Nginx como servidor web y PHP-FPM como procesador de PHP:

1. Instalar Nginx y configurarlo en el puerto **8091** con document root `/var/www/html`
2. Instalar **php-fpm 8.2** y configurarlo para usar el socket unix `/var/run/php-fpm/default.sock`
3. Integrar Nginx con PHP-FPM para que procese archivos `.php`
4. Verificar con `curl http://stapp03:8091/index.php` desde el jump host

## Conceptos clave

### PHP-FPM (FastCGI Process Manager)

PHP-FPM es un gestor de procesos FastCGI para PHP. A diferencia de `mod_php` (que embebe PHP dentro de Apache), PHP-FPM corre como un servicio independiente y se comunica con el servidor web via socket unix o TCP:

```
Con mod_php (Apache):
  Apache recibe request → mod_php ejecuta PHP dentro del proceso Apache

Con PHP-FPM (Nginx o Apache):
  Nginx recibe request → pasa a PHP-FPM via socket → PHP-FPM ejecuta PHP → responde a Nginx
```

### Socket Unix vs TCP

PHP-FPM puede escuchar conexiones de dos formas:

| Metodo | Configuracion | Caso de uso |
|--------|---------------|-------------|
| Socket Unix | `listen = /var/run/php-fpm/default.sock` | Nginx y PHP-FPM en el **mismo** servidor (mas rapido, sin overhead de red) |
| TCP | `listen = 127.0.0.1:9000` | Nginx y PHP-FPM en servidores **diferentes** o cuando se necesita balanceo |

### fastcgi_pass en Nginx

La directiva `fastcgi_pass` le dice a Nginx a donde enviar las peticiones PHP:

```nginx
# Via socket unix
fastcgi_pass unix:/var/run/php-fpm/default.sock;

# Via TCP
fastcgi_pass 127.0.0.1:9000;
```

### Pool de PHP-FPM

PHP-FPM organiza sus procesos en "pools". Cada pool tiene su propia configuracion de usuario, socket y gestion de procesos:

| Parametro | Funcion |
|-----------|---------|
| `user` / `group` | Usuario y grupo que ejecuta los procesos PHP |
| `listen` | Socket o direccion donde escucha |
| `listen.owner` / `listen.group` | Propietario del archivo socket (debe coincidir con el usuario de Nginx) |
| `pm = dynamic` | Modo de gestion: ajusta procesos segun demanda |
| `pm.max_children` | Maximo de procesos hijo simultaneos |
| `pm.start_servers` | Procesos hijo al iniciar |
| `pm.min_spare_servers` | Minimo de procesos inactivos |
| `pm.max_spare_servers` | Maximo de procesos inactivos |

## Pasos

1. Conectarse a app server 3
2. Identificar la distribucion del sistema operativo
3. Instalar Nginx
4. Instalar PHP-FPM 8.2 desde el repositorio Remi
5. Habilitar ambos servicios
6. Crear el directorio para el socket unix
7. Configurar el pool de PHP-FPM con el socket correcto
8. Configurar Nginx para escuchar en el puerto 8091 y pasar `.php` a PHP-FPM
9. Iniciar servicios, resolver conflictos y verificar

## Comandos / Codigo

### 1. Conectarse al app server 3

```bash
ssh banner@stapp03
```

### 2. Identificar la distribucion

```bash
cat /etc/os-release
# o
lsb_release -a
```

Esto es importante para saber que gestor de paquetes usar (`yum`, `dnf`) y que repositorios estan disponibles. En este caso el servidor usa **CentOS Stream 9** / RHEL 9.

### 3. Instalar Nginx

```bash
sudo dnf install -y nginx
```

### 4. Instalar PHP-FPM 8.2 desde Remi

Los repositorios por defecto no traen PHP 8.2, hay que habilitar el repositorio Remi:

```bash
# Instalar EPEL primero
sudo dnf install -y epel-release

# Instalar Remi para RHEL/CentOS 9
sudo dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm

# Resetear modulo PHP y habilitar 8.2
sudo dnf module reset php -y
sudo dnf module enable php:remi-8.2 -y

# Instalar php-fpm y dependencias
sudo dnf install -y php php-fpm php-cli php-common

# Verificar version
php -v
```

**Por que se necesita Remi?** Los repositorios base de RHEL/CentOS suelen traer versiones anteriores de PHP. Remi es un repositorio de terceros mantenido por Remi Collet (contribuidor oficial de PHP) que ofrece versiones recientes.

| Paso | Funcion |
|------|---------|
| `epel-release` | Repositorio EPEL, dependencia para Remi |
| `remi-release-9.rpm` | Agrega el repositorio Remi al sistema |
| `dnf module reset php` | Limpia cualquier stream de PHP previamente habilitado |
| `dnf module enable php:remi-8.2` | Activa el stream de PHP 8.2 de Remi |

### 5. Habilitar los servicios

```bash
sudo systemctl enable nginx
sudo systemctl enable php-fpm
```

### 6. Crear la estructura del socket

```bash
sudo mkdir -p /var/run/php-fpm
sudo chown nginx:nginx /var/run/php-fpm
```

### 7. Configurar PHP-FPM

Editar el archivo del pool (generalmente `/etc/php-fpm.d/www.conf`):

```ini
[www]
; Usuario y grupo que corre el proceso
user = nginx
group = nginx

; Usar socket unix en lugar de TCP
listen = /var/run/php-fpm/default.sock

; Permisos del socket (nginx debe poder escribir)
listen.owner = nginx
listen.group = nginx
listen.mode = 0660

; Gestion de procesos
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```

Puntos importantes:
- `user` y `group` deben ser `nginx` para que los archivos creados por PHP sean accesibles
- `listen.owner` y `listen.group` deben coincidir con el usuario de Nginx para que pueda escribir en el socket
- `listen.mode = 0660` da permisos de lectura/escritura al owner y group del socket

### 8. Configurar Nginx

Crear o editar la configuracion del servidor en `/etc/nginx/conf.d/`:

```nginx
server {
    listen 8091;
    server_name _;
    root /var/www/html;
    index index.php index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    # Todo archivo .php lo pasa a PHP-FPM
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/default.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
```

| Directiva | Funcion |
|-----------|---------|
| `listen 8091` | Puerto donde Nginx acepta conexiones |
| `root /var/www/html` | Directorio raiz de los archivos del sitio |
| `try_files` | Intenta servir el archivo solicitado, si no existe devuelve 404 |
| `location ~ \.php$` | Captura todas las peticiones a archivos `.php` (regex) |
| `fastcgi_pass` | Envia la peticion al socket de PHP-FPM |
| `SCRIPT_FILENAME` | Le dice a PHP-FPM la ruta completa del archivo a ejecutar |
| `include fastcgi_params` | Incluye parametros FastCGI estandar (headers, metodo HTTP, etc.) |

### 9. Iniciar servicios y probar

```bash
sudo systemctl start php-fpm
sudo systemctl start nginx
```

```bash
curl http://localhost:8091/index.php
```

## Troubleshooting

### Problema: 404 Not Found al acceder a index.php

Al probar con curl se obtenia un 404:

```bash
curl http://localhost:8091/index.php
```

```html
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx/1.20.1</center>
</body>
</html>
```

**Causa:** Existia una configuracion preexistente de PHP-FPM en Nginx que apuntaba a un socket diferente. Al buscar:

```bash
sudo grep -r "www.sock" /etc/nginx/
```

```
/etc/nginx/conf.d/php-fpm.conf:        server unix:/run/php-fpm/www.sock;
```

El archivo `/etc/nginx/conf.d/php-fpm.conf` contenia un bloque `upstream` que apuntaba al socket por defecto:

```nginx
upstream php-fpm {
        server unix:/run/php-fpm/www.sock;
}
```

Este upstream no coincidia con el socket configurado (`/var/run/php-fpm/default.sock`), lo que causaba que Nginx no pudiera comunicarse con PHP-FPM.

**Solucion:** Actualizar el upstream para que apunte al socket correcto:

```bash
sudo sed -i 's|unix:/run/php-fpm/www.sock|unix:/var/run/php-fpm/default.sock|' /etc/nginx/conf.d/php-fpm.conf
```

Luego reiniciar Nginx:

```bash
sudo systemctl restart nginx
```

### Verificacion final

```bash
curl http://localhost:8091/index.php
```

```
Welcome to xFusionCorp Industries!
```

### Tabla de problemas comunes

| Problema | Solucion |
|----------|----------|
| `404 Not Found` en archivos `.php` | Verificar que no haya otro archivo de configuracion sobreescribiendo el upstream de PHP-FPM: `grep -r "www.sock" /etc/nginx/` |
| `502 Bad Gateway` | PHP-FPM no esta corriendo o el socket no existe. Verificar: `systemctl status php-fpm` y `ls -la /var/run/php-fpm/default.sock` |
| `Permission denied` al conectar al socket | Verificar que `listen.owner` y `listen.group` sean `nginx`. Verificar permisos: `ls -la /var/run/php-fpm/` |
| `connect() failed - No such file or directory` | El directorio del socket no existe. Crear con: `mkdir -p /var/run/php-fpm && chown nginx:nginx /var/run/php-fpm` |
| PHP-FPM no inicia | Verificar sintaxis: `php-fpm -t`. Revisar logs: `journalctl -u php-fpm` |
| Nginx no inicia | Verificar sintaxis: `nginx -t`. Verificar que el puerto 8091 no este ocupado: `ss -tunlp \| grep 8091` |

## Recursos

- [Nginx - PHP FastCGI Example](https://www.nginx.com/resources/wiki/start/topics/examples/phpfcgi/)
- [PHP-FPM Configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [Nginx - fastcgi_pass](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html#fastcgi_pass)
