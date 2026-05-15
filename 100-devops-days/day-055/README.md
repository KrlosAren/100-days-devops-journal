# Día 55 - Sidecar Containers (patrón native con `initContainers`)

## Problema / Desafío

Hay una app nginx que genera access/error logs. Los devs necesitan acceso a las últimas 24h de logs para diagnóstico, pero los logs no son lo suficientemente críticos para ir a un volumen persistente. **Separation of concerns**: nginx solo sirve páginas, y un segundo container "sidecar" se encarga de leer y eventualmente shipear los logs.

- **Pod:** `webserver`
- **Volumen compartido:** `shared-logs` (emptyDir)
- **Container principal:** `nginx-container` (`nginx:latest`), monta `shared-logs` en `/var/log/nginx`
- **Sidecar:** `sidecar-container` (`ubuntu:latest`), **declarado como init container** con `restartPolicy: Always`, monta `shared-logs` en `/var/log/nginx`, comando:
  ```
  sh -c "while true; do cat /var/log/nginx/access.log /var/log/nginx/error.log; sleep 30; done"
  ```
- Todos los containers deben quedar `Running`.

## Conceptos clave

### El patrón sidecar

Un **sidecar container** es un container auxiliar que vive en el mismo Pod que la app principal, comparte sus recursos (red, volúmenes) y la complementa **sin que la app principal "sepa" que existe**. Casos típicos:

| Sidecar          | Qué hace                                                | Ejemplo de la industria               |
| ---------------- | ------------------------------------------------------- | ------------------------------------- |
| Log shipper      | Lee logs locales y los manda a un agregador             | Fluent Bit, Vector, Promtail          |
| Service mesh proxy | Intercepta y rutea tráfico de red de la app principal | Envoy en Istio, linkerd-proxy         |
| TLS terminator   | Decripta TLS antes de pasar tráfico plano a la app      | nginx/envoy como TLS frontend         |
| Cache/Sync       | Mantiene un cache local o sincroniza con storage remoto | git-sync, fluxcd image-updater        |

La idea fundamental: la **separación de responsabilidades** se hace a nivel de container, no de proceso. La app principal no necesita librerías de logging/networking/TLS — eso se delega al sidecar.

### Native Sidecar Containers (K8s 1.28+)

Hasta K8s 1.28, no había una forma "oficial" de declarar sidecars. La gente ponía dos containers en `spec.containers` y rezaba — esto tenía dos problemas serios:

1. **Orden de arranque indefinido**: el sidecar podía iniciar después del main, así que requests iniciales se perdían (típico con service mesh proxies)
2. **Orden de shutdown indefinido**: el sidecar podía morir antes que el main → última request del main fallaba al no tener el proxy. En Jobs, el sidecar nunca terminaba y el Job quedaba "corriendo" para siempre.

Desde **K8s 1.28** (beta) y **1.29** (stable), hay native sidecar containers: se declaran en `initContainers` con `restartPolicy: Always`. K8s les da semánticas especiales:

| Característica                   | Init container clásico                | Native sidecar (`initContainers` + `restartPolicy: Always`) |
| -------------------------------- | ------------------------------------- | ----------------------------------------------------------- |
| ¿Corre antes del main?           | Sí, debe **terminar** antes           | Sí, debe estar **Ready** antes (no termina)                 |
| ¿Sigue corriendo durante el main?| No (ya terminó)                       | Sí, corre en paralelo                                       |
| ¿Termina con el main?            | N/A                                   | Sí, se le manda SIGTERM **después** del main                |
| ¿Restart si crashea?             | Según `restartPolicy` del Pod         | Siempre (definido explícitamente)                           |
| ¿Bloquea Jobs?                   | No (corre y termina)                  | No (K8s detecta el patrón y lo termina junto al main)       |

### Init container clásico vs Sidecar native: visualización

```
Init container CLÁSICO:
  [init-c] running → terminated → [main-c] starting → running → terminated

Sidecar NATIVE (initContainers + restartPolicy: Always):
  [sidecar] starting → ready ───────────────────────────────────────────┐
                              [main-c]  starting → ready → running → SIGTERM
                                                                         │
                                                              SIGTERM ◀──┘ (al sidecar, al final)
```

