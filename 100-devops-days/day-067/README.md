# Día 67 - Deploy de Guestbook App en Kubernetes (3-tier: PHP + Redis master + Redis slaves)

## Problema / Desafío

El equipo de Nautilus terminó el desarrollo de una **Guestbook app** (clásica de los tutoriales de Kubernetes — frontend PHP + backend Redis con replicación master/slave). Hay que desplegarla en el cluster con su topología completa.

Requirements en bloques:

### Back-end (Redis)

- **Deployment `redis-master`**:
  - `replicas: 1`
  - Container `master-redis-datacenter`, imagen `redis`
  - `requests`: CPU `100m`, memory `100Mi`
  - `containerPort: 6379`
- **Service `redis-master`**: port/targetPort `6379`
- **Deployment `redis-slave`**:
  - `replicas: 2`
  - Container `slave-redis-datacenter`, imagen `gcr.io/google_samples/gb-redisslave:v3`
  - `requests`: CPU `100m`, memory `100Mi`
  - Env var `GET_HOSTS_FROM=dns`
  - `containerPort: 6379`
- **Service `redis-slave`**: port `6379` (selector → pods con label `app: redis-slave`)
- **Service `redis-follower`**: port/targetPort `6379`, selector `app: redis-slave` (alias del anterior)

### Front-end (PHP)

- **Deployment `frontend`**:
  - `replicas: 3`
  - Container `php-redis-datacenter`, imagen `gcr.io/google-samples/gb-frontend@sha256:a908df8486ff66f2c4daa0d3d8a2fa09846a1fc8efd65649c0109695c7c5cbff`
  - `requests`: CPU `100m`, memory `100Mi`
  - Env var `GET_HOSTS_FROM=dns`
  - `containerPort: 80`
- **Service `frontend`**: tipo `NodePort`, port `80`, `nodePort: 30009`

## Conceptos clave

### Arquitectura del stack

```
┌─────────────────────────────── cluster ───────────────────────────────────────┐
│                                                                                │
│  Cliente externo → nodePort 30009                                              │
│                         │                                                      │
│                         ▼                                                      │
│  ┌──────────────────────────────────────┐                                     │
│  │ Service frontend (NodePort)           │                                     │
│  │ port 80 → targetPort 80               │                                     │
│  └──────────┬───────────────────────────┘                                     │
│             │ selector: app=frontend                                           │
│             ▼                                                                  │
│  ┌──────────────────────────────────────┐                                     │
│  │ Deployment frontend (3 replicas)      │                                     │
│  │ image: gb-frontend@sha256:...         │                                     │
│  │ GET_HOSTS_FROM=dns                    │                                     │
│  └──────────┬───────────────────────────┘                                     │
│             │ DNS lookup "redis-master" (writes) y "redis-slave" (reads)       │
│             ▼                                                                  │
│  ┌──────────────────────────┐  ┌──────────────────────────────────────────┐  │
│  │ Service redis-master     │  │ Service redis-slave / redis-follower      │  │
│  │ port 6379                │  │ port 6379 (dos nombres, mismos pods)      │  │
│  └──────────┬───────────────┘  └────────────────┬─────────────────────────┘  │
│             │                                    │                             │
│             ▼                                    ▼                             │
│  ┌──────────────────────────┐  ┌──────────────────────────────────────────┐  │
│  │ Deployment redis-master  │  │ Deployment redis-slave (2 replicas)       │  │
│  │ image: redis             │  │ image: gb-redisslave:v3                   │  │
│  │ 1 replica                │  │ GET_HOSTS_FROM=dns                        │  │
│  └──────────────────────────┘  └──────────────────────────────────────────┘  │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

### Patrón master/slave en Redis (replicación clásica)

| Rol     | Cantidad      | Operaciones aceptadas              | Comportamiento                                                |
| ------- | ------------- | ---------------------------------- | ------------------------------------------------------------- |
| Master  | 1             | Lectura **y** escritura            | Recibe los writes; replica async hacia los slaves              |
| Slave   | N (típico 2+) | **Solo lectura**                   | Recibe el stream de replicación del master; sirve lecturas    |

El frontend escribe a `redis-master:6379` (`SET`, `INCR`, etc.) y lee de `redis-slave:6379` (`GET`, `LRANGE`, etc.). Este patrón distribuye carga y permite scale horizontal de las lecturas.

> Nota terminológica: Redis 5.0+ desaprecia el término "slave" en favor de "replica" (`REPLICAOF` reemplazó a `SLAVEOF`). KodeKloud mantiene el viejo término en el lab para compatibilidad con el tutorial original de K8s, pero pide **también** el Service `redis-follower` — el nombre moderno del mismo concepto.

### `GET_HOSTS_FROM=dns` — la pieza que ata el frontend con Redis

La imagen `gb-frontend` lee esta env var para decidir cómo descubrir los Redis. Dos modos posibles:

| Valor                     | Cómo descubre los hosts                                                          | Problema                                                                       |
| ------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `env` *(legacy)*          | Lee `REDIS_MASTER_SERVICE_HOST` y `REDIS_SLAVE_SERVICE_HOST` (env vars que K8s inyecta automáticamente para cada Service del namespace) | Requiere que el Service exista **antes** de que el Pod del cliente arranque    |
| `dns` *(este lab)*        | Hace `gethostbyname("redis-master")` y `gethostbyname("redis-slave")` — usa kube-dns | Los Services pueden crearse en cualquier orden; el DNS se actualiza al instante |

`dns` es el modo moderno y robusto — funciona aunque los Services se creen después del Pod (kube-dns añade los registros al cluster DNS al instante).

### Por qué dos Services (`redis-slave` + `redis-follower`) con el mismo selector

Los dos Services apuntan a los **mismos Pods** vía `selector: app=redis-slave`. Es un patrón de **aliasing** — el código viejo de la app busca `redis-slave`, el código nuevo busca `redis-follower`. K8s sirve los mismos endpoints bajo ambos nombres sin overhead adicional.

```yaml
# Service A
metadata:
  name: redis-slave
