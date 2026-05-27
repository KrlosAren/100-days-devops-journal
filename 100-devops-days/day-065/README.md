# Día 65 - Deploy de Redis en Kubernetes con ConfigMap

## Problema / Desafío

El equipo de Nautilus notó problemas de performance en una app que pega contra una DB y decidió **incorporar Redis como caché en memoria**. Antes de llevarlo a producción quieren probarlo en el cluster de testing.

Requirements:

- **ConfigMap:** `my-redis-config`, con `maxmemory: 2mb` bajo `data.redis-config`
- **Deployment:** `redis-deployment`
  - `replicas: 1`
  - Container `redis-container`, imagen `redis:alpine`
  - **Request** de **1 CPU**
  - Dos volúmenes montados:
    - `data` (`emptyDir`) en `/redis-master-data`
    - `redis-config` (ConfigMap) en `/redis-master`
  - Container expone puerto `6379`
- El Deployment debe terminar en `Running`

## Conceptos clave

### Qué es Redis y por qué se usa como caché

Redis (REmote DIctionary Server) es un **almacén clave-valor en memoria**, single-thread, conocido por su latencia sub-milisegundo. Los usos más comunes:

| Uso                                | Cómo Redis lo resuelve                                                                |
| ---------------------------------- | ------------------------------------------------------------------------------------- |
| **Caché de queries de DB**         | La app consulta primero Redis; si miss, va a la DB y guarda el resultado en Redis     |
| **Session store**                  | Guarda sesiones de usuario (más rápido que ir a la DB en cada request)                |
| **Rate limiting**                  | Counters atómicos con TTL (`INCR`, `EXPIRE`)                                          |
| **Pub/Sub liviano**                | Canales para notificaciones entre servicios                                           |
| **Cola de jobs**                   | Listas y sorted sets como colas (con `BRPOPLPUSH`, `BZPOPMIN`)                        |
| **Leaderboards / rankings**        | Sorted sets con ordenación O(log N)                                                   |

Como caché de DB, el patrón típico es **cache-aside**: la app consulta primero Redis, si hay miss va a la DB, almacena el resultado en Redis con un TTL y lo devuelve.

### Por qué un ConfigMap para la config de Redis

Redis se configura tradicionalmente con un archivo `redis.conf` (texto plano con directivas `maxmemory 2mb`, `maxmemory-policy allkeys-lru`, etc.). En K8s **no se hornea ese archivo en la imagen** — se inyecta vía ConfigMap como volumen:

| Mecanismo                       | Pros                                                  | Contras                                                  |
| ------------------------------- | ----------------------------------------------------- | -------------------------------------------------------- |
| **Hornear en la imagen**        | Inmutable, fácil de versionar con el código           | Cada cambio de config requiere rebuild + push + redeploy |
| **ConfigMap montado como volumen** *(este lab)* | Cambio de config sin rebuild; redeploy del Pod suficiente | El nombre del ConfigMap es una string suelta — riesgo de typo |
| **ConfigMap como env vars**     | Más simple si la app lee del environment             | Redis no lee `REDIS_MAXMEMORY` del env; necesita archivo |
| **Init container que genera config** | Permite lógica dinámica (templates)              | Más componentes, más complejidad                          |

### Cómo se materializa el ConfigMap en el filesystem del Pod

Cuando un ConfigMap se monta como volumen, **cada clave del `data` se convierte en un archivo** en el `mountPath`. Para este lab:

```yaml
data:
  maxmemory: "2mb"
```

Montado en `/redis-master`, produce:

```
/redis-master/
└── maxmemory       (contenido: "2mb")
```

> **Pitfall**: Redis no lee automáticamente archivos sueltos de un directorio. Para que esto funcione "de verdad" como config de Redis, la imagen tendría que invocarse con `redis-server /redis-master/redis.conf` (o similar), y el ConfigMap tendría que exponer una clave `redis.conf` con el contenido completo del archivo de config. El lab acepta el mount como prueba del patrón — pero anclar este detalle es importante para uso real.

Para lograr el archivo `redis.conf` real, el ConfigMap se estructura así:

```yaml
data:
  redis.conf: |
    maxmemory 2mb
    maxmemory-policy allkeys-lru
    bind 0.0.0.0
    port 6379
```

Y el container se invoca con `command: ["redis-server", "/redis-master/redis.conf"]`.

### Glosario del manifest (lo nuevo)

