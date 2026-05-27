# Día 66 - Deploy de MySQL en Kubernetes (PV + PVC + Secrets + Deployment + Service)

## Problema / Desafío

El equipo de Nautilus va a desplegar un servidor **MySQL** en el cluster con todos los componentes que requiere una DB "production-like" en K8s: storage persistente, credenciales en Secrets, env vars desde `secretKeyRef`, y un Service NodePort para acceso externo. Es la primera vez en el journal que **se ensamblan todas las primitivas a la vez** en un solo stack.

Requirements:

- **PV** `mysql-pv`, capacity `250Mi`, parámetros libres
- **PVC** `mysql-pv-claim`, request `250Mi`
- **Deployment** `mysql-deployment`, imagen MySQL libre, PV montado en `/var/lib/mysql`
- **Service** `mysql`, tipo `NodePort`, `nodePort: 30007`
- **Tres Secrets**:
  - `mysql-root-pass` → `password=YUIidhb667`
  - `mysql-user-pass` → `username=kodekloud_joy`, `password=ksH85UJjhb`
  - `mysql-db-url` → `database=kodekloud_db10`
- **Env vars** en el container, todas vía `secretKeyRef`:
  - `MYSQL_ROOT_PASSWORD` ← `mysql-root-pass.password`
  - `MYSQL_DATABASE` ← `mysql-db-url.database`
  - `MYSQL_USER` ← `mysql-user-pass.username`
  - `MYSQL_PASSWORD` ← `mysql-user-pass.password`

El lab cierra el círculo de los conceptos vistos entre los Días 60 y 65: storage persistente (60), Secrets como fuente de env vars (62), stack multi-componente en un namespace (63), troubleshooting de manifests rotos (64–65).

## Conceptos clave

### Anatomía del stack — qué recurso depende de qué

