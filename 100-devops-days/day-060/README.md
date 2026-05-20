# Día 60 - Persistent Volumes en Kubernetes (PV + PVC + Pod + Service)

## Problema / Desafío

El equipo de Nautilus está armando un template de Kubernetes para una web app que necesita persistencia. Hay que armar la cadena completa: **PersistentVolume + PersistentVolumeClaim + Pod + Service NodePort**.

- **PersistentVolume:** `pv-nautilus`, `storageClassName: manual`, `capacity: 5Gi`, `accessModes: [ReadWriteOnce]`, `hostPath: /mnt/data`
- **PersistentVolumeClaim:** `pvc-nautilus`, `storageClassName: manual`, `requests.storage: 1Gi`, `accessModes: [ReadWriteOnce]`
- **Pod:** `pod-nautilus`, container `container-nautilus`, imagen `nginx:latest`, montar el PVC en `/usr/share/nginx/html`
- **Service:** `web-nautilus`, tipo `NodePort`, `nodePort: 30008`

Es la primera vez en el journal que aparece almacenamiento **fuera del ciclo de vida del Pod** — todo lo visto hasta ahora (Día 54 `emptyDir`, Día 55 sidecars, Día 53 mountPaths) usaba volúmenes que morían con el Pod.

## Conceptos clave

### El triángulo PV / PVC / StorageClass

Kubernetes separa el almacenamiento en tres roles deliberadamente desacoplados:

| Recurso          | Lo crea          | Para qué sirve                                                              | Análogo                                     |
| ---------------- | ---------------- | --------------------------------------------------------------------------- | ------------------------------------------- |
| **PersistentVolume** (PV)       | El admin del cluster | Declarar **dónde** está el almacenamiento real (hostPath, NFS, EBS, etc.)   | El disco físico montado en el datacenter    |
| **PersistentVolumeClaim** (PVC) | El usuario / dev   | Pedir almacenamiento con un perfil ("necesito 1Gi RWO de clase 'fast'")     | Una solicitud al equipo de infra            |
| **StorageClass** (SC)           | El admin           | Definir un *tipo* de almacenamiento y opcionalmente cómo provisionarlo en demanda | El catálogo de "qué tipos de disco hay" |

La separación entre PV y PVC permite que **el dev no sepa dónde está el disco** — solo especifica qué necesita. El admin (o un provisioner dinámico) se encarga de hacer match.

### Static vs dynamic provisioning

Hay dos modelos para que un PVC obtenga su PV:

- **Static** (el de este lab): el admin pre-crea los PVs a mano, y los PVCs hacen match con alguno existente que cumpla los criterios.
- **Dynamic**: el cluster tiene un *provisioner* (típicamente asociado a una StorageClass como `gp2` en AWS, `standard` en GKE, etc.) que crea un PV nuevo en el momento que aparece un PVC pidiendo esa clase.

El `storageClassName: manual` de este lab **no es una clase real con provisioner** — es una convención de nombre para indicar "yo, admin, voy a crear el PV a mano". Sirve para que el PVC matchee solo con PVs de la misma "clase" y no consuma accidentalmente otro PV.

### Ciclo de vida del binding

```
1. admin: kubectl apply -f pv.yaml   →   PV en estado Available
2. dev:   kubectl apply -f pvc.yaml  →   PVC en estado Pending
3. K8s controller compara PVCs Pending con PVs Available y busca match:
        - misma storageClass
        - PV.capacity >= PVC.requests.storage
        - PV.accessModes ⊇ PVC.accessModes
4. Si hay match → PV y PVC pasan a estado Bound (relación 1:1)
5. Cuando un Pod referencia el PVC, el scheduler solo lo asigna a un Node cuando el PVC está Bound
```

El paso 5 explica el `Warning: FailedScheduling ... pod has unbound immediate PersistentVolumeClaims` que aparece en el `describe pod` antes de que el binding suceda — no es un error, es el scheduler esperando a que el controller de PVCs termine su trabajo.

