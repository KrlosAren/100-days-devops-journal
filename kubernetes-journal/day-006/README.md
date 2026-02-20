# Día 06 - Rollback de un Deployment a una revisión previa

## Problema / Desafío

Se desplegó una nueva versión del Deployment `nginx-deployment`, pero un cliente reportó un bug en esta versión. El equipo necesita revertir el Deployment a la revisión anterior para restaurar la versión estable mientras se investiga el problema.

## Conceptos clave

### Rollout History

Kubernetes mantiene un historial de revisiones de cada Deployment. Cada vez que se modifica el template del Pod (por ejemplo, al cambiar la imagen), se crea una nueva revisión. Este historial permite inspeccionar qué cambió en cada versión y revertir a cualquier revisión anterior.

El número de revisiones que se conservan está controlado por `spec.revisionHistoryLimit` (default: 10).

### Rollback (rollout undo)

Un rollback revierte el Deployment a una revisión anterior. Kubernetes lo ejecuta como un rolling update inverso: crea Pods con la configuración de la revisión destino mientras termina los Pods de la revisión actual. La aplicación no tiene downtime durante el proceso.

```
Revisión 2 (bug) ●●●  →  Revisión 2 ●●  Revisión 1 ●  →  Revisión 1 ●●●
```

### --record (deprecado)

El flag `--record` guardaba el comando ejecutado en la anotación `CHANGE-CAUSE` del Deployment. Esto es útil para saber **qué comando** generó cada revisión en el historial. Está deprecado desde Kubernetes 1.22, pero todavía funciona.

## Pasos

1. Inspeccionar el historial de revisiones del Deployment
2. Ver el detalle de la revisión a la que se quiere revertir
3. Ejecutar el rollback a la revisión específica
4. Verificar el estado del rollout
5. Confirmar que los Pods corren con la imagen correcta

## Comandos / Código

### Inspeccionar el historial de revisiones

```bash
kubectl rollout history deployment/nginx-deployment
```

```
REVISION  CHANGE-CAUSE
1         <none>
2         kubectl set image deployment nginx-deployment nginx-container=nginx:stable --kubeconfig=/root/.kube/config --record=true
```

La revisión 1 es la versión original (`nginx:1.16`) y la revisión 2 es la versión con el bug (`nginx:stable`).

### Ver el detalle de una revisión específica

```bash
kubectl rollout history deployment/nginx-deployment --revision=1
```

```
deployment.apps/nginx-deployment with revision #1
Pod Template:
  Labels:       app=nginx-app
        pod-template-hash=989f57c54
  Containers:
   nginx-container:
    Image:      nginx:1.16
    Port:       <none>
    Host Port:  <none>
    Environment:        <none>
    Mounts:     <none>
  Volumes:      <none>
```

Esto confirma que la revisión 1 usa `nginx:1.16`, la versión estable a la que queremos revertir.

### Ejecutar el rollback

```bash
kubectl rollout undo deployment/nginx-deployment --to-revision=1
```

```
deployment.apps/nginx-deployment rolled back
```

Si se omite `--to-revision`, Kubernetes revierte a la revisión inmediatamente anterior.

### Verificar el estado del rollout

```bash
kubectl rollout status deployment/nginx-deployment
```

```
deployment "nginx-deployment" successfully rolled out
```

### Confirmar que los Pods corren con la imagen correcta

```bash
kubectl get pods -o wide
```

```
NAME                               READY   STATUS    RESTARTS   AGE   IP            NODE                      NOMINATED NODE   READINESS GATES
nginx-deployment-989f57c54-2wpgf   1/1     Running   0          15s   10.244.0.13   kodekloud-control-plane   <none>           <none>
nginx-deployment-989f57c54-4wkpb   1/1     Running   0          19s   10.244.0.11   kodekloud-control-plane   <none>           <none>
nginx-deployment-989f57c54-8pchp   1/1     Running   0          17s   10.244.0.12   kodekloud-control-plane   <none>           <none>
```

```bash
kubectl get deployments -o wide
```

```
NAME               READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS        IMAGES       SELECTOR
nginx-deployment   3/3     3            3           6m48s   nginx-container   nginx:1.16   app=nginx-app
```

La columna `IMAGES` muestra `nginx:1.16`, confirmando que el rollback fue exitoso.

### Ver logs de todos los Pods del Deployment

Kubernetes no tiene un comando directo para ver logs de un Deployment completo, pero se puede hacer usando el label selector:

```bash
# Ver logs de todos los pods del deployment usando su label
kubectl logs -l app=nginx-app

# Seguir los logs en tiempo real
kubectl logs -l app=nginx-app -f

# Con prefijo del nombre del pod (útil para distinguir cuál pod genera cada línea)
kubectl logs -l app=nginx-app --prefix

# Últimas N líneas de cada pod
kubectl logs -l app=nginx-app --tail=50
```

El label se obtiene de la columna `SELECTOR` en `kubectl get deployment -o wide`.

Si el Pod tiene múltiples contenedores:

```bash
kubectl logs -l app=nginx-app --all-containers=true
```

#### Alternativa: stern (herramienta externa)

[stern](https://github.com/stern/stern) simplifica la visualización de logs de múltiples Pods, con colores y filtrado por nombre:

```bash
# Instalar
brew install stern

# Ver logs de todos los pods del deployment (match por nombre)
stern nginx-deployment

# Filtrar por contenedor específico
stern nginx-deployment -c nginx-container
```

### Resumen de comandos de rollout

| Comando | Descripción |
|---------|-------------|
| `kubectl rollout history deployment/<nombre>` | Ver historial de revisiones |
| `kubectl rollout history deployment/<nombre> --revision=N` | Ver detalle de una revisión específica |
| `kubectl rollout undo deployment/<nombre>` | Revertir a la revisión anterior |
| `kubectl rollout undo deployment/<nombre> --to-revision=N` | Revertir a una revisión específica |
| `kubectl rollout status deployment/<nombre>` | Ver el estado del rollout en curso |
| `kubectl rollout pause deployment/<nombre>` | Pausar un rollout |
| `kubectl rollout resume deployment/<nombre>` | Reanudar un rollout pausado |

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `CHANGE-CAUSE` muestra `<none>` | El cambio se hizo sin `--record`. Para referencia futura, usar `kubectl annotate deployment/<nombre> kubernetes.io/change-cause="descripción"` |
| El rollback no cambia la imagen | Verificar con `kubectl rollout history deployment/<nombre> --revision=N` que la revisión destino tiene la imagen correcta |
| Error `revision not found` | La revisión fue eliminada por `revisionHistoryLimit`. Verificar revisiones disponibles con `rollout history` |
| Pods quedan en `Pending` después del rollback | Verificar recursos del nodo con `kubectl describe node`. Puede que no haya CPU/memoria suficiente |
| El rollback crea una nueva revisión con número más alto | Esto es comportamiento normal. Kubernetes no "regresa" el número de revisión, crea una nueva revisión con la configuración de la revisión destino |

## Recursos

- [Rolling Back a Deployment - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
- [kubectl rollout - Kubernetes Docs](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/)
- [Deployment Revision History - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#revision-history-limit)
