# Día 50 - Resource Requests y Limits en Pods de Kubernetes

## Problema / Desafío

El equipo de Nautilus está viendo problemas de performance en algunas apps por contención de recursos. La consigna es crear un pod con límites de recursos definidos:

- **Nombre del pod:** `httpd-pod`
- **Nombre del contenedor:** `httpd-container`
- **Imagen:** `httpd:latest`
- **Requests:** memoria `15Mi`, CPU `100m`
- **Limits:** memoria `20Mi`, CPU `100m`

## Conceptos clave

### `requests` vs `limits`: dos números, dos consumidores

Cada contenedor en Kubernetes puede declarar dos valores por recurso (CPU y memoria):

| Campo      | Quién lo usa            | Qué significa                                                                                |
| ---------- | ----------------------- | -------------------------------------------------------------------------------------------- |
| `requests` | El **scheduler**        | Garantía mínima. Solo nodos con al menos esa cantidad disponible pueden recibir este pod     |
| `limits`   | El **kubelet** / kernel | Techo enforced en tiempo de ejecución. Si el contenedor lo intenta cruzar, hay consecuencias |

- `requests` es **planeación**: define el "espacio reservado" del pod en el nodo
- `limits` es **policing**: define qué pasa si el contenedor se pasa de la raya

Si no declarás `requests`, el scheduler asume `0` y puede meterte el pod en un nodo saturado. Si no declarás `limits`, el contenedor puede crecer sin freno y desestabilizar al vecino.

### Qué pasa cuando se excede el límite (no es lo mismo CPU que memoria)

| Recurso     | Comportamiento al cruzar el `limit`                                                                      |
| ----------- | -------------------------------------------------------------------------------------------------------- |
| **CPU**     | Throttling. El proceso sigue vivo, solo se le da menos tiempo de CPU. **Latencia ↑, no muere**           |
| **Memoria** | OOMKilled. El kernel mata el proceso (señal `SIGKILL`). El contenedor reinicia (si la policy lo permite) |

Esta asimetría tiene una razón física: la CPU es **compresible** (podés dar menos ciclos), pero la memoria es **incompresible** (no podés "dar menos RAM" — o cabe o no cabe). Cuando un proceso pide más RAM y no hay, el único recurso es matarlo.

### Unidades de CPU: cores y millicores

Kubernetes mide CPU en **cores** o **millicores** (un milésimo de core):

- `1` o `1000m` = **un core completo** (un hyperthread / vCPU en un nodo cloud)
- `500m` = medio core (50% del tiempo de CPU de un core)
- `100m` = 0.1 core (10% del tiempo de un core)
- `10m` = 0.01 core — útil para sidecars o procesos casi idle

El `m` significa "milli". Como cualquier CPU moderna tiene varios cores, podés perfectamente pedir `2`, `4`, etc. (un solo proceso multi-thread puede consumir varios cores).

### Unidades de memoria: la trampa de `Mi` vs `M`

Esto atrapa a casi todo el mundo la primera vez. Kubernetes acepta **dos sistemas**:

| Sufijo                 | Sistema       | Valor                               |
| ---------------------- | ------------- | ----------------------------------- |
| `K`, `M`, `G`, `T`     | Decimal (SI)  | `1M` = 1 × 1000² = 1,000,000 bytes  |
| `Ki`, `Mi`, `Gi`, `Ti` | Binario (IEC) | `1Mi` = 1 × 1024² = 1,048,576 bytes |

Diferencia práctica: `15Mi` ≈ 15.73 MB, mientras que `15M` = 15 MB **exactos**. Una diferencia de ~5%. En memoria ajustada, eso es lo que decide si tu pod sobrevive o se va a OOMKilled.

> **Convención en el ecosistema:** usar siempre las binarias (`Ki`, `Mi`, `Gi`). Coinciden con lo que reportan `free -h`, `top`, `kubectl top`, etc.

### QoS Classes: el sistema oculto de prioridades

Cuando un nodo se queda sin memoria, el kubelet tiene que evictar pods. ¿A cuál mata primero? Decide según la **QoS Class** que Kubernetes le asigna automáticamente al pod, **derivada** de cómo escribiste `requests` y `limits`:

> **Glosario — "evictar" / "evicted":** Spanglish del inglés *evict* (desalojar). En Kubernetes describe algo muy específico: **el sistema decide matar el pod** porque el nodo está bajo presión de recursos (memoria, disco, PIDs) o porque alguien lo drena con `kubectl drain` para mantenimiento. **No es lo mismo** que un pod que se cae por su cuenta:
>
> | Situación                         | Causa                                                  | Resultado                                                        |
> | --------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------- |
> | Pod se cae solo (`CrashLoopBackOff`) | El proceso adentro sale con error (segfault, exit ≠ 0) | Mismo pod reinicia en el mismo nodo, `Restart Count` ↑           |
> | Pod `OOMKilled`                   | El contenedor cruzó su propio `limits.memory`          | Mismo pod reinicia en el mismo nodo, `Restart Count` ↑           |
> | Pod **`Evicted`**                 | El **nodo entero** está bajo presión, o fue drenado    | Pod queda en `Failed`/`Evicted`, **no se reinicia en ese nodo** — un controller (Deployment, RS) crea uno **nuevo en otro lado** |
>
> Distinción importante porque el debugging es distinto: si tu pod aparece `Evicted`, el problema no es de tu código sino del nodo. Hay que mirar `kubectl describe node <nodo>` para ver eventos de presión (`MemoryPressure`, `DiskPressure`).

