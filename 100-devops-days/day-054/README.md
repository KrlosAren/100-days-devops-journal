# Día 54 - Shared Volumes en Kubernetes (emptyDir)

## Problema / Desafío

El equipo de Nautilus está armando una app multi-container que necesita compartir data temporal entre containers del mismo Pod. Hay que crear un Pod que pruebe el patrón de **volumen compartido**.

- **Pod:** `volume-share-xfusion`
- **Volumen:** `volume-share` (tipo `emptyDir`)
- **Container 1:** `volume-container-xfusion-1`, imagen `ubuntu:latest`, monta el volumen en `/tmp/blog`, debe estar `Running` (`sleep` infinito)
- **Container 2:** `volume-container-xfusion-2`, imagen `ubuntu:latest`, monta el volumen en `/tmp/apps`, debe estar `Running`
- **Prueba:** crear `/tmp/blog/blog.txt` con el texto `Welcome to xFusionCorp Industries` desde el container 1, verificar que aparezca en `/tmp/apps/blog.txt` desde el container 2

## Conceptos clave

### Qué es un `emptyDir`

Es el tipo de volumen más simple de Kubernetes. Cuando el Pod arranca, kubelet crea un directorio vacío en el nodo, y lo monta dentro de los containers que lo declaren en sus `volumeMounts`. Características:

- **Empieza vacío** (de ahí el nombre — no preserva data previa al Pod)
- **Es compartido por todos los containers del Pod** que lo monten
- **Su lifetime es igual al del Pod**: si el Pod se borra, el directorio se borra. Si un container reinicia (crashea y vuelve), el volumen **sigue ahí** — los datos sobreviven al restart del container, pero no al delete del Pod.
- **Vive en el nodo**: si el Pod se reschedula a otro nodo (caso de eviction), el `emptyDir` se pierde y se crea uno nuevo vacío

### Cuándo usar `emptyDir`

- **Cache** local entre restarts del container
- **Scratch space** para procesamiento temporal (ordenamientos, compresión, generación de PDFs, etc.)
- **Compartir datos entre containers del mismo Pod** (sidecar patterns: nginx + php-fpm, app + log shipper, etc.) — este es el caso de hoy
- **Anti-uso:** persistencia. Para data que debe sobrevivir a la vida del Pod hay que usar `PersistentVolumeClaim` o un volume type como `nfs`, `csi`, etc.

### `emptyDir.medium`: disco vs RAM

```yaml
volumes:
  - name: my-cache
    emptyDir:
      medium: Memory    # tmpfs en RAM (muy rápido, pero cuenta como uso de memoria)
      sizeLimit: 500Mi
```

| `medium`    | Backend                  | Uso típico                                                |
| ----------- | ------------------------ | --------------------------------------------------------- |
| (vacío)     | Filesystem del nodo      | Default. Sirve para casi todo                             |
| `Memory`    | `tmpfs` (RAM)            | Cache extremadamente rápido, scratch de cómputo intensivo |

El `tmpfs` aparece como uso de **memoria** del pod (cuenta para limits.memory), no como disco. Si tu app llena el `emptyDir` y excede el memory limit del pod → OOMKilled.

### Mountar el mismo volumen en paths distintos

Esta es la propiedad clave del ejercicio de hoy: **un volumen, dos `mountPath`s diferentes** — sigue siendo un solo volumen físico.

Visualización mental:

```
Pod: volume-share-xfusion
└── volume-share  (emptyDir real, vive en /var/lib/kubelet/.../volumes/.../volume-share)
    ↑                                              ↑
    │                                              │
    │ montado en /tmp/blog                         │ montado en /tmp/apps
    │                                              │
    Container 1                                    Container 2
    (ve archivos en /tmp/blog/)                    (ve los MISMOS archivos en /tmp/apps/)
```

Cuando el container 1 escribe `/tmp/blog/blog.txt`, lo está escribiendo al **mismo inode físico** que el container 2 ve como `/tmp/apps/blog.txt`. Los containers nunca se ven entre sí — solo ven sus propios filesystems — pero el volumen actúa como un puente.

> **Conexión con Día 53:** ahí teníamos dos containers que compartían `emptyDir` pero con paths distintos, y eso causó un bug (nginx mandaba paths a php-fpm vía FastCGI, php-fpm los resolvía en SU filesystem). El takeaway es: **compartir bytes ≠ compartir paths**. Cuando las apps se mandan paths entre sí, los `mountPath` tienen que coincidir. Cuando solo comparten archivos físicos, los paths pueden divergir tranquilamente.

