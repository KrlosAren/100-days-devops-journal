# Día 04 - Resource Requests y Limits en Kubernetes

## Problema / Desafío

Crear un Pod llamado `httpd-pod` con un contenedor `httpd-container` usando la imagen `httpd:latest`, configurando los recursos de CPU y memoria con requests y limits.

## Solución

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
          memory: 15Mi
          cpu: 100m
        limits:
          memory: 20Mi
          cpu: 100m
```

### Desglose del manifiesto

Los campos ya conocidos (`apiVersion`, `kind`, `metadata`, `spec.containers`) funcionan igual que en días anteriores. Lo nuevo es el bloque `resources`.

**`resources`**: Define cuántos recursos de cómputo (CPU y memoria) puede usar el contenedor. Se divide en dos secciones:

**`resources.requests`**: La cantidad **mínima garantizada** de recursos que el contenedor necesita. El scheduler de Kubernetes usa estos valores para decidir en qué nodo colocar el Pod. Solo agenda el Pod en un nodo que tenga al menos esta cantidad disponible.

**`resources.limits`**: La cantidad **máxima** de recursos que el contenedor puede consumir. Si el contenedor intenta exceder estos valores, Kubernetes interviene.

## Conceptos clave

### Requests vs Limits

| Aspecto | Requests | Limits |
|---------|----------|--------|
| Qué define | Mínimo garantizado | Máximo permitido |
| Quién lo usa | El **scheduler** para decidir dónde colocar el Pod | El **kubelet** para controlar el consumo en runtime |
| Obligatorio | No, pero recomendado | No, pero recomendado |
| Si no se define | El contenedor no tiene recursos garantizados | El contenedor puede consumir todo lo que el nodo tenga disponible |

### Unidades de CPU

CPU se mide en **millicores** (milésimas de un core):

| Valor | Equivalente | Descripción |
|-------|-------------|-------------|
| `100m` | 0.1 CPU | Una décima parte de un core |
| `250m` | 0.25 CPU | Un cuarto de core |
| `500m` | 0.5 CPU | Medio core |
| `1000m` o `1` | 1 CPU | Un core completo |
| `2000m` o `2` | 2 CPU | Dos cores |

La `m` significa **milli**. `100m` = 100 milicores = 0.1 de un core de CPU.

Un nodo con 4 cores tiene `4000m` de CPU total disponible. Un contenedor con `requests.cpu: 100m` está pidiendo el 2.5% de un core.

### Unidades de memoria

Memoria se mide en bytes, con sufijos para las unidades:

| Sufijo | Base | Ejemplo | Valor real |
|--------|------|---------|------------|
| `Ki` | Binaria (1024) | `15Ki` | 15 × 1024 = 15,360 bytes |
| `Mi` | Binaria (1024²) | `15Mi` | 15 × 1,048,576 = 15,728,640 bytes |
| `Gi` | Binaria (1024³) | `1Gi` | 1,073,741,824 bytes |
| `K` | Decimal (1000) | `15K` | 15,000 bytes |
| `M` | Decimal (1000²) | `15M` | 15,000,000 bytes |
| `G` | Decimal (1000³) | `1G` | 1,000,000,000 bytes |

> **Importante**: `Mi` (mebibytes, base 1024) y `M` (megabytes, base 1000) **no son iguales**. Kubernetes acepta ambos, pero en la práctica se usa `Mi` y `Gi` (base binaria) que corresponde a cómo los sistemas operativos reportan la memoria.

### Qué pasa cuando un contenedor excede los límites

El comportamiento es diferente para CPU y memoria:

| Recurso | Qué pasa al exceder el limit |
|---------|-------------------------------|
| **CPU** | El contenedor es **throttled** (estrangulado). Kubernetes le reduce los ciclos de CPU disponibles. El proceso sigue corriendo pero más lento. **No se mata el contenedor**. |
| **Memoria** | El contenedor es **OOMKilled** (Out Of Memory Killed). El kernel de Linux mata el proceso. Kubernetes reinicia el contenedor según la `restartPolicy`. |

Esta diferencia existe porque CPU es un recurso **compresible** (se puede limitar sin romper nada) y memoria es **incompresible** (no se puede "devolver" memoria que un proceso ya está usando).

### Cómo el scheduler usa los requests

Cuando se crea un Pod, el scheduler de Kubernetes:

1. Revisa los `requests` de cada contenedor del Pod
2. Busca un nodo que tenga **suficiente capacidad disponible** (capacidad total - suma de requests de Pods ya asignados)
3. Si ningún nodo tiene suficiente capacidad, el Pod queda en estado **Pending**

```
Nodo con 4Gi de memoria y 4000m de CPU:

Pod A requests: memory 1Gi, cpu 1000m  → Asignado ✓ (quedan 3Gi, 3000m)
Pod B requests: memory 2Gi, cpu 1500m  → Asignado ✓ (quedan 1Gi, 1500m)
Pod C requests: memory 2Gi, cpu 1000m  → Pending ✗ (necesita 2Gi pero solo queda 1Gi)
```

> **Nota**: Los requests no reservan recursos físicamente. Solo son una promesa que el scheduler usa para tomar decisiones de colocación. Un contenedor puede usar **menos** de lo que pidió.

### Quality of Service (QoS) Classes

Kubernetes asigna automáticamente una clase de QoS a cada Pod basándose en cómo se configuraron los requests y limits:

| QoS Class | Condición | Prioridad ante presión de recursos |
|-----------|-----------|-------------------------------------|
| **Guaranteed** | Todos los contenedores tienen requests **y** limits definidos, y requests = limits para CPU y memoria | Última en ser terminada (máxima protección) |
| **Burstable** | Al menos un contenedor tiene requests **o** limits definidos, pero no cumple las condiciones de Guaranteed | Terminada después de BestEffort |
| **BestEffort** | Ningún contenedor tiene requests ni limits definidos | Primera en ser terminada (mínima protección) |

El Pod de este ejercicio es **Burstable** porque tiene requests y limits definidos pero con valores diferentes (`memory: 15Mi` vs `memory: 20Mi`).

Si requests y limits fueran iguales para ambos recursos, sería **Guaranteed**:

```yaml
resources:
  requests:
    memory: 20Mi
    cpu: 100m
  limits:
    memory: 20Mi  # igual que requests
    cpu: 100m     # igual que requests
```

Cuando un nodo entra en presión de recursos (memory pressure), Kubernetes empieza a desalojar (evict) Pods en este orden: primero **BestEffort**, luego **Burstable**, y por último **Guaranteed**.

### Aplicar y verificar

```bash
# Crear el Pod
kubectl apply -f httpd-pod.yml

# Verificar que está corriendo
kubectl get pods

# Ver los recursos configurados
kubectl describe pod httpd-pod
```

En la salida de `describe`, buscar la sección `Containers`:

```
Containers:
  httpd-container:
    ...
    Limits:
      cpu:     100m
      memory:  20Mi
    Requests:
      cpu:     100m
      memory:  15Mi
```

Y en la parte inferior, la clase de QoS:

```
QoS Class: Burstable
```

### Comando imperativo equivalente

No existe un comando `kubectl run` que configure resources directamente. La forma más cercana es generar el YAML base y editarlo:

```bash
kubectl run httpd-pod --image=httpd:latest --dry-run=client -o yaml > httpd-pod.yml
```

Esto genera el manifiesto sin la sección `resources`, que se agrega manualmente antes de aplicar.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| Pod en estado `Pending` con evento `Insufficient cpu` o `Insufficient memory` | Los requests exceden la capacidad disponible del nodo. Reducir los valores o agregar más nodos |
| Pod en estado `OOMKilled` | El contenedor excedió el limit de memoria. Aumentar `limits.memory` o investigar por qué el proceso consume tanta memoria |
| Pod reiniciándose constantemente (`CrashLoopBackOff` + `OOMKilled`) | El limit de memoria es demasiado bajo para que el proceso arranque. Verificar el consumo real con `kubectl top pod httpd-pod` |
| `kubectl top` no funciona: `Metrics API not available` | Instalar metrics-server en el clúster: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` |
| Error de sintaxis: `quantities must match the regular expression` | Verificar las unidades. Errores comunes: `15mi` (incorrecto) vs `15Mi` (correcto), `100M` (megabytes de memoria, no milicores) vs `100m` (milicores de CPU) |

## Recursos

- [Resource Management for Pods and Containers - Kubernetes Docs](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Assign CPU Resources to Containers - Kubernetes Docs](https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/)
- [Assign Memory Resources to Containers - Kubernetes Docs](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/)
- [Pod Quality of Service Classes - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- [Resource units in Kubernetes](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#resource-units-in-kubernetes)
