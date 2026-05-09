# Día 49 - Desplegar Aplicaciones con Deployments en Kubernetes

## Problema / Desafío

El equipo de Nautilus necesita crear un Deployment con estos requisitos:

- **Nombre del Deployment:** `httpd`
- **Imagen:** `httpd:latest` (con el tag explícito)

`kubectl` ya está configurado en el `jump-host`.

## Conceptos clave

### ¿Por qué un Deployment y no un Pod?

Un Pod por sí solo es **frágil**: si muere (crash, eviction, falla de nodo), nadie lo recrea. Un Deployment agrega una capa de gestión que aporta:

- **Self-healing:** si un pod gestionado se cae, el controlador lo recrea automáticamente
- **Escalado declarativo:** subir/bajar réplicas con `kubectl scale --replicas=N` o cambiando el manifest
- **Rolling updates:** actualizar la imagen sin downtime, reemplazando pods de a poco
- **Rollbacks:** volver a una revisión anterior con `kubectl rollout undo`
- **Histórico de revisiones:** Kubernetes guarda las versiones previas del Deployment

Para cualquier app stateless en producción, lo correcto es Deployment. El Pod suelto se usa para debugging y labs.

### La cadena: Deployment → ReplicaSet → Pod

Un Deployment **no gestiona pods directamente**. Crea un **ReplicaSet**, y el ReplicaSet es quien mantiene N pods vivos:

```
Deployment (httpd)
   └── ReplicaSet (httpd-7b5f9d) ← creado automáticamente; tiene un sufijo hash de la spec.template
         ├── Pod (httpd-7b5f9d-abc12)
         └── Pod (httpd-7b5f9d-xyz34) ... etc.
```

Cada vez que cambias el `spec.template` del Deployment (por ejemplo, una imagen nueva), Kubernetes crea un **ReplicaSet nuevo** y va escalando el viejo a 0 mientras el nuevo sube a N. Eso es el rolling update.

Si solo cambias `spec.replicas`, no se crea un nuevo ReplicaSet — el existente solo escala arriba o abajo.

### Workloads hermanos: cuándo NO usar Deployment

Es fácil confundir Deployment con sus primos. Cada uno tiene un caso de uso distinto:

| Workload          | Cuántas réplicas         | Identidad     | Storage       | Uso típico                                        |
| ----------------- | ------------------------ | ------------- | ------------- | ------------------------------------------------- |
| **Deployment**    | N (lo que pidas)         | Intercambiable| Efímero       | Apps stateless (web, API, frontends)              |
| **DaemonSet**     | Una **por nodo**         | Por nodo      | Efímero       | Agentes: log shippers, node exporters, CNI       |
| **StatefulSet**   | N con orden estable      | Estable       | Persistente   | Databases, brokers (Kafka), apps con identidad    |
| **Job / CronJob** | Una vez (o programada)   | Efímera       | Efímero       | Tareas batch, migraciones, backups                |

Un Deployment no garantiza un pod por nodo (eso es DaemonSet) ni identidad estable (eso es StatefulSet).

### Las 3 secciones críticas del manifest

```yaml
spec:
  replicas: 1                # Cuántos pods quieres vivos en simultáneo
  selector:                  # Cómo el Deployment encuentra "sus" pods
    matchLabels:
      app: httpd
  template:                  # La "receta" — un PodSpec completo embebido
    metadata:
      labels:
        app: httpd           # ⚠ DEBE matchear el selector.matchLabels
    spec:
      containers: [...]
```

**Regla crítica:** los labels en `template.metadata.labels` deben **incluir todo** lo que está en `selector.matchLabels`. Si no, el API server rechaza el manifest con `selector does not match template labels`. Esto evita que el Deployment quede "huérfano" sin pods que manejar.

> El selector es, además, **inmutable** una vez creado el Deployment. Cambiarlo después requiere borrar y recrear el recurso.

### `apiVersion: apps/v1` (no `v1`)

A diferencia de un Pod (`apiVersion: v1`), un Deployment vive bajo el grupo `apps`. La razón es histórica: los recursos "core" (Pod, Service, ConfigMap, Secret, Namespace) se mantuvieron en `v1`, y los workloads de alto nivel (Deployment, ReplicaSet, StatefulSet, DaemonSet) se movieron a `apps/v1` cuando estabilizaron en Kubernetes 1.9.

Si pones `apiVersion: v1` en un Deployment, kubectl te dice: `no matches for kind "Deployment" in version "v1"`.

## Pasos

