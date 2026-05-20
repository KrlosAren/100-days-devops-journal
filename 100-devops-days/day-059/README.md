# Día 59 - Troubleshooting Deployment: typo en image + ConfigMap inexistente

## Problema / Desafío

El equipo de Nautilus tenía un Deployment `redis-deployment` corriendo bien hasta que un compañero lo modificó "para ajustar algo" y dejó la app caída. Hay que devolverlo a `Running`:

- **Deployment:** `redis-deployment` (namespace `default`)
- **Estado actual:** `READY 0/1`, `AVAILABLE 0`
- **Pista del describe:** `Pod Template` referencia un ConfigMap y una imagen — ambos sospechosos
- **Restricción:** hay que entender qué se rompió antes de tocar nada

A diferencia de los días anteriores que arrancaban manifest en mano, este día arranca con la app rota y la única evidencia es `kubectl`. El foco real del día es **el orden de diagnóstico**.

## Conceptos clave

### Jerarquía de troubleshooting K8s

Los recursos en K8s están encadenados — el error que ves arriba no es donde nació:

```
Deployment            ← lo que pediste (intención)
   ↓ crea
ReplicaSet            ← garantiza N pods (mecanismo)
   ↓ crea
Pod                   ← donde corre el container
   ↓ administrado por
kubelet del Node      ← donde aparecen los errores reales (Events)
```

Reglas prácticas:

- `kubectl get deployment` solo dice **si hay desbalance entre lo deseado y lo disponible** (`READY 0/1`) — nunca dice por qué.
- `kubectl describe deployment` muestra el **Pod Template completo embebido** y la sección `Conditions` (Available=False, Progressing=True/False). Útil para spotear typos en el manifest sin abrir un editor.
- `kubectl describe pod <pod-name>` es **el lugar donde aparecen los errores del kubelet** (sección `Events`). Es lo más informativo cuando un Pod no arranca.
- `kubectl logs <pod>` **no sirve si el container nunca arrancó** — no hay stdout/stderr todavía.

### Por qué `logs` no funcionó hoy

El output observado:

```
Error from server (BadRequest): container "redis-container" in pod
"redis-deployment-6bc546f779-hb4c4" is waiting to start: ContainerCreating
```

`ContainerCreating` significa que el kubelet **todavía está preparando el container**. Hay tres etapas que pueden fallar en este estado:

1. **Setup de volúmenes** (mount ConfigMaps, Secrets, emptyDir, PVCs)
2. **Pull de la imagen**
3. **Arranque del container** (runtime crea el cgroup, namespaces, etc.)

Si el paso 1 falla, el kubelet **nunca llega al paso 2**. Por eso el Pod puede quedar atrapado en `ContainerCreating` indefinidamente sin pasar a `ImagePullBackOff`, aunque la imagen también esté mal: el kubelet falla antes de intentar el pull.

> Esto tiene una consecuencia importante: **fijar bugs en orden incorrecto puede revelar un segundo bug que estaba escondido**. Hoy, el error visible era el ConfigMap; fijar solo eso hubiera revelado el typo de la imagen recién después del próximo intento del kubelet.

### Estados de Pod relevantes

| Estado                          | Qué significa                                                            | Dónde verlo en detalle                          |
| ------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------- |
| `Pending`                       | Aún no scheduled a un Node (sin recursos, taints, nodeSelector imposible) | `describe pod` → sección `Events`              |
| `ContainerCreating`             | Scheduled, pero kubelet aún en setup (volúmenes / pull)                  | `describe pod` → `Events` → `MountVolume`      |
| `ImagePullBackOff` / `ErrImagePull` | El pull de la imagen falló (typo, registry inaccesible, auth)        | `describe pod` → `Events` → `Failed to pull`   |
| `CreateContainerConfigError`    | Referencia a un ConfigMap/Secret/envFrom que no existe                   | `describe pod` → `Events`                       |
| `CrashLoopBackOff`              | El container arrancó y murió varias veces seguidas                       | `kubectl logs <pod> --previous`                 |
| `Running`                       | Container vivo (no implica que la app responda — usar readinessProbe)   | `kubectl logs`                                  |

### Lectura crítica del describe deployment

Ambos bugs son visibles **leyendo el `describe deployment`** — sin necesidad de bajar al Pod. Esto es posible porque el describe del Deployment incluye el Pod Template embebido. Vale leerlo con foco en dos zonas:

```
  Containers:
   redis-container:
    Image:      redis:alpin              ← ❌ typo: falta la "e" final
    ...
  Volumes:
   config:
    Type:          ConfigMap
    Name:          redis-conig            ← ❌ typo: falta la "f"
```

Ambos errores son **silenciosos a nivel de API**: K8s acepta el Deployment porque sintácticamente es válido. La validación real la hace el kubelet en runtime cuando intenta materializar el Pod.

## Pasos

