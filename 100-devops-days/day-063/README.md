# Día 63 - Deploy de Iron Gallery App en Kubernetes (stack multi-componente)

## Problema / Desafío

El equipo de Nautilus tiene una app **Iron Gallery** (frontend nginx) y su base de datos **Iron DB** (MariaDB). Hay que desplegarlas en K8s **aisladas en un namespace propio**, con dos services: uno interno para que el frontend pueda hablarle a la DB, y uno NodePort para exponer la UI hacia afuera.

Requirements precisos:

- **Namespace:** `iron-namespace-nautilus`
- **Deployment app:** `iron-gallery-deployment-nautilus`
  - Labels (Deployment + selector + template): `run: iron-gallery`
  - `replicas: 1`
  - Container `iron-gallery-container-nautilus`, imagen `kodekloud/irongallery:2.0`
  - `limits`: memory `100Mi`, CPU `50m`
  - Dos `emptyDir` montados: `config → /usr/share/nginx/html/data`, `images → /usr/share/nginx/html/uploads`
- **Deployment DB:** `iron-db-deployment-nautilus`
  - Labels: `db: mariadb`
  - Container `iron-db-container-nautilus`, imagen `kodekloud/irondb:2.0`
  - Env: `MYSQL_DATABASE=database_web`, `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`, `MYSQL_USER` (custom, no `root`)
  - Volumen `db` (emptyDir) montado en `/var/lib/mysql`
- **Service DB:** `iron-db-service-nautilus`, `ClusterIP`, port/targetPort `3306`, selector `db: mariadb`
- **Service app:** `iron-gallery-service-nautilus`, `NodePort`, port/targetPort `80`, `nodePort: 32678`, selector `run: iron-gallery`

Nota del lab: **no hay que conectar realmente frontend y DB**; basta con que la página de instalación cargue al pegarle al NodePort.

## Conceptos clave

### Por qué un namespace dedicado

Hasta el Día 62 todo se desplegaba en `default`. Iron Gallery es el primer lab del journal que pide **aislar la app en su propio namespace**. La motivación tiene varias capas:

| Beneficio                                | Cómo lo provee el namespace                                                              |
| ---------------------------------------- | ---------------------------------------------------------------------------------------- |
| **Aislamiento lógico**                   | Recursos con el mismo nombre coexisten en namespaces distintos (`db` en uno, `db` en otro) |
| **Boundary de RBAC**                     | Roles típicamente se definen por namespace — más fácil de granularizar permisos          |
| **Boundary de ResourceQuotas / LimitRanges** | Se pueden poner cuotas globales (CPU, memoria, número de Pods) por namespace             |
| **Boundary de NetworkPolicies**          | Las reglas de aislamiento de red suelen mirar el namespace de origen / destino           |
| **Scope del DNS interno**                | El FQDN de un Service incluye el namespace: `iron-db-service-nautilus.iron-namespace-nautilus.svc.cluster.local` |
| **Boundary de visibilidad operacional**  | `kubectl get all -n <ns>` muestra **solo** los recursos del namespace                    |

> Lo que el namespace **no** te da: aislamiento de red por default. Pods de namespaces distintos se ven entre sí salvo que apliques NetworkPolicies. El "aislamiento" es lógico, no de red.

### Stack multi-componente — qué cambia respecto a un Pod aislado

En labs anteriores cada componente vivía solo. Acá conviven cuatro recursos en el namespace, con relaciones entre ellos:

```
   ┌─────────────────────────────── namespace: iron-namespace-nautilus ───────────────────────────┐
   │                                                                                                │
   │  ┌───────────────────────────┐         ┌─────────────────────────────┐                       │
   │  │  iron-gallery-deployment  │         │  iron-db-deployment         │                       │
   │  │  labels: run=iron-gallery │         │  labels: db=mariadb         │                       │
   │  │  ┌──────────────┐         │         │  ┌──────────────────────┐   │                       │
   │  │  │ Pod          │         │         │  │ Pod                  │   │                       │
   │  │  │ - nginx      │         │         │  │ - mariadb            │   │                       │
   │  │  │ - emptyDir x2│         │         │  │ - emptyDir (db data) │   │                       │
   │  │  └──────────────┘         │         │  └──────────────────────┘   │                       │
   │  └──────────┬────────────────┘         └────────────┬────────────────┘                       │
   │             │ selector run=iron-gallery              │ selector db=mariadb                    │
   │             ▼                                        ▼                                         │
   │  ┌──────────────────────────────┐       ┌─────────────────────────────┐                       │
   │  │ iron-gallery-service          │       │ iron-db-service              │                       │
   │  │ type: NodePort                │       │ type: ClusterIP              │                       │
   │  │ port 80 → targetPort 80       │       │ port 3306 → targetPort 3306  │                       │
   │  │ nodePort 32678                │       │                              │                       │
   │  └──────────────┬────────────────┘       └─────────────────────────────┘                       │
   │                 │                                                                              │
   └─────────────────┼──────────────────────────────────────────────────────────────────────────────┘
                     ▼
              Cliente externo (nodeIP:32678)
```

Detalles a notar:

- El service de la DB es **`ClusterIP`** — la DB no se expone afuera. Solo otros Pods del cluster pueden hablarle.
- El service de la app es **`NodePort`** — accesible desde fuera del cluster via `<nodeIP>:32678`.
- Los selectors son **distintos** entre los dos services (`run: iron-gallery` vs `db: mariadb`) — cada uno apunta solo a sus Pods.

### Distinción entre `ClusterIP`, `NodePort` y `LoadBalancer`

| Tipo de Service     | IP asignada                                              | Accesible desde                                              | Cuándo usar                                                       |
| ------------------- | -------------------------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------------------------- |
| `ClusterIP` (default) | IP virtual interna del cluster                          | **Solo desde dentro** del cluster                            | Servicios internos: DBs, backends, microservicios privados        |
| `NodePort`          | ClusterIP + un puerto en **cada nodo** (30000–32767)     | Dentro del cluster **y** desde fuera via `<nodeIP>:<nodePort>` | Demos, labs, exposición simple sin LoadBalancer                   |
| `LoadBalancer`      | ClusterIP + NodePort + IP pública del cloud provider     | Internet                                                     | Producción en cloud (provisiona ELB / NLB / GCLB)                 |
| `ExternalName`      | Sin IP — devuelve un CNAME                               | Cualquiera que resuelva DNS interno                          | Apuntar a un servicio externo (RDS, hostname legacy)              |

> El `nodePort: 32678` del lab cae dentro del rango permitido por default (30000–32767). Si no lo declarás explícitamente, K8s asigna uno aleatorio del rango.

### Glosario del manifest (lo nuevo / lo que vale anclar)

| Campo                                          | Significado                                                                              |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `metadata.namespace`                           | Namespace donde vive el recurso. Si se omite, va a `default`                             |
| `spec.selector` (en Service)                   | Conjunto de labels que el Service busca en los Pods para considerarlos endpoints         |
| `spec.selector.matchLabels` (en Deployment)    | Labels que el Deployment usa para identificar a "sus" Pods                               |
| `spec.template.metadata.labels`                | Labels que el Deployment escribe en cada Pod que crea                                    |
| `spec.template.spec.containers[].env[].value`  | Valor literal de la variable de entorno (plano, no encriptado)                           |
| `spec.ports[].port`                            | Puerto del Service (lo que ve el cliente que hace `svc.namespace.svc.cluster.local:port`) |
| `spec.ports[].targetPort`                      | Puerto del Pod / container al que el Service redirige                                    |
| `spec.ports[].nodePort`                        | Puerto **del nodo** que el kube-proxy expone (solo aplica si `type: NodePort` o `LoadBalancer`) |
| `spec.type: ClusterIP \| NodePort \| LoadBalancer \| ExternalName` | Tipo de Service                                                                          |

