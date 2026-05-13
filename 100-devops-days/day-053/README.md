# Día 53 - Troubleshooting: VolumeMount mal alineado en Nginx + PHP-FPM

## Problema / Desafío

El equipo tiene un Pod `nginx-phpfpm` con dos containers (nginx + php-fpm) y un ConfigMap `nginx-config`. El Pod corre `2/2 Running` pero al acceder al sitio devuelve `403 Forbidden`. Hay que:

1. Investigar y entender qué está mal
2. Corregir el problema
3. Copiar `/home/thor/index.php` desde el jump host al document root del nginx
4. Confirmar que el sitio responde

## Conceptos clave

### El patrón sidecar nginx + php-fpm

Es un patrón clásico de "dos containers que se hablan localmente":

- **`nginx-container`**: recibe HTTP, sirve estáticos directos, y para los `.php` arma una request FastCGI a `127.0.0.1:9000`
- **`php-fpm-container`**: escucha en `127.0.0.1:9000` (es por eso que comparten `localhost` — están en el mismo Pod), recibe la request FastCGI, **abre el archivo `.php` desde su propio filesystem**, lo ejecuta, y devuelve el output a nginx

Para que el handoff funcione, ambos containers comparten un **volumen `emptyDir`** donde están los archivos PHP. nginx lo monta en el path que tiene como `root` en su config; php-fpm lo monta en el path que recibirá vía `SCRIPT_FILENAME`.

### El contrato FastCGI: los paths tienen que coincidir

Esta es la parte conceptualmente más fina y la causa raíz del bug de hoy. El flujo FastCGI:

1. nginx recibe `GET /index.php`
2. nginx mira su config: `root /var/www/html` → arma el `SCRIPT_FILENAME = /var/www/html/index.php`
3. nginx manda una request FastCGI a `127.0.0.1:9000` con ese path en el mensaje
4. **php-fpm abre el archivo desde su propio filesystem en ese path exacto**
5. Lo ejecuta y devuelve el output

> nginx **no le manda el contenido** del archivo a php-fpm — le manda **la ruta**. php-fpm hace su propio `open()` sobre **su propio filesystem**. Por eso los containers pueden compartir bytes (vía `emptyDir`), pero cada uno tiene **su propia vista** del filesystem.

Si los paths divergen — nginx dice `/var/www/html/index.php` pero php-fpm lo tiene montado en `/usr/share/nginx/html` — php-fpm devuelve "File not found" y nginx lo propaga como `404`, `403`, o `502` según la config.

### Por qué nginx devolvió 403 (no 404 ni 500)

Cuando llega `GET /`, nginx:

1. Resuelve `try_files $uri $uri/ =404` para `/` → busca `/var/www/html/` (el directorio)
2. El directorio **existe** (está montado como emptyDir vacío)
3. Busca `index.html`, `index.htm`, `index.php` en ese directorio → no encuentra ninguno
4. Como `autoindex` está off por default, devuelve `403 Forbidden`

Si el path no existiera devolvería `404`. Si existiera pero sin permisos también `403`. La distinción es útil al debuggear:

| Código | Causa típica con nginx                                                                |
| ------ | -------------------------------------------------------------------------------------- |
| `404`  | El `root` no existe en el filesystem del container, o `try_files` no matchea           |
| `403`  | El directorio existe pero está vacío de archivos índice, o falta permiso de lectura    |
| `502`  | nginx no pudo conectarse con `fastcgi_pass` (php-fpm caído, puerto distinto)           |
| `404` con PHP "File not found" en el body | nginx llegó a php-fpm pero php-fpm no encontró el `SCRIPT_FILENAME` |

### Inmutabilidad de los Pods

Un Pod **stand-alone** (no creado por un Deployment/RS) tiene muchos campos inmutables después de la creación. `spec.containers[].volumeMounts` es uno de ellos. No se puede hacer `kubectl edit pod` y cambiar el mountPath — K8s rechaza el update con `Pod is invalid`.

La forma de "editar" un Pod es **reemplazarlo**: dump del YAML, edit, delete + recreate. `kubectl replace --force` hace exactamente eso en un solo paso.

> En producción esto sería raro de necesitar — los Pods en serio se manejan vía Deployments/StatefulSets/Jobs, y a esos sí se les puede editar la `template` (el controller se encarga de recrear los Pods).

### `kubectl cp` por dentro

Es un wrapper sobre `kubectl exec` + `tar`. El flujo:

1. cliente: comprime el archivo local con `tar` → stream
2. cliente: `kubectl exec <pod> -c <container> -- tar xf -` con el stream como stdin
3. el container extrae el tar a la ruta especificada

