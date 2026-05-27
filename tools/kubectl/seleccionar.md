# kubectl · Seleccionar componentes

Cómo identificar y filtrar Pods, Deployments, containers, namespaces y cualquier recurso del cluster. Esta es la parte que transforma kubectl de "listador" a "lenguaje de consulta".

## Tipos de recursos y sus shortnames

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

## Por nombre directo (lo más común)

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

## Por label selector (`-l` / `--selector`)

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

> **Diferencia importante:** `-l` selecciona los recursos a operar; **NO** edita las labels. Para cambiar labels usar `kubectl label` (ver [Editar componentes](editar.md)).

## Por field selector (`--field-selector`)

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

> **Limitación:** field selector tiene una lista finita de campos soportados (definida por la API). Para filtrar por algo arbitrario, usar `-o jsonpath` con `grep` o `jq`.

## Por namespace (`-n` / `-A`)

```bash
# Recursos en un namespace específico
kubectl get pods -n kube-system

# TODOS los namespaces
kubectl get pods -A
kubectl get pods --all-namespaces

# Cambiar el namespace default de la sesión (kubectx/kubens son atajos)
kubectl config set-context --current --namespace=mi-namespace
```

## Múltiples tipos a la vez

```bash
# Listar varios tipos en un solo comando (lista separada por comas, SIN espacios)
kubectl get pods,services,deployments

# Todo lo "common" en el namespace actual
kubectl get all

# all NO incluye configmaps, secrets, pvc, ingress — hay que pedirlos aparte
kubectl get all,cm,secrets,pvc,ingress
```

## Containers dentro de un Pod multi-container (`-c`)

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

## Output formats (`-o`)

Esto es lo que transforma kubectl de "listador" a "lenguaje de consulta". Los más útiles:

| Formato                      | Para qué sirve                                                                            |
| ---------------------------- | ----------------------------------------------------------------------------------------- |
| `-o wide`                    | Tabla normal + columnas extra (IP, nodo, etc.)                                            |
| `-o yaml` / `-o json`        | Dump completo del recurso — útil para hacer `> archivo.yaml` y editar                     |
| `-o name`                    | Solo `kind/name` — ideal para pipes a otros `kubectl`                                     |
| `-o jsonpath='{...}'`        | Extraer un campo específico (estable para scripts)                                        |
| `-o custom-columns=...`      | Tabla con columnas custom                                                                 |
| `-o go-template='{{...}}'`   | Como jsonpath pero con sintaxis de Go templates (más potente)                             |

### Ejemplos de `jsonpath` (lo más útil en práctica)

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

## Watching (`-w`)

```bash
# Stream de cambios en pods
kubectl get pods -w

# Watching con events incluidos (útil para diagnóstico)
kubectl get pods -w --output-watch-events
```

## Descubrir la estructura de un recurso (`kubectl explain`)

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

## Eventos del cluster (`kubectl events`)

Disponible desde K8s 1.27 (stable). Reemplaza el viejo `kubectl get events --sort-by='.lastTimestamp'`.

```bash
# Eventos del namespace actual
kubectl events

# Eventos de un recurso específico (y sus hijos: Pod, RS si es Deployment)
kubectl events deployment/my-app
kubectl events pod/my-pod
```

Útil cuando un Pod no arranca y se necesita el timeline cronológico de lo que pasó: scheduling, pulls, mounts fallidos, restarts.

## Troubleshooting

| Problema                                                          | Causa                                                                           | Solución                                                                                          |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `kubectl get pods` no muestra nada                                | Estás en el namespace equivocado                                                | Agregar `-n <namespace>` o `-A` para ver todos                                                    |
| `error: container name must be specified for pod ...`             | Pod multi-container y no especificaste cuál                                     | Agregar `-c <container-name>`                                                                     |
| `-l app=nginx` no devuelve nada de lo esperado                    | Typo en el label o case mismatch (los labels son case-sensitive)                | `kubectl get <resource> --show-labels` para ver los labels reales                                 |
| `--field-selector` falla con "field label not supported"          | El campo no está en la lista de fields soportados por la API                    | Usar `-o jsonpath` + `grep` / `jq` en su lugar                                                    |
| `jsonpath` no devuelve nada                                       | El path está mal o el campo no existe en este recurso                            | Validar con `kubectl get <resource> <name> -o yaml` y armar el jsonpath desde ahí                 |
| `kubectl logs` solo muestra el primer container                   | Comportamiento default cuando hay multi-container                                | Especificar `-c <container>` o usar `--all-containers=true`                                       |

## Recursos

- [Labels and Selectors (oficial)](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Field Selectors (oficial)](https://kubernetes.io/docs/concepts/overview/working-with-objects/field-selectors/)
- [JSONPath Support (oficial)](https://kubernetes.io/docs/reference/kubectl/jsonpath/)
- [`kubectl events` command (K8s 1.27+)](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_events/)
