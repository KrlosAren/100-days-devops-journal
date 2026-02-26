# Dia 10 - Pod con ConfigMap, Variable de Entorno y Volume Mount

## Problema / Desafio

Crear un Pod llamado `time-check` en el namespace `devops` que registre la fecha/hora actual en un archivo de log cada cierto intervalo. El intervalo se define mediante un ConfigMap. El Pod debe:

1. Usar el namespace `devops`
2. Crear un ConfigMap `time-config` con `TIME_FREQ=8`
3. Crear un Pod `time-check` con un contenedor `time-check` usando `busybox:latest`
4. Inyectar `TIME_FREQ` como variable de entorno desde el ConfigMap
5. Ejecutar `while true; do date; sleep $TIME_FREQ; done` escribiendo en `/opt/security/time/time-check.log`
6. Montar un volumen `log-volume` en `/opt/security/time`

## Conceptos clave

### ConfigMap

Un ConfigMap almacena datos de configuracion en pares clave-valor, separando la configuracion del contenedor. Permite cambiar valores sin reconstruir la imagen.

```
ConfigMap (time-config)          Pod (time-check)
┌─────────────────────┐         ┌──────────────────────┐
│ TIME_FREQ = 8       │ ──────→ │ env: TIME_FREQ = 8   │
└─────────────────────┘         └──────────────────────┘
```

Formas de consumir un ConfigMap en un Pod:

| Metodo | Uso | Cuando usarlo |
|--------|-----|---------------|
| Variable de entorno | `env.valueFrom.configMapKeyRef` | Cuando necesitas una o pocas claves especificas |
| envFrom | `envFrom.configMapRef` | Cuando necesitas todas las claves del ConfigMap como variables |
| Volumen | `volumes.configMap` | Cuando necesitas los datos como archivos |

### ConfigMap NO es para datos sensibles

Un ConfigMap almacena datos **en texto plano**. Cualquier persona con acceso al namespace puede leer su contenido con `kubectl get configmap -o yaml`. **No** se debe usar para contrasenas, tokens, API keys o certificados.

Para datos sensibles existe **Secret**:

| | ConfigMap | Secret |
|---|-----------|--------|
| Proposito | Configuracion general | Datos sensibles |
| Almacenamiento | Texto plano | Base64 (codificado, **no encriptado**) |
| Ejemplos | Puertos, URLs, feature flags, intervalos | Contrasenas, tokens, llaves SSH, certificados TLS |
| Visibilidad | Visible con `kubectl get configmap -o yaml` | Visible con `kubectl get secret -o yaml` (en base64) |
| Limite de tamano | 1 MB | 1 MB |

```yaml
# ConfigMap — configuracion general
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  TIME_FREQ: "8"
  LOG_LEVEL: "info"
  DB_HOST: "postgres.default.svc"

---
# Secret — datos sensibles
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
data:
  DB_PASSWORD: cGFzc3dvcmQxMjM=     # "password123" en base64
  API_KEY: bXktc2VjcmV0LWtleQ==     # "my-secret-key" en base64
```

**Importante:** base64 **no es encriptacion**, es solo codificacion. Cualquiera puede decodificarlo:

```bash
echo "cGFzc3dvcmQxMjM=" | base64 -d
# password123
```

Para encriptar Secrets en reposo (en etcd), se necesita habilitar **Encryption at Rest** en el cluster o usar herramientas externas como **Sealed Secrets**, **Vault** o **External Secrets Operator**.

#### Como usar un Secret en un Pod

```yaml
# Como variable de entorno
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secret
        key: DB_PASSWORD

# Como volumen (crea archivos con el contenido del secret)
volumes:
  - name: secret-volume
    secret:
      secretName: app-secret
```

La sintaxis es casi identica a ConfigMap: `configMapKeyRef` → `secretKeyRef`, `configMap` → `secret`.

#### Crear un Secret de forma imperativa

```bash
# Desde literales
kubectl create secret generic app-secret \
  --from-literal=DB_PASSWORD=password123 \
  --from-literal=API_KEY=my-secret-key

# Desde un archivo
kubectl create secret generic tls-secret \
  --from-file=cert.pem \
  --from-file=key.pem
```

