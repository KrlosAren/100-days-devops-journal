# kubectl · Volúmenes (PV / PVC / hostPath / emptyDir / CSI)

Cómo conectar storage a los Pods en Kubernetes. K8s separa **dónde** vive el storage (el `Volume`) de **cómo** un Pod lo usa (el `VolumeMount`). Esa separación es la que permite cambiar el backend de storage (de un host local a un disco cloud, por ejemplo) sin tocar la app.

## Tabla de decisión: qué tipo de volumen usar

| Necesidad                                                       | Tipo de volumen                    | Persiste si el Pod muere | Compartible entre Pods   |
| --------------------------------------------------------------- | ---------------------------------- | ------------------------ | ------------------------ |
| Datos efímeros entre containers del **mismo Pod**               | `emptyDir`                         | ❌ (vive lo que el Pod)  | Solo containers del Pod  |
| Datos efímeros que sobreviven restarts del container, no del Pod | `emptyDir` con `medium: Memory`    | ❌                       | Solo containers del Pod  |
| Datos persistentes en **single-node** (lab, dev local)           | `hostPath` (vía PV)                | ✅ (en el nodo)          | Mismo nodo               |
| Datos persistentes en **multi-node** lab                         | `local` PV con node-affinity       | ✅                       | Mismo nodo (pin)         |
| Datos persistentes en **producción cloud**                       | CSI driver (EBS, GCE PD, Azure Disk) | ✅                       | Solo `ReadWriteOnce`     |
| Datos compartidos entre Pods de distintos nodos                  | NFS, CephFS, EFS (CSI)             | ✅                       | `ReadWriteMany`          |
| Config / archivos no sensibles                                   | `configMap` como volumen           | ✅ (vive con el ConfigMap) | Cualquier Pod del ns    |
| Credenciales / archivos sensibles                                | `secret` como volumen              | ✅                       | Cualquier Pod del ns    |
| Acceso al filesystem del nodo (logs, sockets)                    | `hostPath`                         | ✅ (en el nodo)          | Mismo nodo               |

## Conceptos clave

### `Volume` vs `VolumeMount`

Cada Pod declara dos cosas separadas:

```yaml
spec:
  volumes:                    # ← QUÉ volúmenes existen y de dónde salen
    - name: data
      persistentVolumeClaim:
        claimName: my-pvc
  containers:
    - name: app
      volumeMounts:           # ← DÓNDE se montan dentro del container
        - name: data
          mountPath: /var/data
```

El **nombre del volumen** (`data`) es local al Pod — vincula la sección `volumes[]` con la `volumeMounts[]`. Lo que apunta al objeto cluster-wide es el campo bajo el tipo (`persistentVolumeClaim.claimName`, `configMap.name`, etc.).

### `emptyDir` — el más simple

Es un directorio efímero creado al arrancar el Pod. Vive lo que vive el Pod.

```yaml
volumes:
  - name: cache
    emptyDir: {}
```

Variantes útiles:

```yaml
# emptyDir en RAM (más rápido, cuenta contra el memory limit del Pod)
emptyDir:
  medium: Memory
  sizeLimit: 100Mi

# emptyDir en disco con límite
emptyDir:
  sizeLimit: 500Mi
```

**Casos típicos**:
- Buzón entre init container y main container (Día 61)
- Datos compartidos entre containers de un mismo Pod (Día 54, 55)
- Caché temporal de la app

### `hostPath` — solo para labs / single-node

Monta un directorio del **filesystem del nodo** donde corre el Pod.

```yaml
volumes:
  - name: docker-sock
    hostPath:
      path: /var/run/docker.sock
      type: Socket
```

**Problemas con `hostPath`**:

1. **No funciona en multi-node**: si el Pod schedulea a otro nodo, no encuentra los datos.
2. **Riesgo de seguridad**: el Pod accede al filesystem del host. Un Pod malicioso podría leer/escribir cosas críticas.
3. **Lock-in al nodo**: no se puede usar con replicas en distintos nodos.

