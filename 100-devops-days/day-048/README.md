# Día 48 - Desplegar un Pod en un Cluster de Kubernetes

## Problema / Desafío

El equipo de Nautilus arranca con Kubernetes para gestionar aplicaciones. La consigna es crear un Pod con estos requisitos exactos:

- **Nombre del pod:** `pod-nginx`
- **Imagen:** `nginx:latest` (el tag debe especificarse explícitamente)
- **Label:** `app: nginx_app`
- **Nombre del contenedor:** `nginx-container`

`kubectl` ya viene configurado en el `jump-host` y apunta al cluster del lab.

## Conceptos clave

### El Pod: la unidad atómica de Kubernetes

Un **Pod** es la unidad más pequeña que Kubernetes sabe orquestar — *no* un contenedor. Un pod encapsula **uno o más contenedores** que comparten:

- **Network namespace** — misma IP del cluster, mismos puertos, se ven entre sí en `localhost`
- **Storage volumes** — pueden montar los mismos volumes para compartir archivos
- **Lifecycle** — nacen y mueren juntos como una unidad

> En el 95% de los casos un pod tiene un solo contenedor. Los multi-container son para patrones específicos (sidecar para logging, init container para preparar storage, ambassador para proxying).

Kubernetes nunca crea contenedores sueltos — todo va dentro de un pod, aunque el pod tenga un solo contenedor.

### Imperativo vs Declarativo

`kubectl` acepta dos estilos para crear recursos:

| Enfoque         | Cómo se ve                                                      | Cuándo usarlo                                            |
| --------------- | --------------------------------------------------------------- | -------------------------------------------------------- |
| **Imperativo**  | `kubectl run pod-nginx --image=nginx:latest ...`                | Comandos rápidos, debugging interactivo, labs de examen  |
| **Declarativo** | YAML manifest + `kubectl apply -f pod.yml`                      | Producción, GitOps, reproducibilidad, code review        |

El imperativo es directo pero limitado: muchas opciones (multi-container, init containers, probes, volumes complejos, affinity rules) **solo** se pueden expresar en YAML. El declarativo es la forma "real" en cualquier setup serio porque:

- El manifest se versiona en git → toda la infraestructura es revisable, auditable y reproducible
- `kubectl apply` es **idempotente**: aplicar el mismo manifest dos veces no rompe nada — converge al estado deseado
- Es la base de GitOps (ArgoCD, Flux): el cluster reconcilia contra los manifests en un repo

### Anatomía de cualquier manifest de Kubernetes

Esta estructura de 4 campos top-level se repite en **todos** los recursos (Pods, Deployments, Services, ConfigMaps, etc.):

```yaml
apiVersion: <grupo/versión>   # qué API estás usando
kind: <Tipo>                  # qué tipo de recurso es
metadata:                     # identidad: nombre, labels, namespace, annotations
  name: ...
  labels: ...
spec:                         # el deseo (qué quieres que exista)
  ...
```

- **`apiVersion`** — Para Pods (recurso core estable): `v1`. Para Deployments: `apps/v1`. Para CronJobs: `batch/v1`. La versión cambia cuando el API evoluciona.
- **`kind`** — El tipo de recurso. Capitalizado: `Pod`, `Deployment`, `Service`.
- **`metadata`** — Quién es este recurso. Aquí van `name`, `namespace`, `labels`, `annotations`.
- **`spec`** — Qué quieres que sea. Esta sección cambia totalmente según el `kind`.

### Labels: el sistema nervioso de Kubernetes

Los **labels** (`metadata.labels`) son pares clave-valor que se asignan al recurso para:

- **Filtrar:** `kubectl get pods -l app=nginx_app`
- **Vincular recursos:** un Service usa un `selector` que matchea labels para saber a qué pods enviar tráfico
- **Organizar:** entornos (`env=prod`), equipos (`team=platform`), versiones (`version=v2`)

Los labels son la forma en que Services, Deployments, ReplicaSets y NetworkPolicies "encuentran" a los pods que deben gestionar. Sin labels, un Service no sabría a qué pods balancear.

> Los contenedores dentro de `spec.containers` **no tienen labels propios**. Los labels viven a nivel del recurso, en `metadata`.

## Pasos