### Sobre `resources.limits` sin `requests`

El Deployment de la app define:

```yaml
resources:
  limits:
    memory: 100Mi
    cpu: 50m
```

Sin `requests`. K8s aplica una regla de relleno: **si solo se define `limits`, los `requests` se asumen iguales a los `limits`**. Esto afecta:

- **QoS class** del Pod: pasa a ser `Burstable` (no `BestEffort`). Un `BestEffort` es el primero en ser evicted bajo presión de memoria; un `Burstable` está protegido hasta su `request`.
- **Scheduling**: el scheduler reserva `50m CPU` y `100Mi memory` en el nodo elegido, no solo "lo que use".

Para apps reales conviene declarar `requests` **explícitamente**, generalmente menores que `limits`, para que la app tenga garantía mínima pero pueda subir bajo carga. El lab no lo pide, pero es la frontera entre "lab" y "producción".

### `emptyDir` repetido y reutilizado en el lab

Tres `emptyDir` distintos en este lab:

| Volumen      | Pod              | Propósito                                                               |
| ------------ | ---------------- | ----------------------------------------------------------------------- |
| `config`     | Iron Gallery     | `/usr/share/nginx/html/data` — config dinámica que la app genera        |
| `images`     | Iron Gallery     | `/usr/share/nginx/html/uploads` — uploads del usuario                   |
| `db`         | Iron DB          | `/var/lib/mysql` — data files de MariaDB                                |

Es importante recordar (Día 54): **`emptyDir` se pierde cuando el Pod muere**. Para un lab está bien; para producción, los tres deberían ser `PVC` con un StorageClass real — especialmente el de MariaDB, donde perder `/var/lib/mysql` significa perder la base entera.

## Pasos

1. Crear el namespace
2. Aplicar el Deployment de la app (gallery)
3. Aplicar el Deployment de la DB
4. Aplicar el Service `ClusterIP` para la DB
5. Aplicar el Service `NodePort` para la app
6. Verificar que ambos Pods están en `Running`
7. Confirmar que el Service NodePort responde al pegarle al puerto del nodo

## Comandos / Código

### 1. Namespace

```bash
kubectl create namespace iron-namespace-nautilus
```

```
namespace/iron-namespace-nautilus created
```

### 2. Deployment de Iron Gallery

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: iron-namespace-nautilus
  name: iron-gallery-deployment-nautilus
  labels:
    run: iron-gallery
spec:
  replicas: 1
  selector:
    matchLabels:
      run: iron-gallery
  template:
    metadata:
      labels:
        run: iron-gallery
    spec:
      containers:
        - name: iron-gallery-container-nautilus
          image: kodekloud/irongallery:2.0
          resources:
            limits:
              memory: 100Mi
              cpu: 50m
          volumeMounts:
            - name: config
              mountPath: "/usr/share/nginx/html/data"
            - name: images
              mountPath: "/usr/share/nginx/html/uploads"
      volumes:
        - name: config
          emptyDir: {}
        - name: images
          emptyDir: {}
```

```bash
kubectl apply -f deployment-app.yml
```

```
deployment.apps/iron-gallery-deployment-nautilus created
```

### 3. Deployment de Iron DB

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: iron-namespace-nautilus
  name: iron-db-deployment-nautilus
  labels:
    db: mariadb
spec:
  replicas: 1
  selector:
    matchLabels:
      db: mariadb
  template:
    metadata:
      labels:
        db: mariadb
    spec:
      containers:
        - name: iron-db-container-nautilus
          image: kodekloud/irondb:2.0
          env:
            - name: MYSQL_DATABASE
              value: "database_web"
            - name: MYSQL_ROOT_PASSWORD
              value: "d12371760f40c7d8"
            - name: MYSQL_PASSWORD
              value: "d12371760f40c7d8"
            - name: MYSQL_USER
              value: "iron_user"
          volumeMounts:
            - name: db
              mountPath: "/var/lib/mysql"
      volumes:
        - name: db
          emptyDir: {}
```

