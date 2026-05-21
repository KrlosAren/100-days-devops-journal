# Día 61 - Init Containers en Kubernetes

## Problema / Desafío

El equipo de Nautilus tiene apps que necesitan **preparación previa** al arranque del container principal: algunos cambios de configuración no pueden hacerse dentro de la imagen base. La solución es usar **init containers** para correr esa preparación durante el deployment.

- **Deployment:** `ic-deploy-nautilus`, `replicas: 1`
- **Labels:** `app: ic-nautilus` (tanto en el Deployment como en el template)
- **Init container:** `ic-msg-nautilus`, imagen `debian:latest`, escribe un mensaje de bienvenida en `/ic/beta`
- **Main container:** `ic-main-nautilus`, imagen `debian:latest`, lee `/ic/beta` cada 5 segundos en un loop infinito
- **Volumen:** `ic-volume-nautilus` tipo `emptyDir`, montado en ambos containers en `/ic`

El patrón del lab simula un escenario común: **un container prepara un archivo / config que otro container va a consumir**, y la comunicación se hace por un volumen compartido.

## Conceptos clave

### Qué es un init container

Es un container que se ejecuta **antes** de los containers principales del Pod. Características esenciales:

- Corre hasta terminar (exit 0) — no es un proceso de larga duración
- Si falla (exit != 0), el kubelet lo reinicia según `restartPolicy` del Pod
- Si todos los init containers no terminan exitosamente, **el main container nunca arranca**
- Los init containers corren **secuencialmente** (uno por uno, en el orden declarado en el YAML)
- Los main containers corren **en paralelo** entre sí, recién cuando todos los init terminaron

```
[init-c1] run → exit 0
                       ↓
                  [init-c2] run → exit 0
                                          ↓
                                     [main-c1] running ───┐
                                     [main-c2] running ───┤  (paralelo)
                                     [main-c3] running ───┘
```

### Casos de uso típicos

| Caso                                              | Por qué el init container es la herramienta correcta                                       |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| **Esperar a que una dependencia esté lista**     | `until nc -z db 5432; do sleep 1; done` — el main no arranca hasta que la DB responda     |
| **Generar config dinámicamente**                  | Renderizar templates con valores del entorno, IPs del pod, etc.                            |
| **Clonar un repo git**                            | `git-sync` para apps que sirven contenido de un repo                                       |
| **Descargar artefactos / binarios**               | `wget` de un release de GitHub, copiarlo al volumen y luego el main lo ejecuta             |
| **Ajustes de permisos del volumen**               | `chown -R appuser /data` antes de que la app arranque (típico con PVCs y UIDs no-root)    |
| **Inicializar la base de datos**                  | Correr migraciones una sola vez antes que el container app empiece a recibir tráfico       |
| **Setup que requiere herramientas extra**         | Tener `curl`, `git`, `jq` en el init pero no en la imagen final del main (mantiene la imagen slim) |

### Init container vs sidecar — la distinción que se confunde

Después del Día 55 (sidecars native con `initContainers` + `restartPolicy: Always`), vale aclarar la diferencia exacta:

| Característica                   | Init container clásico               | Sidecar native (`initContainers` + `restartPolicy: Always`) |
| -------------------------------- | ------------------------------------ | ----------------------------------------------------------- |
| ¿Corre antes del main?           | Sí, debe **terminar** antes          | Sí, debe estar **Ready** antes (no termina)                 |
| ¿Sigue corriendo con el main?    | No (ya terminó)                      | Sí, corre en paralelo                                       |
| ¿Restart si crashea?             | Según `restartPolicy` del Pod        | Siempre (definido explícitamente)                           |
| Caso típico                      | Setup one-shot                       | Log shipper, service mesh proxy                             |
| Lab que lo usó                   | **Día 61** (hoy)                     | **Día 55**                                                  |

Regla práctica: **si el container debe terminar para que la app arranque → init clásico. Si debe vivir junto a la app → sidecar native.**

### Init container vs main container — diferencias formales

| Aspecto                     | Init container                                                  | Main container                                                |
| --------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------- |
| Campo en el spec            | `spec.template.spec.initContainers`                             | `spec.template.spec.containers`                               |
| Lifetime                    | Corre y termina                                                 | Corre todo el lifetime del Pod                                |
| Orden                       | Secuencial entre ellos, antes de los main                       | Paralelo entre ellos                                          |
| Probes                      | **No soporta** `readinessProbe`, `livenessProbe`, `startupProbe` | Soporta los tres                                              |
| Recursos (requests/limits)  | Soportados, pero compartidos con los main (max de ambos)        | Soportados                                                    |
| Visibles en `kubectl logs`  | Sí, con `kubectl logs <pod> -c <init-name>`                     | Sí, con `kubectl logs <pod>` o `-c <main-name>`               |

