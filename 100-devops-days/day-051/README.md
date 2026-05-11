# Día 51 - Rolling Update en Kubernetes Deployments

## Problema / Desafío

El equipo de Nautilus tiene una app corriendo en el cluster con nginx. Sacaron una nueva versión del web server (`nginx:1.18`) y hay que actualizar el Deployment **sin downtime** — los usuarios no deben notar la actualización.

- **Deployment:** `nginx-deployment`
- **Imagen actual:** `nginx:1.16`
- **Imagen nueva:** `nginx:1.18`
- **Container name:** `nginx-container`
- **Requisito:** todos los pods operativos al terminar

## Conceptos clave

### Qué es un Rolling Update

Es la estrategia **default** de un Deployment para reemplazar pods cuando cambia algo del Pod Template (típicamente la imagen). En vez de matar todos los pods viejos y arrancar los nuevos a la vez (lo que causaría downtime), Kubernetes:

1. Crea **un ReplicaSet nuevo** con la imagen actualizada
2. Escala el RS nuevo de a poco hacia arriba
3. Escala el RS viejo de a poco hacia abajo
4. Repite hasta que el RS nuevo tenga el total de replicas y el viejo quede en 0

El RS viejo no se borra — queda en 0 replicas para poder hacer `rollout undo`.

```
Antes:      RS-old (nginx:1.16) ████████ 3 pods    RS-new (nginx:1.18) ░░░ 0 pods
Durante:    RS-old (nginx:1.16) ████░░░░ 2 pods    RS-new (nginx:1.18) █░░ 1 pod
Durante:    RS-old (nginx:1.16) ██░░░░░░ 1 pod     RS-new (nginx:1.18) ██░ 2 pods
Después:    RS-old (nginx:1.16) ░░░░░░░░ 0 pods    RS-new (nginx:1.18) ███ 3 pods (history)
```

### `maxSurge` y `maxUnavailable`: el ritmo del update

El ritmo del rolling update se controla con dos campos bajo `spec.strategy.rollingUpdate`:

| Campo            | Qué controla                                                                     | Default |
| ---------------- | -------------------------------------------------------------------------------- | ------- |
| `maxSurge`       | Cuántos pods **extra** puede crear arriba del total deseado durante el update    | `25%`   |
| `maxUnavailable` | Cuántos pods pueden estar **caídos** simultáneamente (debajo del total deseado)  | `25%`   |

Aceptan número absoluto (`1`, `2`) o porcentaje (`25%`, `50%`). Para 3 replicas con `25%`:
- `25% × 3 = 0.75` → redondea hacia arriba en surge (`1`), hacia abajo en unavailable (`0`... pero K8s lo trata como `1` en este caso por la regla "al menos 1")
- Durante el update el cluster puede tener entre **2 y 4 pods** corriendo

Para una app crítica con muchos replicas a veces se baja a `maxUnavailable: 0` y `maxSurge: 1` → cero downtime real, pero el update es más lento.

### `Deployment` → `ReplicaSet` → `Pod`: por qué importan las revisiones

Cada vez que cambiás algo del Pod Template, el Deployment crea **un ReplicaSet nuevo** con un `pod-template-hash` distinto. Por eso vas a ver pods como `nginx-deployment-fc677cbc9-9846v` (hash del RS viejo) y después `nginx-deployment-<otro-hash>-xxxxx` (hash del RS nuevo).

`kubectl rollout history` te muestra esa cadena de ReplicaSets — cada uno es una revisión. `kubectl rollout undo` no hace magia: simplemente escala al RS de la revisión anterior y baja el actual.

### Estrategias alternativas (`strategy.type`)

| Tipo            | Comportamiento                                                                                                          | Cuándo usarla                                                                |
| --------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `RollingUpdate` | Reemplazo gradual (default)                                                                                             | El 90% de los casos — apps stateless con health checks bien hechos           |
| `Recreate`      | Mata **todos** los pods viejos antes de crear los nuevos. Hay downtime, pero garantiza que jamás conviven dos versiones | Apps que no toleran dos versiones a la vez (típicamente migraciones de schema, locks exclusivos) |

