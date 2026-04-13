# Dia 18 - Instalar y configurar LAMP Stack (Linux, Apache, MariaDB, PHP)

## Problema / Desafio

Configurar un LAMP stack completo para hospedar un sitio WordPress en Stratos DC:

1. Instalar `httpd`, `php` y sus dependencias en los 3 app servers
2. Apache debe servir en el puerto **8087**
3. Instalar y configurar MariaDB en el DB Server
4. Crear base de datos `kodekloud_db1` y usuario `kodekloud_rin` con password `8FmzjvFU6S` con permisos completos
5. El sitio debe ser accesible desde el LBR mostrando conexion exitosa a la base de datos

**Nota:** ya existe un directorio compartido `/var/www/html` montado en los 3 app servers desde el storage server.

## Conceptos clave

### Que es LAMP

LAMP es un stack de tecnologias para servir aplicaciones web dinamicas:

```
L → Linux           Sistema operativo
A → Apache (httpd)   Servidor web
M → MariaDB/MySQL    Base de datos
P → PHP              Lenguaje de programacion
```

```
Flujo de una peticion:

Cliente → LBR → Apache:8087 → archivo .php?
                  │                │
                  ├── NO (.html, .css, .js) → Sirve directo
                  └── SI (.php) → PHP interpreta
                                    │
                                    └── Necesita datos? → MariaDB:3306
                                                           │
                                                           └── Resultado → PHP → Apache → Cliente
```

### Arquitectura del ejercicio

```
Jump Host
    │
    ▼
LBR (Nginx Load Balancer)
    │
    ├── stapp01:8087 (Apache + PHP) ──┐
    ├── stapp02:8087 (Apache + PHP) ──┼── /var/www/html (NFS compartido)
    └── stapp03:8087 (Apache + PHP) ──┘          │
                                                  ▼
                                          stdb01:3306 (MariaDB)
```

Los 3 app servers comparten el mismo `/var/www/html` via NFS desde el storage server, asi que el codigo PHP es el mismo en los 3.

### mariadb-secure-installation

Al instalar MariaDB, viene con configuracion insegura por defecto. `mariadb-secure-installation` es un script interactivo que:

| Paso | Que hace | Recomendacion |
|------|---------|---------------|
| Set root password | Define password para root de MariaDB | Si — siempre poner password |
| Remove anonymous users | Elimina usuarios anonimos que pueden conectar sin autenticacion | Si |
| Disallow root login remotely | Previene que root se conecte desde otro servidor | Si |
| Remove test database | Elimina la base de datos `test` accesible por todos | Si |
| Reload privilege tables | Aplica los cambios inmediatamente | Si |

### Modulos PHP necesarios

| Paquete | Funcion |
|---------|---------|
| `php` | Interprete PHP base |
| `php-cli` | PHP desde linea de comandos |
| `php-mysqlnd` | Driver nativo para conectar PHP con MySQL/MariaDB |
| `php-opcache` | Cache de bytecode — mejora rendimiento |
| `php-gd` | Manipulacion de imagenes (requerido por WordPress) |
| `php-curl` | Peticiones HTTP desde PHP |
| `php-mbstring` | Soporte de strings multibyte (UTF-8, caracteres especiales) |

`php-mysqlnd` es **critico** — sin el, PHP no puede conectarse a MariaDB y la aplicacion falla.

## Pasos

1. Instalar y configurar MariaDB en el DB Server
2. Crear la base de datos y el usuario
3. Verificar conectividad desde los app servers
4. Instalar Apache y PHP en los 3 app servers
5. Configurar Apache en el puerto 8087
6. Verificar el stack completo

## Comandos / Codigo

### 1. Instalar MariaDB en el DB Server

```bash
ssh peter@stdb01
```

