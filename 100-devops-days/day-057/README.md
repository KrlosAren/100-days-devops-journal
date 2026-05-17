# Día 57 - Variables de entorno en Pods (env + `$(VAR)` substitution)

## Problema / Desafío

El equipo de Nautilus está armando una app de "greetings". Hay que crear un Pod que pruebe el patrón de variables de entorno:

- **Pod:** `print-envars-greeting`
- **Container:** `print-env-container`, imagen `bash`
- **Env vars:**
  - `GREETING = "Welcome to"`
  - `COMPANY = "DevOps"`
  - `GROUP = "Ltd"`
- **Command exacto:** `["/bin/sh", "-c", 'echo "$(GREETING) $(COMPANY) $(GROUP)"']`
- **`restartPolicy: Never`** — para que el container termine y no entre en CrashLoopBackOff (el `echo` corre una vez y sale con exit 0)
- **Verificación:** `kubectl logs -f print-envars-greeting` debe imprimir `Welcome to DevOps Ltd`

## Conceptos clave

### Variables de entorno en Pods — las 4 formas

K8s ofrece varias formas de inyectar variables de entorno en un container, cada una con su caso de uso:

| Forma                       | Sintaxis                                                      | Cuándo usarla                                                         |
| --------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------- |
| **Hardcoded inline**        | `env: [{name: KEY, value: "val"}]`                            | Valores triviales que no son sensibles ni cambian (este lab)         |
| **Desde ConfigMap**         | `env: [{name: KEY, valueFrom: {configMapKeyRef: {...}}}]`     | Configuración no sensible compartida entre varios pods                |
| **Desde Secret**            | `env: [{name: KEY, valueFrom: {secretKeyRef: {...}}}]`        | Passwords, API keys, tokens — encriptados at-rest (con KMS)           |
| **Downward API**            | `env: [{name: POD_IP, valueFrom: {fieldRef: {fieldPath: status.podIP}}}]` | Metadata del pod (nombre, namespace, IP, labels, etc.)            |
| **Import masivo**           | `envFrom: [{configMapRef: {name: ...}}]` o `secretRef`        | Volcar TODO un ConfigMap/Secret como env vars (Twelve-Factor App)    |

### Más allá: ¿de dónde más pueden venir las variables?

- **External Secrets Operator** → puente entre K8s Secrets y backends externos (AWS Secrets Manager, GCP Secret Manager, HashiCorp Vault, 1Password, etc.). El operator lee del backend y crea/actualiza Secrets nativos
- **HashiCorp Vault Agent Injector** → mutating webhook que inyecta un sidecar que monta credenciales en un emptyDir desde Vault
- **CSI Secret Store** → driver de volumen que monta secretos como archivos (no env vars), permite rotación sin reiniciar el pod
- **Argo CD / Helm values** → la config viene de un git repo o un release de Helm; al deploy se renderiza el manifest con las env vars correctas

### `$(VAR)` substitution: ¿qué hace K8s, qué hace el shell?

La consigna usa **paréntesis** (`$(GREETING)`) en vez de **llaves** (`${GREETING}`). No es lo mismo — y entender quién expande cuál es clave:

| Sintaxis           | Quién expande               | Cuándo ocurre                                                    |
| ------------------ | --------------------------- | ---------------------------------------------------------------- |
| `$(VAR)`           | **kubelet** (Kubernetes)    | Antes de pasar el `command` al container — al crear el proceso  |
| `${VAR}` o `$VAR`  | **Shell del container**     | En runtime, cuando el shell ejecuta el comando                   |

Para este lab, K8s ve:

```yaml
command: ["/bin/sh", "-c", 'echo "$(GREETING) $(COMPANY) $(GROUP)"']
env: [GREETING="Welcome to", COMPANY="DevOps", GROUP="Ltd"]
```

K8s reemplaza `$(GREETING)`, `$(COMPANY)`, `$(GROUP)` con sus valores **antes** de crear el container. El proceso recibe como argv:

```
argv[0] = /bin/sh
argv[1] = -c
argv[2] = echo "Welcome to DevOps Ltd"
```

El shell del container nunca ve las variables — solo el string final. Por eso ves `Command: echo "$(GREETING) $(COMPANY) $(GROUP)"` en el `describe` (es el spec original) pero el output es `Welcome to DevOps Ltd` (el resultado tras la substitution).

> **¿Cuál es la diferencia práctica?** Si usaras `${GREETING}` en el comando, K8s no lo expande, y depende del shell. `sh` lo expande, así que también funcionaría. Pero si la imagen no tuviera shell (como `distroless` o `scratch`), `${VAR}` no se expande y queda literal. **`$(VAR)` siempre funciona** porque la expansión la hace kubelet, no el shell — es la forma "K8s-native".

### `restartPolicy` — el campo MÁS confundido del Pod spec

Este es probablemente el error de indentación más común en K8s. **`restartPolicy` es un campo del Pod, NO del container**:

```yaml
spec:
  restartPolicy: Never   # ✅ correcto — a nivel Pod
  containers:
    - name: foo
      image: bar
```

vs:

```yaml
spec:
  containers:
    - name: foo
      image: bar
      restartPolicy: Never   # ❌ ignorado en containers regulares
```

El problema: **K8s NO da error si lo ponés mal indentado** — simplemente lo ignora silenciosamente y aplica el default (`Always`). Entonces tu container completó, K8s lo reinició, completó otra vez, K8s lo reinició, y eventualmente entró en `CrashLoopBackOff` aunque el exit code haya sido `0` siempre.

#### Los 3 valores válidos de `restartPolicy`

| Valor      | Comportamiento                                                              | Cuándo usarlo                                            |
| ---------- | --------------------------------------------------------------------------- | -------------------------------------------------------- |
| `Always`   | Reinicia el container siempre que termine (success o failure)                | **Default**. Apps de larga vida (web servers, daemons)   |
| `OnFailure`| Reinicia solo si termina con exit code ≠ 0                                  | Jobs y CronJobs que pueden fallar y deben reintentar     |
| `Never`    | Nunca reinicia, sin importar el exit code                                   | Tareas one-shot que terminan limpio (este lab)           |

> **Trampa importante:** `restartPolicy` solo aplica a Pods stand-alone. Si el Pod es parte de un Deployment, el RS controller crea pods nuevos cuando los viejos mueren — el `restartPolicy` solo afecta al container DENTRO del Pod, no al ciclo de vida del Pod en sí.

#### Excepción: `restartPolicy` a nivel container (K8s 1.28+)

Desde K8s 1.28 sí existe un `restartPolicy` por container, pero **solo es válido para init containers**: es lo que diferencia un init container clásico (`restartPolicy` no especificado) de un **native sidecar** (`restartPolicy: Always`) — ver Día 55. Para containers regulares se ignora completamente.

### El símbolo del bug: `Restart Count: 2` con `Reason: Completed`

```
State:          Terminated
  Reason:       Completed
  Exit Code:    0
Restart Count:  2

Events:
  Warning  BackOff  9s (x3 over 22s)  kubelet  Back-off restarting failed container
```

Esta combinación es paradójica: el container **completó exitosamente** (exit 0) pero K8s lo está reintentando como si fuera un fallo. Es el síntoma clásico del `restartPolicy` mal puesto:

- K8s no recibió `Never` (porque lo puso indentado mal) → aplica default `Always`
- Container termina con exit 0 (todo bien)
- `Always` significa "reiniciá pase lo que pase" → K8s reinicia
- A los 2-3 restarts seguidos en poco tiempo, K8s entra en exponential back-off
- El evento `BackOff` aparece a pesar de que el exit code es 0 — la "Falla" desde el punto de vista de K8s es "intenté reiniciar 3 veces seguido"

## Pasos

1. Escribir el manifest **con la indentación correcta** de `restartPolicy`
2. `kubectl apply -f pod.yml`
3. `kubectl logs -f print-envars-greeting` para ver el output
4. Verificar el estado final con `describe` — debe ser `Completed` con `Restart Count: 0`

## Comandos / Código

### Manifest CORREGIDO

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: print-envars-greeting
spec:
  restartPolicy: Never          # ← a nivel Pod (NO dentro del container)
  containers:
    - name: print-env-container
      image: bash
      command: ["/bin/sh", "-c", 'echo "$(GREETING) $(COMPANY) $(GROUP)"']
      env:
        - name: GREETING
          value: "Welcome to"
        - name: COMPANY
          value: "DevOps"
        - name: GROUP
          value: "Ltd"
```

> **Diferencia con el manifest original:** moví `restartPolicy: Never` de dentro de `containers[0]` a `spec.restartPolicy`. El YAML del lab original lo tenía dentro del container — K8s lo ignoró silenciosamente y aplicó `Always`.

### Aplicar

```bash
kubectl apply -f pod.yml
```

```
pod/print-envars-greeting created
```

### Ver el output (el test del ejercicio)

```bash
kubectl logs -f print-envars-greeting
```

```
Welcome to DevOps Ltd
```

`-f` (follow) acá no hace nada práctico porque el container termina inmediatamente — el output se imprime una sola vez. En containers de larga vida `-f` es streaming continuo.

### `describe` (con `restartPolicy: Never` correcto)

Con la indentación correcta, este sería el estado esperado:

```
State:          Terminated
  Reason:       Completed
  Exit Code:    0
Restart Count:  0          ← cero restarts (con Never K8s no reintenta)

Environment:
  GREETING:  Welcome to
  COMPANY:   DevOps
  GROUP:     Ltd
```

### `describe` que viste en el lab (con el bug de indentación)

Como en tu YAML original `restartPolicy` quedó dentro del container, K8s aplicó `Always`:

```
State:          Terminated
  Reason:       Completed
  Exit Code:    0
Last State:     Terminated
  Reason:       Completed
  Exit Code:    0