## Pasos

1. Inspeccionar estado actual del Deployment (imagen, replicas, strategy)
2. Ejecutar el rolling update con `kubectl set image`
3. Monitorear el rollout con `kubectl rollout status`
4. Verificar que todos los pods tengan la nueva imagen
5. Revisar el historial con `kubectl rollout history`

## Comandos / Código

### 1. Estado inicial: nginx:1.16

```bash
kubectl get pods
```

```
NAME                               READY   STATUS    RESTARTS   AGE
nginx-deployment-fc677cbc9-9846v   1/1     Running   0          4m8s
nginx-deployment-fc677cbc9-q7s97   1/1     Running   0          4m8s
nginx-deployment-fc677cbc9-sp27v   1/1     Running   0          4m8s
```

```bash
kubectl describe deployment/nginx-deployment
```

```
Name:                   nginx-deployment
Namespace:              default
Labels:                 app=nginx-app
                        type=front-end
Annotations:            deployment.kubernetes.io/revision: 1
Selector:               app=nginx-app
Replicas:               3 desired | 3 updated | 3 total | 3 available | 0 unavailable
StrategyType:           RollingUpdate
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Labels:  app=nginx-app
  Containers:
   nginx-container:
    Image:         nginx:1.16
...
NewReplicaSet:   nginx-deployment-fc677cbc9 (3/3 replicas created)
```

Tres cosas importantes acá:

- El **container name** es `nginx-container` (no `nginx`) → es lo que hay que usar en `kubectl set image`
- `StrategyType: RollingUpdate` → no necesitamos cambiar la strategy, ya viene como queremos
- El RS actual es `nginx-deployment-fc677cbc9` (revisión `1`)

### 2. Ejecutar el rolling update

```bash
kubectl set image deployment/nginx-deployment nginx-container=nginx:1.18
```

```
deployment.apps/nginx-deployment image updated
```

Sintaxis general: `kubectl set image <resource>/<name> <container_name>=<new_image>`. Podés pasar varios pares `container=image` separados por espacios si el pod tiene múltiples contenedores.

> **Equivalentes:** los siguientes hacen lo mismo y todos disparan un rolling update:
>
> | Comando                                                                                          | Característica                                                            |
> | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------- |
> | `kubectl set image deployment/nginx-deployment nginx-container=nginx:1.18`                       | Imperativo, rápido, una sola línea                                        |
> | `kubectl edit deployment/nginx-deployment`                                                       | Abre $EDITOR con el YAML, editás `image:` a mano                          |
> | `kubectl apply -f deployment.yaml` (con `image: nginx:1.18` en el archivo)                       | Declarativo, ideal si el YAML está en git (GitOps)                        |
> | `kubectl patch deployment nginx-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx-container","image":"nginx:1.18"}]}}}}'` | Para automatización, no para tipeo humano |

### 3. Monitorear el rollout

```bash
kubectl rollout status deployment/nginx-deployment
```

```
deployment "nginx-deployment" successfully rolled out
```

Si lo corrés mientras está activo, mostraría líneas tipo `Waiting for deployment ... 1 out of 3 new replicas have been updated...`. Acá ya estaba terminado, por eso salió la línea final directamente.

Este comando es **bloqueante**: se queda esperando hasta que el rollout termina o falla. En CI/CD se usa como gate después de un deploy para confirmar éxito antes de seguir.

Si querés ver en vivo cómo entran y salen los pods:

```bash
kubectl get pods -w
```

Vas a ver cómo van apareciendo pods con un hash distinto (`nginx-deployment-<hash-nuevo>-xxxxx`) y desapareciendo los viejos.

### 4. Confirmar que el update terminó

```bash
kubectl get pods
```

