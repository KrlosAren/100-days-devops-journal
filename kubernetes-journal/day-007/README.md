# Dia 07 - Crear un ReplicaSet con httpd

## Problema / Desafio

Se necesita desplegar un ReplicaSet con 4 replicas de la imagen `httpd:latest`, asegurando que siempre existan exactamente 4 Pods corriendo con los labels `app=httpd_app` y `type=front-end`.

## Conceptos clave

### ReplicaSet

Un ReplicaSet es un recurso de Kubernetes que garantiza que un numero especificado de replicas de un Pod esten corriendo en todo momento. Si un Pod falla o es eliminado, el ReplicaSet crea automaticamente uno nuevo para mantener el estado deseado.

### Diferencia entre ReplicaSet y Deployment

| Caracteristica | ReplicaSet | Deployment |
|----------------|------------|------------|
| Mantiene N replicas | Si | Si (usa un ReplicaSet internamente) |
| Rolling updates | No | Si |
| Rollback | No | Si |
| Historial de revisiones | No | Si |

En la practica, se recomienda usar **Deployments** en lugar de ReplicaSets directamente, porque un Deployment gestiona ReplicaSets y agrega la capacidad de rolling updates y rollbacks. Sin embargo, entender ReplicaSets es fundamental porque son el mecanismo subyacente.

### selector.matchLabels

El `selector.matchLabels` define que Pods son gestionados por este ReplicaSet. Los labels del template del Pod **deben coincidir** con el selector, de lo contrario Kubernetes rechaza el manifiesto.

## Pasos

1. Crear el manifiesto YAML del ReplicaSet
2. Aplicar el manifiesto con `kubectl apply`
3. Verificar que las 4 replicas esten corriendo
4. Probar la auto-reparacion eliminando un Pod

## Comandos / Codigo

### Manifiesto del ReplicaSet

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: httpd-replicaset
  labels:
    app: httpd_app
    type: front-end
spec:
  replicas: 4
  selector:
    matchLabels:
      app: httpd_app
      type: front-end
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

### Aplicar el manifiesto

```bash
kubectl apply -f replicaset-httpd.yml
```

```
replicaset.apps/replicaset created
```

### Verificar el ReplicaSet

```bash
kubectl get replicaset
```

```
NAME               DESIRED   CURRENT   READY   AGE
httpd-replicaset   4         4         4       10s
```

### Verificar los Pods

```bash
kubectl get pods -l app=httpd_app
```

```
NAME               READY   STATUS    RESTARTS   AGE
httpd-replicaset-abc12   1/1     Running   0          15s
httpd-replicaset-def34   1/1     Running   0          15s
httpd-replicaset-ghi56   1/1     Running   0          15s
httpd-replicaset-jkl78   1/1     Running   0          15s
```

### Ver detalle del ReplicaSet

```bash
kubectl describe replicaset httpd-replicaset
```

### Probar la auto-reparacion

```bash
# Eliminar un Pod manualmente
kubectl delete pod httpd-replicaset-abc12

# Verificar que el ReplicaSet crea uno nuevo automaticamente
kubectl get pods -l app=httpd_app
```

El ReplicaSet detecta que solo hay 3 Pods y crea uno nuevo para mantener las 4 replicas deseadas.

### Escalar el ReplicaSet

```bash
# Escalar a 6 replicas
kubectl scale replicaset httpd-replicaset --replicas=6

# Verificar
kubectl get replicaset
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| Pods en `ImagePullBackOff` | Verificar que la imagen `httpd:latest` es accesible. En entornos sin internet usar una imagen local o un registry privado |
| `selector does not match template labels` | Los labels en `spec.selector.matchLabels` deben coincidir exactamente con los labels en `spec.template.metadata.labels` |
| ReplicaSet no crea los Pods | Verificar con `kubectl describe replicaset httpd-replicaset` los eventos para identificar el error |
| Pods quedan en `Pending` | Verificar recursos del nodo con `kubectl describe node`. Puede no haber suficiente CPU/memoria para 4 replicas |

## Recursos

- [ReplicaSet - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Labels and Selectors - Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [httpd - Docker Hub](https://hub.docker.com/_/httpd)