### Por qué importa para este ejercicio

El sidecar de logs **debe arrancar antes** que nginx (para no perderse logs iniciales), **debe seguir corriendo** mientras nginx sirva tráfico, y **debe terminar después** de que nginx haga shutdown gracioso (para shipear los últimos logs). Eso es exactamente lo que da `initContainers` + `restartPolicy: Always`.

### Reutilización del `emptyDir`

El volumen `shared-logs` cumple el rol clásico de "buzón compartido" entre containers — idéntico al patrón de Día 54, pero con un **escritor real** (nginx generando logs) y un **lector real** (el sidecar leyendo).

- nginx **monta** `shared-logs` en `/var/log/nginx` → con eso, el directorio donde nginx normalmente escribe sus logs (`/var/log/nginx/access.log`, `/var/log/nginx/error.log`) ahora vive en el emptyDir compartido
- el sidecar **monta** el mismo `shared-logs` en el mismo path (`/var/log/nginx`) → ve los mismos archivos que nginx genera

Una sutileza importante: nginx en la imagen oficial ya tiene su `/var/log/nginx` configurado como destino de los logs. Al montar el volumen ahí encima, **el directorio original queda tapado** (montar oculta lo que había antes en ese path). Esto está bien porque nginx escribe ahí en tiempo de ejecución — no hay archivos pre-existentes que perder.

## Pasos

1. Escribir el manifest con `initContainers` (para el sidecar native) y `containers` (para nginx)
2. Aplicar y verificar `2/2 Running`
3. Inspeccionar con `describe` que ambos containers montan el mismo volumen
4. Generar tráfico al nginx (o esperar a que escriba logs por su cuenta)
5. Verificar que el sidecar ve los logs

## Comandos / Código

### Manifest correcto

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: webserver
spec:
  volumes:
    - name: shared-logs
      emptyDir: {}

  initContainers:
    - name: sidecar-container
      image: ubuntu:latest
      restartPolicy: Always
      command:
        - sh
        - -c
        - while true; do cat /var/log/nginx/access.log /var/log/nginx/error.log; sleep 30; done
      volumeMounts:
        - name: shared-logs
          mountPath: /var/log/nginx

  containers:
    - name: nginx-container
      image: nginx:latest
      volumeMounts:
        - name: shared-logs
          mountPath: /var/log/nginx
```

Tres diferencias importantes respecto a tu YAML original:

| Cambio                                                      | Por qué                                                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `sidecar-container` movido a `initContainers`               | La consigna pide explícitamente "init container" — el patrón native sidecar                       |
| Agregado `restartPolicy: Always` al sidecar                 | Lo que diferencia un init container clásico de un sidecar native. Sin esto el container terminaría al primer `sleep` y K8s lo trataría como init clásico |
| `- c` → `- -c`                                              | Era un typo. `sh c "..."` busca un archivo llamado `c`, falla con CrashLoopBackOff               |

### Aplicar el manifest

```bash
kubectl apply -f pod.yml
```

```
namespace/test-system created
pod/webserver created
```

> **Nota — namespace dedicado:** en este lab el manifest incluyó también un `namespace: test-system` para aislar el experimento. Por eso los `kubectl` siguientes llevan `-n test-system`. Olvidarse el `-n` da el clásico error `pods "webserver" not found` (kubectl lo busca en `default`).

```bash
kubectl get pod webserver -n test-system
```

```
NAME        READY   STATUS    RESTARTS   AGE
webserver   2/2     Running   0          15s
```

`2/2 Running` cuenta el sidecar **y** el main como containers vivos — aunque el sidecar esté en la sección `initContainers`, K8s lo cuenta como "ready container" porque tiene `restartPolicy: Always`.

### Inspeccionar con `describe`

```bash
kubectl describe pod webserver -n test-system
```

```
Name:             webserver
Namespace:        test-system
Node:             rp3-node/10.0.0.3
Status:           Running
IP:               10.42.2.109