### El request es un MÍNIMO, no un valor exacto

Detalle sutil pero importante: el PVC pide `requests.storage: 1Gi`, pero al bindearse con un PV de `5Gi`, el output muestra `CAPACITY: 5Gi`:

```
NAME           STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-nautilus   Bound    pv-nautilus   5Gi        RWO            manual         2m25s
```

Esto es porque K8s busca un PV que **cumpla o exceda** el request. Si solo existe un PV de 5Gi y el PVC pide 1Gi, el match es válido y el PVC queda con la capacidad del PV (los 5Gi enteros). El "request" es entendido como "necesito al menos esto", no "quiero exactamente esto".

**Consecuencia:** en provisioning estático, hay que dimensionar los PVs cuidadosamente — un PVC que pide 1Gi puede terminar bloqueando un PV de 500Gi si es el único disponible.

### Access modes

| Modo                     | Sigla | Qué permite                                            |
| ------------------------ | ----- | ------------------------------------------------------ |
| ReadWriteOnce            | RWO   | Un solo Node puede montarlo en modo lectura/escritura  |
| ReadOnlyMany             | ROX   | Múltiples Nodes lo montan en modo solo lectura         |
| ReadWriteMany            | RWX   | Múltiples Nodes lo montan en lectura/escritura         |
| ReadWriteOncePod         | RWOP  | Un solo Pod del cluster lo monta RW (K8s 1.27+)        |

Los modos soportados dependen del **backend de almacenamiento**, no de la voluntad del admin. `hostPath` solo soporta RWO (vive en un solo nodo). NFS soporta RWX. Discos en la nube (EBS, GCE PD) suelen ser RWO.

### `hostPath`: el "modo lab"

`hostPath` monta una ruta del **filesystem del nodo** dentro del Pod. Es la opción más barata y se usa en clusters single-node (minikube, kind, K3s, los labs de KodeKloud). Limitaciones:

- **No es portable**: si el Pod se reschedula a otro nodo, el directorio en el nodo nuevo no tiene los datos.
- **No es seguro**: el Pod accede al filesystem del host. En producción es un riesgo de escape de container.
- **No funciona en multi-node sin coordinación**: por eso en clusters reales se usa NFS, Ceph, drivers CSI (AWS EBS, GCE PD, Azure Disk, etc.).

Para este lab es perfecto — el cluster es single-node y `/mnt/data` ya existe en el nodo.

### Reclaim policies — qué pasa al borrar el PVC

Cuando el PVC se borra, el PV no se borra automáticamente. Su destino depende del campo `persistentVolumeReclaimPolicy` del PV:

| Política     | Qué hace al borrar el PVC                                                       | Cuándo aplica                                  |
| ------------ | ------------------------------------------------------------------------------- | ---------------------------------------------- |
| **Retain**   | El PV queda en estado `Released`, los datos **se conservan**, pero el PV ya no se puede bindear automáticamente. El admin tiene que limpiarlo a mano. | **Default** para PVs creados estáticamente     |
| **Delete**   | El PV se borra del cluster y el backend de storage borra el disco subyacente   | **Default** para PVs creados dinámicamente     |
| **Recycle**  | El controller hace `rm -rf` del contenido y el PV vuelve a `Available`          | Deprecado desde K8s 1.20 — no usar              |

En este lab no se especifica → toma el default `Retain`. Si se borrara el PVC, los datos en `/mnt/data` quedarían intactos.

## Pasos

1. Definir el PV con `storageClassName: manual`, 5Gi, RWO, hostPath `/mnt/data`
2. Definir el PVC con `storageClassName: manual`, 1Gi, RWO (el match con el PV es automático)
3. Definir el Pod referenciando el PVC vía `volumes[].persistentVolumeClaim.claimName`
4. Definir el Service NodePort con `selector` que matchee el label del Pod
5. Aplicar todo con un solo `kubectl apply -f pod.yml` (los `---` separan los 4 manifests)
6. Verificar: `kubectl get all`, `kubectl get pvc`, `kubectl describe pod`
7. Probar el endpoint con `curl -I <node-ip>:30008`