```
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-79b79679fc-j5427   1/1     Running   0          9m14s
nginx-deployment-79b79679fc-k5clr   1/1     Running   0          9m20s
nginx-deployment-79b79679fc-rcktq   1/1     Running   0          9m15s
```

Los 3 pods ahora tienen el hash `79b79679fc` (del ReplicaSet nuevo). Compará con el inicial, donde todos tenían hash `fc677cbc9`. Esa diferencia de hash es la huella visible del rolling update.

Inspección completa del Deployment:

```bash
kubectl describe deployment/nginx-deployment
```

```
Name:                   nginx-deployment
Annotations:            deployment.kubernetes.io/revision: 2
Replicas:               3 desired | 3 updated | 3 total | 3 available | 0 unavailable
StrategyType:           RollingUpdate
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Containers:
   nginx-container:
    Image:         nginx:1.18
Conditions:
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
OldReplicaSets:  nginx-deployment-fc677cbc9 (0/0 replicas created)
NewReplicaSet:   nginx-deployment-79b79679fc (3/3 replicas created)
```

Tres detalles clave de este output:

- `revision: 2` — antes era `1`, ahora subió porque hicimos un cambio del Pod Template
- `OldReplicaSets: nginx-deployment-fc677cbc9 (0/0 replicas created)` — el RS viejo sigue ahí en cero replicas, listo para un `rollout undo`
- `NewReplicaSet: nginx-deployment-79b79679fc (3/3)` — el RS nuevo está al 100%

Para extraer solo la imagen actual (más estable que parsear `describe`):

```bash
kubectl get deployment nginx-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'
```

```
nginx:1.18
```

Para extraer solo el campo (más estable que parsear `describe`):

```bash
kubectl get deployment nginx-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'
```

```
nginx:1.18
```

### 5. Revisar el historial de revisiones

```bash
kubectl rollout history deployment/nginx-deployment
```

```
deployment.apps/nginx-deployment
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

Cada revisión corresponde a un ReplicaSet. La `1` es el RS `fc677cbc9` (nginx:1.16, ahora en 0 replicas) y la `2` es el RS `79b79679fc` (nginx:1.18, sirviendo tráfico).

Detalle de una revisión específica:

```bash
kubectl rollout history deployment/nginx-deployment --revision=2
```

```
Pod Template:
  Labels:       app=nginx-app
                pod-template-hash=79b79679fc
  Containers:
   nginx-container:
    Image:      nginx:1.18
```

> **Tip — `CHANGE-CAUSE`:** podés anotar cada update para que `rollout history` lo muestre, agregando la anotación `kubernetes.io/change-cause`:
>
> ```bash
> kubectl annotate deployment/nginx-deployment kubernetes.io/change-cause="Update to nginx 1.18 for CVE patches"
> ```
>
> Hacelo **después** del `set image`, no antes — la anotación viaja con la revisión actual.

### Cómo deshacer (si algo sale mal)

```bash
# Rollback a la revisión anterior (la 1, en este caso)
kubectl rollout undo deployment/nginx-deployment