| QoS Class      | Cómo se obtiene                                                             | Prioridad de eviction               |
| -------------- | --------------------------------------------------------------------------- | ----------------------------------- |
| **Guaranteed** | `requests == limits` para **todos** los recursos (CPU **y** memoria)        | Último en ser evictado (más seguro) |
| **Burstable**  | Tiene `requests` definidos pero `requests != limits` en al menos un recurso | Eviction intermedio                 |
| **BestEffort** | No declaró ningún `requests` ni `limits`                                    | **Primero** en ser evictado         |

Esto es importante para entender el pod de este día: aunque CPU es `100m == 100m`, la **memoria** es `15Mi != 20Mi`. Eso es suficiente para que la QoS Class quede como **`Burstable`**, no `Guaranteed`. Para subirla a `Guaranteed` habría que igualar también memoria (`requests.memory == limits.memory`).

> **Workloads críticos en producción** suelen apuntar a `Guaranteed`: garantiza que el pod no será evictado bajo presión de memoria salvo en el peor escenario. Para batch jobs o cosas que pueden re-correr, `Burstable` (o incluso `BestEffort`) ahorra recursos.

## Pasos

1. Escribir el manifest `pod.yml` con la sección `resources`
2. Aplicar con `kubectl apply -f`
3. Inspeccionar con `kubectl describe` para confirmar requests, limits y **QoS Class**
4. (Opcional) Ver consumo real con `kubectl top pod`

## Comandos / Código

### Solución utilizada

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: httpd-pod
spec:
  containers:
    - name: httpd-container
      image: httpd:latest
      resources:
        requests:
          memory: "15Mi"
          cpu: "100m"
        limits:
          memory: "20Mi"
          cpu: "100m"
```

Aplicar:

```bash
kubectl apply -f pod.yml
```

```
pod/httpd-pod created
```

### Verificar la asignación de recursos y el QoS Class

Después de aplicar, hay que confirmar tres cosas en el `describe`:

1. Los `Requests:` están en `15Mi / 100m`
2. Los `Limits:` están en `20Mi / 100m`
3. La `QoS Class:` es **`Burstable`** (no `Guaranteed`)

```bash
kubectl describe pod httpd-pod
```

```
Name:             httpd-pod
Namespace:        default
Node:             jump-host/10.244.244.165
Status:           Running
IP:               10.22.0.9
Containers:
  httpd-container:
    Image:          httpd:latest
    State:          Running
    Ready:          True
    Restart Count:  0
    Limits:
      cpu:     100m
      memory:  20Mi
    Requests:
      cpu:        100m
      memory:     15Mi
QoS Class:                   Burstable
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  29s   default-scheduler  Successfully assigned default/httpd-pod to jump-host
  Normal  Pulled     26s   kubelet            Successfully pulled image "httpd:latest" in 3.197s
  Normal  Started    25s   kubelet            Started container httpd-container
```

**Por qué quedó `Burstable` y no `Guaranteed`:** la regla de `Guaranteed` exige `requests == limits` para **todos los recursos**. Acá CPU coincide (`100m == 100m`), pero memoria no (`15Mi != 20Mi`), así que basta un solo recurso desalineado para que Kubernetes degrade la QoS Class al nivel intermedio.

Para extraer solo el campo en un script o pipeline:

```bash
kubectl get pod httpd-pod -o jsonpath='{.status.qosClass}'
```

```
Burstable
```

`-o jsonpath` lee directo del API server y devuelve el string sin parseo de texto. Más estable que hacer `kubectl describe | grep "QoS Class"` porque no depende del formato visual de `describe`, que puede cambiar entre versiones de kubectl.

### Ver el consumo real (runtime)

Si el cluster tiene `metrics-server` instalado (lo tiene en el lab):

```bash
kubectl top pod httpd-pod
```

```
NAME        CPU(cores)   MEMORY(bytes)
httpd-pod   1m           8Mi
```

`kubectl top` muestra **uso real** medido en runtime. Útil para calibrar requests y limits: si tu pod usa 8Mi sostenidos, pedir 15Mi de request es razonable; si jamás pasa de 200m de CPU pico, pedir 1 core es desperdicio.

> Distinción crítica: `describe` muestra lo **declarado** en el manifest. `top` muestra lo **consumido** en tiempo real. Para diagnosticar OOMKilled vs limits mal calibrados, hay que mirar ambos.

## Troubleshooting

| Problema                                                                      | Causa y solución                                                                                                                           |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Pod en `OOMKilled` poco después de arrancar                                   | El `limits.memory` es menor de lo que el proceso necesita ni siquiera para inicializar. Subir el límite o investigar memory footprint real |
| Pod en estado `Pending` con event `0/N nodes are available: insufficient cpu` | Los `requests` exceden lo libre en cualquier nodo. Bajar requests o agregar capacidad al cluster                                           |
| App responde lento pero el pod no muere                                       | CPU throttling: el contenedor está pegado al `limits.cpu`. `kubectl top pod` mostrará uso clavado en el techo. Subir el límite de CPU      |
| `kubectl top pod` da `error: Metrics API not available`                       | El cluster no tiene `metrics-server` instalado. Es un addon, no viene por default en kubeadm                                               |
| QoS Class salió `Burstable` y querías `Guaranteed`                            | Revisar que **todos** los recursos tengan `requests == limits` (no solo uno). Bastante común: olvidar igualar memoria                      |
| Puse `memory: 1G` y el contenedor se queja de menos memoria que esperaba      | `1G` (decimal) = 1,000,000,000 bytes. Si esperabas 1 GiB usar `1Gi` (= 1,073,741,824 bytes, ~7% más)                                       |

## Recursos

- [Resource Management for Pods and Containers (oficial)](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Quality of Service for Pods (oficial)](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- [Meaning of CPU (oficial)](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#meaning-of-cpu)
- [Meaning of memory (oficial)](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#meaning-of-memory)
- [metrics-server (kubernetes-sigs)](https://github.com/kubernetes-sigs/metrics-server)
