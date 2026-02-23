# Dia 11 - Instalar y configurar Apache Tomcat

## Problema / Desafio

Se necesita instalar y configurar un servidor Apache Tomcat en App Server 1 (`stapp01`) para que:

1. Corra en el puerto **3000** (en lugar del puerto por defecto 8080)
2. Sirva una aplicacion web a partir del archivo `ROOT.war` ubicado en `/tmp`
3. La pagina sea accesible en `http://stapp01:3000`

## Conceptos clave

### Apache Tomcat

Apache Tomcat es un servidor de aplicaciones web open source que implementa las especificaciones Java Servlet, JavaServer Pages (JSP) y WebSocket. Es el servidor mas usado para desplegar aplicaciones Java web empaquetadas como archivos `.war`.

### Archivo WAR (Web Application Archive)

Un archivo `.war` es un paquete que contiene una aplicacion web Java completa (servlets, JSPs, HTML, CSS, JS, librerias). Tomcat descomprime automaticamente el `.war` al colocarlo en el directorio `webapps/`.

### ROOT.war

Cuando un archivo se llama `ROOT.war`, Tomcat lo despliega como la aplicacion raiz del servidor. Esto significa que es accesible directamente en `/` (sin path adicional), por ejemplo `http://stapp01:3000/`.

### Estructura de directorios de Tomcat

```
/opt/tomcat/                    # Directorio de instalacion
├── bin/                        # Scripts de inicio/parada
│   ├── startup.sh
│   └── shutdown.sh
├── conf/                       # Archivos de configuracion
│   └── server.xml              # Configuracion principal (puertos, conectores)
├── webapps/                    # Directorio de aplicaciones web
│   └── ROOT.war                # Aplicacion raiz
├── logs/                       # Logs del servidor
│   └── catalina.out
└── temp/                       # Archivos temporales
```

### Variables de entorno

Tomcat depende de dos variables de entorno clave:

| Variable | Descripcion | Ejemplo |
|----------|-------------|---------|
| `JAVA_HOME` | Ruta al JDK instalado | `/usr/lib/jvm/java-11-openjdk` |
| `CATALINA_HOME` | Ruta de instalacion de Tomcat | `/opt/tomcat` |

Sin `JAVA_HOME` configurado, Tomcat intenta detectar Java automaticamente pero puede fallar silenciosamente. Se recomienda definirlas explicitamente.

### autoDeploy y unpackWARs

En `server.xml`, el `<Host>` tiene dos atributos que controlan como Tomcat maneja los `.war`:

```xml
<Host name="localhost" appBase="webapps"
      unpackWARs="true" autoDeploy="true">
```

| Atributo | Valor | Comportamiento |
|----------|-------|---------------|
| `unpackWARs` | `true` | Tomcat descomprime el `.war` en una carpeta con el mismo nombre |
| `unpackWARs` | `false` | Tomcat sirve la app directamente desde el `.war` sin descomprimir |
| `autoDeploy` | `true` | Tomcat vigila `webapps/` y despliega automaticamente cualquier `.war` nuevo sin reiniciar |
| `autoDeploy` | `false` | Requiere reiniciar Tomcat para desplegar nuevas aplicaciones |

Con `autoDeploy="true"`, basta con copiar un `.war` a `webapps/` y Tomcat lo despliega en caliente.

## Pasos

1. Instalar Java (dependencia de Tomcat)
2. Crear usuario dedicado para Tomcat
3. Configurar variables de entorno
4. Descargar e instalar Apache Tomcat
5. Cambiar el puerto de 8080 a 3000 en `server.xml`
6. Copiar `ROOT.war` al directorio `webapps/`
7. Iniciar Tomcat
8. Verificar que la aplicacion responde en el puerto 3000

## Comandos / Codigo

### 1. Instalar Java

Tomcat requiere Java (JDK o JRE) para funcionar:

```bash
# En CentOS/RHEL
sudo yum install -y java-11-openjdk java-11-openjdk-devel

# Verificar la instalacion
java -version
```

```
openjdk version "11.0.x"
```

### 2. Crear usuario dedicado para Tomcat

Correr Tomcat como `root` es un riesgo de seguridad. Si un atacante explota una vulnerabilidad en la aplicacion, tendria acceso root al servidor. Lo correcto es crear un usuario dedicado sin login:

```bash
# Crear grupo y usuario tomcat sin shell de login
sudo groupadd tomcat
sudo useradd -M -s /sbin/nologin -g tomcat -d /opt/tomcat tomcat
```