### Estados del Pod cuando hay init containers

Mientras los init containers corren, el Pod muestra estados específicos:

| Estado                      | Significado                                                                          |
| --------------------------- | ------------------------------------------------------------------------------------ |
| `Init:0/2`                  | Tiene 2 init containers, ninguno terminó todavía                                     |
| `Init:1/2`                  | Tiene 2 init containers, 1 terminó exitosamente, otro está corriendo o pendiente     |
| `Init:Error`                | El init container actual terminó con exit != 0                                       |
| `Init:CrashLoopBackOff`     | El init container falla repetidamente, el kubelet lo está reintentando con backoff   |
| `Init:ImagePullBackOff`     | La imagen del init container no se puede pullear                                     |
| `PodInitializing`           | Todos los init terminaron, el kubelet está arrancando los main containers            |
| `Running`                   | Al menos un main container está corriendo                                            |

### Por qué la comunicación entre init y main pasa por un volumen

Los init y main containers **no comparten filesystem** entre sí — cada container tiene su propio rootfs. La forma de pasarse datos es a través de:

| Mecanismo                      | Cuándo usarlo                                                            |
| ------------------------------ | ------------------------------------------------------------------------ |
| **`emptyDir` compartido**     | Datos generados en runtime que ambos containers ven (este lab, Día 54, 55) |
| **Volumen persistente (PVC)** | Datos que también deben sobrevivir al Pod (Día 60)                       |
| **ConfigMap / Secret mount**  | Datos estáticos pre-existentes que el main consume sin necesidad de init |
| **Variables de entorno**       | Datos pequeños y simples (no aplica si el init genera el contenido)      |

En este lab, el init escribe `/ic/beta` en el `emptyDir`, el main lo lee desde el mismo `emptyDir` (mismo path porque ambos montan el volumen en `/ic`). Si los `mountPath` divergieran, el main no encontraría el archivo — el mismo problema conceptual del Día 53.

## Pasos

1. Definir el Deployment con `replicas: 1`, `selector.matchLabels.app: ic-nautilus`
2. Bajo `template.spec`, declarar el volumen `ic-volume-nautilus` tipo `emptyDir`
3. Declarar el `initContainers` con la imagen `debian:latest` y el comando de `echo` al archivo
4. Declarar el `containers` (main) con la imagen `debian:latest` y el `while true; cat; sleep` loop
5. Ambos containers deben montar el mismo volumen en `/ic`
6. `kubectl apply -f deployment.yml`
7. Verificar con `kubectl get deploy` y `kubectl describe deploy`
8. Validar que el main lee lo que el init escribió: `kubectl logs <pod> -c ic-main-nautilus`

## Comandos / Código

### Manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ic-deploy-nautilus
  labels:
    app: ic-nautilus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ic-nautilus
  template:
    metadata:
      labels:
        app: ic-nautilus
    spec:
      volumes:
        - name: ic-volume-nautilus
          emptyDir: {}
      initContainers:
        - name: ic-msg-nautilus
          image: debian:latest
          command:
            - /bin/bash
            - -c
            - echo 'Init Done - Welcome to xFusionCorp Industries' > /ic/beta
          volumeMounts:
            - name: ic-volume-nautilus
              mountPath: /ic
      containers:
        - name: ic-main-nautilus
          image: debian:latest
          command:
            - /bin/bash
            - -c
            - while true; do cat /ic/beta; sleep 5; done
          volumeMounts:
            - name: ic-volume-nautilus
              mountPath: /ic