1. Escribir el manifest `deployment.yml`
2. Validar la indentación con `kubectl apply --dry-run=client -f`
3. Aplicar con `kubectl apply -f deployment.yml`
4. Verificar la cadena Deployment → ReplicaSet → Pod
5. Demostrar self-healing eliminando un pod manualmente

## Comandos / Código

### Solución utilizada

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpd
  labels:
    app: httpd
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpd
  template:
    metadata:
      labels:
        app: httpd
    spec:
      containers:
        - name: httpd
          image: httpd:latest
```

```bash
kubectl apply -f deployment.yml
```

```
deployment.apps/httpd created
```

### Verificar la cadena Deployment → ReplicaSet → Pod

```bash
# 1. El Deployment de alto nivel
kubectl get deployment httpd
```

```
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
httpd   1/1     1            1           10s
```

- **READY 1/1** → 1 pod listo de 1 deseado
- **UP-TO-DATE** → cuántos pods están en la versión más reciente del template
- **AVAILABLE** → cuántos pasaron el `minReadySeconds` y se consideran estables

```bash
# 2. El ReplicaSet que el Deployment creó automáticamente
kubectl get rs -l app=httpd
```

```
NAME               DESIRED   CURRENT   READY   AGE
httpd-6c755866c7   1         1         1       10s
```

El sufijo `-6c755866c7` es un hash de la `spec.template` — sirve para distinguir ReplicaSets de versiones distintas durante un rollout.

```bash
# 3. El pod que el ReplicaSet creó
kubectl get pods -l app=httpd
```

```
NAME                     READY   STATUS    RESTARTS   AGE
httpd-6c755866c7-jwvlx   1/1     Running   0          10s
```

Nota el patrón del nombre: `<deployment>-<rs-hash>-<pod-suffix>`. Tres niveles de identidad reflejando la cadena.

### 4. Inspeccionar el pod gestionado: la cadena de ownership

```bash
kubectl describe pods -l app=httpd
```

```
Name:             httpd-6c755866c7-jwvlx
Namespace:        default
Node:             jump-host/10.244.73.164
Labels:           app=httpd
                  pod-template-hash=6c755866c7
Status:           Running
IP:               10.22.0.9
Controlled By:    ReplicaSet/httpd-6c755866c7
Containers:
  httpd:
    Container ID:   containerd://999471aa7f51d2e8bbfeb4efc222e3234c1dd0ecd3dc5fa1f44859697284ec99
    Image:          httpd:latest
    Image ID:       docker.io/library/httpd@sha256:bac8021a9b7ad41a399dc72bb0e1f0b832b565632df7e62871e07d2aca8b293e
    State:          Running
    Ready:          True
    Restart Count:  0
QoS Class:                   BestEffort
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  75s   default-scheduler  Successfully assigned default/httpd-6c755866c7-jwvlx to jump-host
  Normal  Pulling    75s   kubelet            Pulling image "httpd:latest"
  Normal  Pulled     73s   kubelet            Successfully pulled image "httpd:latest" in 2.688s. Image size: 45250501 bytes.
  Normal  Created    73s   kubelet            Created container: httpd
  Normal  Started    73s   kubelet            Started container httpd
