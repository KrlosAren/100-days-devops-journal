# kubectl — Guía: seleccionar y editar componentes

`kubectl` es la interfaz universal con un cluster de Kubernetes. Todo comando tiene la forma:

```
kubectl <verbo> <recurso> [<selector>] [opciones]
```

Esta guía cubre las dos preguntas que aparecen todo el tiempo:

1. **¿Cómo selecciono lo que quiero ver / tocar?** (pods, deployments, configmaps, containers dentro de pods, etc.)
2. **¿Cómo edito lo que ya está corriendo?** (cambiar imagen, replicas, env vars, etc.)

---

## Parte 1 · Seleccionar componentes

### Tipos de recursos y sus shortnames

Casi todos los recursos tienen un alias corto que ahorra tipeo. Lista completa con `kubectl api-resources`:

| Recurso (largo)         | Shortname    | Ejemplo                                 |
| ----------------------- | ------------ | --------------------------------------- |
| `pods`                  | `po`         | `kubectl get po`                        |
| `deployments`           | `deploy`     | `kubectl get deploy`                    |
| `replicasets`           | `rs`         | `kubectl get rs`                        |
| `services`              | `svc`        | `kubectl get svc`                       |
| `configmaps`            | `cm`         | `kubectl get cm`                        |
| `secrets`               | (sin alias)  | `kubectl get secrets`                   |
| `namespaces`            | `ns`         | `kubectl get ns`                        |
| `persistentvolumes`     | `pv`         | `kubectl get pv`                        |
| `persistentvolumeclaims`| `pvc`        | `kubectl get pvc`                       |
| `ingresses`             | `ing`        | `kubectl get ing`                       |
| `daemonsets`            | `ds`         | `kubectl get ds`                        |
| `statefulsets`          | `sts`        | `kubectl get sts`                       |
| `cronjobs`              | `cj`         | `kubectl get cj`                        |
| `nodes`                 | `no`         | `kubectl get no`                        |

> **Tip de descubrimiento:** `kubectl api-resources --verbs=list -o name` lista todos los recursos consultables del cluster, incluidos CRDs instalados.

### 1.1 Por nombre directo (lo más común)

```bash
# Un recurso específico
kubectl get pod nginx-pod
kubectl get deployment my-app
kubectl describe configmap nginx-config

# Múltiples nombres del mismo tipo
kubectl get pod nginx-pod httpd-pod

# Recurso + tipo en un solo argumento (formato resource/name)
kubectl describe deployment/my-app
kubectl logs pod/nginx-pod
```

### 1.2 Por label selector (`-l` / `--selector`)

Los labels son **el mecanismo principal** de Kubernetes para agrupar recursos. Un Deployment encuentra sus Pods por labels, un Service rutea tráfico por labels, etc.

```bash
# Todos los pods con label app=nginx
kubectl get pods -l app=nginx

# Match múltiple (AND): ambas labels deben coincidir
kubectl get pods -l app=nginx,tier=frontend

# Operadores avanzados (comilla simple, sintaxis "set-based")
kubectl get pods -l 'env in (prod,staging)'
kubectl get pods -l 'env notin (dev)'
kubectl get pods -l 'tier!=cache'
kubectl get pods -l 'app'                  # existe el label (cualquier valor)
kubectl get pods -l '!app'                 # no tiene el label

# Combinar con otros selectores
kubectl get pods -l app=nginx -o wide
kubectl delete pods -l app=temporary       # ⚠️ borrado masivo por label
```

> **Diferencia importante:** `-l` selecciona los recursos a operar; **NO** edita las labels. Para cambiar labels usar `kubectl label` (ver parte 2).

### 1.3 Por field selector (`--field-selector`)

Para filtrar por campos del recurso que NO son labels (típicamente `status.phase`, `metadata.name`, `spec.nodeName`):

```bash
# Pods que están corriendo
kubectl get pods --field-selector status.phase=Running

# Pods que NO están corriendo (Failed, Pending, Succeeded)
kubectl get pods --field-selector status.phase!=Running

# Pods en un nodo específico
kubectl get pods --field-selector spec.nodeName=worker-1

# Casos útiles: encontrar pods evictados acumulados
kubectl get pods --all-namespaces --field-selector status.phase=Failed
```

