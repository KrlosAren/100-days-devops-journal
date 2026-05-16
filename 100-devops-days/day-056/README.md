# Día 56 - Deployment + Service NodePort para nginx

## Problema / Desafío

Los devs de Nautilus quieren desplegar un sitio estático con **alta disponibilidad** y **escalabilidad**. El equipo de DevOps decide usar un Deployment con múltiples replicas, y exponerlo con un Service de tipo `NodePort`.

- **Deployment:** `nginx-deployment`, imagen `nginx:latest`, container `nginx-container`, **3 replicas**
- **Service:** `nginx-service`, tipo `NodePort`, **nodePort = 30011**

## Conceptos clave

### Pod vs Deployment: ¿por qué casi nunca creamos Pods directamente?

Esta es probablemente la distinción más importante para entender Kubernetes.

| Característica                  | Pod (stand-alone)                                       | Deployment                                              |
| ------------------------------- | ------------------------------------------------------- | ------------------------------------------------------- |
| **Tiene lifecycle**             | Sí (`Pending → Running → Succeeded/Failed`)             | Sí, pero a través de los Pods que controla              |
| **Gestiona su propio lifecycle**| **No**: si el Pod se cae, queda muerto                  | **Sí**: si un Pod se cae, crea uno nuevo (self-healing) |
| **Tiene número de replicas**    | No — es uno solo                                        | Sí — `spec.replicas` define cuántas instancias quiero   |
| **Rolling updates**             | No — para cambiar imagen hay que `delete + apply`       | Sí — `kubectl set image` dispara rolling update         |
| **Rollback**                    | No — el Pod viejo no se guarda                          | Sí — historial de ReplicaSets permite `rollout undo`    |
| **Campos inmutables**           | Muchísimos (volumeMounts, image, resources, etc.)        | Casi todos los del template son mutables                 |
| **Para qué sirve en producción**| Casi nada — labs, debugging, jobs one-shot              | El 90% de los workloads productivos                     |

Resumen: **el Pod es el ladrillo, el Deployment es el albañil**. El Pod es la unidad atómica que K8s sabe correr; el Deployment es lo que mantiene viva una flota de Pods.

> Una analogía útil: un Pod es como un proceso en Linux. Si crashea, no resucita solo — alguien tiene que reiniciarlo (`systemd`, `supervisor`, etc.). El Deployment es ese "supervisor": observa los Pods, y si nota que faltan replicas, crea más.

### Self-healing: ¿qué pasa cuando matás un Pod del Deployment?

```bash
kubectl delete pod nginx-deployment-abc123
```

1. K8s borra el Pod
2. El **ReplicaSet** controller nota que tiene 2 Pods donde debería tener 3
3. Crea un Pod nuevo con el template del Deployment
4. El Service automáticamente lo incluye (porque el nuevo Pod tiene el mismo label)
5. Total: ~5-10 segundos de "downtime parcial" (2/3 capacidad), pero **el sistema se cura solo**

Con un Pod stand-alone (sin Deployment), borrar el Pod = downtime indefinido hasta que alguien recree.

### La jerarquía: `Deployment` → `ReplicaSet` → `Pod`

```
Deployment: nginx-deployment (spec.replicas=3, declara qué quiero)
    │
    └── owns ──► ReplicaSet: nginx-deployment-7d9c4b8f (3 replicas reales)
                    │
                    ├── owns ──► Pod: nginx-deployment-7d9c4b8f-xj2pl
                    ├── owns ──► Pod: nginx-deployment-7d9c4b8f-q7s97
                    └── owns ──► Pod: nginx-deployment-7d9c4b8f-9846v
```

- **Deployment** declara *qué estado deseo*: 3 replicas de la imagen X
- **ReplicaSet** controla *cuántos Pods existen*: crea/borra Pods para llegar al número
- **Pod** es la *unidad ejecutable*: un grupo de containers corriendo en un nodo