1. Escribir el manifest `pod.yml` con la estructura `apiVersion / kind / metadata / spec`
2. Aplicar con `kubectl apply -f pod.yml`
3. Verificar que el pod esté en estado `Running`
4. Inspeccionar detalles y filtrar por label

## Comandos / Código

### Solución utilizada (declarativa)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-nginx
  labels:
    app: nginx_app
spec:
  containers:
    - name: nginx-container
      image: nginx:latest
```

Aplicar:

```bash
kubectl apply -f pod.yml
```

```
pod/pod-nginx created
```

### Alternativa: imperativa con `kubectl run`

Para esta misma consigna, también se puede crear el pod sin YAML usando flags directos. Esto es útil para labs rápidos o debugging en una sesión interactiva.

> **Nota histórica importante:** en versiones antiguas de kubectl (pre-v1.18), `kubectl run` creaba un Deployment por default y había que pasarle `--restart=Never` para forzar un Pod puro. Desde **kubectl v1.18+** el comportamiento cambió: `kubectl run` crea **solo Pods**, sin Deployment ni `--restart=Never` necesario. Mucha documentación vieja todavía menciona ese flag — ya no aplica.

El reto aparente: `kubectl run` no expone un flag `--container-name` para renombrar el container dentro del pod (por default le pone el mismo nombre que el pod). La solución es `--overrides`, que inyecta un fragmento de JSON sobre el manifest generado:

```bash
kubectl run pod-nginx \
  --image=nginx:latest \
  --labels="app=nginx_app" \
  --overrides='{
    "apiVersion": "v1",
    "spec": {
      "containers": [
        {
          "image": "nginx:latest",
          "name": "nginx-container"
        }
      ]
    }
  }'
```

```
pod/pod-nginx created
```

#### Por qué hay que repetir `image` dentro del `--overrides`

El JSON de `--overrides` **reemplaza completamente** la sección que toca (no hace merge profundo del array `containers[]`). Si solo pones `{"name": "nginx-container"}`, el container resultante quedaría sin imagen y el pod no arrancaría. Por eso hay que repetir `image: nginx:latest` dentro del override aunque también esté en `--image`.

> Esto ilustra exactamente por qué el manifest YAML es preferible: para una sola personalización (renombrar el container) se necesita JSON inline, repetir campos, escapar comillas, y aún así perder validación de schema en el editor. El `pod.yml` declarativo es más corto, más legible y diff-eable en code review.

### Verificación

```bash
# Ver todos los pods de todos los namespaces (-A = --all-namespaces)
kubectl get pods -A
```

```
NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE
default       pod-nginx                                 1/1     Running     0          6s
```

`READY 1/1` significa que de **1 contenedor esperado** en el pod, **1 está listo** (passed readiness). El segundo número refleja la `spec.containers` declarada; el primero es cuántos están live. Si vieras `0/1`, el contenedor existe pero todavía no pasó el readiness probe (o no arrancó).

```bash
# Ver logs del nginx (debería mostrar el banner de arranque del entrypoint oficial)
kubectl logs pod-nginx
```

```
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
```

> Cuando un pod tiene un solo contenedor, `kubectl logs pod-nginx` basta. Para pods multi-container hay que pasar `-c <container>` (`kubectl logs pod-nginx -c nginx-container`), si no kubectl pide que elijas explícitamente.

```bash
# Ver detalles completos: events, IP, container ID, image digest, etc.
kubectl describe pod pod-nginx
```

```
Name:             pod-nginx
Namespace:        default
Priority:         0
Service Account:  default
Node:             jump-host/10.244.97.141
Start Time:       Fri, 08 May 2026 01:59:48 +0000
Labels:           app=nginx_app
Annotations:      <none>
Status:           Running
IP:               10.22.0.9
Containers:
  nginx-container:
    Container ID:   containerd://f9d882095e9df7d33dbd626289145c5c52f06ee4e65287ea57b5ec97ec28b239
    Image:          nginx:latest
    Image ID:       docker.io/library/nginx@sha256:6e23479198b998e5e25921dff8455837c7636a67111a04a635cf1bb363d199dc
    State:          Running
      Started:      Fri, 08 May 2026 01:59:52 +0000
    Ready:          True
    Restart Count:  0
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-nwpv8 (ro)
QoS Class:                   BestEffort
Events:
  Type    Reason     Age    From               Message
  ----    ------     ----   ----               -------
  Normal  Scheduled  3m19s  default-scheduler  Successfully assigned default/pod-nginx to jump-host
  Normal  Pulling    3m19s  kubelet            Pulling image "nginx:latest"
  Normal  Pulled     3m15s  kubelet            Successfully pulled image "nginx:latest" in 3.304s
  Normal  Created    3m15s  kubelet            Created container: nginx-container
  Normal  Started    3m15s  kubelet            Started container nginx-container