Kubernetes codifica los valores a base64 automaticamente al crearlo de forma imperativa.

### Volumenes en Kubernetes: emptyDir vs PVC

#### emptyDir

Un volumen `emptyDir` es **efimero**. Se crea vacio en el momento en que el Pod se asigna a un nodo y se destruye cuando el Pod se elimina.

```
Pod se crea → emptyDir se crea (vacio) → Pod escribe datos → Pod se elimina → datos PERDIDOS
```

**No** existe como un recurso independiente de Kubernetes. No se puede ver con `kubectl get volumes`. Vive y muere con el Pod.

```yaml
volumes:
  - name: log-volume
    emptyDir: {}       # {} = configuracion por defecto (almacena en disco del nodo)
```

Opciones de emptyDir:

```yaml
# En disco del nodo (por defecto)
emptyDir: {}

# En memoria (RAM) — mas rapido pero limitado y se pierde al reiniciar
emptyDir:
  medium: Memory
  sizeLimit: 100Mi
```

Casos de uso:
- Cache temporal
- Logs de prueba (como en este ejercicio)
- Compartir archivos entre contenedores del mismo Pod (sidecar pattern)

#### PersistentVolume (PV) y PersistentVolumeClaim (PVC)

Para datos que deben **sobrevivir** a la eliminacion del Pod, se usa el sistema de PV/PVC:

```
PersistentVolume (PV)              PersistentVolumeClaim (PVC)           Pod
┌──────────────────────┐          ┌──────────────────────┐          ┌─────────┐
│ Recurso de storage   │ ←bound→  │ Solicitud de storage │ ←mount→  │ Container│
│ (disco real)         │          │ (cuanto necesito)    │          │         │
│ 10Gi, NFS, EBS, etc  │          │ 5Gi, ReadWriteOnce   │          │         │
└──────────────────────┘          └──────────────────────┘          └─────────┘
     Lo crea el admin                Lo crea el developer             Usa el PVC
```

- **PV (PersistentVolume):** representa un recurso de almacenamiento real (disco en AWS EBS, NFS share, disco local del nodo). Lo crea un administrador o se provisiona dinamicamente.
- **PVC (PersistentVolumeClaim):** es una **solicitud** de almacenamiento. El developer dice "necesito 5Gi con acceso ReadWriteOnce" y Kubernetes busca un PV que cumpla esos requisitos.

```yaml
# PersistentVolume — el disco real
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /data/my-pv

---
# PersistentVolumeClaim — la solicitud
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi

---
# Pod — usa el PVC
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  volumes:
    - name: data-volume
      persistentVolumeClaim:
        claimName: my-pvc          # Referencia al PVC, no al PV directamente
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: data-volume
          mountPath: /data
```

#### Access Modes

| Modo | Abreviado | Descripcion |
|------|-----------|-------------|
| `ReadWriteOnce` | RWO | Un solo nodo puede montar el volumen en lectura/escritura |
| `ReadOnlyMany` | ROX | Multiples nodos pueden montar el volumen en solo lectura |
| `ReadWriteMany` | RWX | Multiples nodos pueden montar el volumen en lectura/escritura |

No todos los tipos de storage soportan todos los modos. Por ejemplo, AWS EBS solo soporta `ReadWriteOnce`.

#### Reclaim Policy

Que pasa con el PV cuando se elimina el PVC:

| Politica | Comportamiento |
|----------|---------------|
| `Retain` | El PV y los datos se conservan. Requiere limpieza manual |
| `Delete` | El PV y el storage se eliminan automaticamente |
| `Recycle` | Deprecated. Borra los datos y marca el PV como disponible |

#### Comparacion completa

| | emptyDir | hostPath | PVC |
|---|----------|----------|-----|
| **Persistencia** | Muere con el Pod | Muere con el nodo | Independiente |
| **Se crea cuando** | El Pod se asigna al nodo | El Pod se asigna al nodo | Se crea el recurso PVC |
| **Visible como recurso** | No | No | Si (`kubectl get pvc`) |
| **Compartir entre Pods** | No (solo contenedores del mismo Pod) | Si (Pods en el mismo nodo) | Si (depende del access mode) |
| **Caso de uso** | Cache, temp, logs de prueba | Acceso a archivos del nodo | Bases de datos, datos permanentes |
| **Produccion** | Solo para datos temporales | Evitar (acoplado al nodo) | Recomendado |

