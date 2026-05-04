# Día 45 - Resolver errores en un Dockerfile

## Problema / Desafío

El equipo de desarrollo de Nautilus dejó un `Dockerfile` en `/opt/docker/` de App Server 1 (`stapp01`), pero el `docker build` falla. Hay que identificar los errores y arreglarlo **sin cambiar**:

- la imagen base
- las configuraciones válidas dentro del Dockerfile
- los datos usados (ej. `index.html`)

Resumen del archivo: parte de `httpd:2.4.43`, modifica `httpd.conf` (cambia el puerto a 8080, habilita SSL), copia certificados y un `index.html`.

## Conceptos clave

### Instrucciones de un Dockerfile

| Instrucción | Qué hace | Cuándo usar |
|-------------|----------|-------------|
| `FROM <imagen>` | Define la imagen base | Siempre primera línea |
| `RUN <comando>` | Ejecuta un comando **durante el build** y persiste el resultado en una capa | Instalar paquetes, modificar archivos |
| `COPY <src> <dst>` | Copia archivos del contexto de build a la imagen | Código, configs, certificados |
| `ADD <src> <dst>` | Como `COPY`, pero acepta URLs y descomprime tarballs automáticamente | Solo si necesitas esas capacidades |
| `CMD ["..."]` | Comando default al ejecutar el contenedor | Definir el proceso principal |
| `EXPOSE <puerto>` | Documentación: declara qué puerto usa el contenedor | Informativo (no publica el puerto) |

### `IMAGE` no existe

El error inicial del lab fue usar `IMAGE httpd:2.4.43` como primera línea. Docker no tiene una instrucción `IMAGE` — la palabra reservada para definir la imagen base es `FROM`. El parser falla en línea 1 antes de leer el resto del archivo.

### `ADD` vs `COPY` vs `RUN`

Los tres se confunden con frecuencia:

- **`COPY`** copia archivos del **build context** (la carpeta donde corres `docker build`) a la imagen. Es la opción por defecto cuando solo necesitas mover archivos locales.
- **`ADD`** hace lo mismo que `COPY` y además: descarga URLs y descomprime archivos tar automáticamente. Esta "magia" es justamente lo que la documentación oficial recomienda evitar — usa `COPY` salvo que necesites lo extra.
- **`RUN`** ejecuta un comando dentro del contenedor en construcción. El resultado del comando (archivos modificados, paquetes instalados) queda persistido como una nueva capa de la imagen.

En el Dockerfile original había líneas como:

```dockerfile
ADD sed -i "s/Listen 80/Listen 8080/g" /usr/local/apache2/conf/httpd.conf
```

Esto hace que Docker interprete `sed`, `-i`, `s/Listen 80/Listen 8080/g` como **archivos locales** que debe copiar al destino — archivos que no existen en el contexto. Lo que se quería era *ejecutar* `sed`, así que la instrucción correcta es `RUN`.

### Comillas en `sed`: simples vs dobles

`sed -i "s/Listen 80/Listen 8080/g"` y `sed -i 's/Listen 80/Listen 8080/g'` producen el mismo resultado en este caso — no hay variables, backticks ni `\` especiales que el shell pueda expandir.

**Pero la convención es usar comillas simples** porque:

1. Bloquean la expansión de `$VAR`, `` `cmd` ``, y `!history`. Si tu sed llega a contener uno de esos caracteres, las comillas dobles los modificarán silenciosamente antes de que sed los reciba.
2. Hacen el patrón portable entre shells (bash, sh, dash) sin sorpresas.
3. Es lo que esperan ver quienes leen `sed` en cualquier base de código.

En este Dockerfile específico, las comillas dobles no rompen el build — solo es mala práctica. (Más detalle en la página de [tools/sed](../../tools/sed/) de este sitio.)

## Pasos

1. Inspeccionar el Dockerfile original
2. Correr `docker build` y leer el error
3. Identificar cada problema: `IMAGE`, `ADD`, comillas
4. Corregir el archivo
5. Construir y verificar la imagen
6. (Opcional) Levantar un contenedor y validar con `curl`

## Comandos / Código

### 1. Dockerfile original (con errores)

```dockerfile
IMAGE httpd:2.4.43