1. Diagnóstico inicial: `kubectl get deployment/redis-deployment` → confirmar `READY 0/1`
2. Lectura del describe: `kubectl describe deployment/redis-deployment` → leer Pod Template buscando typos
3. Intentar logs: `kubectl logs deployment/redis-deployment` → confirma que el container ni siquiera arrancó (`ContainerCreating`)
4. Verificar nombre real del ConfigMap: `kubectl get configmap` → ver que el real se llama `redis-config`, no `redis-conig`
5. Verificar nombre real de la imagen: el tag oficial de Redis Alpine es `alpine`, no `alpin` (revisar Docker Hub o `docker pull redis:alpine`)
6. Editar el Deployment en vivo: `kubectl edit deployment/redis-deployment` → corregir ambos campos en una sola edición
7. Verificación: nuevo ReplicaSet, nuevo Pod, `READY 1/1`, logs muestran "Ready to accept connections"

## Comandos / Código

### Diagnóstico

```bash
# Estado del Deployment
kubectl get deployment/redis-deployment

# Pod Template completo + Conditions + Events del Deployment
kubectl describe deployment/redis-deployment

# Logs (no funciona en ContainerCreating, pero confirma el estado)
kubectl logs deployment/redis-deployment

# (Reflejo recomendado, no usado hoy) Eventos del Pod real
kubectl get pods
kubectl describe pod <pod-name>

# Verificar el nombre real del ConfigMap
kubectl get configmap
```

### Output real: estado inicial

```
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
redis-deployment   0/1     1            0           5m30s
```

```
Containers:
 redis-container:
  Image:      redis:alpin
  Port:       6379/TCP
  ...
Volumes:
 config:
  Type:          ConfigMap
  Name:          redis-conig
  Optional:      false
```

```
Error from server (BadRequest): container "redis-container" in pod
"redis-deployment-6bc546f779-hb4c4" is waiting to start: ContainerCreating
```

```
NAME               DATA   AGE
kube-root-ca.crt   1      56m
redis-config       2      20m
```

### Fix con `kubectl edit`

```bash
kubectl edit deployment/redis-deployment
```

Cambios aplicados dentro del editor (vim por defecto):

```diff
       containers:
       - name: redis-container
-        image: redis:alpin
+        image: redis:alpine
         ports:
         - containerPort: 6379
       volumes:
       - name: config
         configMap:
-          name: redis-conig
+          name: redis-config
```

Al guardar, K8s detecta el cambio en el Pod Template, genera un nuevo `pod-template-hash`, y arranca un ReplicaSet nuevo que reemplaza al viejo (rolling update — mismo mecanismo del Día 51).

### Verificación

```
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
redis-deployment   1/1     1            1           22m
```

```
NAME                                READY   STATUS    RESTARTS   AGE
redis-deployment-5476b4ddd6-hvqwv   1/1     Running   0          113s
```

```
1:M 19 May 2026 03:14:53.823 * Running mode=standalone, port=6379.
1:M 19 May 2026 03:14:53.839 * Server initialized
1:M 19 May 2026 03:14:53.839 * Ready to accept connections tcp
1:M 19 May 2026 03:14:53.839 # WARNING: Redis does not require authentication and is not protected by network restrictions...
```

Notar el cambio de hash en el nombre del Pod:

| Antes (broken) | Después (fix)    |
| -------------- | ---------------- |
| `6bc546f779`   | `5476b4ddd6`     |

Esto confirma que el Pod Template cambió — los hashes son determinísticos sobre el contenido del template (visto en Día 52 con `rollout undo`). Si el hash es el mismo después de un edit, significa que K8s consideró que el template no cambió.

## Comparativa: comandos para diagnosticar un Pod que no arranca

| Comando                              | Qué muestra                                                                 | Cuándo es la mejor herramienta                                       |
| ------------------------------------ | --------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `get deployment`                     | Replicas deseadas/disponibles                                              | Confirmar que hay un problema, nada más                          |
| `describe deployment`                | Pod Template + Conditions + Events del controller                          | Leer el manifest aplicado y buscar typos                         |
| `get pods`                           | Lista de pods con su estado                                                | Identificar el Pod problemático y su estado real                |
| `describe pod <name>`                | Events del kubelet (la verdad sobre por qué no arranca)                    | **El reflejo correcto** cuando un Pod no inicia                  |
| `logs <pod>` / `logs deployment/X`   | stdout/stderr del container                                                | Solo si el container llegó a arrancar (no en ContainerCreating)  |
| `logs <pod> --previous`              | stdout/stderr de la instancia anterior del container                       | Diagnosticar CrashLoopBackOff                                    |
| `get events --sort-by=.lastTimestamp` | Todos los eventos del namespace en orden cronológico                      | Cuando no sabés ni siquiera qué Pod mirar                        |

## Conexión con días anteriores