spec:
  selector:
    app: redis-slave        # ← misma key/value
  ports: [...]

---
# Service B
metadata:
  name: redis-follower
spec:
  selector:
    app: redis-slave        # ← misma key/value
  ports: [...]
```

`kubectl get endpoints` sobre ambos Services devolvería las **mismas IPs** — solo cambia el nombre DNS por el que se accede.

### Service Discovery por DNS — qué nombres resuelven

Dentro del cluster, los Services se acceden por:

```
<service-name>.<namespace>.svc.cluster.local
<service-name>.<namespace>          # forma corta cuando el namespace está en search path
<service-name>                       # más corta — funciona si el cliente está en el mismo namespace
```

Para este lab, el frontend (en `default`) puede hacer:

```bash
redis-master                    # ← short form (mismo namespace)
redis-master.default            # ← con namespace
redis-master.default.svc.cluster.local   # ← FQDN completo
```

Todos resuelven a la misma ClusterIP del Service `redis-master`.

### Glosario del manifest (lo nuevo)

| Campo                                     | Significado                                                                                  |
| ----------------------------------------- | -------------------------------------------------------------------------------------------- |
| Imagen por **digest** (`@sha256:...`)     | Pinning inmutable de la imagen. Garantiza que el binario sea exactamente el mismo aunque alguien re-tageé `latest` |
| `containerPort` sin Service en el manifest | El frontend Pod expone `:80` aunque su Service mapea `80→80`. Si se omite, el Service igual rutea porque K8s no valida que la app escuche en el puerto declarado |
| `selector` distinto entre dos Services    | Permite aliasing — múltiples nombres DNS apuntando a los mismos Pods                         |

## Pasos

1. Aplicar el manifest del back-end:
   - Deployment `redis-master`
   - Service `redis-master`
2. Aplicar el manifest del slave:
   - Deployment `redis-slave`
   - Service `redis-slave`
   - Service `redis-follower` (alias del anterior)
3. Aplicar el manifest del front-end:
   - Deployment `frontend`
   - Service `frontend` (NodePort)
4. Validar con `kubectl get pods` que los 6 Pods (1 master + 2 slaves + 3 frontend) estén `Running`
5. Confirmar la página de Guestbook pegando al NodePort externo

## Comandos / Código

### 1. Back-end: redis-master

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-master
  labels:
    app: redis-master-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-master-deployment
  template:
    metadata:
      labels:
        app: redis-master-deployment
    spec:
      containers:
        - name: master-redis-datacenter
          image: redis:latest
          resources:
            requests:
              cpu: 100m
              memory: 100Mi
          ports:
            - containerPort: 6379

---
apiVersion: v1
kind: Service
metadata:
  name: redis-master
  labels:
    app: redis-master
spec:
  selector:
    app: redis-master-deployment
  ports:
    - port: 6379
      targetPort: 6379
```