La relación es por `ownerReferences`. Si borrás el Deployment, K8s borra en cascada los ReplicaSets, y esos borran sus Pods. Si borrás solo el ReplicaSet, sus Pods se borran (pero el Deployment crea uno nuevo).

> **¿Por qué existe la capa ReplicaSet?** Para que el rolling update funcione. Cada vez que cambiás el Pod Template (ej: `set image`), el Deployment crea un **ReplicaSet nuevo** y escala el viejo a 0. Así se puede hacer rollback rápido (ver Día 51 y Día 52).

### Anatomía de un container — campos importantes

Solo declaramos los mínimos en este lab (`name` + `image`), pero un container "serio" puede tener muchos más:

| Campo                  | Para qué sirve                                                                                  |
| ---------------------- | ----------------------------------------------------------------------------------------------- |
| `name`                 | Identificador del container dentro del Pod (único). Lo usás en `kubectl logs/exec -c`            |
| `image`                | Imagen de OCI/Docker (`repo:tag` o `repo@sha256:...`). Usar tag fijo, no `latest`, en prod      |
| `imagePullPolicy`      | `Always` / `IfNotPresent` / `Never`. Default `IfNotPresent` salvo si el tag es `latest`         |
| `command`              | Sobrescribe el `ENTRYPOINT` de la imagen. Lista de strings (un argv por elemento)               |
| `args`                 | Sobrescribe el `CMD` de la imagen. Combinado con `command`                                       |
| `ports`                | Lista de `containerPort` (informacional — kubelet no abre puertos)                              |
| `env`                  | Variables de entorno hardcodeadas (`name`/`value`) o de fuente (`valueFrom: secretKeyRef`)      |
| `envFrom`              | Importar TODO un ConfigMap o Secret como variables de entorno                                   |
| `volumeMounts`         | Qué volúmenes del Pod monta y en qué path                                                       |
| `resources`            | `requests` (para scheduler) y `limits` (enforced en runtime). Ver Día 50                        |
| `livenessProbe`        | Cómo K8s sabe si el container está "vivo". Si falla, K8s lo mata y reinicia                      |
| `readinessProbe`       | Cómo K8s sabe si el container está listo para recibir tráfico. Si falla, el Service lo excluye  |
| `startupProbe`         | Para apps de arranque lento — pospone las otras probes hasta que esta pase                       |
| `securityContext`      | UID/GID que corre el proceso, capabilities, readOnlyRootFilesystem, etc.                         |
| `lifecycle`            | Hooks `postStart` (post-arranque) y `preStop` (pre-shutdown). Útil para graceful shutdown        |

Ejemplo de un container "completo" para referencia:

```yaml
containers:
  - name: nginx-container
    image: nginx:1.27.0                                # tag fijo, no latest
    imagePullPolicy: IfNotPresent
    ports:
      - containerPort: 80
        name: http
        protocol: TCP
    env:
      - name: TZ
        value: "America/Argentina/Buenos_Aires"
      - name: API_KEY
        valueFrom:
          secretKeyRef: { name: api-secrets, key: key }
    resources:
      requests: { cpu: 100m, memory: 64Mi }
      limits:   { cpu: 500m, memory: 128Mi }
    livenessProbe:
      httpGet: { path: /healthz, port: 80 }
      initialDelaySeconds: 15
      periodSeconds: 10
    readinessProbe:
      httpGet: { path: /, port: 80 }
      periodSeconds: 5
    securityContext:
      runAsNonRoot: true
      runAsUser: 101
      readOnlyRootFilesystem: true
```

### Qué es un Service y por qué se necesita

**Problema fundamental**: los Pods son **efímeros**. Sus IPs cambian cuando se recrean (rolling update, eviction, crash). Si una app cliente apunta a `10.42.0.5` y ese Pod muere y se recrea como `10.42.0.7`, el cliente queda apuntando al vacío.