| Flag | Proposito |
|------|-----------|
| `-M` | No crear directorio home |
| `-s /sbin/nologin` | Sin shell de login (no puede hacer SSH) |
| `-g tomcat` | Grupo primario `tomcat` |
| `-d /opt/tomcat` | Directorio home apunta a la instalacion de Tomcat |

### 3. Configurar variables de entorno

Crear un archivo de configuracion para las variables:

```bash
sudo vi /etc/profile.d/tomcat.sh
```

```bash
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export CATALINA_HOME=/opt/tomcat
export PATH=$PATH:$CATALINA_HOME/bin
```

Aplicar los cambios:

```bash
source /etc/profile.d/tomcat.sh

# Verificar
echo $JAVA_HOME
echo $CATALINA_HOME
```

### 4. Descargar e instalar Tomcat

```bash
# Descargar Tomcat (verificar la version mas reciente disponible)
cd /tmp
sudo wget https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.80/bin/apache-tomcat-9.0.80.tar.gz

# Extraer en /opt
sudo tar -xzf apache-tomcat-9.0.80.tar.gz -C /opt/
sudo mv /opt/apache-tomcat-9.0.80 /opt/tomcat

# Dar permisos de ejecucion a los scripts
sudo chmod +x /opt/tomcat/bin/*.sh

# Asignar ownership al usuario tomcat
sudo chown -R tomcat:tomcat /opt/tomcat
```

### 5. Cambiar el puerto a 3000

Editar el archivo `server.xml`:

```bash
sudo vi /opt/tomcat/conf/server.xml
```

Buscar la linea del conector HTTP (por defecto en puerto 8080):

```xml
<!-- Antes -->
<Connector port="8080" protocol="HTTP/1.1"
           connectionTimeout="20000"
           redirectPort="8443" />

<!-- Despues -->
<Connector port="3000" protocol="HTTP/1.1"
           connectionTimeout="20000"
           redirectPort="8443" />
```

Con `sed` de forma directa:

```bash
sudo sed -i 's/port="8080"/port="3000"/' /opt/tomcat/conf/server.xml
```

Verificar el cambio:

```bash
grep 'Connector port' /opt/tomcat/conf/server.xml
```

```
<Connector port="3000" protocol="HTTP/1.1"
```

### 6. Copiar ROOT.war al directorio webapps

```bash
# Limpiar el ROOT por defecto de Tomcat
sudo rm -rf /opt/tomcat/webapps/ROOT
sudo rm -f /opt/tomcat/webapps/ROOT.war

# Copiar el WAR proporcionado
sudo cp /tmp/ROOT.war /opt/tomcat/webapps/ROOT.war
```

### 7. Iniciar Tomcat

```bash
sudo /opt/tomcat/bin/startup.sh
```

```
Using CATALINA_BASE:   /opt/tomcat
Using CATALINA_HOME:   /opt/tomcat
Using CATALINA_TMPDIR: /opt/tomcat/temp
Using JRE_HOME:        /usr
Using CLASSPATH:       /opt/tomcat/bin/bootstrap.jar:/opt/tomcat/bin/tomcat-juli.jar
Tomcat started.
```

### 8. Verificar el servicio

```bash
# Verificar que Tomcat esta escuchando en el puerto 3000
ss -tlnp | grep 3000
```

```
LISTEN  0  100  *:3000  *:*  users:(("java",pid=12345,fd=56))
```

```bash
# Verificar la aplicacion web
curl http://stapp01:3000
```

### Detener y reiniciar Tomcat

```bash
# Detener
sudo /opt/tomcat/bin/shutdown.sh

# Reiniciar (detener + iniciar)
sudo /opt/tomcat/bin/shutdown.sh && sudo /opt/tomcat/bin/startup.sh
```

### Ver logs en tiempo real

```bash
sudo tail -f /opt/tomcat/logs/catalina.out
```

## Configuracion adicional

### Abrir el puerto en el firewall

Si `firewalld` esta activo, el puerto 3000 estara bloqueado por defecto:

```bash
# Verificar si firewalld esta activo
sudo systemctl status firewalld

# Abrir el puerto 3000 de forma permanente
sudo firewall-cmd --zone=public --add-port=3000/tcp --permanent

# Recargar las reglas
sudo firewall-cmd --reload

# Verificar que el puerto esta abierto
sudo firewall-cmd --list-ports
```