```bash
kubectl apply -f backend.yml
```

```
deployment.apps/redis-master created
service/redis-master created
```

### 2. Back-end: redis-slave + dos Services (slave + follower)

> **Detalle del lab**: el requirement pide **tres** Services para Redis: `redis-master`, `redis-slave` y `redis-follower`. El primer envío del manifest omitió el Service `redis-slave` y solo creó dos (`redis-master` y `redis-follower`). La aplicación cargó funcionalmente igual (HTTP 200), pero el validador del lab exige los tres por nombre. El fix consistió en agregar el Service `redis-slave` con el mismo selector `app: redis-slave` que el `redis-follower` — los dos terminan apuntando a los mismos Pods. Manifest correcto con los **tres** Services:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-slave
  labels:
    app: redis-slave-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: redis-slave
  template:
    metadata:
      labels:
        app: redis-slave
    spec:
      containers:
        - name: slave-redis-datacenter
          image: gcr.io/google_samples/gb-redisslave:v3
          resources:
            requests:
              cpu: 100m
              memory: 100Mi
          env:
            - name: GET_HOSTS_FROM
              value: "dns"
          ports:
            - containerPort: 6379

---
# Service 1 — redis-slave (nombre clásico)
apiVersion: v1
kind: Service
metadata:
  name: redis-slave
  labels:
    app: redis-slave
spec:
  selector:
    app: redis-slave
  ports:
    - port: 6379
      targetPort: 6379

---
# Service 2 — redis-follower (alias moderno, mismo selector)
apiVersion: v1
kind: Service
metadata:
  name: redis-follower
  labels:
    app: redis-follower
spec:
  selector:
    app: redis-slave
  ports:
    - port: 6379
      targetPort: 6379
```

```bash
kubectl apply -f slave.yml
```

Después del fix (agregando el Service `redis-slave` que faltaba):

```
deployment.apps/redis-slave unchanged
service/redis-follower unchanged
service/redis-slave created
```

Validación de los tres Services Redis ya creados:

```bash
kubectl get svc redis-master redis-slave redis-follower
```

```
NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
redis-master     ClusterIP   10.43.103.55    <none>        6379/TCP   xx
redis-slave      ClusterIP   10.43.37.187    <none>        6379/TCP   xx
redis-follower   ClusterIP   10.43.72.126    <none>        6379/TCP   xx
```

> Las tres ClusterIPs son **distintas** porque cada Service es un objeto K8s independiente, aunque `redis-slave` y `redis-follower` apunten al mismo conjunto de Pods. El kube-proxy instala reglas iptables/IPVS separadas para cada ClusterIP.

### 3. Front-end (PHP + Service NodePort)

> **Detalle del lab (2do bug del envío)**: el primer manifest del frontend **omitió el bloque `ports:` dentro del container**. La app PHP igual escucha en `:80` (la imagen `gb-frontend` está construida para servir en ese puerto) y el Service NodePort rutea tráfico correctamente — el `curl` devolvió `HTTP 200`. Pero el validador del lab lee la spec literal y rechaza con `containerPort for guestbook deployment is not '80'`. El `describe` lo confirma:
>
> ```
> Containers:
>    php-redis-datacenter:
>     Image:      gcr.io/google-samples/gb-frontend@sha256:...
>     Port:       <none>          ← debería ser 80/TCP
>     Host Port:  <none>
> ```
>
> Fix: agregar `ports: - containerPort: 80` al container del Deployment. Manifest correcto:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: php-redis-datacenter
          image: gcr.io/google-samples/gb-frontend@sha256:a908df8486ff66f2c4daa0d3d8a2fa09846a1fc8efd65649c0109695c7c5cbff
          resources:
            requests:
              cpu: 100m
              memory: 100Mi
          env:
            - name: GET_HOSTS_FROM
              value: "dns"
          ports:
            - containerPort: 80

---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30009
```

```bash
kubectl apply -f frontend.yml
```

