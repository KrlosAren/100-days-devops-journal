# Día 52 - Rollback de un Deployment a la versión anterior

## Problema / Desafío

El equipo de Nautilus desplegó una nueva versión y un cliente reportó un bug. Hay que revertir el Deployment `nginx-deployment` a la revisión anterior — sin re-buildear imágenes ni editar el YAML.

- **Deployment:** `nginx-deployment`
- **Estado actual:** revisión 2 (`nginx:stable`) — con bug
- **Objetivo:** volver a la revisión 1 (la versión que funcionaba)

## Conceptos clave

### Por qué se puede hacer rollback "gratis"

El Deployment **no borra los ReplicaSets viejos** cuando hace un rolling update. Los deja en `0/0 replicas`, como historial. Esto permite que `kubectl rollout undo` haga un **flip-flop**: escala el RS viejo de 0→N y el actual de N→0, sin necesidad de re-construir nada.

El número de ReplicaSets guardados se controla con `spec.revisionHistoryLimit` (default `10`). Si lo bajás a `0` perdés la capacidad de rollback rápido por completo.

### Rollback = rolling update en reverso

`kubectl rollout undo` no es una operación especial — es **el mismo mecanismo** del rolling update normal, ejecutado en sentido contrario. Respeta los mismos campos:

- `strategy.type: RollingUpdate`
- `maxSurge` y `maxUnavailable`
- Readiness probes (si las hubiera)

Por eso el rollback **también es gradual y sin downtime**: si tu rolling update inicial fue seguro, el rollback hereda esa seguridad.

### Comandos clave

| Comando                                                          | Qué hace                                                              |
| ---------------------------------------------------------------- | --------------------------------------------------------------------- |
| `kubectl rollout undo deployment/<name>`                         | Rollback a la revisión **inmediatamente anterior**                    |
| `kubectl rollout undo deployment/<name> --to-revision=N`         | Rollback a una revisión específica (útil si querés saltar 2+ atrás)   |
| `kubectl rollout history deployment/<name>`                      | Lista revisiones disponibles con su `CHANGE-CAUSE`                    |
| `kubectl rollout history deployment/<name> --revision=N`         | Ver el Pod Template de una revisión específica antes de hacer rollback |
| `kubectl rollout undo deployment/<name> --dry-run=client -o yaml`| Preview de la operación sin ejecutarla (poco común pero útil en CI/CD)|

### La trampa de la renumeración

Esta es la parte que confunde a casi todo el mundo la primera vez:

Si tenés revisiones `1` (buena) y `2` (con bug, current), y hacés `kubectl rollout undo`:

```
Antes:                              Después del undo:
REVISION  CHANGE-CAUSE              REVISION  CHANGE-CAUSE
1         <none>                    2         set image ... nginx:stable
2         set image ... nginx:stable 3         <none>
                                    ^ La que era "1" ahora es "3"
```

La revisión "1" **no se eliminó** — es el mismo ReplicaSet (`nginx-deployment-fc677cbc9`), pero K8s le actualizó el annotation `deployment.kubernetes.io/revision` de `1` a `3`. La revisión 2 (con bug) sigue ahí como historial.

Por qué: cada ReplicaSet tiene una sola revisión, así que cuando "reactivás" el RS viejo, K8s necesita marcarlo como la latest — y la única forma de hacer eso es subir su número de revisión arriba de la actual.

### `--record` y `kubernetes.io/change-cause`

El flag `--record=true` en `kubectl set image` (y otros) guardaba el comando completo en una annotation, lo que aparece en `rollout history` como `CHANGE-CAUSE`. **Está deprecado desde k8s v1.22** pero sigue funcionando en clusters como el de este lab.

Reemplazo recomendado: anotar manualmente después de cada cambio importante.

```bash
kubectl annotate deployment/nginx-deployment \
  kubernetes.io/change-cause="Update to nginx:stable for CVE-XXXX patch"
```

## Pasos

1. Inspeccionar estado actual (qué revisión está corriendo y cuál es la culpable del bug)
2. Revisar el historial para identificar a qué revisión rollear
3. (Opcional) Inspeccionar la revisión target antes de rollearle
4. Ejecutar `kubectl rollout undo`
5. Monitorear con `rollout status`
6. Verificar que la imagen volvió a la versión correcta

## Comandos / Código

### 1. Estado inicial: revisión 2 con bug

```bash
kubectl get deployment/nginx-deployment
```

```
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deployment   3/3     3            3           47s
```

```bash
kubectl describe deployment/nginx-deployment
```

```
Name:                   nginx-deployment
Annotations:            deployment.kubernetes.io/revision: 2
                        kubernetes.io/change-cause: kubectl set image deployment nginx-deployment nginx-container=nginx:stable --record=true
Replicas:               3 desired | 3 updated | 3 total | 3 available | 0 unavailable
StrategyType:           RollingUpdate
Pod Template:
  Containers:
   nginx-container:
    Image:         nginx:stable
OldReplicaSets:  nginx-deployment-fc677cbc9 (0/0 replicas created)
NewReplicaSet:   nginx-deployment-6c744d9dd6 (3/3 replicas created)
Events:
  Normal  ScalingReplicaSet  81s   deployment-controller  Scaled up replica set nginx-deployment-fc677cbc9 from 0 to 3
  Normal  ScalingReplicaSet  71s   deployment-controller  Scaled up replica set nginx-deployment-6c744d9dd6 from 0 to 1
  Normal  ScalingReplicaSet  66s   deployment-controller  Scaled down replica set nginx-deployment-fc677cbc9 from 3 to 2
  ...
```