```
┌─────────────────────────────────────────────────────────────────┐
│  Cluster                                                          │
│                                                                   │
│  ┌──────────────────┐        ┌────────────────────────┐          │
│  │ PV mysql-pv      │◄───────┤ PVC mysql-pv-claim     │          │
│  │ 250Mi, hostPath  │  bind  │ 250Mi, RWO, manual SC  │          │
│  └──────────────────┘        └────────────┬───────────┘          │
│                                            │ claimName            │
│                                            ▼                      │
│  ┌────────────┐                  ┌────────────────────────┐      │
│  │ Secret     │                  │ Deployment             │      │
│  │ mysql-root │◄─── secretKeyRef ┤ mysql-deployment       │      │
│  │ mysql-user │◄─── secretKeyRef │ ┌────────────────────┐ │      │
│  │ mysql-db   │◄─── secretKeyRef │ │ Pod (replica 1)    │ │      │
│  └────────────┘                  │ │ container mysql    │ │      │
│                                  │ │ volumeMount /var/  │ │      │
│                                  │ │   lib/mysql        │ │      │
│                                  │ └────────────────────┘ │      │
│                                  └───────────┬────────────┘      │
│                                              │ selector           │
│                                              ▼                    │
│  ┌──────────────────────────────────────────────────┐            │
│  │ Service mysql                                     │            │
│  │ type: NodePort                                    │            │
│  │ port 3306 → targetPort 3306, nodePort 30007       │            │
│  └──────────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

Cinco tipos de recursos (PV, PVC, Secret×3, Deployment, Service) con relaciones por nombre:

| Relación                        | Cómo se establece                                       | Si se rompe                                                |
| ------------------------------- | ------------------------------------------------------- | ---------------------------------------------------------- |
| PVC → PV                        | `storageClassName` + `accessModes` + `storage` matchean | PVC queda en `Pending`, Pod no schedulea                   |
| Pod → PVC                       | `volumes[].persistentVolumeClaim.claimName`             | Pod queda en `Pending` por `unbound PVC`                   |
| Pod → Secret (vía env)          | `valueFrom.secretKeyRef.name` + `.key`                  | Pod queda en `CreateContainerError` con `secret not found` |
| Service → Pod                   | `service.spec.selector` matchea `pod.metadata.labels`   | `Endpoints: <none>`, sin tráfico al Pod                    |
| Deployment → Pod                | `selector.matchLabels` matchea `template.labels`        | Deployment falla al crear el ReplicaSet                    |

### `data:` vs `stringData:` en Secrets (anclar bien)

| Campo            | Qué espera           | Quién codifica          | Cuándo usar                                                 |
| ---------------- | -------------------- | ----------------------- | ----------------------------------------------------------- |
| `data:`          | Valores **ya en base64** | El que escribe el YAML  | Cuando ya tenés los valores codificados (export de otro cluster) |
| `stringData:`    | Valores **planos**       | K8s al hacer apply      | Cuando escribís el YAML a mano (este lab)                   |

> **El error de este lab**: usar `data:` con valores planos (`password: YUIidhb667`) hace que K8s intente decodificar `YUIidhb667` como base64. Como tiene caracteres válidos pero no respeta la longitud múltiplo de 4 y el padding, falla con:
> ```
> Secret in version "v1" cannot be handled as a Secret: illegal base64 data at input byte 8
> ```
> **Fix**: usar `stringData:` para los tres Secrets, o codificar manualmente con `echo -n 'YUIidhb667' | base64`.

### PV `hostPath` — qué es y por qué es solo para labs

El lab termina usando `hostPath` como `volume type` del PV. Es la forma **más simple** de tener un PV: K8s monta un directorio del nodo donde se schedulea el Pod.

| Tipo de PV          | Cuándo usar                                                                | Problemas                                                                       |
| ------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `hostPath`          | Labs, single-node clusters, dev local                                      | **No funciona en multi-node** (si el Pod schedulea a otro nodo, no encuentra los datos) |
| `nfs`               | Compartir entre Pods de distintos nodos                                    | Depende de un servidor NFS externo                                              |
| `awsElasticBlockStore`, `gcePersistentDisk`, `azureDisk` | Producción cloud (legacy in-tree drivers)                                 | Deprecated en favor de CSI drivers                                              |
| **CSI driver**      | Producción real moderna (EBS, GCE PD, Azure Disk, Ceph, Rook, Longhorn)    | Requiere instalar el driver en el cluster                                       |
| `local`             | Mejor que `hostPath` en multi-node — pin del Pod a un nodo específico       | Igual no hay HA si el nodo cae                                                  |

> La razón por la que `hostPath` "funciona" en este lab es porque KodeKloud arma un cluster single-node. En cualquier cluster real con más de un nodo, perdés datos al primer reschedule.

### `accessModes` del PV — significado real

Los modos definen **cómo se monta el volumen**, no cuántos clientes pueden escribir simultáneamente:

| Modo            | Sigla  | Significado real                                                                  |
| --------------- | ------ | --------------------------------------------------------------------------------- |
| `ReadWriteOnce` | RWO    | Montable como `rw` en **un solo nodo** a la vez (varios Pods del mismo nodo pueden compartirlo) |
| `ReadOnlyMany`  | ROX    | Montable como `ro` en múltiples nodos                                             |
| `ReadWriteMany` | RWX    | Montable como `rw` en múltiples nodos (requiere backend que lo soporte: NFS, CephFS) |
| `ReadWriteOncePod` (1.22+) | RWOP | Montable por **un solo Pod** del cluster (no del nodo) — más estricto que RWO |

Para una DB single-replica, `ReadWriteOnce` es lo correcto. Si después se quiere escalar a réplicas, hace falta otra arquitectura (StatefulSet + storage replicado).

> El bug del lab: typo `ReadWriteOne` (sin la `c`) → K8s rechaza con regex de validación. Los nombres son enums, no admiten variantes.

### `kubectl apply -f` con múltiples recursos — comportamiento al error

Cuando un archivo YAML contiene **varios documentos** separados por `---`, `kubectl apply -f` los procesa **uno por uno**:

- Cada recurso válido se crea/actualiza
- Cada recurso inválido **es rechazado individualmente**
- El comando sigue procesando los siguientes
- Al final reporta todos los errores juntos

Esto significa que un apply parcial puede dejar el cluster en un estado **inconsistente**: tenés el Deployment y el PVC creados, pero los Secrets que el Deployment necesita no se crearon. El Pod queda esperando los Secrets que nunca llegan.

> **Patrón operacional**: después de un apply con errores, **fixear y re-aplicar** sin borrar nada. Los recursos ya creados se ven como `unchanged` y solo se aplican los nuevos / corregidos.

## Pasos

1. Escribir el manifest con los **7 recursos** separados por `---` (PV, PVC, Deployment, 3 Secrets, Service)
2. `kubectl apply -f mysql.yaml` — observar los errores
3. Fixear los Secrets: cambiar `data:` por `stringData:`
4. Fixear el PV: corregir indentación de `accessModes` (al nivel de `spec`, no de `capacity`) y typo (`ReadWriteOnce`)
5. Fixear el PV: agregar el `volume type` (`hostPath`)
6. Re-aplicar hasta que `kubectl get pods` muestre `Running`
7. Validar con `kubectl exec` que las env vars se cargaron desde los Secrets

## Comandos / Código

### Manifest final (con los 4 bugs corregidos)

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv
spec:
  storageClassName: manual
  capacity:
    storage: 250Mi
  accessModes:                  # ← fix 2: al nivel de spec, NO bajo capacity
    - ReadWriteOnce             # ← fix 3: con la "c" final
  hostPath:                     # ← fix 4: agregar el volume type
    path: "/mnt/data"

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 250Mi

---
apiVersion: v1
kind: Secret
metadata:
  name: mysql-root-pass
type: Opaque
stringData:                     # ← fix 1: stringData en lugar de data
  password: YUIidhb667

---
apiVersion: v1
kind: Secret
metadata:
  name: mysql-user-pass
type: Opaque
stringData:
  username: kodekloud_joy
  password: ksH85UJjhb

---
apiVersion: v1
kind: Secret
metadata:
  name: mysql-db-url
type: Opaque
stringData:
  database: kodekloud_db10

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql-deployment
  labels:
    app: mysql-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql-deployment
  template:
    metadata:
      labels:
        app: mysql-deployment
    spec:
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: mysql-pv-claim
      containers:
        - name: mysql-deployment
          image: mysql:latest
          ports:
            - containerPort: 3306
          volumeMounts:
            - name: data
              mountPath: "/var/lib/mysql"
          env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-root-pass
                  key: password
            - name: MYSQL_DATABASE
              valueFrom:
                secretKeyRef:
                  name: mysql-db-url
                  key: database
            - name: MYSQL_USER
              valueFrom:
                secretKeyRef:
                  name: mysql-user-pass
                  key: username
            - name: MYSQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-user-pass
                  key: password

---
apiVersion: v1
kind: Service
metadata:
  name: mysql
  labels:
    app: mysql-svc
spec:
  type: NodePort
  selector:
    app: mysql-deployment
  ports:
    - port: 3306
      targetPort: 3306
      nodePort: 30007
```