## Comandos / Código

### Manifest completo

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nautilus
spec:
  storageClassName: manual
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /mnt/data

---

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-nautilus
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi

---

apiVersion: v1
kind: Pod
metadata:
  name: pod-nautilus
  labels:
    app: pod-nautilus
spec:
  volumes:
    - name: web-root
      persistentVolumeClaim:
        claimName: pvc-nautilus
  containers:
    - name: container-nautilus
      image: nginx:latest
      volumeMounts:
        - name: web-root
          mountPath: /usr/share/nginx/html

---

apiVersion: v1
kind: Service
metadata:
  name: web-nautilus
spec:
  type: NodePort
  selector:
    app: pod-nautilus
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30008
```

### Aplicación y verificación

```bash
kubectl apply -f pod.yml
```

```
persistentvolume/pv-nautilus created
persistentvolumeclaim/pvc-nautilus created
pod/pod-nautilus created
service/web-nautilus created
```

```bash
kubectl get all
```

```
NAME               READY   STATUS    RESTARTS   AGE
pod/pod-nautilus   1/1     Running   0          19s

NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/kubernetes     ClusterIP   10.43.0.1       <none>        443/TCP        47m
service/web-nautilus   NodePort    10.43.163.104   <none>        80:30008/TCP   19s
```

```bash
kubectl get pvc -o wide
```

```
NAME           STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   AGE     VOLUMEMODE
pvc-nautilus   Bound    pv-nautilus   5Gi        RWO            manual         2m25s   Filesystem
```

Notar que `CAPACITY` reporta `5Gi`, no los `1Gi` solicitados — el PVC se quedó con la capacidad del PV, como explica la sección "El request es un MÍNIMO".

### Lectura crítica del `describe pod`

Sección Events del Pod justo después del apply:

```
Type     Reason            Age    From               Message
----     ------            ----   ----               -------
Warning  FailedScheduling  3m24s  default-scheduler  0/1 nodes are available: pod has unbound immediate PersistentVolumeClaims. not found
Warning  FailedScheduling  3m14s  default-scheduler  0/1 nodes are available: pod has unbound immediate PersistentVolumeClaims. not found
Normal   Scheduled         3m14s  default-scheduler  Successfully assigned default/pod-nautilus to jump-host
Normal   Pulling           3m15s  kubelet            Pulling image "nginx:latest"
Normal   Pulled            3m11s  kubelet            Successfully pulled image "nginx:latest" in 3.465s
Normal   Created           3m11s  kubelet            Created container: container-nautilus
Normal   Started           3m11s  kubelet            Started container container-nautilus
```

Lectura del cronograma:

| t       | Evento                                                                           | Quién                  |
| ------- | -------------------------------------------------------------------------------- | ---------------------- |
| 3m24s   | `FailedScheduling`: el Pod existe pero su PVC todavía no está `Bound`            | scheduler              |
| 3m14s   | Mismo warning otra vez — el scheduler reintenta cada ~10s                        | scheduler              |
| 3m14s   | `Scheduled`: el controller de PVCs terminó el binding → el Pod ya puede ir a un Node | scheduler              |
| 3m15s   | Pulling de nginx:latest                                                          | kubelet                |
| 3m11s   | Container `Running`                                                              | kubelet + containerd   |

Los dos `FailedScheduling` **no son bugs** — son la huella del scheduler esperando a que el binding termine. La línea `Scheduled` en cuanto el PVC pasó a `Bound` cierra el ciclo. Si esos warnings persistieran indefinidamente, ahí sí habría un problema (PV no existe, storageClass no matchea, capacidad insuficiente, etc.).

### Resultado del navegador: 403

```bash
curl -I https://30008-port-xxxxx.labs.kodekloud.com/
```

```
HTTP/2 403
```

```bash
kubectl logs pod/pod-nautilus
```

```
[error] 78#78: *1 directory index of "/usr/share/nginx/html/" is forbidden,
   client: 10.22.0.1, server: localhost, request: "GET / HTTP/1.1"