```bash
# Instalar MariaDB server y cliente
sudo yum install -y mariadb mariadb-server

# Habilitar e iniciar el servicio
sudo systemctl enable mariadb
sudo systemctl start mariadb

# Ejecutar la configuracion de seguridad
sudo mariadb-secure-installation
```

Respuestas recomendadas para `mariadb-secure-installation`:

```
Enter current password for root (enter for none): [Enter]
Set root password? [Y/n]: Y
New password: [definir password]
Remove anonymous users? [Y/n]: Y
Disallow root login remotely? [Y/n]: Y
Remove test database? [Y/n]: Y
Reload privilege tables now? [Y/n]: Y
```

### 2. Crear base de datos y usuario

```bash
# Conectarse a MariaDB
mysql -u root -p
```

```sql
-- Crear la base de datos
CREATE DATABASE kodekloud_db1;

-- Crear usuario con acceso desde cualquier app server
CREATE USER 'kodekloud_rin'@'%' IDENTIFIED BY '8FmzjvFU6S';

-- Otorgar permisos completos sobre la base de datos
GRANT ALL PRIVILEGES ON kodekloud_db1.* TO 'kodekloud_rin'@'%';

-- Aplicar los cambios de permisos
FLUSH PRIVILEGES;

-- Verificar
SHOW DATABASES;
SELECT user, host FROM mysql.user WHERE user = 'kodekloud_rin';
```

**El `@'%'` es importante:**

| Host | Significado |
|------|------------|
| `@'localhost'` | Solo puede conectar desde el mismo servidor |
| `@'%'` | Puede conectar desde **cualquier** IP |
| `@'172.16.238.%'` | Solo desde IPs del rango 172.16.238.x |
| `@'stapp01'` | Solo desde un host especifico |

Como los app servers necesitan conectarse remotamente al DB server, se usa `@'%'`.

**`GRANT ... ON kodekloud_db1.*`** — el `.*` significa todas las tablas dentro de esa base de datos.

**`FLUSH PRIVILEGES`** — recarga las tablas de permisos. Necesario despues de cambios con `GRANT` o modificaciones directas a la tabla `mysql.user`.

### 3. Verificar conectividad desde los app servers

Antes de instalar todo, verificar que los app servers pueden alcanzar el DB server en el puerto 3306:

```bash
ssh tony@stapp01

# Instalar telnet para probar conectividad
sudo yum install -y telnet

# Probar conexion al puerto 3306 del DB server
telnet stdb01 3306
```

```
Trying 172.16.239.10...
Connected to stdb01.
```

Si dice `Connected`, la conectividad esta bien. Si falla, verificar:
- MariaDB esta escuchando en `0.0.0.0:3306` (no solo `127.0.0.1`)
- No hay firewall bloqueando el puerto

Para verificar en que interfaz escucha MariaDB:

```bash
# En el DB server
sudo netstat -tunlp | grep 3306
```

Si muestra `127.0.0.1:3306`, editar `/etc/my.cnf` o `/etc/my.cnf.d/server.cnf`:

```ini
[mysqld]
bind-address = 0.0.0.0
```

Y reiniciar: `sudo systemctl restart mariadb`

### 4. Instalar Apache y PHP en los app servers

Repetir en los 3 app servers (stapp01, stapp02, stapp03):

```bash
# Instalar Apache
sudo yum install -y httpd

# Instalar PHP con modulos necesarios
sudo yum install -y php php-cli php-mysqlnd php-opcache php-gd php-curl php-mbstring
```

### 5. Configurar Apache en el puerto 8087

Editar la configuracion de Apache:

```bash
sudo vi /etc/httpd/conf/httpd.conf
```

Buscar la directiva `Listen` y cambiar el puerto:

```apache
# Antes
Listen 80

# Despues
Listen 8087
```

Con `sed` de forma directa:

```bash
sudo sed -i 's/Listen 80$/Listen 8087/' /etc/httpd/conf/httpd.conf

# Verificar
grep '^Listen' /etc/httpd/conf/httpd.conf
```