ADD sed -i "s/Listen 80/Listen 8080/g" /usr/local/apache2/conf/httpd.conf

ADD sed -i '/LoadModule\ ssl_module modules\/mod_ssl.so/s/^#//g' conf/httpd.conf

ADD sed -i '/LoadModule\ socache_shmcb_module modules\/mod_socache_shmcb.so/s/^#//g' conf/httpd.conf

ADD sed -i '/Include\ conf\/extra\/httpd-ssl.conf/s/^#//g' conf/httpd.conf

COPY certs/server.crt /usr/local/apache2/conf/server.crt

COPY certs/server.key /usr/local/apache2/conf/server.key

COPY html/index.html /usr/local/apache2/htdocs/
```

### 2. Build inicial: el parser explota en línea 1

```bash
docker build .
```

```
[+] Building 0.3s (1/1) FINISHED                                                  docker:default
 => [internal] load build definition from Dockerfile                                        0.1s
 => => transferring dockerfile: 557B                                                        0.0s
Dockerfile:1
--------------------
   1 | >>> IMAGE httpd:2.4.43
   2 |
   3 |     ADD sed -i "s/Listen 80/Listen 8080/g" /usr/local/apache2/conf/httpd.conf
--------------------
ERROR: failed to build: failed to solve: dockerfile parse error on line 1: unknown instruction: IMAGE
```

El parser de Dockerfile rechaza el archivo entero antes de evaluar nada más. Por eso no veremos los errores de `ADD` hasta que arreglemos `IMAGE`.

### 3. Diagnóstico de cada error

| Línea | ❌ Original | ✅ Corregido | Por qué |
|-------|------------|--------------|---------|
| 1 | `IMAGE httpd:2.4.43` | `FROM httpd:2.4.43` | `IMAGE` no es instrucción válida — la imagen base se define con `FROM` |
| 3 | `ADD sed -i "..." ...` | `RUN sed -i '...' ...` | `ADD` copia archivos; para *ejecutar* un comando se usa `RUN`. Comillas simples para sed por convención |
| 5 | `ADD sed -i ...` | `RUN sed -i ...` | Mismo problema: era un comando, no una copia |
| 7 | `ADD sed -i ...` | `RUN sed -i ...` | Mismo problema |
| 9 | `ADD sed -i ...` | `RUN sed -i ...` | Mismo problema |
| 11–15 | `COPY ...` | `COPY ...` | ✅ Estas sí estaban bien — copian archivos reales del contexto |

### 4. Dockerfile corregido

```dockerfile
FROM httpd:2.4.43

RUN sed -i 's/Listen 80/Listen 8080/g' /usr/local/apache2/conf/httpd.conf

RUN sed -i '/LoadModule\ ssl_module modules\/mod_ssl.so/s/^#//g' conf/httpd.conf

RUN sed -i '/LoadModule\ socache_shmcb_module modules\/mod_socache_shmcb.so/s/^#//g' conf/httpd.conf

RUN sed -i '/Include\ conf\/extra\/httpd-ssl.conf/s/^#//g' conf/httpd.conf

COPY certs/server.crt /usr/local/apache2/conf/server.crt

COPY certs/server.key /usr/local/apache2/conf/server.key

COPY html/index.html /usr/local/apache2/htdocs/
```

### 5. Build exitoso

```bash
docker build .
```

```
[+] Building 10.3s (13/13) FINISHED                                               docker:default
 => [internal] load build definition from Dockerfile                                        0.0s
 => => transferring dockerfile: 557B                                                        0.0s
 => [internal] load metadata for docker.io/library/httpd:2.4.43                             0.4s
 => [internal] load .dockerignore                                                           ...
