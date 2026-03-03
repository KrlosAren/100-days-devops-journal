# Dia 14 - Troubleshooting Nginx + PHP-FPM en Kubernetes

## Problema / Desafio

El setup de Nginx y PHP-FPM en el cluster Kubernetes dejo de funcionar. Se necesita:

1. Investigar y corregir el problema en el Pod `nginx-phpfpm` y el ConfigMap `nginx-config`
2. Copiar `/home/thor/index.php` desde el jump host al document root de nginx dentro del contenedor
3. Verificar que el sitio web funciona

## Conceptos clave

### Arquitectura Nginx + PHP-FPM

Nginx no puede ejecutar PHP directamente. Necesita un interprete externo: **PHP-FPM** (FastCGI Process Manager). En Kubernetes, ambos corren como contenedores separados dentro del mismo Pod:

```
Pod nginx-phpfpm
├── nginx-container        → Recibe peticiones HTTP, sirve archivos estaticos
│                             Si es .php → envia a PHP-FPM via FastCGI
├── php-fpm-container      → Interpreta archivos .php y devuelve el resultado
│
└── shared-files (emptyDir) → Volumen compartido donde viven los archivos
```

### Flujo de una peticion PHP

```
Cliente
  │
  ▼
Nginx (puerto 8099)
  │
  ├── Archivo estatico (.html, .css, .js)?
  │   └── Lo sirve directamente desde el document root
  │
  └── Archivo .php?
      └── location ~ \.php$ matchea
          └── fastcgi_pass 127.0.0.1:9000 → envia a PHP-FPM
              │
              ▼
          PHP-FPM (puerto 9000)
              │
              ├── Lee SCRIPT_FILENAME → $document_root/$fastcgi_script_name
              │   Ejemplo: /usr/share/nginx/html/index.php
              │
              ├── Ejecuta el PHP
              └── Devuelve el resultado HTML a Nginx → al cliente
```

**Punto critico:** PHP-FPM busca el archivo en la ruta que le indica `SCRIPT_FILENAME`. Si esa ruta no coincide con donde PHP-FPM tiene montado el volumen, devuelve `File not found`.

### FastCGI

FastCGI es un protocolo que permite a un servidor web (Nginx) comunicarse con un proceso externo (PHP-FPM) para ejecutar codigo. A diferencia de CGI tradicional, FastCGI mantiene procesos persistentes en vez de crear uno nuevo por cada peticion.

| Directiva | Funcion |
|-----------|---------|
| `fastcgi_pass 127.0.0.1:9000` | Direccion donde corre PHP-FPM. Como estan en el mismo Pod, comparten `localhost` |
| `fastcgi_param SCRIPT_FILENAME` | Ruta completa al archivo PHP que PHP-FPM debe ejecutar |
| `fastcgi_param REQUEST_METHOD` | GET, POST, etc. |
| `include fastcgi_params` | Incluye parametros estandar de FastCGI |

### Por que 127.0.0.1 funciona entre contenedores

En Kubernetes, los contenedores dentro del mismo Pod comparten la **misma red** (mismo network namespace). Por eso `fastcgi_pass 127.0.0.1:9000` funciona — nginx y PHP-FPM se ven como si estuvieran en la misma maquina.

## Diagnostico

### 1. Verificar estado del Pod

```bash
kubectl get pods
```

```
NAME           READY   STATUS    RESTARTS   AGE
nginx-phpfpm   2/2     Running   0          6m34s
```

Ambos contenedores estan `Running` — el problema no es un crash.

### 2. Probar el acceso web

```bash
curl http://nginx-phpfpm-url/
```

```html
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>nginx/1.29.5</center>
</body>
</html>
```

**403 Forbidden** — Nginx esta corriendo pero no puede servir contenido.

### 3. Revisar el describe del Pod

```bash
kubectl describe pod nginx-phpfpm
```

Los volumeMounts relevantes:

```
Containers:
  php-fpm-container:
    Mounts:
      /usr/share/nginx/html from shared-files (rw)    ← PHP-FPM monta aqui

  nginx-container:
    Mounts:
      /var/www/html from shared-files (rw)             ← Nginx monta aqui
      /etc/nginx/nginx.conf from nginx-config-volume
```

