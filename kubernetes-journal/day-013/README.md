# Dia 13 - Crear un ReplicationController en Kubernetes

## Problema / Desafio

Crear un ReplicationController para desplegar multiples Pods de una aplicacion que requiere alta disponibilidad:

- Nombre: `httpd-replicationcontroller`
- Imagen: `httpd:latest`
- Labels: `app: httpd_app`, `type: front-end`
- Nombre del contenedor: `httpd-container`
- Replicas: **3**

Todos los Pods deben estar en estado `Running` despues del despliegue.

## Conceptos clave

### Que es un ReplicationController

Un ReplicationController (RC) garantiza que un numero especifico de replicas de un Pod esten corriendo en todo momento. Si un Pod muere, el RC crea uno nuevo automaticamente.

```
ReplicationController (replicas: 3)
├── Pod 1 (httpd:latest) → Running ✅
├── Pod 2 (httpd:latest) → Running ✅
└── Pod 3 (httpd:latest) → Running ✅

Si Pod 2 muere:
├── Pod 1 (httpd:latest) → Running ✅
├── Pod 3 (httpd:latest) → Running ✅
└── Pod 4 (httpd:latest) → Creado automaticamente ✅
```

### ReplicationController vs ReplicaSet vs Deployment

El ReplicationController es el recurso **mas antiguo** de Kubernetes para manejar replicas. Fue reemplazado progresivamente:

```
ReplicationController (v1, legacy)
    ↓ reemplazado por
ReplicaSet (apps/v1, mas flexible)
    ↓ gestionado por
Deployment (apps/v1, recomendado)
```

| | ReplicationController | ReplicaSet | Deployment |
|---|----------------------|------------|------------|
| **apiVersion** | `v1` | `apps/v1` | `apps/v1` |
| **Selector** | Solo igualdad (`app = httpd`) | Igualdad + conjuntos (`app in (httpd, nginx)`) | Igual que ReplicaSet |
| **Rolling Update** | No | No (manual) | Si (automatico) |
| **Rollback** | No | No | Si (`kubectl rollout undo`) |
| **Estado** | Legacy (no deprecated, pero no recomendado) | Rara vez se usa directamente | **Recomendado para produccion** |

#### Selector de igualdad vs selector de conjuntos

La diferencia principal entre RC y ReplicaSet es el tipo de selector:

```yaml
# ReplicationController — solo igualdad (equality-based)
selector:
  app: httpd_app          # Solo puede matchear app = httpd_app

# ReplicaSet — soporta conjuntos (set-based)
selector:
  matchLabels:
    app: httpd_app
  matchExpressions:
    - key: environment
      operator: In
      values: [production, staging]    # Matchea si environment es production O staging
    - key: tier
      operator: NotIn
      values: [backend]               # Matchea si tier NO es backend
```

Operadores disponibles en `matchExpressions`:

| Operador | Significado | Ejemplo |
|----------|------------|---------|
| `In` | El valor esta en la lista | `environment In [prod, staging]` |
| `NotIn` | El valor NO esta en la lista | `tier NotIn [backend]` |
| `Exists` | La key existe (sin importar valor) | `key: app, operator: Exists` |
| `DoesNotExist` | La key NO existe | `key: deprecated, operator: DoesNotExist` |

#### Por que se sigue viendo en examenes y labs

Aunque en produccion se usa Deployment, el ReplicationController aparece en certificaciones como CKA/CKAD y en labs de practica porque:
- Es parte del core API (`v1`)
- Ayuda a entender como funciona la replicacion antes de aprender Deployments
- Algunos sistemas legacy aun lo usan

### Relacion entre selector y labels

El `selector` del RC **debe coincidir** con los `labels` del template. Asi es como el RC sabe cuales Pods le pertenecen:

```
ReplicationController
├── selector: app=httpd_app          ← Busca Pods con este label
└── template:
    └── labels: app=httpd_app        ← Los Pods se crean con este label
                                        (DEBE coincidir con el selector)
```

Si no coinciden, el RC no puede encontrar sus Pods y crea infinitos Pods nuevos o no gestiona ninguno.

## Pasos

1. Crear el manifiesto YAML del ReplicationController
2. Aplicar el manifiesto con `kubectl apply`
3. Verificar que las 3 replicas estan en estado `Running`

## Comandos / Codigo

### Manifiesto del ReplicationController

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: httpd-replicationcontroller
  labels:
    app: httpd_app
    type: front-end
spec:
  replicas: 3
  selector:
    app: httpd_app
  template:
    metadata:
      name: httpd-container
      labels:
        app: httpd_app
        type: front-end
    spec:
      containers:
        - name: httpd-container
          image: httpd:latest