```
deployment.apps/frontend created
service/frontend created
```

### Verificación general

```bash
kubectl get pods
```

```
NAME                            READY   STATUS    RESTARTS   AGE
frontend-847cd9797d-47jqq       1/1     Running   0          68s
frontend-847cd9797d-76shm       1/1     Running   0          68s
frontend-847cd9797d-tjxgm       1/1     Running   0          68s
redis-master-6c4c4b9d75-phsrv   1/1     Running   0          19m
redis-slave-5476897f9-dpsrw     1/1     Running   0          6m56s
redis-slave-5476897f9-x9qxp     1/1     Running   0          6m56s
```

Seis Pods esperados: 1 master + 2 slaves + 3 frontends.

```bash
kubectl get svc
```

```
NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
frontend         NodePort    10.43.x.x       <none>        80:30009/TCP   xx
redis-master     ClusterIP   10.43.103.55    <none>        6379/TCP       xx
redis-slave      ClusterIP   10.43.y.y       <none>        6379/TCP       xx
redis-follower   ClusterIP   10.43.72.126    <none>        6379/TCP       xx
```

Cuatro Services esperados: 3 internos (Redis) + 1 NodePort (frontend).

### Validación funcional — Guestbook accesible vía NodePort

```bash
curl -I https://30009-port-<lab-id>.labs.kodekloud.com/
```

```
HTTP/2 200
content-type: text/html
content-length: 920
```

`200 OK` con la página HTML cargada confirma que el frontend está sirviendo. La conectividad real al Redis se prueba abriendo la página, escribiendo un mensaje en el guestbook y confirmando que persiste tras refrescar.

### Validación de DNS interno (opcional, exploratoria)

Desde un Pod del frontend, confirmar que los nombres resuelven a las ClusterIPs esperadas:

```bash
kubectl exec -it deployment/frontend -- nslookup redis-master
```

```
Server:         10.43.0.10
Address:        10.43.0.10:53

Name:   redis-master.default.svc.cluster.local
Address: 10.43.103.55
```

```bash
kubectl exec -it deployment/frontend -- nslookup redis-slave
kubectl exec -it deployment/frontend -- nslookup redis-follower
```

Ambos resuelven al mismo conjunto de IPs (las de los 2 Pods `redis-slave-*`).

## Patrón observado: dos Services apuntando a los mismos Pods

`kubectl get endpoints` confirma el aliasing en la práctica:

```bash
kubectl get endpoints redis-slave redis-follower
```

```
NAME             ENDPOINTS                                    AGE
redis-slave      10.22.0.10:6379,10.22.0.11:6379             xx
redis-follower   10.22.0.10:6379,10.22.0.11:6379             xx
```

Las mismas IPs, dos nombres DNS distintos. Es el equivalente K8s de un CNAME / alias de DNS — útil cuando un mismo conjunto de Pods debe ser accesible bajo múltiples nombres por compatibilidad de código viejo y nuevo.

## Conexión con días anteriores

- **Día 56 (Deployment + Service NodePort)**: el frontend de hoy usa exactamente el mismo patrón — Deployment + NodePort para exposición externa.
- **Día 57 (env vars + ConfigMap)**: los Pods de hoy usan `env: name/value` literal (sin ConfigMap), pero el patrón es el mismo. `GET_HOSTS_FROM=dns` es la decisión de runtime que conecta el frontend con Redis.
- **Día 63 (stack multi-componente)**: la primera vez que apareció un stack de 4+ recursos. Hoy es de **9 recursos** (3 Deployments + 4 Services + 6 Pods). El patrón escala bien con el mismo manifest declarativo.
- **Día 64 (troubleshooting con 2 bugs)**: la herramienta `kubectl events` se vuelve a usar para seguir el cronograma de scheduling/pull/start de cada Pod.
- **Día 65 (Redis con ConfigMap)**: primera vez con Redis. Hoy se agrega la dimensión de **replicación** (master + slaves).
- **Día 66 (MySQL stack completo)**: misma idea de stack productivo con DB + Service. Aquí no hay PV (Redis es in-memory por design), pero la estructura general es la misma.