**Solución — Service**: un objeto K8s que da una **IP estable** y un **DNS estable** que ruteam tráfico al conjunto cambiante de Pods (identificados por label). El Service:

1. Tiene una **ClusterIP** virtual fija dentro del cluster (`10.43.x.x` en k3s, `10.96.x.x` en kubeadm default)
2. Tiene un **DNS interno**: `<service-name>.<namespace>.svc.cluster.local`
3. Mantiene una **lista de endpoints** (los Pods que matchean su selector) que actualiza automáticamente cada vez que un Pod aparece/desaparece
4. El **kube-proxy** corriendo en cada nodo instala reglas iptables/IPVS que hacen el ruteo desde la ClusterIP hacia los Pods reales

```
Cliente intra-cluster
    │
    │  request a nginx-service:80 (DNS resuelve a 10.43.110.17)
    ▼
Service ClusterIP: 10.43.110.17:80
    │  kube-proxy intercepta y elige un Pod (round-robin)
    │
    ├──► Pod 10.42.1.5:80  (nginx-deployment-xj2pl)
    ├──► Pod 10.42.2.7:80  (nginx-deployment-q7s97)
    └──► Pod 10.42.0.3:80  (nginx-deployment-9846v)
```

### Tipos de Service (`spec.type`)

| Tipo            | Alcance                  | Cómo se accede                                                                | Cuándo usarlo                                                  |
| --------------- | ------------------------ | ----------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `ClusterIP`     | Solo dentro del cluster  | `<svc-name>.<ns>.svc.cluster.local` o la ClusterIP                            | Default. Tráfico interno (app → DB, app → cache)                |
| `NodePort`      | Externo al cluster       | `<IP-de-cualquier-nodo>:<nodePort>` (rango default: 30000-32767)              | Exposición rápida en labs, on-prem sin load balancer            |
| `LoadBalancer`  | Externo (cloud)          | IP pública asignada por el proveedor cloud (AWS ELB, GCP LB, etc.)            | Producción en cloud. Internamente crea NodePort + LB externo    |
| `ExternalName`  | Alias de DNS externo     | DNS interno mapea a un nombre externo (`db.example.com`)                      | Apuntar a servicios fuera del cluster sin proxy                 |
| Headless (`ClusterIP: None`) | DNS directo a pods | DNS devuelve las IPs de los pods individuales, sin balanceo                  | StatefulSets, descubrimiento peer-to-peer                       |

### Anatomía de un Service NodePort — los 3 puertos

Un Service de tipo `NodePort` involucra **tres puertos distintos** que se confunden todo el tiempo:

```yaml
ports:
  - port: 80           # ← Puerto del Service (ClusterIP)
    targetPort: 80     # ← Puerto del Pod
    nodePort: 30011    # ← Puerto expuesto en CADA nodo del cluster
```

| Campo        | Rol                                                                                                    | Visible desde                |
| ------------ | ------------------------------------------------------------------------------------------------------ | ---------------------------- |
| `port`       | Puerto donde el Service escucha en la ClusterIP virtual                                                | Solo intra-cluster           |
| `targetPort` | Puerto del proceso adentro del Pod al que se redirige                                                  | Solo el Service lo usa       |
| `nodePort`   | Puerto que cada nodo del cluster abre hacia afuera. Tráfico llega ahí → entra al cluster → al Service  | Externo al cluster           |

Flujo de tráfico para acceso externo:

```
Cliente externo (mi laptop)
    │
    │ HTTP GET http://<IP-del-nodo>:30011/
    ▼
Nodo del cluster (kube-proxy escucha 30011 en cada nodo)
    │ kube-proxy NAT-ea hacia la ClusterIP
    ▼
Service ClusterIP (10.43.110.17:80)
    │ kube-proxy elige un endpoint
    ▼
Pod (10.42.1.5:80) — nginx escuchando
```