> **Limitación:** field selector tiene una lista finita de campos soportados (definida por la API). Si querés filtrar por algo arbitrario, usá `-o jsonpath` con `grep` o `jq`.

### 1.4 Por namespace (`-n` / `-A`)

```bash
# Recursos en un namespace específico
kubectl get pods -n kube-system

# TODOS los namespaces
kubectl get pods -A
kubectl get pods --all-namespaces

# Cambiar el namespace default de la sesión (kubectx/kubens son atajos)
kubectl config set-context --current --namespace=mi-namespace
```

### 1.5 Múltiples tipos a la vez

```bash
# Listar varios tipos en un solo comando (lista separada por comas, SIN espacios)
kubectl get pods,services,deployments

# Todo lo "common" en el namespace actual
kubectl get all

# all NO incluye configmaps, secrets, pvc, ingress — hay que pedirlos aparte
kubectl get all,cm,secrets,pvc,ingress
```

### 1.6 Containers dentro de un Pod multi-container (`-c`)

Cuando un Pod tiene varios containers (sidecar, init, etc.), muchos verbos necesitan especificar cuál:

```bash
# Logs de un container específico
kubectl logs nginx-phpfpm -c nginx-container
kubectl logs nginx-phpfpm -c php-fpm-container

# Exec en un container específico
kubectl exec -it nginx-phpfpm -c php-fpm-container -- sh

# Copiar archivos a un container específico
kubectl cp ./index.php nginx-phpfpm:/var/www/html/index.php -c nginx-container

# Init containers
kubectl logs nginx-phpfpm -c init-volume
```

> Sin `-c`, kubectl usa el **primer container** del Pod (el que aparece primero en `spec.containers`). En logs te muestra una advertencia si hay varios; en `exec` falla con `error: container name must be specified`.

### 1.7 Output formats (`-o`)

Esto es lo que transforma kubectl de "listador" a "lenguaje de consulta". Los más útiles:

| Formato                      | Para qué sirve                                                                            |
| ---------------------------- | ----------------------------------------------------------------------------------------- |
| `-o wide`                    | Tabla normal + columnas extra (IP, nodo, etc.)                                            |
| `-o yaml` / `-o json`        | Dump completo del recurso — útil para hacer `> archivo.yaml` y editar                     |
| `-o name`                    | Solo `kind/name` — ideal para pipes a otros `kubectl`                                     |
| `-o jsonpath='{...}'`        | Extraer un campo específico (estable para scripts)                                        |
| `-o custom-columns=...`      | Tabla con columnas custom                                                                 |
| `-o go-template='{{...}}'`   | Como jsonpath pero con sintaxis de Go templates (más potente)                             |

#### Ejemplos de `jsonpath` (lo más útil en práctica)

```bash
# La imagen actual de un Deployment
kubectl get deployment nginx -o jsonpath='{.spec.template.spec.containers[0].image}'

# Todos los nombres de pod
kubectl get pods -o jsonpath='{.items[*].metadata.name}'

# IP de cada pod (más legible con \n)
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'

# QoS class de un pod
kubectl get pod httpd-pod -o jsonpath='{.status.qosClass}'

# Imagen + tag + nodo de cada pod
kubectl get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,NODE:.spec.nodeName
```

> **Por qué jsonpath > grep:** parsear `describe` con `grep` se rompe entre versiones de kubectl (cambian el formato). `jsonpath` lee directo del API server, es estable y composable.

### 1.8 Watching (`-w`)

```bash
# Stream de cambios en pods
kubectl get pods -w

# Watching con events incluidos (útil para diagnóstico)
kubectl get pods -w --output-watch-events
```

### 1.9 Descubrir la estructura de un recurso (`kubectl explain`)

```bash
# Ver los campos top-level
kubectl explain pod

# Ver subcampos (nested)
kubectl explain pod.spec
kubectl explain pod.spec.containers
kubectl explain pod.spec.containers.resources

# Con --recursive ves todo el árbol
kubectl explain pod.spec --recursive
```

Es el reemplazo en vivo de "ir a la doc de Kubernetes" — funciona offline, está siempre en sync con la versión de tu cluster, y muestra qué campos son obligatorios y cuáles opcionales.

---