```bash
kubectl apply -f deployment-db.yml
```

```
deployment.apps/iron-db-deployment-nautilus created
```

> **Sobre las credenciales en `env`**: están en plano en el manifest, lo cual es exactamente lo que el Día 62 dejó como **anti-patrón**. La forma correcta sería un `Secret` con `MYSQL_ROOT_PASSWORD` y referenciarlo con `valueFrom.secretKeyRef`. El lab no lo pide, pero conviene anotarlo: en producción, **ningún password va literal en el Deployment**.

### 4. Service de Iron DB (ClusterIP)

```yaml
apiVersion: v1
kind: Service
metadata:
  namespace: iron-namespace-nautilus
  name: iron-db-service-nautilus
spec:
  type: ClusterIP
  selector:
    db: mariadb
  ports:
    - protocol: TCP
      port: 3306
      targetPort: 3306
```

```bash
kubectl apply -f service-db.yml
```

```
service/iron-db-service-nautilus created
```

### 5. Service de Iron Gallery (NodePort)

```yaml
apiVersion: v1
kind: Service
metadata:
  namespace: iron-namespace-nautilus
  name: iron-gallery-service-nautilus
spec:
  type: NodePort
  selector:
    run: iron-gallery
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 32678
```

```bash
kubectl apply -f service-app.yml
```

```
service/iron-gallery-service-nautilus created
```

### Verificación general del namespace

```bash
kubectl get all -n iron-namespace-nautilus
```

```
NAME                                                   READY   STATUS    RESTARTS   AGE
pod/iron-db-deployment-nautilus-7f9c79866d-rlkpx       1/1     Running   0          3m
pod/iron-gallery-deployment-nautilus-87cf5796b-7lzlh   1/1     Running   0          12m

NAME                                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/iron-db-service-nautilus        ClusterIP   10.43.147.116   <none>        3306/TCP       3m
service/iron-gallery-service-nautilus   NodePort    10.43.153.135   <none>        80:32678/TCP   7s

NAME                                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/iron-db-deployment-nautilus        1/1     1            1           3m
deployment.apps/iron-gallery-deployment-nautilus   1/1     1            1           12m
```

> El comando `kubectl get all -n <ns>` es la forma más rápida de tener el panorama de un stack desplegado en un namespace — muestra Pods, Services, Deployments y ReplicaSets en una sola vista.

### Verificación del Service del frontend (sin abrir browser)

```bash
# Desde el jump host, pegarle al NodePort
curl -sI http://<nodeIP>:32678 | head -5
```

```
HTTP/1.1 200 OK
Server: nginx/1.19.6
...
```

### Validación del endpoint del Service de DB

```bash
kubectl get endpoints iron-db-service-nautilus -n iron-namespace-nautilus
```

```
NAME                       ENDPOINTS         AGE
iron-db-service-nautilus   10.244.0.42:3306  3m
```

Si la columna `ENDPOINTS` quedara vacía, significa que **ningún Pod matchea el selector** del Service. Es el bug clásico de selector/labels (revisado a fondo en el Día 58).

## Anatomía de las relaciones entre recursos (lo que el lab "obliga a ver")