"GET / HTTP/1.1" 403 555
```

```bash
kubectl exec -it pod-nautilus -- ls -la /usr/share/nginx/html
```

```
total 8
drwxr-xr-x 2 root root 4096 May 20 11:30 .
drwxr-xr-x 3 root root 4096 May 19 23:05 ..
```

El document root está vacío. El PVC montado **sobrescribió** el contenido default de la imagen `nginx:latest` (que viene con un `index.html` de bienvenida) — y como `/mnt/data` en el nodo arrancó vacío, nginx no tiene nada que servir.

## Por qué nginx devuelve 403 (no 404)

Mismo análisis del Día 53:

1. nginx recibe `GET /`
2. Resuelve `try_files $uri $uri/ =404` para `/` → busca `/usr/share/nginx/html/` (el directorio)
3. El directorio **existe** (está montado)
4. Busca `index.html`, `index.htm` → no encuentra ninguno
5. Como `autoindex` está off por default, devuelve `403 Forbidden`

| Código | Causa típica con nginx                                                              |
| ------ | ----------------------------------------------------------------------------------- |
| `404`  | El `root` no existe en el filesystem del container, o `try_files` no matchea        |
| `403`  | El directorio existe pero está vacío de archivos índice, o falta permiso de lectura |

## emptyDir vs PV: cuándo usar cada uno

| Dimensión                    | `emptyDir` (Día 54)                                      | PersistentVolume                                          |
| ---------------------------- | -------------------------------------------------------- | --------------------------------------------------------- |
| **Lifetime**                 | Vida del Pod — se destruye con el Pod                    | Independiente del Pod — sobrevive deletes y reschedules   |
| **Visibilidad**              | Solo containers del mismo Pod                            | Cualquier Pod que reclame el mismo PVC                    |
| **Setup**                    | Cero — kubelet lo crea automáticamente                   | Requiere PV + PVC + storageClass + backend                |
| **Casos de uso típicos**     | Cache local, scratch space, comunicación entre sidecars  | Bases de datos, contenido web persistente, queues durables |
| **Sobrevive a reschedule**   | No — `emptyDir` nuevo en el Node nuevo                   | Sí (si el backend lo soporta)                             |
| **Sobrevive a `delete pod`** | No                                                       | Sí                                                        |

Regla práctica: usar `emptyDir` cuando los datos son **disposable** y caben en la vida del Pod. Usar PV cuando los datos **tienen que existir antes** del Pod o **tienen que existir después** del Pod.

## Conexión con días anteriores

- **Día 53 (nginx 403)**: el mismo error reaparece, mismo árbol de decisión de nginx. La causa raíz hoy es distinta (PVC vacío en lugar de mountPath desalineado), pero el síntoma a nivel HTTP es idéntico.
- **Día 54 (emptyDir)**: ahí los datos morían con el Pod; hoy sobreviven a borrarlo. El PV es el escalón siguiente en la "escalera de persistencia" — emptyDir → hostPath suelto → PV/PVC → CSI dinámico.
- **Día 56 (Service NodePort)**: misma estrategia de exposición. La novedad de hoy no está en el Service, está en el storage.
- **Día 59 (troubleshooting)**: el patrón "warning en describe pod que no es realmente un error" se repite. Ahí era `ContainerCreating` esperando volúmenes; acá es `FailedScheduling` esperando el binding del PVC. Ambos son estados transitorios del scheduler/kubelet, no fallas.

## Reflexión: el lab pasa con 403 — ¿qué nos dice eso?

La consigna fue cumplida estructuralmente:

- ✅ `pv-nautilus` creado con los specs pedidos
- ✅ `pvc-nautilus` bound al PV
- ✅ `pod-nautilus` montando el PVC en el document root
- ✅ `web-nautilus` exponiendo el Pod en NodePort 30008

Pero el endpoint responde **403**, porque el document root está vacío. El validador del lab pasa de todos modos: solo verifica la **existencia y configuración de los recursos**, no que el contenido servido tenga sentido a nivel HTTP.

Esto separa dos categorías de "está funcionando":

| Categoría                     | Qué se verifica                                              | Cómo se verifica                                  |
| ----------------------------- | ------------------------------------------------------------ | ------------------------------------------------- |
| **Validación estructural**    | Recursos K8s existen con la forma correcta                   | `kubectl get`, `kubectl describe`, validadores YAML |
| **Validación funcional**      | La app cumple su propósito a nivel de protocolo / negocio    | Tests E2E, smoke tests, health checks reales      |

Este laboratorio expone bien el patrón: al validar el acceso a la web obtenemos un **403** — todo está ejecutándose, pero no hay contenido. Si solo miramos `kubectl get pods` (todo `Running`), perdemos el problema entero: a nivel de aplicación está roto, y la experiencia del usuario final es la de un sitio caído. La forma de cerrar ese gap es agregar una **`readinessProbe`** que valide contra un endpoint tipo `/health` esperando código `200` — mientras la app no devuelva contenido válido, el Pod queda `NotReady` y el Service deja de incluirlo en sus Endpoints. En un flujo DevOps, ese probe es la frontera entre "el deploy aplicó" y "el deploy funciona".

## Anexo: los tres probes de Kubernetes

> *Esta sección se introduce acá porque el cierre de la Reflexión menciona `readinessProbe`. Si en un día futuro aparece un lab específico de probes, este bloque se migra entero a ese día.*

Kubernetes ofrece tres tipos de probes (`livenessProbe`, `readinessProbe`, `startupProbe`). Cada uno responde a una pregunta distinta del kubelet al container, y dispara una **acción distinta** del cluster. Confundir cuál usar es uno de los errores más comunes — la clave no está en *qué chequean*, sino en *qué acción provocan al fallar*.

### Los tres probes en una tabla

| Probe              | Pregunta que responde                            | Acción al **fallar**                                                | Cuándo corre                                                  |
| ------------------ | ------------------------------------------------ | ------------------------------------------------------------------- | ------------------------------------------------------------- |
| **`livenessProbe`**  | ¿Sigue vivo el proceso o está colgado / zombi?    | El kubelet **mata y reinicia el container** (aplica `restartPolicy`) | Todo el lifetime del container (después del `startupProbe`)    |
| **`readinessProbe`** | ¿Puede recibir tráfico ahora?                    | kube-proxy **lo saca de los Endpoints del Service** (no se reinicia) | Todo el lifetime del container                                |
| **`startupProbe`** (K8s 1.16+) | ¿Terminó el arranque inicial?            | El container es **matado** si nunca pasa (igual que liveness)        | Solo durante el arranque — al primer success deja de correr    |

Punto crítico: **liveness reinicia, readiness desconecta**. Confundirlos es el bug clásico — un endpoint lento bajo `livenessProbe` causa `CrashLoopBackOff` con la app sana, que solo necesitaba más tiempo.

### Cuándo usar cada uno

| Situación                                                                                | Probe correcto                          | Por qué                                                          |
| ---------------------------------------------------------------------------------------- | --------------------------------------- | ---------------------------------------------------------------- |
| La app entra en deadlock y deja de procesar requests aunque el TCP siga vivo            | **liveness**                            | Solo un restart la saca del estado                               |
| La app está cargando un cache de 30s al arrancar y todavía no puede atender              | **readiness** (o **startup** + readiness) | Restartearla no acelera el cache; mejor no mandarle tráfico      |
| La app levanta lento (Java, .NET, init scripts) pero después es rápida                   | **startup** + liveness corto            | Sin startup hay que elegir entre `initialDelaySeconds` enorme o falsos positivos de liveness |
| El backend depende de otra app que puede caerse temporalmente                            | **readiness**                           | No conviene restartear al cliente cuando una dep externa cae     |
| El rolling update debe esperar a que las nuevas replicas estén listas antes de retirar las viejas | **readiness**                  | El rolling update usa readiness para decidir cuándo avanzar       |

### Los 4 handlers — qué se chequea

Cualquiera de los tres probes acepta cualquiera de estos handlers:

| Handler        | Qué hace                                                                          | Cuándo conviene                                              |
| -------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `httpGet`      | El kubelet manda un GET HTTP/S a un path; **2xx o 3xx = success**                 | Apps web — el caso más común                                 |
| `tcpSocket`    | El kubelet abre un socket TCP al puerto. Conexión exitosa = success               | Apps no-HTTP (DBs, brokers, gRPC sin healthcheck)            |
| `exec`         | El kubelet corre un comando **dentro del container**. Exit code 0 = success       | Cuando hay que ejecutar lógica que no es accesible por HTTP/TCP |
| `grpc` (1.24+) | El kubelet llama el [gRPC Health Checking Protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md) | Apps gRPC — antes había que meter `grpc_health_probe` como binario en la imagen |

### Parámetros de timing (compartidos por todos los probes)

| Campo                   | Default | Qué controla                                                       |
| ----------------------- | ------- | ------------------------------------------------------------------ |
| `initialDelaySeconds`   | 0       | Cuánto espera el kubelet antes del primer check                    |
| `periodSeconds`         | 10      | Cada cuánto repite el check                                        |
| `timeoutSeconds`        | 1       | Cuánto espera la respuesta antes de considerar el check fallido    |
| `failureThreshold`      | 3       | Cuántos fallos consecutivos cuentan como "el probe falló"          |
| `successThreshold`      | 1       | Cuántos éxitos seguidos cuentan como recuperación (solo readiness / startup) |

### Ejemplo con los tres probes juntos

```yaml
containers:
- name: app
  image: my-slow-java-app:1.0
  startupProbe:                       # Hasta que pase, los otros 2 no corren
    httpGet:
      path: /healthz
      port: 8080
    periodSeconds: 5
    failureThreshold: 60               # Hasta 5 min para arrancar (5s × 60)
  livenessProbe:                      # Una vez arrancado, chequear que no se cuelgue
    httpGet:
      path: /healthz
      port: 8080
    periodSeconds: 10
    failureThreshold: 3                # 30s sin responder → restart
  readinessProbe:                     # ¿Puede atender tráfico?
    httpGet:
      path: /ready                     # endpoint distinto: valida dependencias (DB, cache)
      port: 8080
    periodSeconds: 5
    failureThreshold: 2                # 10s sin estar listo → fuera de Endpoints
