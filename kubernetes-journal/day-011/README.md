# Dia 11 - Troubleshooting de Pod: ImagePullBackOff

## Problema / Desafio

Un miembro junior del equipo DevOps no pudo desplegar un stack en Kubernetes. El Pod `webserver` no inicia y presenta errores. Se necesita identificar y corregir el problema para que el Pod este en estado `Running` y la aplicacion sea accesible.

El Pod tiene dos contenedores:
- `httpd-container` con imagen `httpd:latest`
- `sidecar-container` con imagen `ubuntu:latest`

## Conceptos clave

### Sidecar Pattern

Un Pod puede tener multiples contenedores que comparten red y volumenes. El **sidecar** es un contenedor auxiliar que complementa al contenedor principal:

```
Pod (webserver)
├── httpd-container (principal)    → Sirve la aplicacion web
│   └── escribe logs en /var/log/httpd/
│
├── sidecar-container (auxiliar)   → Lee y procesa los logs
│   └── lee logs desde /var/log/httpd/
│
└── Volume compartido (shared-logs)
    └── emptyDir montado en /var/log/httpd en ambos contenedores
```

Casos de uso tipicos del sidecar:
- Recoleccion de logs (como en este ejercicio)
- Proxy/service mesh (Envoy, Istio)
- Sincronizacion de archivos
- Monitoreo

### ImagePullBackOff

`ImagePullBackOff` es un estado que indica que Kubernetes no pudo descargar la imagen del contenedor. Despues de varios intentos fallidos (`ErrImagePull`), Kubernetes aplica un backoff exponencial entre reintentos.

```
ErrImagePull → reintento → ErrImagePull → reintento → ImagePullBackOff (espera cada vez mas)
```

Causas comunes:

| Causa | Ejemplo | Como detectar |
|-------|---------|---------------|
| Typo en el nombre/tag de la imagen | `httpd:latests` en vez de `httpd:latest` | `kubectl describe pod` → Events |
| Imagen no existe en el registry | `mi-app:v99` | Verificar en Docker Hub o registry privado |
| Registry privado sin credenciales | `mi-registry.com/app:v1` | Falta `imagePullSecrets` en el Pod |
| Sin acceso a internet | Cualquier imagen publica | Verificar conectividad del nodo |

### READY 1/2

En `kubectl get pods`, la columna READY muestra `contenedores_listos/total_contenedores`:

```
NAME        READY   STATUS             RESTARTS   AGE
webserver   1/2     ImagePullBackOff   0          52s
```

- `1/2` = 1 de 2 contenedores esta listo
- El `sidecar-container` (ubuntu) esta `Running`
- El `httpd-container` fallo porque no pudo descargar la imagen

## Pasos

1. Verificar el estado del Pod con `kubectl get pods`
2. Investigar la causa con `kubectl describe pod`
3. Identificar el error en los Events
4. Corregir el problema con `kubectl edit pod`
5. Verificar que el Pod esta en estado `Running` con `2/2` contenedores

## Comandos / Codigo

### 1. Verificar el estado del Pod

```bash
kubectl get pods
```

```
NAME        READY   STATUS             RESTARTS   AGE
webserver   1/2     ImagePullBackOff   0          52s
```

El Pod tiene 2 contenedores pero solo 1 esta listo. El status `ImagePullBackOff` indica problemas al descargar una imagen.

### 2. Describir el Pod para investigar

```bash
kubectl describe pod webserver
```

En la seccion de **Containers** se ve el problema:

```
Containers:
  httpd-container:
    Image:          httpd:latests    ← TYPO: "latests" en vez de "latest"
    State:          Waiting
      Reason:       ErrImagePull
```

Y en la seccion de **Events** se confirma:

```
Warning  Failed   18s  kubelet  Failed to pull image "httpd:latests":
  rpc error: code = NotFound desc = failed to pull and unpack image
  "docker.io/library/httpd:latests": failed to resolve reference
  "docker.io/library/httpd:latests": docker.io/library/httpd:latests: not found
```

El error es claro: la imagen `httpd:latests` no existe. El tag correcto es `httpd:latest` (sin la `s` extra).

Mientras tanto, el `sidecar-container` esta corriendo sin problemas:

```
sidecar-container:
    Image:         ubuntu:latest
    State:          Running
```

### 3. Corregir el typo con kubectl edit

```bash
kubectl edit pod webserver
```

Esto abre el manifiesto del Pod en el editor (vi por defecto). Buscar la linea con la imagen incorrecta y corregirla:

```yaml
# Antes
image: httpd:latests

# Despues
image: httpd:latest
```

Guardar y salir (`:wq` en vi). Kubernetes aplica el cambio automaticamente.

### Otras formas de editar un manifiesto en Kubernetes

#### `kubectl set image` — atajo para cambiar imagen

```bash
kubectl set image pod/webserver httpd-container=httpd:latest
```

Rapido, sin abrir editor. `kubectl set` tiene atajos para otros cambios comunes:

```bash
kubectl set image pod/webserver httpd-container=httpd:2.4    # Cambiar imagen
kubectl set env pod/webserver TIME_FREQ=10                   # Cambiar/agregar variable
kubectl set resources pod/webserver -c httpd-container --limits=memory=256Mi  # Limites
kubectl set serviceaccount pod/webserver my-sa               # Service account
```

#### `kubectl patch` — modificar campos especificos sin editor

```bash
# JSON merge patch (default)
kubectl patch pod webserver -p '{"spec":{"containers":[{"name":"httpd-container","image":"httpd:latest"}]}}'

# Strategic merge patch (inteligente con listas, merge por nombre del contenedor)
kubectl patch pod webserver --type=strategic -p '{"spec":{"containers":[{"name":"httpd-container","image":"httpd:latest"}]}}'

# JSON patch (operaciones precisas por path)
kubectl patch pod webserver --type=json -p '[{"op":"replace","path":"/spec/containers/0/image","value":"httpd:latest"}]'
```

| Tipo de patch | Comportamiento | Uso |
|---------------|---------------|-----|
| `merge` (default) | Reemplaza campos que coinciden | Cambios simples |
| `strategic` | Inteligente con listas (merge por nombre) | Cuando hay multiples contenedores |
| `json` | Operaciones precisas por path (replace, add, remove) | Control exacto sobre que campo cambiar |

`patch` es ideal para **scripts y automatizacion** donde no se quiere abrir un editor interactivo.

#### `kubectl replace --force` — para campos inmutables

Algunos campos de un Pod no se pueden cambiar en caliente (ports, volumeMounts, nombre del contenedor). En esos casos hay que eliminar y recrear:

```bash
# Exportar el YAML actual
kubectl get pod webserver -o yaml > webserver.yaml

# Editar el archivo localmente
vi webserver.yaml

# Eliminar y recrear en un solo paso
kubectl replace --force -f webserver.yaml
```

`--force` hace `delete` + `create` automaticamente. El Pod tiene downtime durante la recreacion.

#### `kubectl delete` + `kubectl apply` — reescribir completo

```bash
kubectl delete pod webserver
kubectl apply -f webserver-corregido.yaml
```

Mismo efecto que `replace --force` pero en dos pasos manuales.

#### Comparacion de metodos

| Metodo | Requiere eliminar Pod | Interactivo | Mejor para |
|--------|----------------------|-------------|------------|
| `kubectl edit` | No* | Si (editor) | Cambios rapidos e interactivos |
| `kubectl set` | No* | No | Atajos para imagen, env, resources |
| `kubectl patch` | No* | No | Scripts y automatizacion |
| `kubectl replace --force` | Si (automatico) | No | Campos inmutables |
| `kubectl delete` + `apply` | Si (manual) | No | Reescribir el manifiesto completo |

*Solo para campos mutables (imagen, env, labels). Campos inmutables requieren recrear el Pod.

#### En produccion se usan Deployments, no Pods directos

Con un Deployment, cualquier cambio se aplica automaticamente creando nuevos Pods sin downtime:

```bash
# Todos estos funcionan sin eliminar nada — el Deployment gestiona el rollout
kubectl set image deployment/webserver httpd-container=httpd:2.4
kubectl edit deployment webserver
kubectl patch deployment webserver -p '{"spec":{"template":{"spec":{"containers":[{"name":"httpd-container","image":"httpd:2.4"}]}}}}'
kubectl apply -f deployment.yaml
```