### 4. Revisar el ConfigMap

```bash
kubectl get configmap nginx-config -o yaml
```

```nginx
events {
}
http {
  server {
    listen 8099 default_server;
    listen [::]:8099 default_server;

    root /var/www/html;                          ← document root
    index  index.html index.htm index.php;
    server_name _;

    location / {
      try_files $uri $uri/ =404;
    }
    location ~ \.php$ {
      include fastcgi_params;
      fastcgi_param REQUEST_METHOD $request_method;
      fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
      fastcgi_pass 127.0.0.1:9000;
    }
  }
}
```

### 5. Identificar el problema

El volumen `shared-files` (emptyDir) es **uno solo**, pero cada contenedor lo monta en una ruta diferente:

```
Volumen shared-files (emptyDir)
│
├── nginx-container lo ve en:      /var/www/html
└── php-fpm-container lo ve en:    /usr/share/nginx/html
```

El ConfigMap de nginx tiene `root /usr/share/nginx/html` y `SCRIPT_FILENAME $document_root$fastcgi_script_name`. Esto significa:

1. Nginx busca archivos en `/usr/share/nginx/html` ✅ (coincide con su volumeMount)
2. `$document_root` resuelve a `/usr/share/nginx/html`
3. Nginx le dice a PHP-FPM: "ejecuta `/usr/share/nginx/html/index.php`"
4. PHP-FPM intenta leer `/usr/share/nginx/html/index.php` ❌ (su volumen esta en `/var/www/html`)

**Dos problemas:**
1. El volumen esta **vacio** (emptyDir sin archivos) → 403 Forbidden
2. `SCRIPT_FILENAME` usa `$document_root` que resuelve a `/usr/share/nginx/html`, pero PHP-FPM tiene el volumen montado en `/var/www/html` → PHP-FPM no encuentra los archivos

```
Nginx                                    PHP-FPM
  │                                        │
  ├── root: /usr/share/nginx/html          ├── volume en: /var/www/html
  │                                        │
  └── SCRIPT_FILENAME:                     └── Intenta leer:
      /usr/share/nginx/html/index.php          /usr/share/nginx/html/index.php
                                               ❌ Esa ruta no existe en php-fpm
```

## Solucion

### 1. Corregir el ConfigMap

El problema esta en `SCRIPT_FILENAME`: usa `$document_root` que resuelve a la ruta de nginx, no a la de PHP-FPM. La solucion es hardcodear la ruta del volumen de PHP-FPM:

```bash
kubectl edit configmap nginx-config
```

Cambiar el bloque `location ~ \.php$`:

```nginx
# Antes — $document_root resuelve a /usr/share/nginx/html (ruta de nginx, no de php-fpm)
location ~ \.php$ {
    include fastcgi_params;
    fastcgi_param REQUEST_METHOD $request_method;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass 127.0.0.1:9000;
}

# Despues — ruta explicita al volumen de PHP-FPM
location ~ \.php$ {
    include fastcgi_params;
    fastcgi_param REQUEST_METHOD $request_method;
    fastcgi_param SCRIPT_FILENAME /var/www/html$fastcgi_script_name;
    fastcgi_pass 127.0.0.1:9000;
}
```

Ahora PHP-FPM recibe `/var/www/html/index.php`, que es donde tiene montado el volumen.

**Por que esta solucion y no cambiar `root`?**

| Solucion | Que cambia | Efecto |
|----------|-----------|--------|
| Cambiar `SCRIPT_FILENAME` a `/var/www/html` | Solo la ruta que recibe PHP-FPM | Nginx sigue sirviendo desde su ruta, PHP-FPM usa la suya |
| Cambiar `root` a `/var/www/html` | El document root de nginx | Nginx buscaria archivos en `/var/www/html` que coincide con su mount, pero cambia todo el comportamiento del server |

Ambas son validas. Cambiar `SCRIPT_FILENAME` es mas quirurgico — solo afecta a PHP-FPM sin alterar como nginx sirve archivos estaticos.

### Hay que reiniciar el Pod?