```

Dos campos que **solo aparecen en pods gestionados por un Deployment** (compará con el `describe` de un Pod suelto en day-048):

- **`Labels: pod-template-hash=6c755866c7`** — Kubernetes inyecta automáticamente este label al pod (vos solo declaraste `app: httpd` en el manifest). Es el mismo hash que aparece en el nombre del ReplicaSet, y es lo que el Deployment usa internamente para distinguir pods de la versión actual vs versiones anteriores durante un rollout.
- **`Controlled By: ReplicaSet/httpd-6c755866c7`** — esta línea es la **ownerReference** materializada. Es metadata del pod que apunta a su "padre". Cuando borres el Deployment con `kubectl delete deployment httpd`, Kubernetes sigue esta cadena (Deployment → RS → Pod) en cascada y limpia todo. Es también lo que permite el self-healing: el ReplicaSet sabe qué pods le pertenecen leyendo la ownerReference, y si falta uno, crea otro.

> Si querés ver la `ownerReference` cruda (no solo el resumen "Controlled By"), `kubectl get pod httpd-6c755866c7-jwvlx -o yaml` la muestra en `metadata.ownerReferences[]` con el `uid` exacto del ReplicaSet padre.

### Estado del rollout

```bash
kubectl rollout status deployment/httpd
```

```
deployment "httpd" successfully rolled out
```

Útil sobre todo en pipelines de CI/CD: este comando bloquea hasta que el rollout termina (o falla), así que lo podés usar como gate de despliegue.

### Demostrar self-healing (la propiedad clave)

La razón principal por la que se usa un Deployment en vez de un Pod suelto: **si el pod muere, el ReplicaSet lo recrea**. Esto se prueba en vivo con tres comandos:

```bash
# 1. Estado inicial — un pod gestionado
kubectl get pods
```

```
NAME                     READY   STATUS    RESTARTS   AGE
httpd-6c755866c7-7hzq5   1/1     Running   0          13s
```

```bash
# 2. Borrar manualmente el pod, simulando una falla
kubectl delete pod httpd-6c755866c7-7hzq5
```

```
pod "httpd-6c755866c7-7hzq5" deleted from default namespace
```

```bash
# 3. Listar pods de nuevo — debería haber otro vivo
kubectl get pods
```

```
NAME                     READY   STATUS    RESTARTS   AGE
httpd-6c755866c7-7mjsx   1/1     Running   0          2s
```

Lo que pasó en 2 segundos:

- **Mismo prefijo `httpd-6c755866c7-`** → es el mismo Deployment, el mismo ReplicaSet (no cambió la `spec.template`)
- **Sufijo distinto (`7hzq5` → `7mjsx`)** → es un **pod nuevo**, no el mismo reiniciado. `RESTARTS: 0` lo confirma — un restart sería el mismo pod con su contador subiendo
- **AGE 2s** → el ReplicaSet detectó que faltaba un pod (su `spec.replicas: 1` no se cumplía con 0 pods vivos) y creó uno nuevo casi instantáneo, sin descargar la imagen porque el digest ya estaba cacheado en el nodo

Si hubiéramos hecho lo mismo con un Pod suelto (day-048), el pod habría desaparecido y nadie lo recrearía. Esa es la diferencia operativa entre Pod y Deployment llevada a la práctica.

> **No usar `kubectl delete` en producción para esto.** El comando es válido para demos de aprendizaje, pero en producción nunca borrarías un pod a mano. Si querés probar resiliencia real, mirá [chaos engineering tools como `chaos-mesh` o `litmus`](https://chaos-mesh.org/) que inyectan fallas controladas.

## Comparación: Pod vs Deployment

| Aspecto                       | Pod suelto                                  | Deployment                                              |
| ----------------------------- | ------------------------------------------- | ------------------------------------------------------- |
| Si el pod muere               | Queda muerto                                | El ReplicaSet crea uno nuevo automáticamente            |
| Escalar a N réplicas          | Imposible (es 1 pod)                        | `kubectl scale --replicas=N deployment/httpd`           |
| Cambiar la imagen             | Borrar y recrear                            | `kubectl set image` o `kubectl apply` → rolling update  |
| Rollback                      | No existe                                   | `kubectl rollout undo deployment/httpd`                 |
| Apto para producción          | No (excepto pods de sistema controlados)    | Sí, para apps stateless                                 |

## Troubleshooting

| Problema                                                                              | Causa y solución                                                                                                                                          |
| ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `error validating ...: unknown field "template"`                                      | El `template` quedó indentado adentro de `selector`. Subirlo un nivel para que esté al mismo nivel que `selector`                                         |
| `selector does not match template labels`                                             | Los labels en `template.metadata.labels` no incluyen los de `selector.matchLabels`. Sincronizarlos                                                        |
| `no matches for kind "Deployment" in version "v1"`                                    | Falta el grupo. Cambiar a `apiVersion: apps/v1`                                                                                                           |
| Deployment creado pero `READY 0/1`                                                    | `kubectl describe deployment httpd` para ver eventos. Suele ser `ImagePullBackOff` en el pod                                                              |
| Cambié `spec.replicas` y no veo nuevo ReplicaSet                                      | Esperado — solo cambios en `spec.template` crean un ReplicaSet nuevo. Las réplicas se ajustan en el RS existente                                          |
| Deployment se creó pero el pod sigue mostrando una imagen vieja                       | Probable que tengas un pod *suelto* con el mismo label vagando. `kubectl get pods -l app=httpd` y borrarlo si no es del Deployment                        |
| `kubectl edit` cambió el selector y ahora el Deployment "perdió" sus pods             | El selector es inmutable. Hay que `kubectl delete deployment httpd` (con `--cascade=orphan` si querés conservar pods) y recrearlo                         |

## Recursos

- [Documentación oficial de Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Workloads en Kubernetes (overview)](https://kubernetes.io/docs/concepts/workloads/)
- [Rolling Update strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)
- [kubectl rollout reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout)