| Campo                                      | Significado                                                                                  |
| ------------------------------------------ | -------------------------------------------------------------------------------------------- |
| `volumes[].configMap.name`                 | Nombre del ConfigMap en el namespace que se va a montar                                      |
| `volumes[].configMap.items`                | (Opcional) Selecciona claves específicas del ConfigMap y las renombra al montarlas           |
| `volumes[].configMap.defaultMode`          | Permisos de los archivos montados (default `0644`)                                           |
| `volumes[].configMap.optional`             | Si `true`, el Pod arranca aunque el ConfigMap no exista                                      |
| `resources.requests.cpu: 1`                | El Pod **reserva** 1 CPU completa en el nodo donde se schedulee                              |
| `resources.limits.cpu: 1`                  | El Pod **no puede usar más** de 1 CPU (throttling cuando excede)                              |

### `requests` vs `limits` — la diferencia sutil del requirement

El lab dice "container should **request** for 1 CPU". Eso se traduce al campo `requests.cpu: "1"`, no a `limits`. Sin embargo:

| Escenario                                                | QoS class resultante  | Comportamiento bajo presión        |
| -------------------------------------------------------- | --------------------- | ---------------------------------- |
| Solo `requests` (sin `limits`)                           | `Burstable`           | Puede usar CPU/memoria más allá del request si hay disponible |
| Solo `limits` (sin `requests`)                           | `Burstable`           | K8s asume `requests == limits` automáticamente |
| `requests == limits` (ambos iguales)                     | `Guaranteed`          | Protegido contra eviction; menos throttling |
| Ni `requests` ni `limits`                                | `BestEffort`          | Primer candidato a eviction        |

Para el lab, declarar **solo `requests: cpu: 1`** es la lectura más literal del requirement. Pero al declarar solo `limits: cpu: 1`, el comportamiento efectivo del Pod es **idéntico** porque K8s rellena el request — el validador del lab no distingue.

### CPU "1" — qué significa exactamente

`cpu: 1` (o equivalentemente `1000m`, "1000 millicpu") significa **1 core virtual completo**. Es **mucho** para Redis en un lab — Redis single-thread normalmente consume mucho menos. Pero el lab lo pide así, probablemente para forzar que el scheduler tenga que encontrar un nodo con esa capacidad disponible.

Alternativas para entender la escala:

| Notación              | Equivalente              | Caso típico de uso                        |
| --------------------- | ------------------------ | ----------------------------------------- |
| `cpu: "100m"`         | 0.1 cores                | Sidecar liviano (log shipper)             |
| `cpu: "250m"`         | 0.25 cores               | API REST sencilla                          |
| `cpu: "500m"`         | 0.5 cores                | Microservicio con carga moderada           |
| `cpu: "1"` / `"1000m"` | 1 core                   | Redis dedicado, app con carga real         |
| `cpu: "2"`            | 2 cores                  | Workers multi-thread, procesamiento pesado |

### Por qué el Pod expone `containerPort: 6379` aunque no haya Service

El requirement pide que el container "exponga" el puerto 6379. Eso se declara con `containerPort`:

```yaml
ports:
  - containerPort: 6379
```

**Importante**: declarar `containerPort` **no abre realmente un puerto** — el container ya lo abrió (o no) según lo que haga su proceso. La declaración es **informativa**: documenta para humanos y permite que un Service o NetworkPolicy referencie el puerto por nombre. Si no se declara, igual el Pod puede recibir tráfico en ese puerto si el container lo escucha.

> El requirement del lab dice "expose port 6379", lo cual en lenguaje K8s estricto significa "declarar `containerPort`". No requiere crear un Service todavía.

## Pasos

1. Escribir el manifest con el `ConfigMap` y el `Deployment` en el mismo archivo (separados por `---`)
2. `kubectl apply -f deployment.yml`
3. Observar el Pod con `kubectl get pods` — si queda en `ContainerCreating`, mirar eventos
4. Si hay error `MountVolume.SetUp failed for volume "redis-config" : configmap "<name>" not found`, fixear el nombre del ConfigMap en el manifest
5. Re-aplicar — el Deployment dispara un rolling update con la spec corregida
6. Verificar que el Pod nuevo está `Running` y el viejo fue terminado

## Comandos / Código

### Manifest final (con el fix aplicado)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-redis-config
data:
  maxmemory: "2mb"