#### StorageClass y aprovisionamiento dinamico

En clusters reales no se crean PVs manualmente. Se usa un **StorageClass** que provisiona PVs automaticamente cuando se crea un PVC:

```yaml
# PVC con StorageClass — Kubernetes crea el PV automaticamente
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  storageClassName: standard      # StorageClass del cluster (gp2, standard, etc.)
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

```bash
# Ver StorageClasses disponibles en el cluster
kubectl get storageclass
```

El flujo con aprovisionamiento dinamico:

```
PVC se crea → StorageClass detecta → crea PV automaticamente → PVC se vincula al PV → Pod lo monta
```

### Redireccion de salida en el comando

El comando usa `>>` para redirigir la salida de `date` al archivo de log:

```bash
while true; do date >> /opt/security/time/time-check.log; sleep $TIME_FREQ; done
```

| Operador | Comportamiento |
|----------|---------------|
| `>` | Sobreescribe el archivo en cada escritura |
| `>>` | Agrega al final del archivo (append) |

Se usa `>>` para que cada iteracion agregue una linea nueva al log sin borrar las anteriores.

## Pasos

1. Crear el namespace `devops`
2. Crear el ConfigMap `time-config` con `TIME_FREQ=8`
3. Crear el manifiesto del Pod con el volumen, variable de entorno y comando
4. Aplicar los manifiestos
5. Verificar que el Pod esta corriendo y escribiendo logs

## Comandos / Codigo

### 1. Crear el namespace

```bash
kubectl create namespace devops
```

```
namespace/devops created
```

### 2. Crear el ConfigMap

#### Forma imperativa

```bash
kubectl create configmap time-config --namespace=devops --from-literal=TIME_FREQ=8
```

#### Forma declarativa (YAML)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-config
  namespace: devops
data:
  TIME_FREQ: "8"
```

Verificar:

```bash
kubectl get configmap time-config -n devops -o yaml
```

```yaml
apiVersion: v1
kind: ConfigMap
data:
  TIME_FREQ: "8"
metadata:
  name: time-config
  namespace: devops
```

### 3. Manifiesto del Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: time-check
  namespace: devops
spec:
  volumes:
    - name: log-volume
      emptyDir: {}
  containers:
    - name: time-check
      image: busybox:latest
      env:
        - name: TIME_FREQ
          valueFrom:
            configMapKeyRef:
              name: time-config
              key: TIME_FREQ
      command:
        - /bin/sh
        - -c
        - while true; do date >> /opt/security/time/time-check.log; sleep $TIME_FREQ; done
      volumeMounts:
        - name: log-volume
          mountPath: /opt/security/time
```

### Estructura del manifiesto explicada

```
Pod (time-check)
├── metadata
│   ├── name: time-check
│   └── namespace: devops
└── spec
    ├── volumes                              # Definicion del volumen (a nivel de Pod)
    │   └── log-volume (emptyDir)
    └── containers
        └── time-check
            ├── image: busybox:latest
            ├── env                          # Variable de entorno desde ConfigMap
            │   └── TIME_FREQ → configMapKeyRef → time-config.TIME_FREQ
            ├── command                      # Comando que ejecuta el contenedor
            │   └── while true; do date >> ...log; sleep $TIME_FREQ; done
            └── volumeMounts                 # Montar el volumen en el contenedor
                └── log-volume → /opt/security/time
```

**Puntos importantes:**

- `volumes` se define a nivel de `spec` del Pod (no dentro del container)
- `volumeMounts` se define dentro del container y referencia el volumen por nombre
- `env.valueFrom.configMapKeyRef` toma el valor de una clave especifica del ConfigMap
- El `command` usa `/bin/sh -c` para interpretar el script con variables y redireccion

### 4. Aplicar los manifiestos

Si todo esta en un solo archivo `time-check.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-config
  namespace: devops
data:
  TIME_FREQ: "8"