Por eso requiere **`tar` instalado en el container**. Las imágenes mínimas tipo `alpine`, `scratch`, `distroless` pueden no tenerlo — ahí `kubectl cp` falla con `error: executable not found in $PATH`.

## Pasos

1. Inspeccionar el Pod y el ConfigMap para entender el setup actual
2. Reproducir el 403 con `curl`
3. Identificar el mismatch entre el `root` del nginx config y los `volumeMounts` de los containers
4. Dump del Pod YAML, fix del path, `kubectl replace --force`
5. Confirmar el nuevo mount con `describe`
6. `kubectl cp` del `index.php` al document root
7. Validar con `curl -I` esperando `200`

## Comandos / Código

### 1. Inspección inicial

```bash
kubectl get pods
```

```
NAME           READY   STATUS    RESTARTS   AGE
nginx-phpfpm   2/2     Running   0          2m23s
```

El Pod está `Running` con `2/2` containers ready. El problema **no es de scheduling ni de imágenes** — los containers están vivos. El bug está más arriba en la stack (config o file system).

```bash
kubectl describe pod nginx-phpfpm
```

Output relevante:

```
Containers:
  php-fpm-container:
    Image:          php:7.2-fpm-alpine
    Mounts:
      /usr/share/nginx/html from shared-files (rw)      ← mount A
  nginx-container:
    Image:          nginx:latest
    Mounts:
      /etc/nginx/nginx.conf from nginx-config-volume (rw,path="nginx.conf")
      /var/www/html from shared-files (rw)              ← mount B (DISTINTO de mount A)
Volumes:
  shared-files:
    Type:       EmptyDir
  nginx-config-volume:
    Type:       ConfigMap
    Name:       nginx-config
```

**Pista clave**: el volumen `shared-files` (un `emptyDir`) está montado en paths **distintos** en cada container:

| Container         | Mount path                |
| ----------------- | ------------------------- |
| `php-fpm-container` | `/usr/share/nginx/html` |
| `nginx-container`   | `/var/www/html`         |

### 2. Revisar el ConfigMap del nginx

```bash
kubectl describe configmap nginx-config
```

```
nginx.conf:
----
events {
}
http {
  server {
    listen 8099 default_server;
    listen [::]:8099 default_server;
    root /var/www/html;                     ← document root es /var/www/html
    index  index.html index.htm index.php;
    location ~ \.php$ {
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
      fastcgi_pass 127.0.0.1:9000;
    }
  }
}
```

Confirmación del análisis: nginx usa `root /var/www/html`, y por lo tanto el `SCRIPT_FILENAME` que le manda a php-fpm es `/var/www/html/<file>.php`. Pero php-fpm tiene el volumen montado en `/usr/share/nginx/html` — **nunca va a encontrar archivos en `/var/www/html/`** porque ese path no existe en su filesystem.

### 3. Reproducir el bug

```bash
curl https://30008-port-5gnib5nmeym7ow4o.labs.kodekloud.com/
```

```
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>nginx/1.29.8</center>
</body>
</html>
```

403 confirma: nginx llegó al directorio `/var/www/html`, lo encontró vacío (porque nadie copió nada todavía), y no había índice. Igual aunque hubiera un `.php` ahí, php-fpm no podría servirlo por el mismatch de paths.

### 4. Fix: alinear el mountPath del php-fpm-container

#### Dump del Pod YAML

```bash
kubectl get pod nginx-phpfpm -o yaml > pod.yaml
```

#### Editar el archivo

En `pod.yaml`, dentro de `spec.containers`, ubicar el container `php-fpm-container` y cambiar el `mountPath`:

```yaml
    volumeMounts:
    - mountPath: /usr/share/nginx/html   # ← antes
    - mountPath: /var/www/html           # ← después
      name: shared-files
```

> **Por qué fixear ese y no el de nginx:** el `root` del ConfigMap es `/var/www/html`. Podríamos haber cambiado el `root` del nginx Y el mount del nginx a `/usr/share/nginx/html`, pero eso son dos cambios (ConfigMap + Pod) en vez de uno. Cambiar solo el mount del php-fpm es el fix mínimo.

#### Reemplazar el Pod

```bash
kubectl replace --force -f pod.yaml
```

```
pod "nginx-phpfpm" deleted
pod/nginx-phpfpm replaced
```

`--force` hace `delete + create` en un solo paso. Sin `--force`, `kubectl replace` falla porque el Pod tiene campos inmutables que no coinciden con el YAML (resourceVersion, status, etc.).