### Por qué se necesita `command` en este Pod

Las imágenes de Ubuntu no tienen un proceso PID 1 que se quede corriendo: arrancan, no encuentran nada que hacer, y el container termina (`Completed`). Para que el Pod se quede `Running`, hay que sobrescribir el comando con algo que bloquee indefinidamente. Los clásicos:

```yaml
command: ["sh", "-c", "sleep infinity"]      # GNU coreutils — Ubuntu, Debian, Fedora
command: ["tail", "-f", "/dev/null"]          # universal, funciona en Alpine también
command: ["sleep", "3600"]                    # un número grande pero finito
```

> **Trampa en Alpine:** `sleep infinity` no siempre funciona en Alpine viejo (la BusyBox `sleep` no acepta el argumento `infinity`). `tail -f /dev/null` es el más portable.

## Pasos

1. Escribir el manifest `pod.yml` con el volumen `emptyDir` y los dos containers
2. Aplicar con `kubectl apply -f`
3. Verificar con `describe` que los dos containers montan el mismo volumen en paths distintos
4. Escribir un archivo desde el container 1 con `kubectl exec`
5. Leer el archivo desde el container 2 con `kubectl exec` — confirmar que aparece

## Comandos / Código

### 1. Manifest del Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-share-xfusion
spec:
  volumes:
    - name: volume-share
      emptyDir: {}
  containers:
    - name: volume-container-xfusion-1
      image: ubuntu:latest
      volumeMounts:
        - name: volume-share
          mountPath: /tmp/blog
      command:
        - sh
        - -c
        - sleep infinity

    - name: volume-container-xfusion-2
      image: ubuntu:latest
      volumeMounts:
        - name: volume-share
          mountPath: /tmp/apps
      command:
        - sh
        - -c
        - sleep infinity
```

Estructura a tener clara:

- **`spec.volumes`**: declara el volumen **a nivel de Pod**, una sola vez. El nombre `volume-share` es el identificador que usarán los containers.
- **`spec.containers[].volumeMounts[]`**: cada container declara qué volúmenes monta y dónde. El campo `name` referencia al volume declarado arriba; el `mountPath` es **local al container**.
- **`{}` después de `emptyDir`** es importante: indica "objeto vacío, usá defaults" (filesystem del nodo, sin límite de tamaño). Sin `{}` el campo queda en `null` y K8s rechaza el manifest.

### 2. Aplicar y verificar

```bash
kubectl apply -f pod.yml
```

```
pod/volume-share-xfusion created
```

```bash
kubectl get pods
```

```
NAME                   READY   STATUS    RESTARTS   AGE
volume-share-xfusion   2/2     Running   0          41s
```

`READY 2/2` confirma que ambos containers iniciaron correctamente — sin el `sleep infinity` veríamos `Completed` o `CrashLoopBackOff`.

### 3. Confirmar el shared mount con `describe`

```bash
kubectl describe pod volume-share-xfusion
```

Output relevante (las dos secciones de `Mounts:` y la sección `Volumes:`):

```
Containers:
  volume-container-xfusion-1:
    Image:    ubuntu:latest
    Command:  sh -c sleep infinity
    Mounts:
      /tmp/blog from volume-share (rw)             ← mismo volumen
  volume-container-xfusion-2:
    Image:    ubuntu:latest
    Command:  sh -c sleep infinity
    Mounts:
      /tmp/apps from volume-share (rw)             ← mismo volumen, distinto path

Volumes:
  volume-share:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:
    SizeLimit:  <unset>
```

Tres confirmaciones:

- Los dos containers referencian `volume-share` en sus `Mounts:`
- Los `mountPath`s son distintos (`/tmp/blog` vs `/tmp/apps`) pero apuntan al mismo volumen lógico
- `Type: EmptyDir` con `Medium:` vacío (filesystem del nodo, no `tmpfs`) y `SizeLimit: <unset>` (sin límite)

> **Detalle de QoS Class:** en este Pod aparece `QoS Class: BestEffort` porque no declaramos ni `requests` ni `limits` en ningún container. En un pod productivo serio habría que agregar resources (ver Día 50 para el detalle del cálculo de QoS).

### 4. Escribir desde el container 1

```bash
kubectl exec -it volume-share-xfusion -c volume-container-xfusion-1 \
  -- sh -c "echo Welcome to xFusionCorp Industries > /tmp/blog/blog.txt"