El Deployment crea nuevos Pods con la configuracion actualizada y elimina los viejos progresivamente (rolling update). Por eso en produccion rara vez se editan Pods directamente.

### 4. Verificar la correccion

```bash
kubectl get pods
```

```
NAME        READY   STATUS    RESTARTS   AGE
webserver   2/2     Running   0          4m36s
```

Ahora `2/2` contenedores estan listos y el status es `Running`.

### 5. Verificar la aplicacion

```bash
curl http://webserver-ip:puerto
```

```html
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<title>It works! Apache httpd</title>
</head>
<body>
<p>It works!</p>
</body>
</html>
```

## Metodologia de troubleshooting de Pods

Cuando un Pod no inicia, seguir este flujo:

```
kubectl get pods          → Ver el STATUS del Pod
       │
       ├── ImagePullBackOff / ErrImagePull
       │   └── kubectl describe pod → Verificar imagen (typo, tag, registry)
       │
       ├── CrashLoopBackOff
       │   └── kubectl logs <pod> → Ver error de la aplicacion
       │
       ├── Pending
       │   └── kubectl describe pod → Verificar recursos (CPU/memoria) o nodeSelector
       │
       ├── ContainerCreating (mucho tiempo)
       │   └── kubectl describe pod → Verificar volumenes, configmaps, secrets
       │
       └── Running pero no responde
           └── kubectl exec -it <pod> -- sh → Debug dentro del contenedor
```

### Comandos utiles para troubleshooting

```bash
# Estado general
kubectl get pods
kubectl get pods -o wide                    # Incluye nodo e IP

# Investigar un Pod
kubectl describe pod <pod-name>             # Detalle completo + Events
kubectl logs <pod-name>                     # Logs del contenedor (si hay uno solo)
kubectl logs <pod-name> -c <container>      # Logs de un contenedor especifico
kubectl logs <pod-name> --previous          # Logs del contenedor anterior (si reinicio)

# Debug interactivo
kubectl exec -it <pod-name> -- /bin/sh      # Shell dentro del contenedor
kubectl exec -it <pod-name> -c <container> -- /bin/sh  # Shell en contenedor especifico

# Ver eventos del cluster
kubectl get events --sort-by='.lastTimestamp'

# Ver el YAML actual del Pod
kubectl get pod <pod-name> -o yaml
```

## Manifiesto corregido del Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: webserver
  labels:
    app: web-app
spec:
  volumes:
    - name: shared-logs
      emptyDir: {}
  containers:
    - name: httpd-container
      image: httpd:latest
      volumeMounts:
        - name: shared-logs
          mountPath: /var/log/httpd
    - name: sidecar-container
      image: ubuntu:latest
      command:
        - sh
        - -c
        - while true; do cat /var/log/httpd/access.log /var/log/httpd/error.log; sleep 30; done
      volumeMounts:
        - name: shared-logs
          mountPath: /var/log/httpd
```

**Puntos clave del manifiesto:**

- Ambos contenedores montan el mismo volumen `shared-logs` en `/var/log/httpd`
- `httpd-container` escribe los logs de Apache en ese directorio
- `sidecar-container` lee esos logs cada 30 segundos con `cat`
- El volumen `emptyDir` permite compartir archivos entre contenedores del mismo Pod

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `ImagePullBackOff` | Verificar nombre y tag de la imagen con `kubectl describe pod`. Corregir con `kubectl edit pod` o `kubectl set image` |
| `ErrImagePull` con registry privado | Agregar `imagePullSecrets` al Pod con las credenciales del registry |
| `kubectl edit` no permite cambiar ciertos campos | Algunos campos son inmutables. Exportar el YAML, corregir, borrar el Pod y recrear |
| Pod en `Running` pero un contenedor reinicia | Revisar logs del contenedor especifico: `kubectl logs <pod> -c <container>` |
| Sidecar no ve los logs de httpd | Verificar que ambos contenedores montan el mismo volumen en el mismo path |

## Recursos

- [Debug Pods - Kubernetes Docs](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Container Images - Kubernetes Docs](https://kubernetes.io/docs/concepts/containers/images/)
- [Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
- [httpd - Docker Hub](https://hub.docker.com/_/httpd)