> **Importante**: `nodePort` se abre en **TODOS los nodos** del cluster, incluso los que no corren ningún Pod del Service. kube-proxy en cada nodo hace el routing. Por eso podés pegarle a cualquier `IP-de-nodo:30011` y va a funcionar.

### El selector como pegamento de los 3 niveles

Esta es la parte que mucha gente no internaliza al principio:

```yaml
# Deployment
spec:
  selector:
    matchLabels:
      app: nginx-deployment           # ← (1) busca pods con este label
  template:
    metadata:
      labels:
        app: nginx-deployment         # ← (2) PONE este label en los pods que crea

# Service
spec:
  selector:
    app: nginx-deployment             # ← (3) rutea tráfico a pods con este label
```

Los tres `app: nginx-deployment` **DEBEN coincidir**. No hay un check formal — son solo strings — pero si difieren, todo se desconecta silenciosamente:

- Si el `selector` del Deployment no matchea el `template.labels`: el Deployment crea pods pero los considera "huérfanos" y crea más → loop infinito
- Si el `selector` del Service no matchea: el Service queda con 0 endpoints → 503/timeout al acceder
- Si el `template.labels` cambia pero el `selector` no: el Deployment no reconoce sus propios pods como suyos

**Comprobar la conexión Service → Pods**:

```bash
kubectl get endpoints nginx-service       # debe listar 3 IP:port (una por replica)
```

Si `ENDPOINTS` está vacío, el selector no matchea ningún Pod.

## Pasos

1. Escribir `deployment.yml` con 3 replicas
2. `kubectl apply -f deployment.yml` y verificar que aparezcan 3 Pods Running
3. Escribir `service.yml` con tipo NodePort y `nodePort: 30011`
4. `kubectl apply -f service.yml` y verificar que tenga endpoints
5. Probar acceso por la ClusterIP (intra) y por el NodePort (extra)

## Comandos / Código

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-deployment
  template:
    metadata:
      labels:
        app: nginx-deployment
    spec:
      containers:
        - name: nginx-container
          image: nginx:latest
```

```bash
kubectl apply -f deployment.yml
```

```
deployment.apps/nginx-deployment created
```

```bash
kubectl get deployment/nginx-deployment
```

```
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deployment   3/3     3            3           15s
```

`3/3` confirma que las 3 replicas están corriendo y listas.

### Service NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: NodePort
  selector:
    app: nginx-deployment
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30011
```

```bash
kubectl apply -f service.yml
```

```
service/nginx-service created
```

```bash
kubectl get svc nginx-service
```

```
NAME            TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
nginx-service   NodePort   10.43.110.17   <none>        80:30011/TCP   8s
```

Lectura clave de la columna `PORT(S)`:

- **`80`** → el `port` del Service (en la ClusterIP `10.43.110.17`)
- **`30011`** → el `nodePort` (expuesto en cada nodo)
- (`targetPort: 80` no aparece acá — está implícito en la config interna)

### Verificar que el Service tiene endpoints

```bash
kubectl get endpoints nginx-service
```

```
NAME            ENDPOINTS                                       AGE
nginx-service   10.42.0.3:80,10.42.1.5:80,10.42.2.7:80           10s
```

Tres endpoints = tres pods listos detrás del Service. Si la lista estuviera vacía o tuviera menos de 3, el selector del Service no estaría matcheando todos los Pods.

> **Alternativa moderna:** `kubectl get endpointslice -l kubernetes.io/service-name=nginx-service`. Desde K8s 1.21 se usan `EndpointSlice` (más escalables) pero `kubectl get endpoints` sigue funcionando por compatibilidad.

### Verificar la conexión (las 3 vías reales)

#### Vía 1 — Intra-cluster con FQDN completo (`<svc>.<ns>.svc.cluster.local`)

Crear un pod ephemeral (con `--rm` se borra al terminar) en el namespace `default` y pegarle al Service del namespace `test-system` usando el FQDN:

```bash
kubectl run test-curl --image=curlimages/curl -it --rm --restart=Never \
  -- curl -I http://nginx-service.test-system.svc.cluster.local:80/
```

```
HTTP/1.1 200 OK
Server: nginx/1.31.0
Date: Sat, 16 May 2026 12:38:24 GMT
Content-Type: text/html
Content-Length: 896
Last-Modified: Wed, 13 May 2026 12:43:09 GMT
Connection: keep-alive
ETag: "6a0471dd-380"
Accept-Ranges: bytes
```

El FQDN tiene la forma `<service>.<namespace>.svc.cluster.local`. Esta es la forma **portable** — funciona desde cualquier namespace, ideal para apps cross-namespace.

#### Vía 2 — Externa al cluster, vía NodePort

```bash
curl -I http://10.0.0.1:30011
```

```
HTTP/1.1 200 OK
Server: nginx/1.31.0
Date: Sat, 16 May 2026 12:39:29 GMT
Content-Type: text/html
Content-Length: 896
Last-Modified: Wed, 13 May 2026 12:43:09 GMT
Connection: keep-alive
ETag: "6a0471dd-380"
Accept-Ranges: bytes
```

`10.0.0.1` es la IP de un nodo del cluster. El puerto `30011` es el `nodePort` configurado — **abierto en TODOS los nodos**, así que cualquier IP de nodo del cluster + `:30011` funciona. Lo confirmás con `kubectl get nodes -o wide`.

#### Vía 3 — Intra-cluster con nombre corto (mismo namespace)

```bash
kubectl run test-curl -n test-system --image=curlimages/curl -it --rm --restart=Never \
  -- curl -I http://nginx-service:80
```

```
HTTP/1.1 200 OK
Server: nginx/1.31.0
Date: Sat, 16 May 2026 12:40:40 GMT
Content-Type: text/html
Content-Length: 896
Last-Modified: Wed, 13 May 2026 12:43:09 GMT
Connection: keep-alive
ETag: "6a0471dd-380"
Accept-Ranges: bytes
```

```
pod "test-curl" deleted from test-system namespace
```

Notá el `-n test-system` en `kubectl run`: el pod cliente vive en el **mismo namespace** que el Service. Eso es lo que permite resolver el nombre corto `nginx-service` sin FQDN — el DNS de cluster (`CoreDNS`) auto-completa el sufijo `.test-system.svc.cluster.local` cuando el pod hace la query.

> **¿Por qué `--rm` y `--restart=Never`?** `--restart=Never` le dice a `kubectl run` que cree un Pod stand-alone (no un Deployment). `--rm` borra el Pod cuando termina el comando. Combinado con `-it` da un "container ephemeral" perfecto para troubleshooting: corre, hace lo suyo, desaparece.

#### Las 3 vías compradas

| Vía                                | Comando                                                                | Cuándo funciona                                                          |
| ---------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| FQDN completo                      | `curl http://nginx-service.test-system.svc.cluster.local`              | Desde cualquier pod del cluster, en cualquier namespace                  |
| Nombre corto                       | `curl http://nginx-service`                                            | Solo si el pod cliente está en el **mismo namespace** que el Service     |
| NodePort externo                   | `curl http://<IP-de-cualquier-nodo>:30011`                             | Desde afuera del cluster (cualquier IP de nodo sirve)                    |
| ClusterIP directo (sin DNS)        | `curl http://10.43.110.17`                                             | Sirve pero es frágil — la IP cambia si el Service se recrea              |

**Confirmación de que las 3 vías llegan al mismo contenido**: el header `ETag: "6a0471dd-380"` es idéntico en las tres respuestas. El ETag es un hash del contenido + mtime del archivo servido. Si las 3 replicas tuvieran versiones distintas de la imagen, podrías ver ETags distintos. Acá las 3 corren `nginx:1.31.0` con el mismo `index.html` default → mismo ETag.

### Confirmar el balanceo entre replicas