# Rollback a una revisión específica
kubectl rollout undo deployment/nginx-deployment --to-revision=1
```

`undo` dispara otro rolling update — esta vez del RS nuevo al viejo. Lleva el mismo tiempo que el deploy original.

## Qué pasa por debajo durante el rolling update

Si corrés `kubectl get rs` mientras el update está en curso vas a ver **dos ReplicaSets coexistiendo**:

```
NAME                          DESIRED   CURRENT   READY   AGE
nginx-deployment-fc677cbc9    2         2         2       5m   ← el viejo bajando
nginx-deployment-79b79679fc   1         1         1       30s  ← el nuevo subiendo
```

### Cronograma real de este rolling update

La sección `Events` del describe registra cada movimiento de scale con timestamp. Para este rollout específico (3 replicas, `maxSurge=25%`, `maxUnavailable=25%`):

```
8m33s   Scaled up   replica set nginx-deployment-79b79679fc   from 0 to 1
8m28s   Scaled down replica set nginx-deployment-fc677cbc9    from 3 to 2
8m28s   Scaled up   replica set nginx-deployment-79b79679fc   from 1 to 2
8m27s   Scaled down replica set nginx-deployment-fc677cbc9    from 2 to 1
8m27s   Scaled up   replica set nginx-deployment-79b79679fc   from 2 to 3
8m26s   Scaled down replica set nginx-deployment-fc677cbc9    from 1 to 0
```

Lo que muestra esto:

- **El primer surge va solo** (`8m33s`): K8s sube el nuevo RS de 0 a 1 sin tocar el viejo. Hay 4 pods totales durante 5 segundos.
- **A partir del segundo `8m28s` los pares van juntos**: scale-down del viejo + scale-up del nuevo en el mismo timestamp. Esto solo pasa cuando el primer pod nuevo ya está `Ready` — ahí K8s gana confianza para mover los pares en paralelo.
- **Duración total: ~7 segundos** (8m33s → 8m26s). El rolling update completo de 3 pods de nginx es casi instantáneo porque la imagen ya estaba cacheada en el nodo y nginx arranca rápido. Una app Java o un container con muchas migraciones podría tardar minutos.

El gating en cada paso es el **readiness probe**: si el pod nuevo nunca queda `Ready`, el rollout se traba (no avanza, no rompe). Por eso tener readiness probes bien configuradas es lo que hace seguro al rolling update — sin ellas, Kubernetes asume `Ready=true` apenas el proceso arranca, y podés terminar reemplazando pods sanos por pods rotos sin darte cuenta.

> **Detalle a notar en este lab:** el Deployment **no tiene readiness probe configurado** (mirá el `Pod Template` en el describe — no aparece ningún `Readiness` ni `Liveness`). Por eso el update fue tan rápido: K8s consideró cada pod `Ready` apenas arrancó, sin verificar nada. En producción esto sería riesgoso — para nginx serviría algo tipo `httpGet /` en el puerto 80.

## Troubleshooting

| Problema                                                                            | Causa y solución                                                                                                                                          |
| ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `error: unable to find container named "nginx"`                                     | El nombre del contenedor en el Pod Template no es `nginx` sino `nginx-container`. Verificar con `kubectl describe deployment <name>` antes de hacer `set image` |
| `rollout status` se queda colgado en `Waiting for rollout to finish`                | El pod nuevo no está pasando readiness. Inspeccionar con `kubectl describe pod <pod-nuevo>` y `kubectl logs <pod-nuevo>` — típicamente probe falla o imagen no se encuentra |
| Pods nuevos en `ImagePullBackOff`                                                   | El tag de la imagen no existe en el registry (typo, o nunca se pusheó). El RS viejo sigue sirviendo tráfico — Kubernetes no mata pods sanos por pods rotos. Corregir la imagen y volver a `set image` |
| Rolling update aparenta éxito pero la app se rompió                                 | La readiness probe es demasiado permisiva (ej: solo chequea que el puerto esté abierto, no que la app responda). Mejorar el probe — el rolling update es solo tan seguro como el probe |
| `rollout history` muestra `CHANGE-CAUSE: <none>`                                    | Nadie anotó la revisión. Usar `kubectl annotate deployment/... kubernetes.io/change-cause="..."` después de cada cambio importante                       |
| Necesitás pausar un rollout a mitad de camino para validar                          | `kubectl rollout pause deployment/<name>` — congela el estado actual (típicamente con un mix de pods viejos y nuevos). Reanudar con `kubectl rollout resume` |

## Recursos

- [Performing a Rolling Update (tutorial oficial)](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)
- [Deployments — Rolling Update strategy (oficial)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment)
- [`kubectl rollout` reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout)
- [Pod Readiness y rollouts (oficial)](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-readiness-gate)
