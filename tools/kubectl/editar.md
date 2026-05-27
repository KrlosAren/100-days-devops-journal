# kubectl · Editar componentes

Cómo modificar recursos que ya están en el cluster. Hay varios caminos según si se requiere un cambio puntual interactivo, un cambio versionado en git, un cambio quirúrgico de un solo campo, o un atajo imperativo para una operación común.

## Tabla de decisión: cuándo usar cada método

| Quiero hacer...                                              | Comando recomendado                                          | Tipo            |
| ------------------------------------------------------------ | ------------------------------------------------------------ | --------------- |
| Cambiar la imagen de un Deployment                           | `kubectl set image`                                          | Imperativo      |
| Cambiar replicas de un Deployment                            | `kubectl scale`                                              | Imperativo      |
| Cambiar env vars de un Deployment                            | `kubectl set env`                                            | Imperativo      |
| Cambiar resources (CPU/RAM) de un Deployment                 | `kubectl set resources`                                      | Imperativo      |
| Cambio arbitrario con archivo YAML versionado en git         | `kubectl apply -f`                                           | Declarativo     |
| Cambio rápido "a mano" del manifest                          | `kubectl edit`                                               | Interactivo     |
| Cambio quirúrgico de UN solo campo (automatización)          | `kubectl patch`                                              | Programático    |
| Cambiar un campo **inmutable** de un Pod stand-alone         | `kubectl replace --force` o `delete + apply`                 | Destructivo     |
| Agregar/cambiar un label en recursos existentes              | `kubectl label`                                              | Especializado   |
| Agregar/cambiar una annotation                               | `kubectl annotate`                                           | Especializado   |
| Rollback de un Deployment                                    | `kubectl rollout undo`                                       | Especializado   |

## `kubectl edit` — Edición interactiva

Abre `$EDITOR` con el YAML actual del recurso. Al guardar, K8s aplica el diff.

```bash
kubectl edit deployment my-app
kubectl edit configmap nginx-config
kubectl edit pod nginx-pod                  # ⚠️ campos inmutables fallarán
```

**Cuándo usarlo:** cambios puntuales, exploratorios, en desarrollo. No queda traza en git — para producción usar `apply` con archivos versionados.

**Variantes:**

```bash
# Forzar un editor distinto al default
KUBE_EDITOR=nano kubectl edit deployment my-app

# Editar a partir de un output específico (JSON vs YAML)
kubectl edit -o json deployment my-app
```

## `kubectl apply` — Declarativo (la forma "seria")

Lee un YAML y reconcilia el estado del cluster con él. Si el recurso no existe, lo crea. Si existe, hace merge inteligente.

```bash
# Aplicar un archivo
kubectl apply -f deployment.yaml

# Un directorio entero (todos los .yaml/.json adentro)
kubectl apply -f ./manifests/

# Recursivo
kubectl apply -f ./manifests/ -R

# Desde stdin (típico en pipes)
cat deployment.yaml | kubectl apply -f -

# Con dry-run para preview
kubectl apply -f deployment.yaml --dry-run=server
kubectl apply -f deployment.yaml --dry-run=client -o yaml

# Diff antes de aplicar (muy útil)
kubectl diff -f deployment.yaml
```

**Cuándo usarlo:** siempre que el manifest esté en git (GitOps). Es la forma idiomática y el estado deseado queda versionado.

> **`apply` vs `create`:** `kubectl create` falla si el recurso ya existe. `kubectl apply` lo crea **o** lo actualiza. Para CI/CD siempre `apply`.

> **Apply con múltiples recursos**: si un archivo tiene varios documentos (`---` entre ellos), `apply` los procesa **uno por uno** y reporta errores individualmente. Recursos válidos se crean aunque otros del mismo archivo fallen. Hay que validar con `kubectl get` después.

## `kubectl patch` — Cambio quirúrgico de un campo

Tres modos: `--type=strategic` (default), `--type=merge`, `--type=json`.

```bash
# Strategic merge patch (el más común, entiende la estructura de K8s)
kubectl patch deployment my-app \
  -p '{"spec":{"replicas":5}}'

# JSON merge patch (RFC 7396)
kubectl patch deployment my-app \
  --type=merge \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","image":"app:v2"}]}}}}'

# JSON patch (RFC 6902) — más explícito, op-by-op
kubectl patch deployment my-app \
  --type=json \
  -p='[{"op":"replace","path":"/spec/replicas","value":3}]'
```

**Cuándo usarlo:** en scripts y CI donde se necesita cambiar UN campo específico sin tocar el resto. Es lo que usan los operators bajo el capó.

## `kubectl set <subcomando>` — Atajos imperativos

Para los cambios más comunes hay subcomandos que evitan tener que armar un JSON patch a mano.

```bash
# Cambiar la imagen de un container en un Deployment
kubectl set image deployment/my-app my-container=my-image:v2

# Múltiples imágenes a la vez (varios containers)
kubectl set image deployment/my-app c1=img1:v2 c2=img2:v2

# Cambiar env vars
kubectl set env deployment/my-app DB_HOST=postgres LOG_LEVEL=debug

# Quitar una env var
kubectl set env deployment/my-app DB_HOST-

# Cambiar resources (requests/limits)
kubectl set resources deployment/my-app --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=512Mi

# Cambiar serviceaccount
kubectl set serviceaccount deployment/my-app my-sa
```

Todos disparan un rolling update automáticamente.

## `kubectl replace` y `kubectl replace --force`