### Autopsia de los 4 bugs encontrados en cadena

#### Primer apply

```bash
kubectl apply -f mysql.yaml
```

```
persistentvolumeclaim/mysql-pv-claim created
deployment.apps/mysql-deployment created
service/mysql created
Error: PersistentVolume ... quantities must match the regular expression ...
Error: Secret ... illegal base64 data at input byte 8
Error: Secret ... illegal base64 data at input byte 8
Error: Secret ... illegal base64 data at input byte 9
```

> Notar que el PVC, Deployment y Service **se crearon igual**. Los errores son del PV y de los 3 Secrets. El Pod queda en `Pending` porque el PVC está unbound (el PV no existe).

#### Bug 1 — Secrets con `data:` en lugar de `stringData:`

```yaml
# ❌ Mal
data:
  password: YUIidhb667        # K8s intenta decodificar "YUIidhb667" como base64 → falla

# ✅ Bien
stringData:
  password: YUIidhb667        # K8s lo codifica al apply
```

> **Por qué falla con `data:`**: base64 espera un string que sea múltiplo de 4 caracteres y que use solo el alfabeto `A-Z a-z 0-9 + /` con `=` de padding. `YUIidhb667` tiene 10 caracteres (no múltiplo de 4) y `7` final no es válido como último byte sin padding.

#### Bug 2 — `accessModes` mal indentado en el PV

```yaml
# ❌ Mal — accessModes bajo capacity
spec:
  capacity:
    storage: 250Mi
    accessModes:               # K8s lee esto como parte de capacity
      - ReadWriteOnce

# ✅ Bien — accessModes al nivel de spec
spec:
  capacity:
    storage: 250Mi
  accessModes:
    - ReadWriteOnce
```

> El error `quantities must match the regex` es engañoso — el real problema es que `capacity` esperaba **solo** `storage`, y la indentación incorrecta puso `accessModes` ahí, donde se intentó parsear como una `quantity`.

#### Bug 3 — Typo `ReadWriteOne` (debería ser `ReadWriteOnce`)

```yaml
# ❌ Mal
accessModes:
  - ReadWriteOne

# ✅ Bien
accessModes:
  - ReadWriteOnce
```