Iniciar y habilitar Apache:

```bash
sudo systemctl enable httpd
sudo systemctl start httpd
```

Verificar:

```bash
curl localhost:8087
```

```
App is able to connect to the database using user kodekloud_rin
```

### 6. Repetir en los otros app servers

El proceso es identico en stapp02 y stapp03:

```bash
# Script rapido para cada server
sudo yum install -y httpd php php-cli php-mysqlnd php-opcache php-gd php-curl php-mbstring
sudo sed -i 's/Listen 80$/Listen 8087/' /etc/httpd/conf/httpd.conf
sudo systemctl enable httpd
sudo systemctl start httpd
curl localhost:8087
```

### 7. Verificar desde el jump host

```bash
# Verificar cada app server
for host in stapp01 stapp02 stapp03; do
  echo -n "$host: "
  curl -s $host:8087
  echo
done
```

```
stapp01: App is able to connect to the database using user kodekloud_rin
stapp02: App is able to connect to the database using user kodekloud_rin
stapp03: App is able to connect to the database using user kodekloud_rin
```

Verificar a traves del LBR:

```bash
curl http://lbr
```

## Orden de instalacion correcto

El orden importa porque cada capa depende de la anterior:

```
1. MariaDB (DB Server)     ← Primero: la base de datos debe existir
2. Crear DB + usuario      ← Segundo: las credenciales deben estar listas
3. Verificar conectividad  ← Tercero: confirmar que los app servers alcanzan el DB
4. Apache + PHP (App Servers) ← Cuarto: el stack web que conecta a la DB
5. Verificar end-to-end    ← Ultimo: probar todo el flujo
```

Si se instala Apache/PHP primero y la DB no esta lista, la aplicacion mostrara error de conexion.

## Diferencia entre mysql y mariadb (comandos)

MariaDB es un fork de MySQL. Los comandos son intercambiables:

| MySQL | MariaDB | Funcion |
|-------|---------|---------|
| `mysql` | `mysql` o `mariadb` | Cliente de linea de comandos |
| `mysqld` | `mariadbd` | Servidor |
| `mysql_secure_installation` | `mariadb-secure-installation` | Configuracion de seguridad |
| `mysqldump` | `mariadb-dump` | Backup de bases de datos |

Los comandos `mysql*` siguen funcionando en MariaDB como alias.

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| PHP no conecta a MariaDB | Verificar que `php-mysqlnd` esta instalado: `php -m \| grep mysql` |
| `Access denied for user 'kodekloud_rin'` | Verificar que el usuario fue creado con `@'%'` y no `@'localhost'`. Verificar password |
| `Can't connect to MySQL server on stdb01` | Verificar que MariaDB escucha en `0.0.0.0:3306` y no en `127.0.0.1`. Verificar firewall |
| Apache no inicia: `Address already in use` | Otro proceso usa el puerto 8087. Verificar con `netstat -tunlp \| grep 8087` |
| `curl localhost:8087` muestra pagina de test de Apache | El archivo `index.php` no esta en `/var/www/html/` o el mount NFS no funciona |
| Funciona en stapp01 pero no en stapp02/03 | Verificar que Apache y PHP estan instalados en los 3. Verificar que `/var/www/html` esta montado (NFS) |
| `FLUSH PRIVILEGES` olvidado | Los cambios de permisos no se aplican hasta ejecutar `FLUSH PRIVILEGES` o reiniciar MariaDB |

## Recursos

- [Apache HTTP Server](https://httpd.apache.org/docs/2.4/)
- [MariaDB - CREATE USER](https://mariadb.com/kb/en/create-user/)
- [MariaDB - GRANT](https://mariadb.com/kb/en/grant/)
- [PHP - MySQLnd](https://www.php.net/manual/en/book.mysqlnd.php)
- [mariadb-secure-installation](https://mariadb.com/kb/en/mariadb-secure-installation/)