```

**Puntos importantes:**

- `apiVersion: v1` — el RC pertenece al core API, no a `apps/v1`
- `selector.app` debe coincidir con `template.metadata.labels.app`
- Los labels del template pueden tener **mas** labels que el selector, pero el selector debe ser un subconjunto de los labels del template
- `metadata.name` en el template es el nombre sugerido para los Pods (Kubernetes agrega un sufijo aleatorio)

### Estructura del manifiesto explicada

```
ReplicationController
├── metadata
│   ├── name: httpd-replicationcontroller    # Nombre del RC
│   └── labels:
│       ├── app: httpd_app
│       └── type: front-end
└── spec
    ├── replicas: 3                          # Cuantos Pods mantener
    ├── selector:
    │   └── app: httpd_app                   # Busca Pods con este label
    └── template                             # Plantilla para crear Pods
        ├── metadata
        │   ├── name: httpd-container
        │   └── labels:
        │       ├── app: httpd_app           # DEBE coincidir con selector
        │       └── type: front-end
        └── spec
            └── containers
                └── httpd-container
                    └── image: httpd:latest
```

### Aplicar el manifiesto

```bash
kubectl apply -f rc-httpd.yaml
```

```
replicationcontroller/httpd-replicationcontroller created
```

### Verificar el ReplicationController

```bash
kubectl get rc
```

```
NAME                          DESIRED   CURRENT   READY   AGE
httpd-replicationcontroller   3         3         3       30s
```

| Columna | Significado |
|---------|------------|
| DESIRED | Replicas configuradas (3) |
| CURRENT | Pods que existen actualmente |
| READY | Pods listos para recibir trafico |

### Verificar los Pods

```bash
kubectl get pods
```

```
NAME                                READY   STATUS    RESTARTS   AGE
httpd-replicationcontroller-abc12   1/1     Running   0          30s
httpd-replicationcontroller-def34   1/1     Running   0          30s
httpd-replicationcontroller-ghi56   1/1     Running   0          30s
```

Los 3 Pods estan en estado `Running`.

### Verificar los labels

```bash
kubectl get pods --show-labels
```

```
NAME                                READY   STATUS    RESTARTS   AGE   LABELS
httpd-replicationcontroller-abc12   1/1     Running   0          30s   app=httpd_app,type=front-end
httpd-replicationcontroller-def34   1/1     Running   0          30s   app=httpd_app,type=front-end
httpd-replicationcontroller-ghi56   1/1     Running   0          30s   app=httpd_app,type=front-end
```

### Ver detalle del RC

```bash
kubectl describe rc httpd-replicationcontroller
```

### Probar la auto-recuperacion

Si se elimina un Pod, el RC crea uno nuevo automaticamente:

```bash
# Eliminar un Pod
kubectl delete pod httpd-replicationcontroller-abc12

# Verificar que se creo uno nuevo
kubectl get pods
```

```
NAME                                READY   STATUS    RESTARTS   AGE
httpd-replicationcontroller-def34   1/1     Running   0          2m
httpd-replicationcontroller-ghi56   1/1     Running   0          2m
httpd-replicationcontroller-xyz99   1/1     Running   0          5s    ← nuevo
```

El RC detecta que solo hay 2 Pods y crea uno nuevo para mantener las 3 replicas.

## Equivalente con Deployment (recomendado en produccion)

Para referencia, asi se veria el mismo recurso como Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpd-deployment
  labels:
    app: httpd_app
    type: front-end
spec:
  replicas: 3
  selector:
    matchLabels:                    # set-based selector (mas flexible)
      app: httpd_app
  template:
    metadata:
      labels:
        app: httpd_app
        type: front-end
    spec:
      containers:
        - name: httpd-container
          image: httpd:latest
```

Diferencias clave:
- `apiVersion: apps/v1` en vez de `v1`
- `selector.matchLabels` en vez de `selector` directo
- Soporta rolling updates y rollback automaticamente

## Errores comunes

| Error | Causa | Solucion |
|-------|-------|----------|
| RC crea Pods infinitamente | El `selector` no coincide con los `labels` del template | Asegurar que `selector` es subconjunto de `template.metadata.labels` |
| `selector does not match template labels` | Selector y labels no coinciden | Revisar que los valores sean identicos |
| Pods en `ImagePullBackOff` | Nombre o tag de la imagen incorrecto | Verificar que `httpd:latest` es accesible |
| `metadata.name` con guion bajo | Los nombres de recursos en K8s no permiten `_` | Usar guiones `-` en vez de guiones bajos `_` |

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| RC muestra `READY 0/3` | Los Pods no estan listos. Verificar con `kubectl describe pod` para ver errores |
| Pod eliminado pero no se recrea | Verificar que el RC sigue existiendo: `kubectl get rc` |
| Quiero escalar las replicas | `kubectl scale rc httpd-replicationcontroller --replicas=5` |
| Quiero migrar de RC a Deployment | Crear un Deployment con los mismos labels/selector. Eliminar el RC. El Deployment adoptara los Pods existentes si los labels coinciden |

## Recursos

- [ReplicationController - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/replicationcontroller/)
- [ReplicaSet - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Deployments - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