| Relación                                       | Cómo se establece                                                                                  | Si se rompe                                                       |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Service → Pod                                   | `service.spec.selector` matchea `pod.metadata.labels`                                              | Service queda sin endpoints; `kubectl get endpoints` muestra `<none>` |
| Deployment → Pod (vía ReplicaSet)               | `deployment.spec.selector.matchLabels` matchea `template.metadata.labels`                          | Deployment falla con "selector does not match template labels"    |
| Pod → DNS interno                               | El kube-dns crea un registro `<service>.<namespace>.svc.cluster.local`                             | El frontend no resuelve `iron-db-service-nautilus` por DNS         |
| Frontend → DB                                   | El frontend hace `connect(iron-db-service-nautilus.iron-namespace-nautilus:3306)`                  | Si los nombres no matchean, falla la conexión (no aplica en este lab) |
| Cliente externo → Frontend                      | El kube-proxy escucha en `<nodeIP>:32678` y forwardea al Pod                                       | Si `nodePort` está en uso por otro Service, el apply falla         |

## Conexión con días anteriores

- **Día 48 (primer Pod)**: el mismo bloque `spec.containers` con `image`, ahora multiplicado por dos containers en dos Deployments.
- **Día 49 (Deployments)**: la misma cáscara `Deployment → ReplicaSet → Pod`, ahora con `selector.matchLabels` apuntando a `run` y `db` (en vez del clásico `app`).
- **Día 50 (Resource Limits)**: aparece otra vez el bloque `resources.limits`, ahora con la observación de que omitir `requests` no es free — hereda los valores del `limits` y cambia el QoS class.
- **Día 54 (`emptyDir`)**: tres `emptyDir` distintos en un solo stack. Sigue valiendo la regla: **no usar `emptyDir` para datos a conservar**.
- **Día 56 (Deployment + NodePort)**: idéntico patrón, ahora aplicado a un stack con dos Deployments en lugar de uno.
- **Día 57 (env vars)**: las variables de DB están planas en el manifest. El Día 57 introdujo el patrón cómo evitarlo (ConfigMap / Secret + `valueFrom`); acá se vuelve al estilo plano por requirement del lab.
- **Día 58 (autopsia de labels)**: el riesgo de desalinear `selector` con `template.labels` sigue presente — ahora multiplicado por dos Deployments y dos Services.
- **Día 60 (PV + PVC)**: el `emptyDir` del Pod de MariaDB es la versión "lab" del PVC que existiría en producción. Misma forma del manifest, distinto backend.
- **Día 62 (Secrets)**: el lab pide passwords planos en `env`. La pieza que falta para hacerlo "production-grade" es exactamente lo que se vio ayer: convertir esas envs a `valueFrom.secretKeyRef` apuntando a un Secret.

## Reflexión: dos containers, dos labels distintas — qué se aprende del patrón

Este ha sido uno de los labs más completos de la sección de K8s en este challenge, y resulta interesante porque empiezan a verse **patrones de sistemas productivos reales**: un frontend, una DB, dos services con propósitos distintos (uno interno, uno expuesto), todo aislado en un namespace propio. La idea de "aplicación en K8s" deja de ser un Pod aislado y pasa a ser **un grafo de recursos relacionados**.

Los **labels** son la pieza fundamental que sostiene todo eso. No son metadata decorativa — son el mecanismo concreto que **une recursos heterogéneos**: un Service encuentra sus Pods porque los labels matchean, un Deployment sabe cuáles ReplicaSets son suyos por el mismo mecanismo, una NetworkPolicy decide qué tráfico permite mirando labels. Un typo pequeño en cualquiera de los 4 lugares donde aparece `run: iron-gallery` rompe la cadena, y el síntoma es siempre el mismo: el recurso "existe" pero "no funciona". Ser consciente de esto desde el principio cambia la forma de debuggear — el primer reflejo pasa a ser `kubectl get endpoints` antes que mirar logs.

Comparado con desplegar en **ECS en AWS**, los matices se notan: ECS abstrae el concepto de "Service" (Task Definition + Service) en algo más opinionado y con menos piezas para alinear; K8s te da primitivas más pequeñas pero pide consistencia manual entre ellas. Cuando se excava, los conceptos hacen match: Task Definition ≈ Pod template, Service de ECS ≈ Deployment + Service, Target Group ≈ Endpoints, ALB Listener Rule ≈ Ingress. Saber traducir esos conceptos hace que el salto entre plataformas sea de **vocabulario y mecánica**, no de paradigma — y eso, para alguien que ya manejó orquestadores en cloud, hace que K8s deje de sentirse como un mundo aparte.