## Parte 2 · Editar componentes

### 2.0 Tabla de decisión: cuándo usar cada método

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

### 2.1 `kubectl edit` — Edición interactiva

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

### 2.2 `kubectl apply` — Declarativo (la forma "seria")

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

### 2.3 `kubectl patch` — Cambio quirúrgico de un campo

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

**Cuándo usarlo:** en scripts y CI donde necesitás cambiar UN campo específico sin tocar el resto. Es lo que usan los operators bajo el capó.

### 2.4 `kubectl set <subcomando>` — Atajos imperativos

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

### 2.5 `kubectl replace` y `kubectl replace --force`

`kubectl replace -f` reemplaza el recurso completo por lo que dice el archivo. Sin `--force`, falla si el recurso tiene campos inmutables que difieren.

`--force` hace `delete + create`, lo que sí permite cambiar campos inmutables (al costo de "matar y recrear").

```bash
# Reemplazar sin force (falla en campos inmutables)
kubectl replace -f pod.yaml

# Reemplazar con force (delete + create)
kubectl replace --force -f pod.yaml
```

**Cuándo usarlo:** casi siempre solo para **Pods stand-alone** (no creados por un Deployment) cuando necesitás cambiar `volumeMounts`, `containers`, etc. Para Deployments/StatefulSets se edita la template y el controller hace todo solo.

### 2.6 `kubectl scale` — Especializado para replicas

```bash
# Subir o bajar replicas
kubectl scale deployment/my-app --replicas=5
kubectl scale statefulset/my-db --replicas=3

# Condicional (solo si actualmente tiene 3 replicas)
kubectl scale deployment/my-app --current-replicas=3 --replicas=5

# Por label selector (múltiples Deployments a la vez)
kubectl scale deployment -l tier=frontend --replicas=10
```

### 2.7 `kubectl label` y `kubectl annotate`

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

### 2.8 `kubectl rollout` — Especializado para Deployments / StatefulSets / DaemonSets

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

`kubectl rollout restart` es especialmente útil cuando cambiaste un ConfigMap o Secret y necesitás que los pods recarguen — ver siguiente sección.

### 2.9 Casos especiales y trampas comunes

#### ConfigMaps y Secrets: el cambio NO se propaga solo

Si cambiás un ConfigMap (`kubectl edit cm nginx-config`), los pods que lo tienen montado **no se enteran automáticamente**:

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

#### Pods stand-alone: muchos campos son inmutables

Para un Pod creado directamente (no por un Deployment), los siguientes campos NO se pueden editar:

- `spec.containers[].image` (solo se puede cambiar vía la API, no con `kubectl edit`)
- `spec.containers[].volumeMounts`
- `spec.containers[].resources`
- `spec.volumes`
- `spec.nodeName`

Para cambiarlos hay que `delete + create` (o `kubectl replace --force`).

> **Por eso casi nunca se crean Pods stand-alone en producción** — un Deployment te abstrae esto: editás la template del Deployment y el RS controller recrea los pods automáticamente con el spec nuevo.

#### Campos que SÍ son mutables en un Pod

- Labels y annotations
- `spec.activeDeadlineSeconds`
- `spec.tolerations` (solo agregar, no remover)
- Status (lo escribe el kubelet, pero técnicamente se puede patchear)

---

## Cheatsheet rápido

```bash
# === SELECCIÓN ===
kubectl get pod <name>                              # Por nombre
kubectl get pods -l app=nginx                       # Por label
kubectl get pods -n kube-system                     # En un namespace
kubectl get pods -A                                 # Todos los namespaces
kubectl get pods --field-selector status.phase=Failed  # Por field
kubectl get pods,svc,cm                             # Múltiples tipos
kubectl logs my-pod -c my-container                 # Container específico
kubectl get pod my-pod -o jsonpath='{.status.podIP}' # Campo específico
kubectl explain deployment.spec.strategy            # Documentación

# === EDICIÓN ===
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

- [`kubectl` Cheat Sheet (oficial)](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Commands reference (oficial)](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands)
- [Labels and Selectors (oficial)](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [JSONPath Support (oficial)](https://kubernetes.io/docs/reference/kubectl/jsonpath/)
- [Declarative Management of Kubernetes Objects (oficial)](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