Los `accessModes` son enums — `ReadWriteOnce`, `ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod`. Cualquier variante es rechazada por el validador.

#### Bug 4 — PV sin `volume type`

```bash
The PersistentVolume "mysql-pv" is invalid: spec: Required value: must specify a volume type
```

Un PV **necesita** declarar de dónde sale el storage real. No basta con declarar `capacity` y `accessModes`; hay que decir si es `hostPath`, `nfs`, `awsElasticBlockStore`, un CSI driver, etc.

```yaml
spec:
  storageClassName: manual
  capacity:
    storage: 250Mi
  accessModes:
    - ReadWriteOnce
  hostPath:                    # ← agregado
    path: "/mnt/data"
```

### Re-apply final

```bash
kubectl apply -f mysql.yaml
```

```
persistentvolume/mysql-pv created
persistentvolumeclaim/mysql-pv-claim unchanged
deployment.apps/mysql-deployment unchanged
secret/mysql-root-pass configured
secret/mysql-user-pass configured
secret/mysql-db-url configured
service/mysql unchanged
```

> Notar `unchanged` y `configured`: los recursos ya existían y la diff del apply los detecta como cambios menores o sin cambios.

### El warning que se ve pero no rompe — `storageclass "manual" not found`

```bash
kubectl events
```

```
11m  Warning  ProvisioningFailed  PersistentVolumeClaim/mysql-pv-claim  storageclass.storage.k8s.io "manual" not found
```

Este warning aparece porque K8s intenta hacer **dynamic provisioning** con la StorageClass `manual`, no la encuentra como recurso del cluster, y eventualmente el PVC encuentra el PV **estático** que coincide (mismo `storageClassName: manual` + mismos `accessModes` + suficiente `capacity`). El binding funciona aunque la StorageClass no exista como objeto, porque el campo `storageClassName` también funciona como **selector** para hacer match con PVs estáticos.

| Tipo de provisioning | Cuándo ocurre                                                            |
| -------------------- | ------------------------------------------------------------------------ |
| **Estático**         | PV creado a mano (este lab). El PVC busca uno que matchee y bindea       |
| **Dinámico**         | Solo PVC creado, con StorageClass real. K8s crea el PV automáticamente   |

### Verificación

```bash
kubectl get pods
```

```
NAME                                READY   STATUS    RESTARTS   AGE
mysql-deployment-6679df875f-9l2nw   1/1     Running   0          11m
```

```bash
kubectl get pvc
```

```
NAME             STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
mysql-pv-claim   Bound    mysql-pv   250Mi      RWO            manual         11m
```

```bash
kubectl get secrets
```

```
NAME              TYPE     DATA   AGE
mysql-db-url      Opaque   1      9m
mysql-root-pass   Opaque   1      9m
mysql-user-pass   Opaque   2      9m
```

> Notar `DATA: 2` en `mysql-user-pass` — confirma que las dos claves (`username` y `password`) se almacenaron.

```bash
kubectl get svc
```

```
NAME    TYPE       CLUSTER-IP     PORT(S)          AGE
mysql   NodePort   10.43.210.54   3306:30007/TCP   11m
```

### Validación funcional — las env vars vienen de los Secrets

```bash
kubectl exec -it deployment/mysql-deployment -c mysql-deployment -- /bin/bash
```

Dentro del container:

```bash
printenv | grep -i mysql
```

```
MYSQL_ROOT_PASSWORD=YUIidhb667         ← desde mysql-root-pass.password
MYSQL_PASSWORD=ksH85UJjhb              ← desde mysql-user-pass.password
MYSQL_USER=kodekloud_joy               ← desde mysql-user-pass.username
MYSQL_DATABASE=kodekloud_db10          ← desde mysql-db-url.database

# Auto-inyectadas por K8s (Service discovery legacy):
MYSQL_PORT=tcp://10.43.210.54:3306
MYSQL_PORT_3306_TCP_ADDR=10.43.210.54
MYSQL_PORT_3306_TCP_PORT=3306
MYSQL_PORT_3306_TCP=tcp://10.43.210.54:3306
MYSQL_PORT_3306_TCP_PROTO=tcp
MYSQL_SERVICE_PORT=3306
MYSQL_SERVICE_HOST=10.43.210.54

# Inyectadas por la imagen oficial de MySQL:
MYSQL_MAJOR=9.7
MYSQL_VERSION=9.7.0-1.el9
MYSQL_SHELL_VERSION=9.7.0-1.el9
```