> En producción real, **nunca usar `hostPath`** para datos de aplicación. Solo es aceptable para casos puntuales como acceder a `/var/log` para un log shipper o a `/var/run/docker.sock` para un agente del host.

### `PersistentVolume` (PV) y `PersistentVolumeClaim` (PVC)

Es la abstracción "seria" de storage. Separa **lo disponible** (PV) de **lo que la app pide** (PVC).

```yaml
# PV: el storage real, definido por un admin o creado dinámicamente
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv
spec:
  capacity:
    storage: 250Mi
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  hostPath:                   # ← el "volume type" — DE DÓNDE sale el storage real
    path: /mnt/data
```

```yaml
# PVC: la app pide storage con ciertas características
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  resources:
    requests:
      storage: 250Mi
```

```yaml
# Pod: monta el PVC
spec:
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: mysql-pv-claim
  containers:
    - name: mysql
      volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
```

### Binding del PVC al PV

El **PVC busca un PV que satisfaga sus requisitos**:

- `storageClassName` debe matchear
- `accessModes` solicitados ⊆ disponibles del PV
- `storage` solicitado ≤ capacity del PV

Si encuentra un PV que matchea, lo **bindea** (uno-a-uno, exclusivo). Si no encuentra, el PVC queda en `Pending` y el Pod que lo usa queda en `Pending` también con "unbound PVC".

### `accessModes` — qué significan realmente

| Modo                          | Sigla  | Significado real                                                                                |
| ----------------------------- | ------ | ----------------------------------------------------------------------------------------------- |
| `ReadWriteOnce`               | RWO    | Montable como `rw` en **un solo nodo** a la vez (varios Pods del mismo nodo pueden compartirlo) |
| `ReadOnlyMany`                | ROX    | Montable como `ro` en múltiples nodos                                                           |
| `ReadWriteMany`               | RWX    | Montable como `rw` en múltiples nodos (requiere backend que lo soporte: NFS, CephFS)            |
| `ReadWriteOncePod` (1.22+)    | RWOP   | Montable por **un solo Pod** del cluster (no del nodo) — más estricto que RWO                  |

> Declarar `ReadWriteMany` no te da RWX si el backend no lo soporta. `hostPath` físicamente no puede ser RWX en multi-node porque los nodos no comparten filesystem. El **ground truth lo determina el storage subyacente**.

### `storageClassName` — provisioning estático vs dinámico

| Valor                                   | Comportamiento                                                                              |
| --------------------------------------- | ------------------------------------------------------------------------------------------- |
| Nombre de una StorageClass real         | **Dynamic provisioning**: K8s pide al cloud provider un disco nuevo automáticamente         |
| Nombre arbitrario (ej. `manual`)        | **Static provisioning**: el PVC busca PVs estáticos con el mismo `storageClassName`         |
| `""` (string vacío) o ausente           | El PVC no acepta ninguna StorageClass por default — útil cuando hay default class definida  |

> El warning `ProvisioningFailed: storageclass "X" not found` aparece cuando K8s intenta provisionar dinámicamente pero no encuentra la StorageClass. Si existe un PV estático con el mismo `storageClassName`, el binding **funciona igual** — el warning queda en eventos pero no rompe nada (Día 66).

### Tipos de `volume source` para el PV

Lo que va bajo `spec` del PV define **de dónde sale el storage real**:

| Tipo                     | Cuándo usar                                                            | Problemas                                                                       |
| ------------------------ | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `hostPath`               | Labs, single-node clusters, dev local                                  | No funciona en multi-node, riesgo de seguridad                                  |
| `local`                  | Multi-node lab con pin a un nodo específico                            | Sin HA si el nodo cae                                                           |
| `nfs`                    | Compartir entre Pods de distintos nodos                                | Depende de un servidor NFS externo                                              |
| `awsElasticBlockStore`, `gcePersistentDisk`, `azureDisk` *(in-tree)* | Cloud legacy                          | **Deprecated** en favor de CSI drivers                                          |
| **CSI driver**           | Producción moderna (EBS, GCE PD, Azure Disk, Ceph, Rook, Longhorn)     | Requiere instalar el driver en el cluster                                       |