**Si.** Nginx carga el archivo `nginx.conf` al iniciar y lo mantiene en memoria. Editar el ConfigMap actualiza el objeto en Kubernetes, pero **no recarga automaticamente** el archivo dentro del contenedor.

```
kubectl edit configmap → Actualiza el ConfigMap en etcd ✅
                       → Nginx dentro del contenedor sigue usando el .conf viejo ❌
```

Hay que recrear el Pod para que nginx cargue la nueva configuracion.

#### Como recrear un Pod directo (sin Deployment)

**Opcion 1: `replace --force`** (recomendada — un solo paso)

```bash
# Exportar el YAML actual
kubectl get pod nginx-phpfpm -o yaml > /tmp/nginx-phpfpm.yaml

# Eliminar y recrear en un solo paso
kubectl replace --force -f /tmp/nginx-phpfpm.yaml
```

`--force` hace `delete` + `create` automaticamente. El Pod tiene downtime breve durante la recreacion.

**Opcion 2: `delete` + `apply`** (dos pasos manuales)

```bash
# Exportar primero
kubectl get pod nginx-phpfpm -o yaml > /tmp/nginx-phpfpm.yaml

# Eliminar
kubectl delete pod nginx-phpfpm

# Recrear
kubectl apply -f /tmp/nginx-phpfpm.yaml
```

Mismo resultado que `replace --force` pero en pasos separados. Util si necesitas editar el YAML antes de recrear.

**Opcion 3: `nginx -s reload`** (sin recrear el Pod)

```bash
kubectl exec nginx-phpfpm -c nginx-container -- nginx -s reload
```

Esto le envia una senal a nginx para que re-lea `nginx.conf` sin reiniciar el proceso. **Pero** solo funciona si el archivo dentro del contenedor ya se actualizo. Con ConfigMaps montados usando `subPath` (como en este caso), el archivo **nunca se propaga automaticamente**, asi que esta opcion **no aplica aqui**.

| Tipo de mount del ConfigMap | Se propaga automaticamente? | `nginx -s reload` funciona? |
|-----------------------------|---------------------------|---------------------------|
| Volumen directo | Si (1-2 min) | Si, despues de la propagacion |
| `subPath` | **No** | **No** — hay que recrear el Pod |
| Variable de entorno | **No** | No aplica |

#### Si fuera un Deployment (produccion)

```bash
# Rolling restart — crea Pods nuevos y elimina los viejos sin downtime
kubectl rollout restart deployment/nginx-phpfpm
```

Con un Deployment no necesitas exportar YAML ni tener downtime. Por eso en produccion **siempre** se usa Deployment en vez de Pods directos.

#### Comparacion de metodos para recrear

| Metodo | Downtime | Pasos | Cuando usarlo |
|--------|----------|-------|---------------|
| `replace --force` | Si (breve) | 1 | Pod directo, cambio rapido |
| `delete` + `apply` | Si | 2 | Pod directo, necesitas editar YAML antes |
| `nginx -s reload` | No | 1 | ConfigMap con volumen directo (sin subPath) |
| `rollout restart` | No | 1 | Solo Deployments (produccion) |

### 2. Recrear el Pod

```bash
kubectl delete pod nginx-phpfpm
```

El Pod se recrea automaticamente (o aplicar el YAML de nuevo).

### 3. Copiar el archivo index.php al contenedor

**Importante:** al recrear el Pod, el volumen `emptyDir` se **destruye y se crea uno nuevo vacio**. Todos los archivos que estaban en el volumen se pierden. Por eso hay que copiar `index.php` **despues** de recrear el Pod.

```bash
kubectl cp /home/thor/index.php nginx-phpfpm:/usr/share/nginx/html/index.php -c nginx-container
```

```
Ciclo de vida del emptyDir:
Pod original    → emptyDir con archivos → kubectl delete pod → emptyDir DESTRUIDO
Pod recreado    → emptyDir NUEVO (vacio) → kubectl cp → archivos copiados
```

Como ambos contenedores montan el mismo volumen `shared-files`, el archivo queda visible para ambos aunque los mount paths sean diferentes:

```
Volumen shared-files (emptyDir)
└── index.php

nginx-container ve:      /usr/share/nginx/html/index.php ✅
php-fpm-container ve:    /var/www/html/index.php ✅
```

Es el **mismo archivo** en el mismo volumen — cada contenedor lo accede desde su propio mount path.

### 4. Verificar

```bash
# Verificar que el archivo existe en ambos contenedores
kubectl exec nginx-phpfpm -c nginx-container -- ls /usr/share/nginx/html/
kubectl exec nginx-phpfpm -c php-fpm-container -- ls /var/www/html/

# Probar el acceso
curl http://nginx-phpfpm-url/
```

El sitio deberia responder con el contenido generado por `index.php`.

## Resumen del flujo

```
1. kubectl get pods → 2/2 Running (no hay crash)
2. curl → 403 Forbidden (Nginx corre pero sin contenido)
3. kubectl describe pod → volumeMounts diferentes entre contenedores
4. kubectl get configmap → SCRIPT_FILENAME usa $document_root (ruta de nginx, no de php-fpm)
5. kubectl edit configmap → cambiar SCRIPT_FILENAME a /var/www/html$fastcgi_script_name
6. kubectl delete pod → recrear el Pod para cargar nueva config
7. kubectl cp index.php → copiar archivo al volumen (emptyDir se borro al recrear)
8. curl → sitio funciona ✅
```

## Leccion DevOps: Pods multi-container

En Pods con multiples contenedores:

- **Comparten red** — `localhost` / `127.0.0.1` funciona entre ellos
- **Pueden compartir volumenes** — pero cada contenedor puede montarlo en una **ruta diferente**
- **No comparten filesystem** fuera de los volumenes montados explicitamente
- **emptyDir se destruye** al eliminar/recrear el Pod — hay que copiar archivos de nuevo

Siempre verificar en Pods multi-container:

1. Los mount paths de cada contenedor (`kubectl describe pod`)
2. Que las rutas en la configuracion coincidan con el mount path del contenedor que las usa
3. El tipo de volumen — `emptyDir` es efimero, `PVC` persiste

## Cuando se propagan los cambios de un ConfigMap

| Tipo de mount | Propagacion | Se necesita reiniciar? |
|---------------|------------|----------------------|
| Como volumen (`volumes.configMap`) | Automatica (1-2 min) | No, pero la app debe re-leer el archivo. Nginx necesita `reload` |
| Como `subPath` | **Nunca se propaga** | Si, hay que recrear el Pod |
| Como variable de entorno (`envFrom`) | **Nunca se propaga** | Si, hay que recrear el Pod |

En este ejercicio, `nginx.conf` esta montado con `path: "nginx.conf"` (subPath), asi que los cambios **no se propagan automaticamente** y hay que recrear el Pod.

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| 403 Forbidden | El document root esta vacio o nginx no tiene permisos. Verificar que hay archivos con `kubectl exec` |
| `File not found` de PHP-FPM | `SCRIPT_FILENAME` apunta a una ruta que PHP-FPM no puede leer. Verificar que `root` coincide con el volumeMount de PHP-FPM |
| Cambio en ConfigMap no se refleja | Si usa `subPath`, hay que recrear el Pod. Si es volumen directo, esperar 1-2 min y hacer `nginx -s reload` |
| `kubectl cp` falla con `tar not found` | La imagen del contenedor no tiene `tar`. Usar `kubectl exec` con `cat` o `tee` como alternativa |
| PHP-FPM no responde | Verificar que corre en puerto 9000: `kubectl exec -c php-fpm-container -- netstat -tlnp` |
| Sitio muestra HTML crudo en vez de ejecutar PHP | La directiva `location ~ \.php$` no esta configurada o el `fastcgi_pass` apunta a la direccion incorrecta |

## Recursos

- [PHP-FPM - Documentacion oficial](https://www.php.net/manual/en/install.fpm.php)
- [Nginx + PHP-FPM Configuration](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)
- [ConfigMaps - Kubernetes Docs](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [kubectl cp](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_cp/)
- [Volumes - subPath](https://kubernetes.io/docs/concepts/storage/volumes/#using-subpath)
