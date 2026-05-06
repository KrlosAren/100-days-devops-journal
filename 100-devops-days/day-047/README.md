# Día 47 - Dockerizar una app Flask en Python

## Problema / Desafío

El equipo de Nautilus tiene una app Python (Flask) que debe correr en contenedor sobre App Server 1 (`stapp01`). El código y dependencias ya están en `/python_app/src/`. Hay que:

- Crear un `Dockerfile` en `/python_app/` que use cualquier imagen oficial de Python como base
- Instalar las dependencias declaradas en `requirements.txt`
- Exponer el puerto `8087` (donde escucha Flask)
- Definir el `CMD` para ejecutar `server.py`
- Construir la imagen como `nautilus/python-app`
- Correr un contenedor `pythonapp_nautilus` mapeando `8094` (host) → `8087` (contenedor)

Validación: `curl localhost:8094` debe devolver `Welcome to xFusionCorp Industries!`.

## Conceptos clave

### Variantes de la imagen oficial de Python

La imagen `python` en Docker Hub no es una sola — son varias familias con tags como `python:<v>-alpine`, `python:<v>-slim`, `python:<v>-bookworm`, etc.

| Variante                | Base                                | Tamaño aprox. | Cuándo usarla                                                      |
| ----------------------- | ----------------------------------- | ------------- | ------------------------------------------------------------------ |
| `python:3.12` (default) | Debian completo                     | ~1 GB         | Compat máxima, builds que necesitan compiladores y libs del SO     |
| `python:3.12-slim`      | Debian mínimo (sin doc, sin extras) | ~150 MB       | Producción cuando necesitas glibc pero no todo Debian              |
| `python:3.12-alpine`    | Alpine Linux + musl libc            | ~50 MB        | Apps puras Python o con wheels precompilados — muy ligera          |
| `python:3.12-bookworm`  | Debian 12 explícito                 | ~1 GB         | Cuando necesitas pinear la versión de Debian para reproducibilidad |

**Cuidado con alpine + paquetes con C extensions:** alpine usa `musl` en vez de `glibc`. Paquetes de Python que dependen de wheels precompilados para `manylinux` (NumPy, pandas, psycopg2, cryptography…) no instalan directo y obligan a compilar en build, lo que aumenta el tiempo y a veces requiere instalar `gcc`, `musl-dev`, headers, etc. Para esta app (solo Flask), alpine es ideal.

### `WORKDIR`: directorio de trabajo dentro de la imagen

`WORKDIR /app` hace dos cosas:

1. Crea el directorio si no existe.
2. Cambia el directorio activo para todas las instrucciones siguientes (`COPY`, `RUN`, `CMD`).

Sin `WORKDIR`, cada `COPY` o `RUN` necesitaría rutas absolutas (`COPY ./src/ /app/`, `RUN cd /app && pip install...`). Con `WORKDIR`, las rutas relativas funcionan limpiamente.

### `EXPOSE` es documentación, no publicación

Una confusión clásica: `EXPOSE 8087` **no abre el puerto** ni lo publica al host. Es metadata informativa que dice "este contenedor escucha aquí". Para publicar de verdad, hay que pasar `-p` al `docker run`:

```bash
EXPOSE 8087                          # solo documenta
docker run -p 8094:8087 imagen       # esto sí publica
```

Sirve para herramientas que leen la metadata (como `docker run -P`, que mapea automáticamente todos los `EXPOSE`) y como contrato visible de qué puerto debe usar el operador.

### `CMD` exec form vs shell form

```dockerfile
# Exec form (recomendada) — JSON array
CMD ["python3", "/app/server.py"]

# Shell form — string que se ejecuta vía /bin/sh -c
CMD python3 /app/server.py
```

Diferencias:

- **Exec form** corre el comando directamente como PID 1. Las señales (`SIGTERM`, `SIGINT`) llegan al proceso real. Esto es lo que quieres para que `docker stop` apague Flask limpiamente en vez de matar `sh` y dejar al hijo huérfano.
- **Shell form** envuelve el comando en `/bin/sh -c`. PID 1 es `sh`, no Python. Las señales no se propagan bien por default. La ventaja es que puedes usar variables de entorno y operadores de shell (`&&`, `|`, `>`).

### Flask dev server vs producción

Cuando Flask arranca con `app.run(debug=True)`, levanta su **dev server** integrado, que:

- Recarga código al cambiar archivos
- Muestra debugger interactivo en errores
- **No es para producción** — single-thread, sin manejo robusto de concurrencia, debugger expone shell remota

El propio Flask lo grita en los logs:

```
WARNING: This is a development server. Do not use it in a production deployment.
Use a production WSGI server instead.
```

Para producción real se usa **gunicorn**, **uwsgi**, o **uvicorn** (para apps async). Para este lab el dev server está OK porque la consigna es solo "ejecutar `server.py`".

## Pasos

1. Inspeccionar `requirements.txt` y `server.py` para entender la app
2. Elegir la imagen base de Python
3. Escribir el Dockerfile
4. Construir la imagen con tag `nautilus/python-app`
5. Correr el contenedor con port mapping
6. Validar con `curl`

## Comandos / Código

### 1. Inspeccionar la app

```bash
cat /python_app/src/requirements.txt
```

```
flask
```

```bash
cat /python_app/src/server.py
```

```python
from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello():
    return "Welcome to xFusionCorp Industries!"

if __name__ == "__main__":
    app.config['TEMPLATES_AUTO_RELOAD'] = True
    app.run(host='0.0.0.0', debug=True, port=8087)
```