```
3000/tcp
```

Sin este paso, `curl http://stapp01:3000` funcionara localmente pero no desde otros servidores.

### Crear servicio systemd

Usar `startup.sh` y `shutdown.sh` funciona, pero tiene desventajas: Tomcat no se reinicia automaticamente si el servidor se reinicia, y no se puede gestionar con `systemctl`. Crear un servicio systemd resuelve esto:

```bash
sudo vi /etc/systemd/system/tomcat.service
```

```ini
[Unit]
Description=Apache Tomcat 9
After=network.target

[Service]
Type=forking

User=tomcat
Group=tomcat

Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
# Recargar systemd
sudo systemctl daemon-reload

# Iniciar Tomcat como servicio
sudo systemctl start tomcat

# Habilitar inicio automatico al boot
sudo systemctl enable tomcat

# Verificar estado
sudo systemctl status tomcat
```

```
● tomcat.service - Apache Tomcat 9
   Active: active (running)
```

Ahora se puede gestionar Tomcat con:

```bash
sudo systemctl start tomcat
sudo systemctl stop tomcat
sudo systemctl restart tomcat
sudo systemctl status tomcat
```

### Eliminar aplicaciones por defecto

Tomcat incluye varias aplicaciones en `webapps/` que no deben estar en produccion:

| App | Riesgo |
|-----|--------|
| `manager` | Permite desplegar/eliminar apps remotamente. Tiene credenciales por defecto |
| `host-manager` | Permite crear virtual hosts remotamente |
| `docs` | Documentacion — expone la version exacta de Tomcat |
| `examples` | Ejemplos con codigo vulnerable a ataques |

```bash
# Eliminar todas las apps por defecto (excepto ROOT que es nuestra app)
sudo rm -rf /opt/tomcat/webapps/manager
sudo rm -rf /opt/tomcat/webapps/host-manager
sudo rm -rf /opt/tomcat/webapps/docs
sudo rm -rf /opt/tomcat/webapps/examples
```

En un entorno de practica o lab no es critico, pero en produccion **siempre** se deben eliminar.

## Resumen rapido de comandos

```bash
# Instalacion completa en orden
sudo yum install -y java-11-openjdk
sudo groupadd tomcat && sudo useradd -M -s /sbin/nologin -g tomcat -d /opt/tomcat tomcat
cd /tmp && sudo wget https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.80/bin/apache-tomcat-9.0.80.tar.gz
sudo tar -xzf apache-tomcat-9.0.80.tar.gz -C /opt/ && sudo mv /opt/apache-tomcat-9.0.80 /opt/tomcat
sudo chmod +x /opt/tomcat/bin/*.sh
sudo chown -R tomcat:tomcat /opt/tomcat
sudo sed -i 's/port="8080"/port="3000"/' /opt/tomcat/conf/server.xml
sudo rm -rf /opt/tomcat/webapps/ROOT /opt/tomcat/webapps/ROOT.war
sudo cp /tmp/ROOT.war /opt/tomcat/webapps/ROOT.war
sudo /opt/tomcat/bin/startup.sh
curl http://stapp01:3000
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `java: command not found` | Instalar Java con `yum install -y java-11-openjdk` |
| Tomcat no inicia | Revisar logs en `/opt/tomcat/logs/catalina.out` para ver el error |
| Puerto 3000 no responde | Verificar con `ss -tlnp \| grep 3000` que Tomcat esta escuchando. Revisar firewall con `firewall-cmd --list-ports` |
| `Address already in use: 3000` | Otro proceso usa el puerto. Identificar con `ss -tlnp \| grep 3000` y detenerlo |
| Pagina 404 en `/` | Verificar que `ROOT.war` esta en `/opt/tomcat/webapps/` y que Tomcat lo descomprimio (debe existir `/opt/tomcat/webapps/ROOT/`) |
| Cambio de puerto no aplica | Reiniciar Tomcat despues de editar `server.xml`. Verificar que el `sed` modifico el archivo correctamente |

## Recursos

- [Apache Tomcat 9 Documentation](https://tomcat.apache.org/tomcat-9.0-doc/)
- [Tomcat Configuration Reference - HTTP Connector](https://tomcat.apache.org/tomcat-9.0-doc/config/http.html)
- [Deploying WAR files in Tomcat](https://tomcat.apache.org/tomcat-9.0-doc/deployer-howto.html)