```

### Aplicación y verificación

```bash
kubectl apply -f deployment.yml
```

```
deployment.apps/ic-deploy-nautilus created
```

```bash
kubectl get deploy
```

```
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
ic-deploy-nautilus   1/1     1            1           12s
```

### Lectura crítica del describe

```bash
kubectl describe deploy
```

```
Name:                   ic-deploy-nautilus
Selector:               app=ic-nautilus
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
Pod Template:
  Labels:  app=ic-nautilus
  Init Containers:
   ic-msg-nautilus:
    Image:      debian:latest
    Command:
      /bin/bash
      -c
      echo 'Init Done - Welcome to xFusionCorp Industries' > /ic/beta
    Mounts:
      /ic from ic-volume-nautilus (rw)
  Containers:
   ic-main-nautilus:
    Image:      debian:latest
    Command:
      /bin/bash
      -c
      while true; do cat /ic/beta; sleep 5; done
    Mounts:
      /ic from ic-volume-nautilus (rw)
  Volumes:
   ic-volume-nautilus:
    Type:          EmptyDir (a temporary directory that shares a pod's lifetime)
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
NewReplicaSet:   ic-deploy-nautilus-7c7d4f95bf (1/1 replicas created)
Events:
  Normal  ScalingReplicaSet  23s   deployment-controller  Scaled up replica set ic-deploy-nautilus-7c7d4f95bf from 0 to 1
```

Detalles a notar en el describe:

| Bloque                                 | Qué confirma                                                                         |
| -------------------------------------- | ------------------------------------------------------------------------------------ |
| `Init Containers:` aparece **separado** de `Containers:` | El API server entiende y reporta init containers como categoría aparte    |
| Ambos bloques muestran `/ic from ic-volume-nautilus (rw)` | El volumen está montado en los **dos** containers con el mismo path        |
| `Volumes: ic-volume-nautilus → EmptyDir` | El kubelet creó un directorio efímero en el nodo al arrancar el Pod                 |
| `Available: True` y `Replicas: 1 available` | El init container terminó exitosamente — sino el Pod nunca pasaría a `Running`    |
| Solo un evento (`ScalingReplicaSet`)    | El init terminó tan rápido que no aparece evento de su transición                   |

### Verificar que el patrón funcionó

```bash
kubectl get pods
kubectl logs <pod-name> -c ic-main-nautilus
```

El log esperado del main container es el mensaje repetido cada 5 segundos:

```
Init Done - Welcome to xFusionCorp Industries
Init Done - Welcome to xFusionCorp Industries
Init Done - Welcome to xFusionCorp Industries
...
```

Para ver el log del init (útil para debugging):

```bash
kubectl logs <pod-name> -c ic-msg-nautilus
```

Como el init solo hace un `echo > /ic/beta`, no genera stdout — el comando es silencioso por diseño. Si hubiera fallado, ahí aparecería el error.

## emptyDir + initContainers — el "buzón temporal" entre containers

El patrón se repite a lo largo del journal con variantes distintas:

| Día     | Quién escribe              | Quién lee                  | Para qué                                    |
| ------- | -------------------------- | -------------------------- | ------------------------------------------- |
| Día 54  | Container 1 (manual)       | Container 2 (manual)       | Probar mecanismo de volumen compartido      |
| Día 53  | Volumen pre-existente      | nginx + php-fpm            | Servir PHP — el contrato FastCGI            |
| Día 55  | nginx (logs)               | sidecar (log shipper)      | Streaming de logs en tiempo real            |
| Día 61  | initContainer (`echo`)     | main container (`cat` loop) | Setup one-shot consumido por la app principal |

La diferencia clave entre Día 55 y Día 61 está en **el rol y el lifecycle del container "auxiliar"**: en Día 55 el auxiliar vive junto al main (sidecar); en Día 61 el auxiliar termina antes de que el main empiece (init).

## Conexión con días anteriores

- **Día 54 (`emptyDir`)**: misma primitiva de volumen, distinto rol — acá actúa como buzón one-shot entre init y main.
- **Día 55 (sidecars native)**: contrasta explícitamente con hoy. Hoy `initContainers` se usa para su semántica clásica (corre y termina); en Día 55 se usa para sidecars con `restartPolicy: Always`. El campo YAML es el mismo, el comportamiento es distinto según `restartPolicy`.
- **Día 53 (mismo `mountPath` en dos containers)**: la regla "ambos containers deben montar el volumen en paths donde tiene sentido para cada uno" se repite. Acá ambos lo montan en `/ic` para usar la misma ruta absoluta — más simple que el caso de Día 53 donde los paths divergían.
- **Día 49 (Deployments)**: el wrapper sigue siendo el mismo: Deployment → ReplicaSet → Pod. Lo nuevo está dentro del Pod template, no en el controller.
- **Día 60 (PVCs como bootstrap)**: una alternativa a usar initContainer + emptyDir es prepoblar un PV con datos persistentes que el main consume directo. Trade-off: el initContainer es efímero y replicable, el PV es persistente pero requiere setup previo.

## Reflexión: ¿cuándo init container, cuándo otra cosa?

Init containers son útiles, pero no son la única forma de preparar un Pod. Hay alternativas que vale evaluar antes de meter lógica en un init:

| Necesidad                                            | Alternativa potencial                                          | Cuándo el init container gana                                         |
| ---------------------------------------------------- | -------------------------------------------------------------- | --------------------------------------------------------------------- |
| Config estática conocida en build time               | **Hornear en la imagen** (Dockerfile `COPY`)                   | Si la config depende de info que solo existe en runtime (IPs, secrets) |
| Config estática conocida al deploy                   | **ConfigMap montado como volumen**                             | Si la config debe ser generada o transformada antes de que el main la use |
| Esperar a que una DB esté lista                      | **`readinessProbe` del main** que reintenta hasta la conexión  | Si el main debe **arrancar limpio** sin manejar retry logic           |
| Migrar el esquema de DB                              | **Job de K8s** (no Pod) corrido en CI/CD antes del deploy      | Si la migración debe correr **siempre** antes de cada Pod (raro)       |
| Cargar contenido de un repo git                      | **Imagen custom** con el repo ya clonado en build time          | Si el contenido cambia más rápido que los builds de imagen (`git-sync`) |
| Esperar a otra dependencia interna                   | **Lógica de retry en la app**                                  | Si no se puede modificar la app (third-party, legacy)                 |

La experiencia previa antes de este lab venía mayoritariamente de **Docker y Docker Compose**, donde estos patrones no se encuentran con frecuencia — no es que falten, es que el modelo de Compose esconde la necesidad detrás de `depends_on`, healthchecks y entrypoints custom. El único caso real de uso "tipo init container" antes de Kubernetes había sido montar un **EFS en una EC2 y correr un container previo para ajustar los permisos del volumen** antes de que la app arrancara — sin saberlo en ese momento, ese es uno de los casos canónicos del patrón initContainer en K8s (el `chown -R appuser /data` antes de que la app no-root pueda escribir). Lo interesante de ver este lab es que **K8s formaliza con un campo dedicado (`initContainers`) algo que en Docker se resuelve con hacks ad-hoc** (entrypoints que validan y luego hacen `exec`, scripts de wait-for-it, etc.). La regla mental que queda de hoy: cuando aparezca la pregunta "¿necesito que algo termine antes de que la app arranque?", el reflejo correcto es buscar si un initContainer simplifica el manifest, en lugar de inflar el entrypoint del main.

## Troubleshooting

| Problema                                                      | Causa                                                                                       | Solución                                                                                  |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Pod queda en `Init:0/1` indefinidamente                       | El init container está corriendo lento, o se quedó esperando algo (typical `until ...; do sleep`) | `kubectl logs <pod> -c <init-name>` para ver qué hace                                  |
| Pod en `Init:CrashLoopBackOff`                                | El init container falla con exit != 0 repetidas veces                                       | `kubectl logs <pod> -c <init-name> --previous` para ver el error de la instancia anterior |
| Pod en `Init:Error`                                           | El init container terminó con exit code distinto a 0                                        | Mismo enfoque — revisar logs del init                                                     |
| El main container no ve el archivo creado por el init         | Los `mountPath` divergen, o el init escribió a un path fuera del volumen                    | Verificar que ambos containers montan el mismo volumen en paths consistentes              |
| El archivo aparece vacío al leerlo desde el main              | El init escribió pero el shell del `command` interpretó mal las comillas / redirecciones    | Probar el `echo` aislado dentro del container: `kubectl exec ... -- bash -c "..."`         |
| El init container no termina nunca                            | El comando es un proceso de larga duración (típico si copiaste un loop por error)           | El init debe ser **one-shot** — si necesitás algo que viva junto al main, usar sidecar native (Día 55) |
| `kubectl logs <pod>` sin `-c` muestra solo el main           | Por default, `logs` apunta al primer container del array `containers:`, no a los init       | Siempre especificar `-c <container-name>` cuando hay múltiples containers o init containers |
| El Deployment se actualiza pero el init no vuelve a correr    | Pregunta engañosa — un Pod nuevo del rolling update **sí** vuelve a correr el init           | Confirmar que el Pod es nuevo (`pod-template-hash` cambió) y no el mismo Pod restarteado  |

## Recursos

- [Init Containers (oficial)](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Pod Lifecycle — Init Containers in detail](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#init-containers)
- [Debug Init Containers](https://kubernetes.io/docs/tasks/debug/debug-application/debug-init-containers/)
- [Sidecar Containers (relación con initContainers + restartPolicy: Always)](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
- [git-sync — ejemplo real de init container que clona un repo](https://github.com/kubernetes/git-sync)