#### Por qué `kubectl exec deployment/<name>` NO sirve para esto

```bash
for i in {1..20}; do
  kubectl exec -it deployment/nginx-deployment -n test-system -- hostname
done
```

```
nginx-deployment-699d747d58-k98pp
nginx-deployment-699d747d58-k98pp
nginx-deployment-699d747d58-k98pp
... (20 veces el mismo pod)
```

**No es un bug del Service** — es que `kubectl exec deployment/X` resuelve internamente al **primer Pod** que matchea el selector y exec-ea directo a ese, sin pasar nunca por kube-proxy. Equivale a:

```bash
# Lo que kubectl hace por debajo:
POD=$(kubectl get pods -l app=nginx-deployment -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -- hostname
```

Para validar balanceo necesitamos: (a) requests HTTP que **sí pasen por el Service**, y (b) que cada Pod devuelva contenido distinto.

#### Test real: inyectar hostname y curl al Service

```bash
# Paso 1: en cada pod, sobrescribir el index.html con su propio hostname
for pod in $(kubectl get pods -n test-system -l app=nginx-deployment -o jsonpath='{.items[*].metadata.name}'); do
  kubectl exec -n test-system $pod -- sh -c "echo $pod > /usr/share/nginx/html/index.html"
done

# Paso 2: pegarle 30 veces al Service desde un pod ephemeral
kubectl run test-curl -n test-system --image=curlimages/curl -it --rm --restart=Never \
  -- sh -c 'for i in $(seq 1 30); do curl -s http://nginx-service/; done' \
  | sort | uniq -c
```

Output real:

```
  15 nginx-deployment-699d747d58-k98pp
   6 nginx-deployment-699d747d58-tf2h8
   9 nginx-deployment-699d747d58-v8z8g
   1 pod "test-curl" deleted from test-system namespace
```

Lectura:

- **Las 3 replicas respondieron** — el balanceo funciona, los 3 pods están detrás del Service
- **15 + 6 + 9 = 30 requests** = todas las del loop
- **La distribución es desbalanceada (50%/30%/20%)** — esto NO es un bug, es **variancia con muestra chica**. kube-proxy en iptables usa selección random independiente por request (probabilidad 1/3 cada uno). Con 30 muestras la desviación esperada es alta; con 300 converge a ~100 cada uno, con 3000 a ~1000.
- **La última línea `1 pod "test-curl" deleted ...`** viene del `--rm` (kubectl avisa por stderr que borró el pod). Es ruido — para limpiarlo, agregar `2>/dev/null` al final del comando.

#### Cómo funciona kube-proxy por dentro (a nivel iptables)

```
# Reglas iptables que instala kube-proxy para el Service (simplificado):

KUBE-SVC-NGINX:
  -m statistic --mode random --probability 0.33333  -j KUBE-SEP-POD1
  -m statistic --mode random --probability 0.50000  -j KUBE-SEP-POD2   ← prob 0.5 sobre lo que sobra
  -j KUBE-SEP-POD3                                                       ← el resto cae acá
```

Cada packet que llega al ClusterIP atraviesa esa chain. Las probabilidades 0.33 / 0.5 / 1.0 están calibradas para dar ~1/3 cada una sobre el total. Pero **la decisión es por-connection** (gracias a conntrack), no por-packet — una vez que una TCP connection se establece con un endpoint, todos sus packets van ahí. Cada `curl` del loop abre una connection nueva → decisión nueva.

> **Implicación práctica:** si tu cliente usa **HTTP keep-alive** (mantiene la connection abierta entre requests), todas esas requests van al mismo pod. Lo mismo aplica a WebSockets, gRPC sin re-resolución de DNS, conexiones JDBC con pool fijo, etc. Para distribuir carga real con clientes long-lived, hace falta un **Service mesh** (Istio/Linkerd) o un LB L7 (Ingress con nginx/Envoy) que haga balanceo por-request en vez de por-connection.