```

Cosas dignas de subrayar de este output:

- **`Image:` vs `Image ID:`** — `Image` es lo que pediste (`nginx:latest`, un tag mutable). `Image ID` es el **digest SHA256 inmutable** que el kubelet realmente bajó. Si el tag `latest` cambia mañana, este pod sigue corriendo *este* digest; solo al recrear el pod resolvería el `latest` nuevo.
- **`QoS Class: BestEffort`** — porque el pod no tiene `requests` ni `limits` definidos. Es el QoS más bajo: si el nodo se queda sin memoria, este es el primero en ser evictado. En producción real querés al menos `Burstable` (con requests) o `Guaranteed` (requests = limits).
- **`Events`** es la sección más útil para debugging — la línea de tiempo de qué le pasó al pod desde su creación. Si algo va mal (`ImagePullBackOff`, `CrashLoopBackOff`), aparece acá con el motivo.

```bash
# Filtrar por label — confirma que el label se aplicó correctamente
kubectl get pods -l app=nginx_app
```

### Validar el manifest sin aplicar (dry-run)

Antes de aplicar al cluster real, conviene validar la sintaxis y la estructura:

```bash
kubectl apply --dry-run=client -f pod.yml
```

`--dry-run=client` valida localmente sin contactar el API server. `--dry-run=server` lo valida contra el cluster (incluye admission controllers) pero sin persistir.

## Comparación: Imperativo vs Declarativo en este caso

| Aspecto                              | `kubectl run` (imperativo)                          | YAML + `kubectl apply` (declarativo)                  |
| ------------------------------------ | --------------------------------------------------- | ----------------------------------------------------- |
| Velocidad para crear                 | Muy rápido (una línea)                              | Hay que escribir el manifest                          |
| Versionable en git                   | No (es una invocación efímera)                      | Sí (el `.yml` se commitea)                            |
| Idempotente                          | No (`kubectl run` falla si ya existe)               | Sí (`apply` actualiza si existe, crea si no)          |
| Permite multi-container, probes, etc.| Limitado o imposible                                | Sí, todo es expresable                                |
| Ideal para                           | Labs, debugging, exámenes (CKAD, CKA)               | Producción, GitOps, code review                       |

## Troubleshooting

| Problema                                      | Causa y solución                                                                                                       |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `pod/pod-nginx unchanged` al aplicar          | No es error — `apply` es idempotente: el cluster ya tiene ese estado y no hace nada                                    |
| `Error from server (NotFound): pods "pod-nifnx" not found` | Typo en el nombre del pod (típico al transcribir). kubectl no hace fuzzy match: el nombre debe coincidir exacto. Ejecutar `kubectl get pods` para ver los nombres reales |
| Pod en `ImagePullBackOff`                     | El nodo no pudo descargar `nginx:latest`. Revisar conectividad del nodo al registry o si el tag existe                 |
| Pod en `Pending` por mucho tiempo             | `kubectl describe pod pod-nginx` → revisar events. Suele ser falta de recursos del nodo o un nodeSelector imposible    |
| Error `error validating "pod.yml"`            | Sintaxis YAML incorrecta o campo mal indentado. Validar con `kubectl apply --dry-run=client -f pod.yml`                |
| Cambié el `image:` en el YAML pero no actualiza | Un Pod *no* hace rolling update — para eso se usa Deployment. Borrar el pod (`kubectl delete pod pod-nginx`) y reaplicar |
| `kubectl run` falla con "already exists"      | A diferencia de `apply`, `run` es one-shot. Borrar primero con `kubectl delete pod pod-nginx` o usar `apply`            |

## Recursos

- [Documentación oficial de Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Imperative vs Declarative management](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/)
- [Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