Tres grupos distintos de variables conviviendo en el environment:

| Origen                                                | Cómo aparece                                                              |
| ----------------------------------------------------- | ------------------------------------------------------------------------- |
| **`secretKeyRef`** que declaraste explícitamente     | `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`, `MYSQL_USER`, `MYSQL_DATABASE`   |
| **Service discovery legacy** de K8s                   | `MYSQL_PORT`, `MYSQL_SERVICE_HOST`, etc. — auto-inyectadas para cada Service del namespace |
| **`ENV` de la Dockerfile** de la imagen `mysql:latest` | `MYSQL_MAJOR`, `MYSQL_VERSION`, `MYSQL_SHELL_VERSION`                     |

> Para apagar el grupo legacy (que puede generar conflictos de naming con tus propias vars), agregar al Pod spec:
> ```yaml
> spec:
>   enableServiceLinks: false
> ```

## El patrón de "errores en cadena" del lab

Cuatro bugs distintos, cada uno enmascarando al siguiente:

```
1. Apply inicial → Secrets fail (base64) + PV fail (regex)
                                                          │
   Fix Secrets ──► stringData                             │
                                                          ▼
2. Apply → PV fail (regex sigue)
                              │
   Fix indentación accessModes ──► accessModes al nivel correcto
                                                          │
                                                          ▼
3. Apply → PV fail (regex sigue!)
                              │
   Fix typo ReadWriteOne ──► ReadWriteOnce
                                                          │
                                                          ▼
4. Apply → PV fail ("must specify a volume type")
                                            │
   Fix agregando hostPath ──► hostPath: /mnt/data
                                                          │
                                                          ▼
5. Apply → todos los recursos created ✓
```

La lección operacional, repetida desde Día 59: **leer cada mensaje de error específicamente** antes de cambiar nada. El error `quantities must match the regex` apareció en los puntos 2 **y** 3 — eran dos causas distintas con el mismo síntoma superficial. Si en el punto 2 solo se hubiera revertido el fix de la indentación al ver que "el error es el mismo", se habría perdido el verdadero fix.

## Conexión con días anteriores

- **Día 60 (PV + PVC + Pod + Service)**: idéntico patrón del stack de hoy, pero sin Secrets. Hoy se agrega la capa de Secrets como fuente de env vars. Misma estructura, más componentes.
- **Día 62 (Secrets)**: introdujo `data:` vs `stringData:`. Hoy se vio en la práctica por qué el detalle importa — escribir el secret a mano en plano dentro de `data:` rompe el apply.
- **Día 63 (stack multi-componente)**: misma idea de "ensamblar varios recursos en un solo manifest". El de Iron Gallery era app + DB + 2 Services. El de hoy es DB + PV + PVC + Secrets + Service.
- **Día 64 (troubleshooting de dos bugs)**: la regla "si fixeaste un bug y el síntoma persiste, asumir que hay otro bug" se vuelve a aplicar — pero acá fueron **cuatro** bugs en cadena, no dos.
- **Día 65 (Redis con ConfigMap, `kubectl events`)**: se mantiene el reflejo de usar `kubectl events` como primer comando de debug. Acá fue la clave para ver el warning `ProvisioningFailed` y validar que el binding del PVC al final funcionó.

## Reflexión: ensamblar el stack completo y leer los errores con calma

Algo que me queda como **aprendizaje importante** es el **orden de creación de los recursos** en K8s. Pensaba que se creaban en base a la relación que tenían entre sí (Secrets antes que el Deployment que los referencia, PV antes que el PVC que lo reclama), pero no necesariamente — K8s procesa el archivo en el **orden en que están definidos**, y los recursos dependientes simplemente **reintentan** hasta que sus dependencias aparecen. Por eso es importante cómo se definen en el manifest: aunque "funciona" en cualquier orden, ordenar de **menos a más dependiente** evita estados intermedios feos.

Al crear **7 recursos** en un solo apply, hay que ser **mucho más detallista** con los typos. Es muy fácil equivocarse en un campo (`accessModes` mal indentado, `ReadWriteOne` sin la `c`, una clave de Secret mal escrita) y los bugs resultantes **no siempre son sencillos de identificar** — el mensaje de error puede apuntar a un síntoma superficial que esconde la causa real (como el `quantities must match the regex` que en realidad era un problema de indentación, no de cantidades).