```

### 6. Verificar la imagen

```bash
docker image ls
```

```
REPOSITORY   TAG       IMAGE ID       CREATED              SIZE
<none>       <none>    bf9378856bef   About a minute ago   166MB
```

La imagen está como `<none>:<none>` porque construimos sin `-t`. Para dejarla con tag se usa `docker build -t mi-imagen:v1 .`.

### 7. Validar con un contenedor

```bash
curl -I localhost:8080
```

```
HTTP/1.1 200 OK
content-type: text/html
content-length: 464459
```

`200 OK` en el puerto **8080** confirma que la línea `RUN sed -i 's/Listen 80/Listen 8080/g'` se aplicó: el `httpd.conf` ahora escucha en 8080 en vez del default 80.

## Optimización: combinar los `RUN sed` en uno solo

Cada `RUN` crea una **capa nueva** en la imagen. Cuatro `RUN sed` separados = cuatro capas casi vacías (cada una solo cambia un par de líneas en `httpd.conf`). Combinarlas en un solo `RUN` con `&&` reduce el número de capas y el tamaño final de la imagen.

```dockerfile
RUN sed -i 's/Listen 80/Listen 8080/g' /usr/local/apache2/conf/httpd.conf \
 && sed -i '/LoadModule\ ssl_module modules\/mod_ssl.so/s/^#//g' conf/httpd.conf \
 && sed -i '/LoadModule\ socache_shmcb_module modules\/mod_socache_shmcb.so/s/^#//g' conf/httpd.conf \
 && sed -i '/Include\ conf\/extra\/httpd-ssl.conf/s/^#//g' conf/httpd.conf
```

### Por qué `&&` y no solo `\`

`\` al final de línea solo le indica al shell que la línea continúa — no separa comandos. Si encadenas con solo `\`, el shell interpreta todo como una única invocación:

```bash
# ❌ Sin && entre las líneas, el shell ve:
sed -i 's/Listen 80/Listen 8080/g' /usr/local/apache2/conf/httpd.conf sed -i '/LoadModule.../' conf/httpd.conf ...
```

Y `sed` toma el primer patrón y trata el resto (incluyendo las palabras `sed`, `-i` y los demás patrones) como **archivos a editar**, lo que falla con `sed: can't read sed: No such file or directory`.

| Separador | Comportamiento |
|-----------|----------------|
| `&&` | Ejecuta el siguiente **solo si el anterior tuvo exit code 0**. Correcto para `RUN`: un fallo aborta el build |
| `;` | Ejecuta el siguiente **siempre**, falle o no el anterior. Peligroso — un error silencioso pasa desapercibido |
| `\` solo | No separa comandos, solo continúa la línea lógicamente |

> Trade-off de combinar: menos capas hacen la imagen más pequeña, pero pierdes granularidad en el cache de build. Si modificas un solo sed, Docker tiene que volver a ejecutar todos los del mismo `RUN`. Para configs estables como esta no importa; para builds donde cambia código frecuentemente, conviene mantener separados los comandos costosos.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `dockerfile parse error on line N: unknown instruction: X` | La palabra clave no existe — revisar mayúsculas y nombre real (`FROM`, `RUN`, `COPY`, `ADD`, `CMD`, `ENTRYPOINT`, `EXPOSE`, `ENV`, `WORKDIR`, `USER`, `LABEL`, `ARG`, `VOLUME`, `HEALTHCHECK`, `ONBUILD`, `STOPSIGNAL`, `SHELL`) |
| `ADD failed: file not found in build context` | `ADD`/`COPY` busca el archivo relativo al contexto (`.` en `docker build .`). Verificar que el archivo existe ahí, no en otra ruta del host |
| `sed: -e expression: unterminated 's' command` | Falta el `/` de cierre en el patrón sed o falta un argumento — revisar cada `s/.../.../flags` |
| Imagen construye pero `curl` da `Connection refused` | El cambio de puerto no se aplicó o el contenedor no expone el puerto — `docker logs <id>` para ver si Apache arrancó, y verificar `-p host:8080` al hacer `docker run` |
| Build muy lento porque baja la imagen base cada vez | `docker pull` no la dejó en cache — `docker image ls` para confirmar; el primer build siempre paga el download |

## Recursos

- [Dockerfile reference — instrucciones completas](https://docs.docker.com/reference/dockerfile/)
- [Best practices: ADD vs COPY](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#add-or-copy)
- [Tutorial sed en este sitio](../../tools/sed/)
- [httpd 2.4 docs — Listen directive](https://httpd.apache.org/docs/2.4/bind.html)