#### Modos de kube-proxy

kube-proxy tiene varios modos seleccionables al instalar el cluster:

| Modo         | Algoritmo                          | Default en               | Performance        | Algoritmos disponibles |
| ------------ | ---------------------------------- | ------------------------ | ------------------ | ---------------------- |
| `iptables`   | Random con weights (lo que vimos)  | kubeadm, k3s              | O(N) reglas        | Solo random            |
| `IPVS`       | Configurable por algoritmo         | Cluster grandes (1000+)   | O(1) lookup        | `rr`, `lc`, `dh`, `sh`, `wlc`, etc. |
| `nftables`   | Equivalente a iptables pero mejor  | K8s 1.31+ (alpha→beta)    | Mejor que iptables | Random                 |
| `kernelspace`| Windows-only                       | Windows nodes             | -                  | -                      |

Lo ves con: `kubectl get cm kube-proxy -n kube-system -o yaml | grep mode:`. La mayoría de clusters chicos usan `iptables` y para los efectos prácticos del balanceo se siente igual que round-robin.

## Cuándo NO usar NodePort

- **En producción cloud**: usar `LoadBalancer`. El cloud provider crea un LB externo (con DNS, TLS termination, etc.) y los nodos no quedan expuestos directamente.
- **Si necesitás HTTPS / paths múltiples / virtual hosts**: usar un **Ingress** controller. Un solo LoadBalancer por delante del Ingress, y el Ingress hace ruteo L7 (por path, por host).
- **Si el cluster está en una red corporativa con firewalls estrictos**: NodePort abre puertos en cada nodo (rango 30000-32767), lo cual choca con políticas de firewall corporativas comunes.

## Troubleshooting

| Problema                                                                  | Causa y solución                                                                                                                              |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `kubectl get svc` muestra el Service pero `ENDPOINTS` está vacío          | El `selector` del Service no matchea los labels de ningún Pod. Verificar con `kubectl get pods --show-labels`                                |
| Deployment crea pods pero `READY 0/3`                                     | Imagen no se puede pull, falta config, app crashea al arrancar. `kubectl describe pod <pod>` y `kubectl logs <pod>`                          |
| Service responde 503 / connection refused desde afuera                    | Pod no escucha en `targetPort`. Verificar con `kubectl exec <pod> -- ss -tlnp` o cambiar `targetPort` para que matchee el puerto real         |
| Pego al NodePort y obtengo timeout                                        | Firewall del nodo bloquea el puerto. En cloud, abrir el security group para el rango 30000-32767 desde la IP que necesite                    |
| `nodePort: 30011` ya está en uso                                          | Otro Service ya tomó ese puerto. Cambiar a otro valor en el rango 30000-32767, o dejar `nodePort` sin especificar para que K8s lo asigne     |
| El Deployment crea pods nuevos en loop, infinitamente                     | `selector.matchLabels` no matchea `template.metadata.labels`. Resultado: los pods no son reconocidos como del Deployment → se crean más      |
| Borré el pod y no se recrea                                               | El pod no estaba siendo controlado por un Deployment (era stand-alone). Verificar con `kubectl get pod <name> -o jsonpath='{.metadata.ownerReferences}'` |
| Tag `:latest` causa comportamiento inesperado en rolling updates          | Con `:latest`, K8s no sabe si la "imagen actual" es la misma que la "imagen nueva". Usar tags inmutables (`nginx:1.27.0`) en prod            |

## Recursos

- [Deployments (oficial)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Service (oficial)](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Service types — NodePort/LoadBalancer/etc (oficial)](https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types)
- [Container spec reference (oficial)](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.30/#container-v1-core)
- [`kubectl explain` para descubrir campos](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#explain) — ej: `kubectl explain pod.spec.containers --recursive`
- [Pod Lifecycle (oficial)](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Connecting Applications with Services (tutorial)](https://kubernetes.io/docs/tutorials/services/connect-applications-service/)