```

> **Por qué `-c`:** el Pod tiene 2 containers; sin `-c` `kubectl exec` falla con `error: container name must be specified`. Es lo mismo que vimos en Día 53 para `kubectl cp` y `kubectl logs`.

> **Por qué `sh -c "..."`:** los redirects (`>`, `>>`, `|`) son interpretados por la **shell**, no por `exec`. Sin el wrapping `sh -c`, el `>` se interpretaría en la shell **local** del jump-host (intentando escribir en su disco, no en el del pod). Wrapping con `sh -c` envía el comando como string al shell DENTRO del container.

Verificación dentro del mismo container:

```bash
kubectl exec -it volume-share-xfusion -c volume-container-xfusion-1 \
  -- sh -c "cat /tmp/blog/blog.txt"
```

```
Welcome to xFusionCorp Industries
```

### 5. Leer desde el container 2 (la prueba clave)

```bash
kubectl exec -it volume-share-xfusion -c volume-container-xfusion-2 \
  -- sh -c "cat /tmp/apps/blog.txt"
```

```
Welcome to xFusionCorp Industries
```

**El test pasó**: el archivo escrito por el container 1 en `/tmp/blog/blog.txt` apareció en `/tmp/apps/blog.txt` del container 2. No se hizo copia ni sincronización — es **el mismo archivo físico** visto desde dos paths distintos.

## Comandos alternativos útiles

### Entrar interactivamente a un container (en vez de un one-shot)

```bash
# Abrir una shell dentro de un container
kubectl exec -it volume-share-xfusion -c volume-container-xfusion-2 -- bash

# Una vez adentro:
root@volume-share-xfusion:/# ls /tmp/apps/
blog.txt
root@volume-share-xfusion:/# cat /tmp/apps/blog.txt
Welcome to xFusionCorp Industries
root@volume-share-xfusion:/# exit
```

### Verificar el path real del `emptyDir` en el nodo

```bash
# Solo si tenés acceso al nodo (en un cluster real esto es raro)
kubectl get pod volume-share-xfusion -o jsonpath='{.metadata.uid}'
# → 7a3e8f2c-...

# En el nodo, el emptyDir vive en:
# /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~empty-dir/volume-share
```

> En labs como KodeKloud (donde el jump-host ES el nodo) sí se puede mirar este path. En clusters gestionados (EKS, GKE, AKS) generalmente no tenés SSH al nodo, así que esto queda en concepto.

## Troubleshooting

| Problema                                                                          | Causa y solución                                                                                                                              |
| --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Pod en estado `Completed` apenas arranca                                          | La imagen no tiene un proceso que se quede corriendo. Agregar `command: ["sh","-c","sleep infinity"]` o similar                              |
| `kubectl exec` falla con `container name must be specified`                       | El Pod tiene varios containers — agregar `-c <container-name>`. Listar con `kubectl get pod <name> -o jsonpath='{.spec.containers[*].name}'`  |
| Archivo escrito en container 1 no aparece en container 2                          | Los containers están montando volúmenes distintos. Verificar con `describe` que ambos referencien el mismo `volume-share` en sus `Mounts:`    |
| Manifest rechazado con `Invalid value: "null"` en `emptyDir`                      | Falta el `{}` después de `emptyDir:`. Es un objeto, no un valor escalar                                                                       |
| Pod desaparece y al volver el `emptyDir` está vacío                               | El `emptyDir` no es persistente: si el Pod se borra (no solo si el container reinicia) el volumen se pierde. Para persistencia usar PVC       |
| El `emptyDir` llena el disco del nodo                                             | Sin `sizeLimit` el volumen puede crecer hasta agotar el disco del nodo. Agregar `emptyDir: { sizeLimit: 500Mi }` para limitarlo               |
| Pod evictado por `MemoryPressure` aunque la app parecía liviana                   | Usaste `medium: Memory` y el `emptyDir` (tmpfs) cuenta para los limits.memory del pod. Bajá el sizeLimit o sacá el `medium: Memory`           |

## Recursos

- [Volumes — emptyDir (oficial)](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir)
- [Communicate Between Containers in the Same Pod (tutorial oficial)](https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/)
- [`kubectl exec` reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#exec)
- [Pod lifecycle — container states](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