---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-deployment
  labels:
    app: redis-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-deployment
  template:
    metadata:
      labels:
        app: redis-deployment
    spec:
      volumes:
        - name: data
          emptyDir: {}
        - name: redis-config
          configMap:
            name: my-redis-config   # ← clave: este nombre debe matchear el ConfigMap real
      containers:
        - name: redis-container
          image: redis:alpine
          resources:
            requests:
              cpu: "1"
          ports:
            - containerPort: 6379
          volumeMounts:
            - name: data
              mountPath: /redis-master-data
            - name: redis-config
              mountPath: /redis-master
```

> **Comparado con tu versión del lab**: agregué `containerPort: 6379` (faltaba en el manifest publicado, aunque el requirement lo pide), y moví `cpu: 1` de `limits` a `requests` para alinearlo con el lenguaje del requirement. El validador acepta ambas formas, pero la segunda es la literal.

### Apply

```bash
kubectl apply -f deployment.yml
```

```
configmap/my-redis-config created
deployment.apps/redis-deployment created
```

### El bug encontrado en el camino (autopsia)

Al hacer el primer apply, el Pod quedó en `ContainerCreating`. La salida de `kubectl events`:

```
LAST SEEN          TYPE      REASON              OBJECT                                  MESSAGE
33s                Normal    SuccessfulCreate    ReplicaSet/...                          Created pod
33s                Normal    Scheduled           Pod/...                                 Successfully assigned
1s (x7 over 33s)   Warning   FailedMount         Pod/...                                 MountVolume.SetUp failed for volume "redis-config" : configmap "redis-config" not found
```

> La causa: el volumen `redis-config` referenciaba `configMap.name: redis-config`, pero el ConfigMap real se llama `my-redis-config`. El Pod **se schedulea** (el scheduler no valida nombres de ConfigMaps), pero el kubelet **no logra montar el volumen** y el container nunca arranca.

### Fix + rolling update

Al corregir `configMap.name` a `my-redis-config` y reaplicar:

```bash
kubectl apply -f deployment.yml
```

```
configmap/my-redis-config unchanged
deployment.apps/redis-deployment configured
```

```bash
kubectl events deployment/redis-deployment
```

Los eventos muestran el patrón completo del rolling update:

```
4s    Normal  ScalingReplicaSet   Deployment/redis-deployment              Scaled up replica set redis-deployment-597cdc4c66 from 0 to 1
4s    Normal  SuccessfulCreate    ReplicaSet/redis-deployment-597cdc4c66   Created pod
3s    Normal  Pulling             Pod/...                                   Pulling image "redis:alpine"
1s    Normal  Started             Pod/...                                   Started container redis-container
1s    Normal  Pulled              Pod/...                                   Successfully pulled image "redis:alpine"
0s    Normal  SuccessfulDelete    ReplicaSet/redis-deployment-6cd487969    Deleted pod (RS viejo)
0s    Normal  ScalingReplicaSet   Deployment/redis-deployment              Scaled down replica set redis-deployment-6cd487969 from 1 to 0
```

> Detalles a notar:
> - **Dos ReplicaSets** durante el rolling: el viejo (`6cd487969`) y el nuevo (`597cdc4c66`). El pod-template-hash cambia porque el spec del template cambió.
> - **Orden de operaciones**: K8s creó el Pod nuevo, esperó a que entrara Ready, **y recién después** borró el viejo. El default `maxUnavailable: 25%, maxSurge: 25%` permite tener temporalmente 2 Pods (1 viejo + 1 nuevo).

### Verificación final

```bash
kubectl get pods
```

```
NAME                                READY   STATUS    RESTARTS   AGE
redis-deployment-597cdc4c66-26h7j   1/1     Running   0          80s
```

```bash
kubectl describe pod redis-deployment-597cdc4c66-26h7j
```

Bloques relevantes del describe:

```
Containers:
  redis-container:
    Image:          redis:alpine
    State:          Running
    Limits:
      cpu:  1
    Requests:
      cpu:        1
    Mounts:
      /redis-master from redis-config (rw)
      /redis-master-data from data (rw)
Volumes:
  data:
    Type:       EmptyDir
  redis-config:
    Type:      ConfigMap
    Name:      my-redis-config
    Optional:  false
QoS Class:  Burstable
```

> El `Optional: false` confirma el comportamiento estricto — si el ConfigMap no existe, el Pod no arranca. Eso es lo que generó el bug del primer apply.

### Verificación funcional (opcional)

Para confirmar que Redis está realmente sirviendo:

```bash
kubectl exec -it redis-deployment-597cdc4c66-26h7j -- redis-cli ping
# PONG

kubectl exec -it redis-deployment-597cdc4c66-26h7j -- redis-cli SET hello world
# OK