No sabía sobre **`data` y `stringData`** ni cuál era la diferencia. Lo entendí en este lab: `data` espera el valor **ya en base64**, `stringData` lo acepta plano y K8s lo codifica al apply. Para escribir Secrets a mano, `stringData` es siempre la opción correcta; `data` solo sirve cuando ya tenés los valores codificados (típicamente al copiar/exportar desde otro cluster).

El bug más complicado fue el **`must specify a volume type`**. No conocía ese key del PV ni las diferencias entre los tipos (`hostPath`, `nfs`, `csi`, etc.) ni los casos de uso de cada uno. Saber que `hostPath` solo sirve para single-node clusters y que en producción real se usan CSI drivers fue uno de los aprendizajes más concretos del día.

Había manejado **MySQL fuera de K8s**, tanto en instalaciones locales como en Docker. Me pareció **bastante similar** — varios conceptos se unen (env vars de configuración, mount del data dir, exposición del puerto 3306). La diferencia principal está en que K8s **separa la responsabilidad** del storage (PV/PVC) de la del cómputo (Deployment), mientras que en Docker `-v /host:/var/lib/mysql` es una decisión única.

## Troubleshooting

| Problema                                                              | Causa                                                                                                | Solución                                                                                                  |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `Secret in version "v1" cannot be handled: illegal base64 data`       | Usás `data:` con valores planos. K8s intenta decodificar como base64 y falla                         | Cambiar a `stringData:` o codificar manualmente: `echo -n 'valor' \| base64`                              |
| `PersistentVolume invalid: quantities must match the regex`           | Indentación mal: un campo (típicamente `accessModes`) está donde se esperaba una quantity            | Validar la indentación del PV spec — `accessModes` va al nivel de `spec`, no de `capacity`                |
| `PersistentVolume invalid: unsupported value "ReadWriteOne"`          | Typo en el access mode                                                                               | Los modos válidos son: `ReadWriteOnce`, `ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod`              |
| `PersistentVolume invalid: must specify a volume type`                | El PV declara `capacity` y `accessModes` pero no de dónde sale el storage                            | Agregar uno de: `hostPath`, `nfs`, `csi`, `awsElasticBlockStore`, etc.                                    |
| `kubectl apply` parcial: algunos recursos created, otros con error    | Comportamiento esperado de apply con múltiples docs                                                  | Fixear los recursos rechazados y re-aplicar; los ya creados se ven como `unchanged`                       |
| Pod en `Pending`: `pod has unbound immediate PersistentVolumeClaims`  | El PVC no se bindeó a ningún PV (PV no existe o specs no matchean)                                   | `kubectl describe pvc <name>` para ver razón; típicamente `storageClassName` o `accessModes` no matchean  |
| Warning `ProvisioningFailed: storageclass "X" not found`              | K8s intenta dynamic provisioning pero la StorageClass no existe como recurso                         | Si hay un PV estático con el mismo `storageClassName`, el warning es ruido. Si no, crear la StorageClass  |
| `Failed to create endpoint for service ... "X" already exists`        | El Service existe en estado raro después de un apply parcial                                          | `kubectl delete svc <name>` y re-aplicar, o `kubectl apply --force` para reemplazar                       |
| Env var del container vacía aunque el Secret existe                   | La `key` del `secretKeyRef` no matchea ninguna clave del Secret                                       | `kubectl get secret <name> -o yaml` para ver las claves reales del Secret                                 |
| `MYSQL_*` variables auto-inyectadas que generan conflicto             | K8s inyecta env vars de Service discovery legacy por cada Service del namespace                       | `spec.enableServiceLinks: false` en el Pod spec para apagarlas                                            |
| MySQL pierde los datos al recrear el Pod                              | El PV usa `hostPath` y el cluster es multi-node — el Pod schedulea a otro nodo sin los datos         | Usar un CSI driver real o `local` PV con node-affinity al nodo correcto                                   |
| Apply funciona pero el Pod queda en `CreateContainerError`            | El Pod se schedulea pero falla al crear el container — típicamente Secret/ConfigMap referenciado falta | `kubectl describe pod <name>` para ver el error exacto                                                    |

## Recursos

- [Persistent Volumes (oficial)](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Secrets (oficial)](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Using Secrets as environment variables](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/#define-container-environment-variables-using-secret-data)
- [MySQL Docker Hub image — env vars](https://hub.docker.com/_/mysql)
- [Service environment variables (legacy)](https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/#environment-variables)
- [hostPath PV warnings](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