```

Notar que `/healthz` y `/ready` suelen ser **endpoints distintos**:

- `/healthz` (liveness) → solo dice "el proceso responde" (rompe deadlocks)
- `/ready` (readiness) → valida además dependencias externas (DB conectada, cache caliente, etc.)

### Gotchas comunes

| Antipatrón                                                                     | Por qué duele                                                                                              | Fix                                                          |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| Usar liveness sobre un endpoint que toca la DB                                 | Si la DB cae 30s, todos los containers se reinician en cascada → outage masivo                            | Liveness debe chequear **solo el proceso local**, no dependencias |
| `initialDelaySeconds: 300` en liveness de una app lenta                        | Bloquea la detección de fallas reales durante 5 minutos                                                    | Usar `startupProbe` para el arranque y liveness corto después |
| Mismo endpoint para liveness y readiness                                       | Si una dep externa cae, el container se reinicia (no sirve) Y se saca de Endpoints (correcto, pero el restart fue ruido) | Endpoints separados con responsabilidades distintas          |
| No definir ningún probe                                                        | K8s asume que el container está OK desde el arranque → tráfico va a un Pod que todavía no está listo       | Al menos un readinessProbe                                    |
| `exec` con script costoso cada 5 segundos                                      | El probe consume CPU/IO del container — puede degradar la app que está probando                            | Preferir `httpGet` cuando sea posible                         |

### Por qué readinessProbe fue lo correcto en este lab

Volviendo al 403 del Día 60, las tres opciones contra el mismo síntoma:

| Probe elegido           | Qué pasaría                                                                                                                | Veredicto                                          |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `livenessProbe` que fallara con 403 | El container entraría en `CrashLoopBackOff` — pero reiniciar nginx no crea el `index.html`. Restart loop inútil      | ❌ ruido sin valor                                  |
| `startupProbe` que esperara un 200  | El container quedaría en "not-yet-started" para siempre; el deploy nunca avanza y el `failureThreshold` se acaba → kill | ❌ bloquea el deploy sin información útil           |
| `readinessProbe` que fallara con 403 | El Pod queda `Running` pero `NotReady`, fuera de los Endpoints del Service. `kubectl get pods` muestra `0/1 Ready`     | ✅ traza visible, sin restart loops, deploy detenido controladamente |

El criterio general: **si el problema se resuelve reiniciando, es liveness. Si solo se resuelve esperando o arreglando algo externo, es readiness.**

## Troubleshooting

| Problema                                                                | Causa                                                                                                  | Solución                                                                                          |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| PVC queda en `Pending` indefinidamente                                  | No hay PV `Available` con storageClass + size + accessModes compatibles                                | `kubectl describe pvc` → ver mensaje del controller. Verificar `kubectl get pv`                   |
| Pod queda en `Pending`, `describe pod` muestra `unbound immediate PVCs` | El PVC todavía no está `Bound`. Si ya pasaron minutos, el binding está fallando                       | Mirar el estado del PVC; si está `Pending`, el problema es del binding, no del Pod                |
| nginx devuelve 403 después de montar el PVC                             | El PVC sobrescribió el `/usr/share/nginx/html` default de la imagen y el storage está vacío           | Poblar el storage (kubectl cp / initContainer / configMap como bootstrap)                         |
| PV en estado `Released` no se rebindea                                  | Reclaim policy `Retain` deja el PV con referencia al PVC viejo                                         | Editar el PV y borrar el campo `spec.claimRef`, o recrear el PV                                   |
| PVC reporta más capacidad que la solicitada                             | No es un bug — el PVC se queda con la capacidad del PV bound, y el request es un mínimo               | Diseñar tamaños de PV cercanos a los requests esperados                                            |
| Pod no puede escribir en el volumen ("read-only filesystem")            | El backend de storage no soporta el accessMode pedido, o el `securityContext` del Pod restringe write | Verificar `accessModes` del PV vs PVC, y `securityContext.readOnlyRootFilesystem`                 |
| Cambié el PV después de crearlo y los cambios no se aplican             | Algunos campos del PV son inmutables después del binding (capacity, storageClass)                     | Borrar el PVC y el PV, recrear con la config nueva                                                |

## Recursos

- [Persistent Volumes (oficial)](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [PV / PVC lifecycle](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#lifecycle-of-a-volume-and-claim)
- [Access Modes — qué soporta cada backend](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [hostPath — limitaciones y alternativas](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
- [Reclaim policies](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming)
- [CSI — Container Storage Interface](https://kubernetes.io/docs/concepts/storage/volumes/#csi)
- [Configure Liveness, Readiness and Startup Probes (oficial)](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Pod Lifecycle — probe section](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes)
- [gRPC Health Checking Protocol](https://github.com/grpc/grpc/blob/master/doc/health-checking.md)