> Desde K8s 1.21+ los drivers in-tree están **deprecated**. Los providers (AWS, GCP, Azure) migran a CSI. Para producción moderna, **siempre CSI**.

### `local` PV — mejor que `hostPath` en multi-node

A diferencia de `hostPath`, un `local` PV declara explícitamente a qué nodo está pineado:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: example-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: local-storage
  local:
    path: /mnt/disks/ssd1
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - worker-1
```

K8s sabe que este volumen solo está en `worker-1` y va a schedulear el Pod ahí.

### CSI drivers — la forma moderna de hacer storage

CSI (Container Storage Interface) es un protocolo estándar que permite a cualquier vendor implementar storage para K8s sin tocar el core. Ejemplos comunes:

| Driver                  | Para qué                                       |
| ----------------------- | ---------------------------------------------- |
| `ebs.csi.aws.com`       | AWS Elastic Block Store                        |
| `pd.csi.storage.gke.io` | GCE Persistent Disk                            |
| `disk.csi.azure.com`    | Azure Disk                                     |
| `rook-ceph.rbd.csi.ceph.com` | Ceph RBD (block) on-prem o cloud-agnostic |
| `efs.csi.aws.com`       | AWS EFS (NFS-compatible, RWX)                  |
| `longhorn.io`           | Longhorn — storage distribuido para clusters K8s |

La gran ventaja: una sola spec de PVC, distintos backends según el cluster.

### `reclaimPolicy` — qué pasa con el PV cuando se borra el PVC

| Política    | Comportamiento                                                                            |
| ----------- | ----------------------------------------------------------------------------------------- |
| `Delete`    | El PV (y los datos) se borran cuando el PVC se borra. **Default para dynamic provisioning** |
| `Retain`    | El PV queda en estado `Released` con los datos intactos. Requiere intervención manual     |
| `Recycle`   | **Deprecated**. Hacía `rm -rf` del contenido y volvía a `Available`                       |

> Para datos importantes en producción, **siempre `Retain`**. Evita borrados accidentales por un `kubectl delete pvc`.

## Volúmenes especiales: ConfigMap y Secret como volumen

Tanto ConfigMaps como Secrets pueden montarse como volumen. La sintaxis es similar a un PVC pero apuntando al objeto correspondiente:

```yaml
volumes:
  - name: config
    configMap:
      name: nginx-config        # ← nombre del ConfigMap
  - name: certs
    secret:
      secretName: tls-secret    # ← nombre del Secret
```

Detalles importantes:

- **Cada clave del ConfigMap/Secret se convierte en un archivo** en el `mountPath`
- Para Secrets, el contenido se monta en **tmpfs (memoria)**, no en disco
- Los cambios al ConfigMap/Secret se propagan **periódicamente** al filesystem (no instantáneo)
- La app dentro del container debe **releer el archivo** para ver el cambio

Para detalles completos ver [Config y Secretos](config-y-secretos.md).

## Comandos útiles

```bash
# Listar PVs del cluster
kubectl get pv

# Listar PVCs de un namespace
kubectl get pvc -n <ns>

# Diagnosticar por qué un PVC está Pending
kubectl describe pvc <name>

# Ver qué Pod está usando un PVC
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\t"}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{" "}{end}{"\n"}{end}' | grep <pvc-name>

# Ver dónde está montado un PV (en qué nodo)
kubectl describe pv <name> | grep -i "node"

# Forzar liberación de un PV bindeado (cuidado)
kubectl patch pv <name> -p '{"spec":{"claimRef": null}}'