`host='0.0.0.0'` es importante: Flask escuchando en `127.0.0.1` solo aceptaría conexiones del propio contenedor; con `0.0.0.0` acepta desde cualquier interfaz, lo que permite que el port mapping de Docker funcione.

### 2. Dockerfile

```dockerfile
FROM python:3.12.13-alpine

WORKDIR /app

COPY ./src/ .

RUN pip3 install -r requirements.txt

EXPOSE 8087

CMD ["python3", "/app/server.py"]
```

### 3. Construir la imagen

```bash
docker build -t nautilus/python-app .
```

```bash
docker image ls
```

```
REPOSITORY            TAG       IMAGE ID       CREATED          SIZE
nautilus/python-app   latest    cff57e78ea50   19 seconds ago   62.5MB
```

62.5 MB es notablemente liviana — la base alpine + Python + Flask suman menos que la imagen base de Debian sola. Ese es el valor de elegir alpine cuando se puede.

### 4. Ejecutar el contenedor (foreground primero, para ver logs)

```bash
docker run --name pythonapp_nautilus -p 8094:8087 nautilus/python-app
```

```
 * Serving Flask app 'server'
 * Debug mode: on
WARNING: This is a development server. Do not use it in a production deployment...
 * Running on all addresses (0.0.0.0)
 * Running on http://127.0.0.1:8087
 * Running on http://172.12.0.2:8087
 * Debugger is active!
 * Debugger PIN: 126-068-238
```

Foreground es útil para confirmar que arranca sin errores. `Ctrl+C` lo detiene y libera la terminal.

### 5. Re-ejecutar en detached

```bash
# Quitar el contenedor anterior primero (sino, conflicto de nombre)
docker rm pythonapp_nautilus

docker run --name pythonapp_nautilus -p 8094:8087 -d nautilus/python-app
```

```
c0baab2eb46146340dae27f0e38a9fd19cf4b40947c432e9f327f8542c5c163e
```

```bash
docker ps
```

```
CONTAINER ID   IMAGE                 COMMAND                  CREATED         STATUS         PORTS                                       NAMES
c0baab2eb461   nautilus/python-app   "python3 /app/server…"   3 seconds ago   Up 2 seconds   0.0.0.0:8094->8087/tcp, :::8094->8087/tcp   pythonapp_nautilus
```

### 6. Validar la app

```bash
curl localhost:8094
```

```
Welcome to xFusionCorp Industries!
```

App respondiendo correctamente — el port mapping `8094 → 8087` funciona y Flask está sirviendo la ruta `/`.

## Optimización: aprovechar el cache de capas para `pip install`

El Dockerfile actual hace:

```dockerfile
COPY ./src/ .                              # copia TODO (código + requirements.txt)
RUN pip3 install -r requirements.txt       # instala deps
```

El problema: cada vez que **modificas el código** (por ejemplo, cambias `server.py`), Docker invalida la capa del `COPY` — y por consecuencia también la capa del `RUN pip3 install`. Tienes que volver a descargar e instalar Flask aunque las dependencias no hayan cambiado.

La regla del cache de Docker: **una capa se invalida si su input cambia, y todas las capas siguientes también**. Para evitar reinstalar deps en cada build, hay que separar lo que cambia poco (deps) de lo que cambia mucho (código):

```dockerfile
FROM python:3.12.13-alpine

WORKDIR /app

COPY ./src/requirements.txt .

RUN pip3 install -r requirements.txt

COPY ./src/server.py .

EXPOSE 8087

CMD ["python3", "/app/server.py"]
```

> **Trade-off:** dos `COPY` separados son una línea más de Dockerfile, pero ahorran segundos (o minutos en proyectos con muchas deps) en cada build de iteración. Para imágenes con `pandas`, `tensorflow`, etc., la diferencia es enorme — esa es la razón por la que el patrón es estándar en el ecosistema Python.

## Troubleshooting

| Problema                                                                              | Solución                                                                                                                                                    |
| ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pip: command not found` durante el build                                             | La imagen base no incluye pip — usar `python:<v>-alpine` o `python:<v>-slim` (no `python:<v>-alpine-bare` o variantes minimal)                              |
| `error: command 'gcc' failed: No such file or directory` al instalar wheels en alpine | Paquete necesita compilar — agregar `RUN apk add --no-cache gcc musl-dev <headers>` antes del `pip install`, o cambiar a `python:<v>-slim`                  |
| `curl: (52) Empty reply from server`                                                  | Flask escuchando en `127.0.0.1` en vez de `0.0.0.0` — verificar el `app.run(host=...)`                                                                      |
| `Bind for 0.0.0.0:8094 failed: port is already allocated`                             | Otro contenedor o proceso usa el 8094 — `docker ps` o `ss -tlnp \| grep 8094`                                                                               |
| El contenedor inicia pero `docker stop` tarda 10s en detenerlo                        | `CMD` está en shell form (`CMD python3 ...`) — Python no recibe `SIGTERM` y Docker mata después del timeout. Cambiar a exec form (`CMD ["python3", "..."]`) |
| Cambié el código pero el contenedor sigue mostrando lo viejo                          | Reconstruir la imagen (`docker build -t ...`) y recrear el contenedor — la imagen es inmutable, no toma cambios del host después del build                  |

## Recursos

- [Imagen oficial de Python — variantes y tags](https://hub.docker.com/_/python)
- [Dockerfile reference: CMD](https://docs.docker.com/reference/dockerfile/#cmd)
- [Flask deployment options (production WSGI)](https://flask.palletsprojects.com/en/latest/deploying/)
- [Best practices: minimize layers and use cache](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#leverage-build-cache)