Restart Count:  2          ← K8s reinició 2 veces aunque el container terminó OK

Events:
  Normal   Pulled    (x3)   kubelet  Successfully pulled image "bash"
  Normal   Created   (x3)   kubelet  Created container: print-env-container
  Normal   Started   (x3)   kubelet  Started container print-env-container
  Warning  BackOff   (x3)   kubelet  Back-off restarting failed container
```

La línea `(x3)` en los events es la huella de los reintentos. El container se ejecutó 3 veces (cada vez imprimió "Welcome to DevOps Ltd"), y K8s estaba a punto de hacer un 4to intento con exponential backoff cuando vimos el describe.

> **Por qué K8s NO te avisa de la mala indentación:** YAML es un lenguaje permisivo, y la API de K8s acepta campos extra en muchos schemas. Existe un mecanismo (`--validate=strict`) que rechaza campos desconocidos, pero `kubectl apply` por default es laxo (`--validate=warn`) — sólo avisa por stderr y aplica igual. Para detectar este tipo de error en CI: usar `kubectl apply --validate=strict -f pod.yml`.

## Cómo NO confundir env vars con substitution

### Diferentes formas de pasar las mismas 3 vars

#### Forma 1 — Hardcoded (la del lab)

```yaml
env:
  - name: GREETING
    value: "Welcome to"
  - name: COMPANY
    value: "DevOps"
  - name: GROUP
    value: "Ltd"
```

#### Forma 2 — Desde un ConfigMap

```yaml
# Primero crear el CM
kubectl create configmap greeting-config \
  --from-literal=GREETING="Welcome to" \
  --from-literal=COMPANY=DevOps \
  --from-literal=GROUP=Ltd
```

```yaml
# En el pod
env:
  - name: GREETING
    valueFrom:
      configMapKeyRef: { name: greeting-config, key: GREETING }
  - name: COMPANY
    valueFrom:
      configMapKeyRef: { name: greeting-config, key: COMPANY }
  - name: GROUP
    valueFrom:
      configMapKeyRef: { name: greeting-config, key: GROUP }
```

#### Forma 3 — Import masivo con `envFrom`

```yaml
envFrom:
  - configMapRef: { name: greeting-config }
```

K8s toma TODAS las keys del ConfigMap y las inyecta como env vars con el mismo nombre. Más limpio si tenés 5+ vars. Ojo: si dos ConfigMaps tienen la misma key, K8s da un evento `InvalidVariableNames` y skipea las que colisionan.

#### Forma 4 — Downward API (metadata del pod)

```yaml
env:
  - name: MY_POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: MY_POD_IP
    valueFrom:
      fieldRef:
        fieldPath: status.podIP
  - name: MY_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
```

Útil para apps que necesitan saber su propia identidad (logging, distributed tracing).

## Troubleshooting

| Problema                                                                              | Causa y solución                                                                                                                              |
| ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Pod en `CrashLoopBackOff` aunque el container termina con exit 0                      | `restartPolicy` está mal indentado (dentro del container) o no se especificó. Moverlo a `spec.restartPolicy: Never` (o `OnFailure`)            |
| `kubectl logs -f` muestra el output pero el pod queda `Running` y reinicia            | Mismo: `restartPolicy` no es `Never`. Con `Never` el pod queda en `Completed` y no reinicia                                                  |
| `echo "$(GREETING) $(COMPANY)"` imprime literalmente `"$(GREETING) $(COMPANY)"`        | La env var no existe (typo en `name`) o se está usando una sintaxis no soportada. K8s solo expande `$(VAR)`, no `$VAR`                       |
| `kubectl describe pod ... Environment:` está vacío                                    | Bloque `env:` mal indentado (probablemente fuera del container). Verificar con `kubectl get pod <name> -o yaml`                              |
| Necesito una env var con el carácter `$` literal                                      | Escapar con `$$` en el `value`. `value: "price $$10"` → `price $10`                                                                          |
| Quiero referenciar una env var dentro de otra (chained)                               | K8s expande `$(VAR1)` solo si `VAR1` fue declarada **antes** en el mismo `env:`. El orden de la lista importa                                |
| Pod entra `RunContainerError` o `CreateContainerConfigError`                          | La env var referencia un ConfigMap/Secret que no existe. `kubectl describe pod` muestra el detalle en Events                                  |

## Recursos

- [Define Environment Variables for a Container (oficial)](https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/)
- [Dependent Environment Variables / `$(VAR)` substitution (oficial)](https://kubernetes.io/docs/tasks/inject-data-application/define-interdependent-environment-variables/)
- [Distribute Credentials Securely Using Secrets (oficial)](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)
- [Pod restart policy (oficial)](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#restart-policy)
- [Downward API (oficial)](https://kubernetes.io/docs/concepts/workloads/pods/downward-api/)
- [External Secrets Operator](https://external-secrets.io/) — puente a Vault/AWS/GCP/Azure Secrets