# Listar StorageClasses disponibles
kubectl get sc

# Ver la StorageClass default del cluster
kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
```

## Troubleshooting

| Problema                                                              | Causa                                                                                                | Solución                                                                                                  |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| PVC queda en `Pending` indefinido                                     | No hay PV que satisfaga los requisitos (storageClassName, accessModes, storage)                      | `kubectl describe pvc <name>` para ver razón exacta                                                       |
| Pod en `Pending`: `pod has unbound immediate PersistentVolumeClaims`  | PVC no bindeó (causa anterior)                                                                       | Fixear el PVC primero; el Pod va a schedulear automáticamente                                             |
| `must specify a volume type` al crear un PV                           | El PV declara `capacity` y `accessModes` pero falta el tipo (`hostPath`, `csi`, etc.)                | Agregar uno de los volume sources en `spec`                                                               |
| `unsupported value "ReadWriteOne"`                                    | Typo en accessMode                                                                                   | Modos válidos: `ReadWriteOnce`, `ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod`                       |
| `accessModes` rechazado con error de regex                            | Indentación mal: `accessModes` bajo `capacity` en lugar de al nivel de `spec`                        | `accessModes` va al **nivel de `spec`**, no de `capacity`                                                |
| Warning `storageclass "X" not found` pero PVC bindeó igual            | Provisioning dinámico falló, pero el PVC encontró un PV estático con el mismo `storageClassName`     | Ignorar el warning si el PVC quedó `Bound`. Si es persistente, crear la StorageClass                      |
| PV en `Released` después de borrar el PVC                             | `reclaimPolicy: Retain` lo dejó así con los datos intactos                                           | `kubectl patch pv <name> -p '{"spec":{"claimRef":null}}'` para volverlo a `Available`                     |
| Pod con `hostPath` schedulea pero los datos no aparecen               | Multi-node cluster — el Pod cayó en un nodo que no tiene los datos                                   | Usar `local` PV con node-affinity, o migrar a un CSI driver                                               |
| `MountVolume.SetUp failed for volume "X" : configmap "Y" not found`   | El nombre del ConfigMap referenciado no matchea el real                                              | `kubectl get cm -n <ns>` para ver los reales; corregir el nombre                                          |
| El PV existe pero el Pod no schedulea                                 | Si es `local` PV, el nodo target puede estar `NotReady` o sin recursos                               | `kubectl describe nodes` para ver estado de los nodos                                                     |
| Borrar el PVC borró también los datos                                 | `reclaimPolicy: Delete` (default en dynamic provisioning) borra el storage al borrar el PVC          | Para datos críticos usar `reclaimPolicy: Retain`. Recuperar desde backups                                 |

## Referencias del journal

| Día     | Cubre                                                                       |
| ------- | --------------------------------------------------------------------------- |
| 53      | Troubleshooting de `volumeMounts` mal alineados (nginx + php-fpm)           |
| 54      | `emptyDir` como volumen compartido entre containers                         |
| 55      | Sidecar containers + `emptyDir` para log streaming                          |
| 60      | PV + PVC + Pod + Service desde cero                                         |
| 61      | Init container + `emptyDir` como buzón one-shot                             |
| 62      | Secret como volumen (tmpfs en memoria)                                      |
| 65      | ConfigMap como volumen (cada key = un archivo)                              |
| 66      | PV `hostPath` con `accessModes` y `volumeType` en stack completo de MySQL  |

## Recursos

- [Persistent Volumes (oficial)](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Volumes (oficial)](https://kubernetes.io/docs/concepts/storage/volumes/)
- [Storage Classes (oficial)](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [CSI Drivers list](https://kubernetes-csi.github.io/docs/drivers.html)
- [Local Persistent Volumes blog post](https://kubernetes.io/blog/2019/04/04/kubernetes-1.14-local-persistent-volumes-ga/)
- [hostPath PV warnings](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