Lectura rápida:

- `revision: 2` → estamos en la revisión con bug
- `change-cause: kubectl set image ... nginx:stable --record=true` → así nos dejaron en este estado
- `OldReplicaSets: nginx-deployment-fc677cbc9 (0/0)` → el RS viejo (revisión 1) está dormido, listo para reactivarse
- `NewReplicaSet: nginx-deployment-6c744d9dd6 (3/3)` → el RS con el bug, sirviendo tráfico

### 2. Revisar el historial

```bash
kubectl rollout history deployment/nginx-deployment
```

```
deployment.apps/nginx-deployment
REVISION  CHANGE-CAUSE
1         <none>
2         kubectl set image deployment nginx-deployment nginx-container=nginx:stable --record=true
```

La revisión `1` no tiene `CHANGE-CAUSE` (creación inicial del deployment, no se anotó). Esa es a la que queremos volver.

### 3. (Recomendado) Inspeccionar la revisión target antes de rollear

Antes de cualquier rollback en producción, vale la pena confirmar **qué imagen** tiene la revisión a la que vas:

```bash
kubectl rollout history deployment/nginx-deployment --revision=1
```

```
Pod Template:
  Labels:       app=nginx-app
                pod-template-hash=fc677cbc9
  Containers:
   nginx-container:
    Image:      nginx:1.16
```

Confirmado: vamos a volver a `nginx:1.16`. Esto te protege de errores comunes: "creí que la revisión anterior era la X pero en realidad era la Y".

### 4. Ejecutar el rollback

#### Opción A: undo a la revisión inmediatamente anterior

```bash
kubectl rollout undo deployment/nginx-deployment
```

```
deployment.apps/nginx-deployment rolled back
```

#### Opción B: undo a una revisión específica

```bash
kubectl rollout undo deployment/nginx-deployment --to-revision=1
```

```
deployment.apps/nginx-deployment rolled back
```

> **Cuándo usar cada una:** si querés ir solo "un paso atrás", la opción A es más simple y resistente a errores. Si hay más de 2 revisiones y querés saltar varios atrás (ej: revisión 5 con bug, querés volver a 2 saltando 3 y 4), `--to-revision=N` es obligatorio. En este lab cualquiera de las dos funciona porque solo hay 2 revisiones.

### 5. Monitorear el rollback

```bash
kubectl rollout status deployment/nginx-deployment
```

```
deployment "nginx-deployment" successfully rolled out
```

(Acá ya estaba terminado al consultar — si lo corrés mientras está activo aparecen líneas tipo `Waiting for deployment ... 1 old replicas are pending termination...`.)

### 6. Verificar que volvimos a la imagen correcta

```bash
kubectl describe deployment/nginx-deployment
```

```
Name:                   nginx-deployment
Annotations:            deployment.kubernetes.io/revision: 3
Replicas:               3 desired | 3 updated | 3 total | 3 available | 0 unavailable
StrategyType:           RollingUpdate
Pod Template:
  Containers:
   nginx-container:
    Image:         nginx:1.16
OldReplicaSets:  nginx-deployment-6c744d9dd6 (0/0 replicas created)
NewReplicaSet:   nginx-deployment-fc677cbc9 (3/3 replicas created)
Events:
  Normal  ScalingReplicaSet  13m                 Scaled up replica set nginx-deployment-fc677cbc9 from 0 to 3   ← deploy original
  Normal  ScalingReplicaSet  12m                 Scaled up replica set nginx-deployment-6c744d9dd6 from 0 to 1  ← rolling update a nginx:stable
  Normal  ScalingReplicaSet  12m                 Scaled down replica set nginx-deployment-fc677cbc9 from 3 to 2
  ...
  Normal  ScalingReplicaSet  12m                 Scaled down replica set nginx-deployment-fc677cbc9 from 1 to 0
  Normal  ScalingReplicaSet  5m6s                Scaled up replica set nginx-deployment-fc677cbc9 from 0 to 1   ← rollback empieza
  Normal  ScalingReplicaSet  5m5s                Scaled down replica set nginx-deployment-6c744d9dd6 from 3 to 2
  Normal  ScalingReplicaSet  5m3s (x4 over 5m5s) (combined from similar events): Scaled down replica set nginx-deployment-6c744d9dd6 from 1 to 0
```

Confirmaciones clave de este output:

- **`revision: 3`** (no `1`) — la renumeración predicha en la sección teórica se cumplió. La revisión 1 dejó de existir; el mismo ReplicaSet `fc677cbc9` ahora es revisión 3.
- **`Image: nginx:1.16`** — volvimos a la imagen original, sin el bug
- **`OldReplicaSets: nginx-deployment-6c744d9dd6 (0/0)`** — el RS con el bug está dormido pero presente (podríamos hacer rollout forward si quisiéramos)
- **`NewReplicaSet: nginx-deployment-fc677cbc9 (3/3)`** — el RS reactivado sirviendo tráfico
- **Events** muestra **dos rolling updates encadenados en el mismo Deployment**: el deploy original (12m, RS old→new), y el rollback (5m, RS new→old)

> **Nota — "combined from similar events":** Kubernetes compacta eventos repetitivos del mismo RS en una sola línea con `(x4 over 5m5s)`. Aparece solo durante el rollback porque los scale-downs son todos del mismo RS (`6c744d9dd6`). En el rolling update inicial cada evento queda separado porque alternan entre dos RS distintos.

### 7. Verificar el nuevo historial

```bash
kubectl rollout history deployment/nginx-deployment
```

```
deployment.apps/nginx-deployment
REVISION  CHANGE-CAUSE
2         kubectl set image deployment nginx-deployment nginx-container=nginx:stable --record=true
3         <none>
```

Observación predicha y cumplida: **la revisión `1` desapareció** del history, y aparece la `3` (que internamente es el mismo RS `fc677cbc9` que era la revisión 1, con el annotation `deployment.kubernetes.io/revision` bumpeado de `1` a `3`).

### 8. Verificar los pods

```bash
kubectl get pods -o wide
```

```
NAME                               READY   STATUS    RESTARTS   AGE     IP           NODE
nginx-deployment-fc677cbc9-ffvrj   1/1     Running   0          5m23s   10.22.0.17   jump-host
nginx-deployment-fc677cbc9-lq7sj   1/1     Running   0          5m25s   10.22.0.15   jump-host
nginx-deployment-fc677cbc9-xbx8s   1/1     Running   0          5m24s   10.22.0.16   jump-host
```

Los 3 pods ahora tienen hash `fc677cbc9` (el RS reactivado). Compará con la pre-rollback: los pods de antes tenían hash `6c744d9dd6` (el RS con bug).

> **Detalle no obvio — el hash `fc677cbc9` se reutilizó:**
> El `pod-template-hash` no es aleatorio: se calcula como un hash determinístico del Pod Template. Misma template (mismas labels, misma `image: nginx:1.16`) = mismo hash. Por eso K8s **no creó un RS nuevo** durante el rollback — encontró que el hash de la template coincidía con un RS ya existente (`fc677cbc9`, que estaba en 0 replicas) y simplemente lo reactivó.
>
> Implicación práctica: si volvieras a hacer `kubectl set image ... nginx:stable` ahora, K8s reutilizaría el RS `6c744d9dd6` (no crearía uno nuevo) porque el hash de esa template también sigue siendo el mismo. Es por eso que las revisiones de Deployments son tan baratas: K8s no acumula RSs basura, solo los que tienen Pod Templates distintos.

## Cómo se ve el flip-flop a nivel de ReplicaSets

```bash
kubectl get rs -l app=nginx-app
```

Esperado tras el rollback:

```
NAME                          DESIRED   CURRENT   READY   AGE
nginx-deployment-fc677cbc9    3         3         3       5m   ← REACTIVADO (era el viejo, ahora el current)
nginx-deployment-6c744d9dd6   0         0         0       2m   ← DORMIDO (era el current, ahora el viejo)
```

El RS no se borra ni se recrea — solo cambian sus replicas y sus annotations. Es la operación más barata posible que K8s puede hacer para revertir un deploy.

## Troubleshooting

| Problema                                                                  | Causa y solución                                                                                                                                |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `error: unable to find specified revision N`                              | La revisión ya no existe en el historial — fue purgada por `revisionHistoryLimit`. Revisar `kubectl rollout history` para ver las disponibles  |
| `rollout undo` ejecuta pero el bug sigue apareciendo                      | El bug no estaba en la imagen sino en config (ConfigMap, Secret, env var) que no es parte del Pod Template. El rollback no toca eso             |
| Después del undo `rollout history` muestra revisiones renumeradas raras   | Comportamiento normal — la revisión a la que rolleaste se renumera al máximo + 1 (ver sección "La trampa de la renumeración")                  |
| `CHANGE-CAUSE: <none>` en la revisión a la que querés volver              | Nadie anotó la revisión cuando se creó. Para futuras: usar `kubectl annotate ... kubernetes.io/change-cause="..."` después de cada cambio        |
| Rollback "trabado": `rollout status` no avanza                            | El RS viejo no logra escalar — típicamente porque la imagen ya no está en el registry (fue borrada del repo). Verificar con `describe pod`     |
| Borraste manualmente un RS viejo y ahora no podés rollear                 | El RS viejo se necesita para rollback. Para reconstruir hay que editar el YAML del deployment con la imagen anterior y `kubectl apply`         |

## Recursos

- [Rolling Back a Deployment (oficial)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
- [`kubectl rollout undo` reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout)
- [Deprecation of `--record`](https://github.com/kubernetes/kubectl/issues/1067) — por qué se va el flag y qué hacer en su lugar
- [`revisionHistoryLimit` (oficial)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#revision-history-limit)