Init Containers:
  sidecar-container:
    Image:         ubuntu:latest
    Command:
      sh
      -c
      while true; do cat /var/log/nginx/access.log /var/log/nginx/error.log; sleep 30; done
    State:          Running
      Started:      Fri, 15 May 2026 08:37:56 -0400
    Ready:          True
    Restart Count:  0
    Mounts:
      /var/log/nginx from shared-logs (rw)

Containers:
  nginx-container:
    Image:          nginx:latest
    State:          Running
      Started:      Fri, 15 May 2026 08:37:58 -0400
    Ready:          True
    Restart Count:  0
    Mounts:
      /var/log/nginx from shared-logs (rw)

Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True   ← True aunque el sidecar siga Running (semántica nueva)
  Ready                       True
  ContainersReady             True
  PodScheduled                True

Volumes:
  shared-logs:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
QoS Class:    BestEffort

Events:
  Normal  Scheduled  118s  default-scheduler  Successfully assigned test-system/webserver to rp3-node
  Normal  Pulling    119s  kubelet            spec.initContainers{sidecar-container}: Pulling image "ubuntu:latest"
  Normal  Pulled     118s  kubelet            spec.initContainers{sidecar-container}: Successfully pulled image "ubuntu:latest" in 765ms
  Normal  Created    118s  kubelet            spec.initContainers{sidecar-container}: Created container: sidecar-container
  Normal  Started    118s  kubelet            spec.initContainers{sidecar-container}: Started container sidecar-container
  Normal  Pulling    117s  kubelet            spec.containers{nginx-container}: Pulling image "nginx:latest"
  Normal  Pulled     116s  kubelet            spec.containers{nginx-container}: Successfully pulled image "nginx:latest" in 741ms
  Normal  Created    116s  kubelet            spec.containers{nginx-container}: Created container: nginx-container
  Normal  Started    116s  kubelet            spec.containers{nginx-container}: Started container nginx-container
```

Cuatro confirmaciones críticas del patrón native sidecar:

1. **El sidecar está bajo `Init Containers:`** (no `Containers:`) pero su `State: Running`. Un init clásico no estaría `Running` mientras el main corre — habría terminado primero (`Terminated: Completed`).
2. **`Initialized: True` aunque el sidecar siga Running**. Esto es nuevo de native sidecars: la condición pasa a `True` cuando el sidecar está **Ready**, no cuando termina. Con init clásicos, `Initialized` solo era `True` después de que todos los init terminaran.
3. **Los Events muestran arranque ORDENADO**: sidecar a los `118s/119s` (pull → create → start), nginx a los `116s/117s` (pull → create → start) — **2 segundos después**. Sin `initContainers + restartPolicy: Always`, los dos containers arrancarían en paralelo.
4. **Ambos containers montan `shared-logs` en `/var/log/nginx`** — emptyDir compartido, mismo path en este caso (a diferencia del Día 54 donde usamos paths distintos).

### Generar tráfico y ver el output del sidecar

Para que aparezcan logs hay que pegarle a nginx. Como el Pod no tiene Service, le pegamos desde adentro del Pod:

```bash
# Una alternativa: port-forward al puerto 80 del nginx
kubectl port-forward pod/webserver 8080:80 &
curl http://localhost:8080/
curl http://localhost:8080/no-existe   # genera un 404 que va a error.log