- **Día 51 (rolling update)**: el `kubectl edit` de hoy disparó el mismo mecanismo — nuevo Pod Template → nuevo `pod-template-hash` → nuevo ReplicaSet → rollout. La diferencia es que ahí el cambio era una imagen "buena por una mejor"; acá es una imagen "rota por una correcta".
- **Día 52 (rollback)**: los hashes del Pod (`6bc546f779` → `5476b4ddd6`) son la huella visible del controller decidiendo si genera RS nuevo o reusa uno existente.
- **Día 53 (troubleshooting nginx + php-fpm)**: ahí también el Pod estaba `Running` pero la app fallaba a nivel de aplicación; hoy el Pod ni siquiera arrancó. Los dos extremos del troubleshooting K8s.
- **Día 56–57 (ConfigMaps + env vars)**: el patrón de hoy es el mismo que ahí — referenciar un ConfigMap por nombre desde el Pod. La diferencia es que un typo en el nombre **no falla al `kubectl apply`**, solo en runtime.

## Reflexión: el camino más corto

Hoy los dos bugs aparecieron leyendo `describe deployment`. La alternativa "más K8s-idiomática" hubiera sido `kubectl describe pod <pod-name>` — donde el kubelet expone explícitamente sus errores en la sección `Events`. Por ejemplo, para un ConfigMap inexistente, el kubelet emite algo como:

```
Warning  FailedMount  ...  MountVolume.SetUp failed for volume "config" :
configmap "redis-conig" not found
```

Y para una imagen con tag inexistente:

```
Warning  Failed  ...  Failed to pull image "redis:alpin": ...
manifest for redis:alpin not found: manifest unknown
```

Ambos comandos llegan al mismo destino pero por rutas distintas: `describe deployment` requiere **leer el manifest aplicado** y encontrar inconsistencias por inspección; `describe pod` te da **el error que el sistema vio al intentar materializar el Pod**.

Cuando un Pod no levanta, conviene hilar fino y descartar capas de abajo hacia arriba: primero `kubectl logs` para confirmar si la app llegó a arrancar (descartar bug aplicativo); si el container ni siquiera corrió, `kubectl describe pod` para leer los `Events` del kubelet — ahí aparecen los typos de ConfigMap, Secret o image, y los volúmenes que no se pueden montar. Solo al final vale releer el manifest con `describe deployment` buscando inconsistencias por inspección. Hoy ese orden se saltó porque los typos eran visibles a simple vista en el Pod Template, pero ese atajo solo funciona cuando el error está en un campo de texto plano del manifest. K8s es declarativo y potente, pero al apoyarse tanto en strings (nombres de ConfigMaps, tags de imágenes, paths) deja mucha superficie para el error humano que el API server no intercepta.

## Troubleshooting

| Problema                                                       | Causa                                                                                                   | Solución                                                                                          |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Pod stuck en `ContainerCreating` indefinidamente               | Setup de volúmenes falla (ConfigMap/Secret no existe, PVC no se puede bindear, emptyDir mal formado)    | `describe pod` → leer sección `Events` para identificar qué volumen falla                         |
| `logs` devuelve `is waiting to start: ContainerCreating`       | El container nunca arrancó, no hay stdout/stderr que mostrar                                            | Usar `describe pod` en lugar de `logs` para diagnosticar                                          |
| Imagen con typo aceptada por el API server                     | K8s no valida que el tag/repo exista al crear el Deployment — solo el kubelet, en runtime               | Verificar con `docker pull <image>` antes, o leer el Pod Template post-creación                   |
| ConfigMap referenciado con nombre incorrecto                   | Igual que arriba: el API server no valida la existencia de objetos referenciados por nombre             | `kubectl get configmap` para comparar nombres reales contra el manifest                           |
| Fix aplicado pero el Pod sigue roto                            | Posiblemente había **dos** bugs y solo se vio el primero. Volver a `describe pod` después del primer fix | Re-correr `describe pod` después de cada edit hasta que `Events` esté limpio                      |
| `kubectl edit` abre un editor que no podés usar                | El editor default puede ser vim. Si no lo dominás, exportar otro                                        | `export KUBE_EDITOR="nano"` (o `"code --wait"` para VSCode) antes de correr `kubectl edit`        |
| Editaste el deployment pero no se actualizó                    | Probablemente guardaste sin cambios reales, o el editor agregó/quitó solo whitespace                    | K8s diff-compara el template; si el hash no cambió, no hubo cambio real. Volver a editar         |
| Pod arranca pero la app no responde                            | El container está `Running` pero la app interna tarda en estar lista                                    | Esperar unos segundos, ver `kubectl logs` para confirmar mensaje de "ready" / "listening"         |

## Recursos

- [Debug Pods (oficial)](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Pod Lifecycle — estados y transiciones](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [kubectl edit — semantics](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#edit)
- [Redis official Docker image — tags](https://hub.docker.com/_/redis)
- [ConfigMap — uso en volúmenes](https://kubernetes.io/docs/concepts/configuration/configmap/#configmaps-and-pods)
- [Common pod errors — KodeKloud blog](https://kodekloud.com/blog/kubernetes-pod-status/)