## Troubleshooting

| Problema                                                                | Causa                                                                                                       | Solución                                                                                                       |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `kubectl get pods` desde el host no muestra nada                        | Olvido de `-n iron-namespace-nautilus`. Por default, `kubectl` apunta a `default`                           | Agregar `-n iron-namespace-nautilus` o setear el namespace por default con `kubectl config set-context --current --namespace=...` |
| Apply del Service NodePort falla con `nodePort: provided port is already allocated` | Otro Service ya está usando `32678`                                                                          | `kubectl get svc --all-namespaces -o jsonpath='{.items[?(@.spec.ports[*].nodePort==32678)].metadata.name}'` para localizar el conflicto |
| `nodePort` rechazado con `provided port is not in the valid range`      | Rango permitido es `30000–32767` (configurable)                                                              | Usar un puerto dentro del rango o ajustar `--service-node-port-range` en el kube-apiserver (rara vez deseable)  |
| `kubectl get endpoints <svc>` muestra `<none>`                          | El selector del Service no matchea ningún Pod                                                                | Verificar que `service.spec.selector` matchea exactamente `pod.metadata.labels` (case-sensitive, sin typos)     |
| Pod de DB queda en `ContainerCreating` mucho tiempo                     | Pulling de la imagen (`kodekloud/irondb:2.0` puede tardar la primera vez)                                    | `kubectl describe pod -n iron-namespace-nautilus <db-pod>` y mirar los eventos                                  |
| Pod de DB en `CrashLoopBackOff` después de unos segundos                | Falta alguna env var obligatoria (`MYSQL_USER` con `MYSQL_PASSWORD` requeridas juntas en mariadb image)      | `kubectl logs <db-pod> -n iron-namespace-nautilus --previous` y leer el error de mysqld                         |
| La página de instalación no carga al pegarle al `nodeIP:32678`          | El Pod arrancó pero el container devuelve 502/404                                                            | `kubectl logs <gallery-pod> -n iron-namespace-nautilus` y verificar que nginx esté sirviendo                    |
| `OOMKilled` en el Pod de gallery                                        | El `limits.memory: 100Mi` es muy ajustado para nginx + assets. Si la app crece, el kernel mata el container | Subir el `limits.memory` (300–500Mi típicamente cómodo para nginx). El lab fuerza 100Mi por requirement         |
| `Deployment selector does not match template labels`                    | Mismatch entre `spec.selector.matchLabels` y `spec.template.metadata.labels`                                | Mirar ambos bloques y verificar que cada key/value coincide exactamente                                         |
| Pods siguen siendo `Burstable` aunque solo definimos `limits`           | Es el comportamiento esperado — K8s asume `requests == limits` si solo se define `limits`                     | No es un problema, es la regla. Para `Guaranteed` declarar `requests == limits` explícitamente                  |
| El namespace tiene recursos huérfanos después de borrar un Deployment    | Se borró el Deployment pero el ReplicaSet quedó (no debería con `--cascade=foreground`)                    | `kubectl delete rs -n <ns> -l <selector>` o borrar el namespace entero (`delete ns <name>` borra todo dentro)  |
| Querer borrar todo el stack de una                                       | Recurso por recurso es tedioso si son muchos                                                                | `kubectl delete namespace iron-namespace-nautilus` borra **todos** los recursos dentro en cascada               |

## Recursos

- [Namespaces (oficial)](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
- [Service (Types: ClusterIP, NodePort, LoadBalancer)](https://kubernetes.io/docs/concepts/services-networking/service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Configure Quality of Service for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/)
- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [MariaDB official env vars](https://hub.docker.com/_/mariadb)