# O directamente desde el container con curl interno:
kubectl exec -it webserver -c nginx-container -- sh -c "apt update && apt install -y curl && curl localhost/"
```

Ahora ver lo que el sidecar está catteando:

```bash
kubectl logs webserver -c sidecar-container
```

Esperado (con un cycle del `while`):

```
10.244.0.1 - - [14/May/2026:13:10:23 +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.4.0" "-"
10.244.0.1 - - [14/May/2026:13:10:25 +0000] "GET /no-existe HTTP/1.1" 404 153 "-" "curl/8.4.0" "-"
2026/05/14 13:10:25 [error] 30#30: *2 open() "/usr/share/nginx/html/no-existe" failed (2: No such file or directory), client: 10.244.0.1, ...
```

El sidecar imprime cada 30s el contenido completo del `access.log` y `error.log`. En producción real esto sería streaming hacia un agregador (Loki, Cloudwatch, Elasticsearch).

> **Stream vivo de los logs:**
> ```bash
> kubectl logs -f webserver -c sidecar-container
> ```

### Versión "compat" (sin native sidecar)

Si tu cluster es < K8s 1.28, no podés usar `initContainers` + `restartPolicy: Always`. La forma vieja era declarar el sidecar como un container regular más:

```yaml
spec:
  volumes:
    - name: shared-logs
      emptyDir: {}
  containers:
    - name: nginx-container
      image: nginx:latest
      volumeMounts:
        - { name: shared-logs, mountPath: /var/log/nginx }
    - name: sidecar-container
      image: ubuntu:latest
      command: ["sh","-c","while true; do cat /var/log/nginx/access.log /var/log/nginx/error.log; sleep 30; done"]
      volumeMounts:
        - { name: shared-logs, mountPath: /var/log/nginx }
```

Funciona, pero **no garantiza** orden de arranque ni de shutdown. En este lab probablemente la consigna acepte cualquiera de los dos enfoques — pero la versión "moderna" con `initContainers` es la que matchea literal con la consigna ("init container").

## Cuándo NO usar este patrón

- **Para persistir logs más allá de la vida del Pod**: el `emptyDir` se borra al borrar el Pod. Para logs de auditoría/compliance hay que ir a un PV/PVC o, mejor, shipping real a un backend externo.
- **Para shipping serio en producción**: `while true; cat ...; sleep 30` re-lee los archivos completos en cada ciclo, no es streaming, y duplica los logs si crece el archivo. Usar Fluent Bit / Vector / Promtail como sidecar de verdad.
- **Cuando el sidecar es necesario en MUCHOS pods**: si todos tus pods necesitan log shipping, mejor usar un DaemonSet del agente en cada nodo (un agente por nodo, no uno por pod). Reduce overhead masivamente.

## Troubleshooting

| Problema                                                                    | Causa y solución                                                                                                                                  |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sidecar en `CrashLoopBackOff` con `sh: 0: Can't open c`                     | El `command` tiene `c` en vez de `-c`. El `-` es parte del flag                                                                                   |
| Sidecar arranca y muere, `Restart Count` sube                               | Falta `restartPolicy: Always` en el init container — sin eso K8s lo trata como init clásico, lo corre una vez y espera que termine               |
| Pod en `Init:0/1` indefinido                                                | El sidecar nunca termina (porque tiene `while true`) Y le falta `restartPolicy: Always`. K8s espera que termine antes de seguir → deadlock        |
| Sidecar imprime `cat: /var/log/nginx/access.log: No such file or directory` | Los logs todavía no se generaron. Esperado al principio — nginx no escribe archivos hasta recibir la primera request                              |
| `kubectl logs webserver` falla con `container name must be specified`       | El Pod tiene varios containers — usar `-c <nombre>`. Lista con `kubectl get pod webserver -o jsonpath='{.spec.containers[*].name}{"\n"}{.spec.initContainers[*].name}'` |
| Sidecar imprime los logs **duplicados** cada 30s                            | `cat` re-lee el archivo entero cada ciclo. Es comportamiento esperado del comando dado — para no duplicar habría que usar `tail -f` o un offset  |
| Cluster es K8s < 1.28 y rechaza `restartPolicy: Always` en initContainer    | La feature es 1.28+. Usar la versión "compat" con el sidecar en `containers:` (sin garantías de orden)                                            |

## Recursos

- [Sidecar Containers (oficial, K8s 1.28+)](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
- [Init Containers (oficial)](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Pod Logging Architectures (oficial)](https://kubernetes.io/docs/concepts/cluster-administration/logging/) — comparación entre sidecar shipping, node-level agent (DaemonSet), y direct application logging
- [Native Sidecar Containers KEP-753](https://github.com/kubernetes/enhancements/issues/753) — el doc de diseño con el "por qué"
- [The Distributed System Toolkit: Patterns for Composite Containers (Burns & Oppenheimer)](https://kubernetes.io/blog/2015/06/the-distributed-system-toolkit-patterns/) — el paper original que definió el patrón sidecar