`kubectl replace -f` reemplaza el recurso completo por lo que dice el archivo. Sin `--force`, falla si el recurso tiene campos inmutables que difieren.

`--force` hace `delete + create`, lo que sí permite cambiar campos inmutables (al costo de "matar y recrear").

```bash
# Reemplazar sin force (falla en campos inmutables)
kubectl replace -f pod.yaml

# Reemplazar con force (delete + create)
kubectl replace --force -f pod.yaml
```

**Cuándo usarlo:** casi siempre solo para **Pods stand-alone** (no creados por un Deployment) cuando se necesita cambiar `volumeMounts`, `containers`, etc. Para Deployments/StatefulSets se edita la template y el controller hace todo solo.

## `kubectl scale` — Especializado para replicas

```bash
# Subir o bajar replicas
kubectl scale deployment/my-app --replicas=5
kubectl scale statefulset/my-db --replicas=3

# Condicional (solo si actualmente tiene 3 replicas)
kubectl scale deployment/my-app --current-replicas=3 --replicas=5

# Por label selector (múltiples Deployments a la vez)
kubectl scale deployment -l tier=frontend --replicas=10
```

## `kubectl label` y `kubectl annotate`

```bash
# Agregar/cambiar un label
kubectl label pod my-pod env=prod
kubectl label pod my-pod env=staging --overwrite        # cambiar valor existente
kubectl label pod my-pod env-                            # eliminar el label

# Aplicar a múltiples con selector
kubectl label pods -l app=nginx tier=frontend

# Annotations: igual sintaxis
kubectl annotate deployment my-app kubernetes.io/change-cause="Update for CVE-2024-XXXX"
kubectl annotate pod my-pod description=temp --overwrite
```

## `kubectl rollout` — Deployments / StatefulSets / DaemonSets

```bash
# Ver estado del rollout actual
kubectl rollout status deployment/my-app

# Pausar / reanudar
kubectl rollout pause deployment/my-app
kubectl rollout resume deployment/my-app

# Reiniciar todos los pods (rolling restart sin cambiar nada)
kubectl rollout restart deployment/my-app

# Historial y rollback
kubectl rollout history deployment/my-app
kubectl rollout undo deployment/my-app
kubectl rollout undo deployment/my-app --to-revision=3
```

`kubectl rollout restart` es especialmente útil tras cambiar un ConfigMap o Secret cuando se necesita que los pods recarguen — ver siguiente sección.

## Casos especiales y trampas comunes

### ConfigMaps y Secrets: el cambio NO se propaga solo

Al cambiar un ConfigMap (`kubectl edit cm nginx-config`), los pods que lo tienen montado **no se enteran automáticamente**:

- Si está montado como **volumen**: el archivo eventualmente se actualiza (puede tardar minutos), pero la app no sabe que cambió → muchas apps necesitan reload
- Si está montado como **env var**: el cambio NO se propaga nunca al pod existente

Soluciones:

```bash
# Opción A: forzar un rolling restart del deployment
kubectl rollout restart deployment/my-app

# Opción B: matar los pods, que el controller los recree
kubectl delete pod -l app=my-app

# Opción C (app-specific): pedirle a la app que recargue
kubectl exec my-pod -- nginx -s reload
```

### Pods stand-alone: muchos campos son inmutables

Para un Pod creado directamente (no por un Deployment), los siguientes campos NO se pueden editar:

- `spec.containers[].image` (solo se puede cambiar vía la API, no con `kubectl edit`)
- `spec.containers[].volumeMounts`
- `spec.containers[].resources`
- `spec.volumes`
- `spec.nodeName`

Para cambiarlos hay que `delete + create` (o `kubectl replace --force`).

> **Por eso casi nunca se crean Pods stand-alone en producción** — un Deployment te abstrae esto: editás la template del Deployment y el RS controller recrea los pods automáticamente con el spec nuevo.

### Campos que SÍ son mutables en un Pod

- Labels y annotations
- `spec.activeDeadlineSeconds`
- `spec.tolerations` (solo agregar, no remover)
- Status (lo escribe el kubelet, pero técnicamente se puede patchear)

### `edit` desaparece tu cambio al rato

Si hay un controller (ArgoCD, Flux) reconciliando contra un repo, tu `kubectl edit` será **sobrescrito** la próxima vez que el controller corra. El fix debe hacerse en el repo de manifests, no con `edit`.

## Cheatsheet rápido

```bash
kubectl edit deployment my-app                      # Interactivo
kubectl apply -f manifest.yaml                      # Declarativo
kubectl set image deployment/my-app c=img:v2        # Cambiar imagen
kubectl set env deployment/my-app KEY=value         # Cambiar env vars
kubectl scale deployment/my-app --replicas=5        # Cambiar replicas
kubectl patch deployment my-app -p '{"spec":...}'   # Quirúrgico
kubectl replace --force -f pod.yaml                 # Reemplazo destructivo
kubectl label pod my-pod env=prod                   # Labels
kubectl annotate ... kubernetes.io/change-cause=... # Annotations
kubectl rollout restart deployment/my-app           # Forzar recrear pods
kubectl rollout undo deployment/my-app              # Rollback
kubectl delete pod my-pod                           # Borrar (el controller lo recrea si aplica)
```

## Recursos

- [Declarative Management of Kubernetes Objects (oficial)](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
- [Update API Objects (oficial)](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/)
- [Rolling Updates (oficial)](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)