kubectl exec -it redis-deployment-597cdc4c66-26h7j -- redis-cli GET hello
# "world"
```

Y para validar que el ConfigMap está montado:

```bash
kubectl exec -it redis-deployment-597cdc4c66-26h7j -- ls /redis-master
# maxmemory

kubectl exec -it redis-deployment-597cdc4c66-26h7j -- cat /redis-master/maxmemory
# 2mb
```

> Notar que Redis **no está leyendo este archivo** automáticamente — el server sigue con sus defaults. El lab valida el mount, no la efectividad de la config. Para que Redis use el `maxmemory: 2mb` real, habría que invocarlo con un `--maxmemory 2mb` o un archivo `redis.conf` apropiado.

## El patrón recurrente — typos en referencias por string

Tercera vez en el journal que aparece el mismo tipo de bug:

| Día     | Bug                                                              | Cómo se manifestó                                              |
| ------- | ---------------------------------------------------------------- | -------------------------------------------------------------- |
| Día 59  | Typo en `image` + ConfigMap inexistente                          | `ErrImagePull` + `ContainerCreating` indefinido                |
| Día 64  | Typo en `image` + `port`/`targetPort` mal del Service            | `ErrImagePull` + `502` desde el proxy externo                  |
| Día 65  | `configMap.name` no matchea el ConfigMap real                     | `FailedMount` recurrente, Pod en `ContainerCreating`           |

La lección común: **K8s usa strings como referencias entre recursos**. No hay verificación al apply de que el ConfigMap, Secret, imagen o label existan. Los bugs aparecen **al runtime**, cuando el kubelet intenta montar o pullear. El antídoto operacional:

1. Después de cada apply, mirar `kubectl get pods` para confirmar que llegó a `Running`
2. Si queda en `ContainerCreating` más de unos segundos, `kubectl describe` o `kubectl events` para ver por qué
3. Antes de aplicar a producción, validar manifests con herramientas como `kubeval`, `kubeconform` o `kube-linter`

### `kubectl events` vs `kubectl describe` para troubleshooting

| Comando                                  | Cuándo usarlo                                                         | Output                                          |
| ---------------------------------------- | --------------------------------------------------------------------- | ----------------------------------------------- |
| `kubectl get events`                     | Vista cruda, lista plana de eventos del namespace                     | Una tabla larga, hay que ordenarla manualmente  |
| `kubectl events <resource>`              | Eventos filtrados a un recurso, ordenados cronológicamente (K8s 1.27+) | Tabla limpia, lo más útil para troubleshooting  |
| `kubectl describe <resource>`            | Vista completa del recurso + sus eventos al final                     | Mucho más info, pero los eventos están al final |
| `kubectl logs <pod>`                     | Logs del proceso dentro del container                                 | Solo útil si el container llegó a arrancar      |

El comando `kubectl events deployment/redis-deployment` que usaste en el lab es la forma **más limpia** de ver "qué le pasó a este Deployment desde que lo apliqué" — vale anclarlo como reemplazo moderno de `get events --sort-by`.

## Conexión con días anteriores

- **Día 57 (env vars + ConfigMap)**: introdujo el ConfigMap como fuente de env vars. Acá se usa como **volumen** — misma fuente, distinta forma de consumirla.
- **Día 59 (troubleshooting ConfigMap inexistente)**: bug idéntico en su naturaleza — un ConfigMap referenciado por nombre que no matchea. Día 59 lo vio como typo simultáneo con image; hoy fue solo.
- **Día 60 (PV + PVC)**: misma sintaxis `volumes[]` + `volumeMounts[]`, con un tipo distinto de fuente. La estructura del manifest es **idéntica**; lo único que cambia es qué hay bajo el campo `volumes[].<source>` (`emptyDir`, `configMap`, `secret`, `persistentVolumeClaim`).
- **Día 62 (Secrets como volumen)**: muy parecido a hoy — un volumen que apunta a un objeto cluster-wide con datos. Diferencias: Secret es tmpfs, ConfigMap es disco normal del nodo; Secret almacena base64, ConfigMap plano.
- **Día 64 (troubleshooting con dos bugs)**: el flujo de `kubectl get pods` → `kubectl describe` (o `kubectl events`) → fix → re-apply se repite. Cada nuevo troubleshooting refina el reflejo.

## Reflexión: el patrón "referencia por string" como deuda silenciosa de K8s

El lab falló en primera instancia porque me faltaron dos cosas que el validador sí chequeaba específicamente:

1. **En `resources`** debía declarar `requests` y no `limits` para la petición de CPU. K8s rellena uno con el otro automáticamente, así que en el `describe` aparecen ambos en `1` — pero el validador lee la spec literal, no la efectiva.
2. **El `containerPort: 6379`** que el requirement pide con "expose port 6379". Declararlo es solo informativo (no abre el puerto), pero el validador necesita verlo en la spec.

Después de fixear esos dos, el lab pasó. La lección que queda: **el validador chequea la spec literal**, no el comportamiento efectivo del Pod. Un Pod puede arrancar y servir tráfico perfectamente aunque le falte declarar `containerPort`; el validador no.

No había usado **Redis** antes en producción, así que no tenía mapeadas las implicaciones de `maxmemory-policy`, persistencia (RDB vs AOF) ni replicación — son cosas que toca explorar fuera del scope del lab.

Tampoco había usado **`kubeval`, `kube-linter` ni `kubeconform`**; son herramientas que voy a instalar en mi entorno local para usarlas próximamente. Encajan exactamente con el problema recurrente que vengo viendo desde el Día 59: validar la spec antes de que el cluster acepte el manifest, en lugar de descubrir los typos al runtime.

**`kubectl events`** lo usé por primera vez en este lab y resultó muy potente — me permitió validar muy rápido que el volumen no se pudo encontrar, y esa identificación fue **más rápida que con `kubectl describe`**. La diferencia operativa es que `events` da el timeline en una tabla limpia, mientras que `describe` te obliga a scrollear hasta la sección de events del recurso. Pasa a ser el primer reflejo de troubleshooting de acá en adelante.

## Troubleshooting

| Problema                                                            | Causa                                                                                                | Solución                                                                                          |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Pod queda en `ContainerCreating` indefinido con `FailedMount`       | `configMap.name` (o `secret.secretName`) no matchea ningún objeto en el namespace                    | `kubectl get configmaps -n <ns>` para ver los reales; corregir el nombre en el manifest           |
| `kubectl apply` no muestra error pero el Pod no arranca             | El apply solo valida sintaxis del YAML — no resuelve referencias hasta runtime                       | Confirmar siempre con `kubectl get pods` después del apply                                        |
| `MountVolume.SetUp failed` se repite varias veces (`x7 over 33s`)   | El kubelet reintenta con backoff exponencial; el contador en `kubectl events` indica los reintentos | Es normal durante el debug; no significa que el problema empeore                                   |
| Después del fix, el Pod viejo sigue ahí con el mismo error          | El rolling update está en curso — el Pod nuevo arrancando, el viejo todavía no se borró             | Esperar a que el nuevo entre Ready; el viejo se borra automáticamente                              |
| `cpu: 1` rechazado con `node didn't fit, insufficient cpu`         | El nodo no tiene 1 CPU disponible para reservar (otros Pods ya reservaron casi todo)                | Bajar el `request` o liberar recursos en el cluster (`kubectl top nodes` para ver capacidad real) |
| Redis arranca pero no respeta el `maxmemory` del ConfigMap         | Redis no lee `/redis-master/maxmemory` automáticamente; necesita `redis-server <conf-file>`         | Estructurar el ConfigMap con clave `redis.conf` completa y montarlo como archivo de config        |
| ConfigMap actualizado pero el Pod sigue con el contenido viejo     | Los ConfigMaps montados se refrescan periódicamente (~1 min), pero la app puede cachear              | `kubectl rollout restart deployment/redis-deployment` fuerza Pod nuevo con la última versión       |
| `containerPort: 6379` declarado pero el container no escucha       | Declarar `containerPort` es solo informativo — no abre el puerto. El container debe escucharlo       | Verificar que el proceso (Redis) está escuchando: `netstat -tlnp` dentro del Pod                  |
| `QoS Class: Burstable` aunque pediste `requests == limits`         | Si solo declaraste uno de los dos, K8s rellena automáticamente; revisar con `describe`               | Para `Guaranteed` declarar **ambos** explícitamente y con el mismo valor                          |
| Apply borra y recrea el Deployment en vez de hacer rolling update  | El selector del Deployment cambió (los selectors son inmutables)                                     | Para cambiar selector, hay que `delete` + `create`. Evitar tocar selectors después del primer apply |

## Recursos

- [ConfigMaps (oficial)](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- [Redis: Configuration](https://redis.io/docs/management/config/)
- [`kubectl events` command (K8s 1.27+)](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_events/)
- [QoS classes for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/)
- [Resource units in Kubernetes](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#resource-units-in-kubernetes)
