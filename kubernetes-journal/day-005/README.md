# Día 05 - Rolling Update de un Deployment

## Problema / Desafío

Existe un Deployment llamado `nginx-deployment` con 3 réplicas corriendo la imagen `nginx:1.16`. Se necesita actualizar la imagen a `nginx:1.18` y verificar que todos los Pods estén funcionales después del update.

## Conceptos clave

### Rolling Update

Es la estrategia de actualización por defecto en Kubernetes. Reemplaza los Pods de forma gradual: crea Pods nuevos con la versión actualizada mientras va terminando los Pods viejos, garantizando que la aplicación nunca tenga downtime durante el proceso.

El flujo es:

```
Pod v1.16 ●●●  →  Pod v1.16 ●●  Pod v1.18 ●  →  Pod v1.16 ●  Pod v1.18 ●●  →  Pod v1.18 ●●●
```

### Parámetros del Rolling Update

Kubernetes controla la velocidad del rolling update con dos parámetros en `spec.strategy.rollingUpdate`:

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `maxUnavailable` | 25% | Cantidad máxima de Pods que pueden estar no disponibles durante el update |
| `maxSurge` | 25% | Cantidad máxima de Pods adicionales que se pueden crear por encima del número deseado de réplicas |

Con 3 réplicas y los valores por defecto:
- `maxUnavailable: 25%` → redondeado a 0, al menos 3 Pods disponibles
- `maxSurge: 25%` → redondeado a 1, máximo 4 Pods en total durante el update

### kubectl set image

Comando imperativo para actualizar la imagen de un contenedor en un Deployment sin editar el manifiesto YAML directamente.

```bash
kubectl set image deployment/<nombre-deployment> <nombre-contenedor>=<nueva-imagen>
```

### Rollout

Un **rollout** es el proceso que Kubernetes ejecuta cuando se detecta un cambio en el template del Pod de un Deployment. Cada rollout crea un nuevo **ReplicaSet** y va migrando los Pods del ReplicaSet anterior al nuevo.

## Pasos

1. Verificar el estado actual de los Pods
2. Verificar el Deployment y la imagen actual
3. Actualizar la imagen del contenedor
4. Verificar el estado del rollout
5. Confirmar que los Pods están corriendo con la nueva imagen

## Comandos / Código

### Verificar estado actual

```bash
# Ver los Pods del deployment
kubectl get pods
```

```
NAME                               READY   STATUS    RESTARTS   AGE
nginx-deployment-989f57c54-58ds8   1/1     Running   0          2m41s
nginx-deployment-989f57c54-6889n   1/1     Running   0          2m41s
nginx-deployment-989f57c54-q6dcp   1/1     Running   0          2m41s
```

```bash
# Ver el deployment con la imagen actual
kubectl get deployment -o wide
```

```
NAME               READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS        IMAGES       SELECTOR
nginx-deployment   3/3     3            3           3m5s   nginx-container   nginx:1.16   app=nginx-app
```

La columna `IMAGES` muestra `nginx:1.16`, que es la versión que debemos actualizar.

### Actualizar la imagen

```bash
kubectl set image deployment/nginx-deployment nginx-container=nginx:1.18
```

```
deployment.apps/nginx-deployment image updated
```

El formato del comando es: `deployment/<nombre>` seguido de `<contenedor>=<imagen:tag>`. El nombre del contenedor (`nginx-container`) se obtiene de la columna `CONTAINERS` en el `get deployment -o wide`.

### Verificar el rollout

```bash
# Ver el estado del rollout en tiempo real
kubectl rollout status deployment/nginx-deployment
```

```
deployment "nginx-deployment" successfully rolled out
```

Este comando bloquea hasta que el rollout termine. Si todos los Pods nuevos están listos, muestra el mensaje de éxito.

### Confirmar la actualización

```bash
# Verificar que los Pods están corriendo
kubectl get pods
```

Los Pods tendrán nombres nuevos (hash diferente) porque se crearon con el nuevo ReplicaSet.

```bash
# Verificar que la imagen se actualizó
kubectl get deployment -o wide
```

La columna `IMAGES` ahora debe mostrar `nginx:1.18`.

```bash
# Ver el detalle del deployment
kubectl describe deployment nginx-deployment
```

En la sección de eventos se puede ver el proceso del rolling update:

```
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  ...   deployment-controller  Scaled up replica set nginx-deployment-xxxx to 1
  Normal  ScalingReplicaSet  ...   deployment-controller  Scaled down replica set nginx-deployment-yyyy to 2
  ...
```

### Alternativas para actualizar la imagen

```bash
# Opción 1: kubectl set image (usado en este ejercicio)
kubectl set image deployment/nginx-deployment nginx-container=nginx:1.18

# Opción 2: kubectl edit (abre el manifiesto en el editor)
kubectl edit deployment nginx-deployment

# Opción 3: kubectl patch
kubectl patch deployment nginx-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx-container","image":"nginx:1.18"}]}}}}'
```

### Rollback en caso de error

Si la nueva versión tiene problemas, se puede revertir al estado anterior:

```bash
# Ver historial de rollouts
kubectl rollout history deployment/nginx-deployment

# Revertir al rollout anterior
kubectl rollout undo deployment/nginx-deployment

# Revertir a una revisión específica
kubectl rollout undo deployment/nginx-deployment --to-revision=1
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| Rollout se queda en progreso, Pods en `ImagePullBackOff` | La imagen especificada no existe en el registry. Verificar el nombre y tag con `kubectl describe pod <pod>` |
| Pods nuevos en `CrashLoopBackOff` después del update | La nueva versión tiene un error. Hacer rollback con `kubectl rollout undo deployment/nginx-deployment` |
| `kubectl rollout status` nunca termina | El deployment puede tener un `progressDeadlineSeconds` (default 600s). Verificar con `kubectl describe deployment` los eventos |
| Solo algunos Pods se actualizaron | El rollout puede estar pausado. Verificar con `kubectl rollout status` y reanudar con `kubectl rollout resume` |
| Error `no container named "X" found` en `set image` | El nombre del contenedor no coincide. Verificar con `kubectl get deployment -o wide` la columna `CONTAINERS` |

## Recursos

- [Performing a Rolling Update - Kubernetes Docs](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)
- [Updating a Deployment - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)
- [Rolling Back a Deployment - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
- [kubectl set image - Kubernetes Docs](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/kubectl_set_image/)