## Reflexión: la primera arquitectura "real" del journal

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- Este es el primer lab del journal con **arquitectura productiva real** (master/slave, distribución read/write, service aliasing, DNS-based discovery). ¿Cómo se siente la diferencia respecto a labs anteriores?
- El detalle del Service `redis-slave` faltante: ¿lo notaste durante el envío o pasó desapercibido? ¿El validador del lab lo aceptó igual?
- `GET_HOSTS_FROM=dns` vs el modelo de env vars legacy: ¿conocías la distinción antes? ¿Te parece que el modelo DNS es estrictamente superior, o tiene trade-offs?
- Apps que separan reads de writes (master/slave en Redis, primary/replica en Postgres): ¿es un patrón que viste antes en tu carrera? ¿Implementado por la app o por una capa de routing (ProxySQL, PgBouncer)?
- El aliasing de Services (`redis-slave` y `redis-follower` apuntando a los mismos Pods): ¿te parece elegante o frágil?
2–10 líneas, tono directo, primera persona implícita como en días previos. -->

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Validador del lab marca Redis incompleto aunque la app cargue           | Falta uno de los **tres** Services pedidos (`redis-master`, `redis-slave`, `redis-follower`)         | Crear los tres explícitamente en el manifest, aunque dos compartan selector                       |
| Validador rechaza con `containerPort for X deployment is not 'N'`       | El bloque `ports:` está ausente en el container del Deployment, aunque la app escuche en ese puerto  | Declarar `ports: - containerPort: N` aunque sea solo informativo. El validador lee la spec literal |
| Frontend devuelve HTTP 500 al guardar un guestbook entry                 | Frontend no resuelve `redis-master` (Service no existe o nombre distinto)                            | `kubectl exec -it <frontend-pod> -- nslookup redis-master` para confirmar resolución               |
| Frontend devuelve la página vacía o sin entries cargados                 | Frontend no resuelve `redis-slave` (Service no existe)                                               | Mismo enfoque — nslookup y `kubectl get endpoints`                                                |
| Pod del frontend en `Pending`                                            | No hay capacidad — `requests` de los 3 Pods de frontend (`100m × 3`) + los 3 Pods Redis no caben en el nodo | `kubectl describe pod` para ver el mensaje de scheduler                                            |
| Pod en `ImagePullBackOff` con `gcr.io/google_samples/...`               | El registry `gcr.io` requiere internet — en clusters airgapped no funciona                            | Pre-pull la imagen al nodo o usar mirror interno                                                  |
| `Endpoints: <none>` en el Service `redis-slave` o `redis-follower`      | El selector no matchea ningún Pod (typo o label distinto del Pod template)                            | `kubectl get pods -l app=redis-slave --show-labels` para confirmar labels reales                  |
| `GET_HOSTS_FROM=dns` ignorado por el frontend                            | La env var debe llamarse exactamente así (case-sensitive)                                            | Verificar en `kubectl describe pod` que aparece en `Environment:`                                  |
| Page tarda mucho en cargar la primera vez                                | Pull de imagen `gb-frontend` es ~341 MB — primera vez requiere descarga completa                      | Esperar; siguientes pulls usan cache del nodo                                                     |
| Frontend conecta solo al master, no al slave                             | `GET_HOSTS_FROM` no está seteado o está mal escrito (defaults a `env`)                                | Confirmar en `describe` que `GET_HOSTS_FROM=dns` aparece                                          |
| Service `redis-slave` y `redis-follower` devuelven Endpoints distintos   | Los selectors no son idénticos                                                                       | Ambos Services deben tener el **mismo** `spec.selector` para apuntar a los mismos Pods             |
| Conectividad al NodePort 30009 falla con timeout                         | El proxy externo de KodeKloud puede tardar 30s+ en mapear el nuevo nodePort                          | Esperar y reintentar; verificar que el Service tiene endpoints                                    |

## Recursos

- [Guestbook tutorial (oficial K8s)](https://kubernetes.io/docs/tutorials/stateless-application/guestbook/)
- [Service DNS in Kubernetes](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Redis Replication (oficial)](https://redis.io/docs/management/replication/)
- [`GET_HOSTS_FROM` en gb-frontend source](https://github.com/kubernetes/examples/tree/master/guestbook)
- [Service environment variables (legacy)](https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/#environment-variables)
- [Image pinning by digest](https://kubernetes.io/docs/concepts/containers/images/#image-names)