> **Alternativa más quirúrgica** (sin tocar `replace --force`): se puede hacer `kubectl delete pod nginx-phpfpm` y luego `kubectl apply -f pod.yaml` por separado. Funcionalmente equivalente.

### 5. Verificar el nuevo estado

```bash
kubectl describe pod nginx-phpfpm | grep -A 2 Mounts:
```

Esperado:

```
    Mounts:
      /var/www/html from shared-files (rw)              ← php-fpm-container, ahora correcto
    ...
    Mounts:
      /etc/nginx/nginx.conf from nginx-config-volume (rw,path="nginx.conf")
      /var/www/html from shared-files (rw)              ← nginx-container, sin cambios
```

Los dos containers ahora ven el `emptyDir` al mismo path. El contrato FastCGI funciona.

### 6. Copiar el `index.php` al document root

El directorio sigue vacío — el fix anterior alineó los paths pero no creó contenido. Hay que copiar el archivo:

```bash
kubectl cp /home/thor/index.php nginx-phpfpm:/var/www/html/index.php -c nginx-container
```

> **Por qué `-c nginx-container`:** el Pod tiene 2 containers. Sin `-c`, `kubectl cp` usa el primer container del Pod (el default). Acá el primer container es `php-fpm-container`, pero los dos comparten el mismo `emptyDir`, así que copiar a cualquiera de los dos pone el archivo en el volumen compartido. Aún así, ser explícito es buena práctica.

> **`kubectl cp` en ambas direcciones:**
>
> ```bash
> # Local → Pod
> kubectl cp ./mi-archivo.php nginx-phpfpm:/var/www/html/mi-archivo.php -c nginx-container
>
> # Pod → Local
> kubectl cp nginx-phpfpm:/var/www/html/index.php ./index.php -c nginx-container
> ```

### 7. Validación final

```bash
curl -I https://30008-port-5gnib5nmeym7ow4o.labs.kodekloud.com/
```

```
HTTP/2 200
content-type: text/html; charset=UTF-8
x-powered-by: PHP/7.2.34
date: Wed, 13 May 2026 02:01:11 GMT
```

Tres confirmaciones en el header:

- **`HTTP/2 200`** → la request llegó al endpoint correcto y se sirvió OK
- **`x-powered-by: PHP/7.2.34`** → php-fpm efectivamente ejecutó el archivo (no es estático servido por nginx). El handoff FastCGI funcionó.
- **`content-type: text/html`** → el output del PHP es HTML

## Troubleshooting

| Problema                                                                                | Causa y solución                                                                                                                                            |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pod corre `2/2 Running` pero el sitio devuelve 403                                      | Directorio del `root` existe pero vacío (típico justo después de crear el Pod sin contenido), o mismatch de volumeMounts. Verificar con `describe pod`     |
| Pod corre pero el sitio devuelve `404 File not found` con header `x-powered-by: PHP`    | nginx llegó a php-fpm, pero php-fpm no encontró el `SCRIPT_FILENAME`. Casi siempre es paths de mount no alineados                                          |
| Pod corre pero el sitio devuelve `502 Bad Gateway`                                      | nginx no pudo conectarse al `fastcgi_pass` — php-fpm crasheado, puerto distinto al `127.0.0.1:9000`, o falta de permiso de socket                          |
| `kubectl edit pod ... → error: Pod is invalid: spec.containers[*].volumeMounts: Forbidden` | Los volumeMounts son inmutables en un Pod ya creado. Hay que `delete + create` (o `kubectl replace --force`)                                              |
| `kubectl cp ... → error: executable file not found in $PATH: "tar"`                     | La imagen del container no tiene `tar` (caso común en `scratch`, `distroless`). Workaround: usar `kubectl exec ... -- sh -c "cat > /path/file"` con stdin |
| Cambiaste el ConfigMap pero nginx sigue sirviendo la config vieja                       | nginx no recarga la config automáticamente cuando el ConfigMap cambia. Hay que `kubectl exec ... nginx -s reload` o recrear el Pod                         |

## Recursos

- [Communicate Between Containers in the Same Pod (oficial)](https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/)
- [emptyDir Volumes (oficial)](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir)
- [`kubectl cp` reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#cp)
- [PHP-FPM + nginx config patterns (nginx docs)](https://www.nginx.com/resources/wiki/start/topics/examples/phpfastcgionnginx/)
- [Why immutability matters in Pod spec](https://kubernetes.io/docs/concepts/workloads/pods/#pod-update-and-replacement)