---
apiVersion: v1
kind: Pod
metadata:
  name: time-check
  namespace: devops
spec:
  volumes:
    - name: log-volume
      emptyDir: {}
  containers:
    - name: time-check
      image: busybox:latest
      env:
        - name: TIME_FREQ
          valueFrom:
            configMapKeyRef:
              name: time-config
              key: TIME_FREQ
      command:
        - /bin/sh
        - -c
        - while true; do date >> /opt/security/time/time-check.log; sleep $TIME_FREQ; done
      volumeMounts:
        - name: log-volume
          mountPath: /opt/security/time
```

```bash
kubectl apply -f time-check.yaml
```

```
configmap/time-config created
pod/time-check created
```

### 5. Verificar

```bash
# Verificar que el Pod esta corriendo
kubectl get pod time-check -n devops
```

```
NAME         READY   STATUS    RESTARTS   AGE
time-check   1/1     Running   0          30s
```

```bash
# Ver las variables de entorno del contenedor
kubectl exec time-check -n devops -- env | grep TIME_FREQ
```

```
TIME_FREQ=8
```

```bash
# Ver el contenido del log (debe tener una fecha cada 8 segundos)
kubectl exec time-check -n devops -- cat /opt/security/time/time-check.log
```

```
Wed Feb 26 12:00:00 UTC 2026
Wed Feb 26 12:00:08 UTC 2026
Wed Feb 26 12:00:16 UTC 2026
```

```bash
# Ver los logs en tiempo real
kubectl exec time-check -n devops -- tail -f /opt/security/time/time-check.log
```

### Verificar el ConfigMap asociado al Pod

```bash
kubectl describe pod time-check -n devops
```

En la salida buscar la seccion `Environment`:

```
Environment:
  TIME_FREQ:  <set to the key 'TIME_FREQ' of config map 'time-config'>
```

Y la seccion `Mounts`:

```
Mounts:
  /opt/security/time from log-volume (rw)
```

## Flujo completo del ejercicio

```
1. kubectl create namespace devops
2. ConfigMap time-config (TIME_FREQ=8) en namespace devops
3. Pod time-check:
   ├── env: TIME_FREQ ← ConfigMap time-config
   ├── command: while true; do date >> .../time-check.log; sleep $TIME_FREQ; done
   └── volumeMount: log-volume → /opt/security/time
4. Verificar: kubectl exec → cat time-check.log
```

## Otras formas de inyectar ConfigMaps

### envFrom (todas las claves como variables)

```yaml
containers:
  - name: time-check
    envFrom:
      - configMapRef:
          name: time-config
```

Con `envFrom`, **todas** las claves del ConfigMap se convierten en variables de entorno automaticamente. Util cuando el ConfigMap tiene muchas claves.

### Como volumen (claves como archivos)

```yaml
volumes:
  - name: config-volume
    configMap:
      name: time-config
containers:
  - name: time-check
    volumeMounts:
      - name: config-volume
        mountPath: /etc/config
```

Esto crea un archivo `/etc/config/TIME_FREQ` con contenido `8`. Util para archivos de configuracion completos.

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| Pod en `CreateContainerConfigError` | El ConfigMap no existe o el nombre/key no coinciden. Verificar con `kubectl get configmap -n devops` |
| Pod en `CrashLoopBackOff` | El comando tiene error de sintaxis. Verificar con `kubectl logs time-check -n devops` |
| Log vacio | El Pod puede no haber tenido tiempo de escribir. Esperar al menos 8 segundos y verificar de nuevo |
| `Error from server (NotFound): namespaces "devops" not found` | Crear el namespace primero: `kubectl create namespace devops` |
| Variable `TIME_FREQ` vacia en el contenedor | Verificar que el ConfigMap tiene la clave correcta: `kubectl get configmap time-config -n devops -o yaml` |
| Archivo de log no existe | Verificar que el volumen esta montado: `kubectl describe pod time-check -n devops` y buscar la seccion Mounts |

## Recursos

- [ConfigMaps - Kubernetes Docs](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- [Volumes - Kubernetes Docs](https://kubernetes.io/docs/concepts/storage/volumes/)
- [busybox - Docker Hub](https://hub.docker.com/_/busybox)
