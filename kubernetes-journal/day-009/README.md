# Dia 09 - Crear un Job Countdown en Kubernetes

## Problema / Desafio

Crear un Job en Kubernetes llamado `countdown-devops` que ejecute un contenedor con Ubuntu y realice un `sleep 5` antes de finalizar. A diferencia de un CronJob (dia 08), un Job se ejecuta una sola vez y termina.

## Conceptos clave

### Job vs CronJob

| | Job | CronJob |
|---|-----|---------|
| Ejecucion | **Una sola vez** | Periodica segun schedule |
| Caso de uso | Tarea puntual | Tarea recurrente |
| Se completa | Cuando el Pod termina exitosamente | Nunca (sigue creando Jobs) |

Un Job es el recurso base. Un CronJob simplemente automatiza la creacion de Jobs segun un horario.

### restartPolicy en Jobs

En un Job, `restartPolicy` solo acepta `OnFailure` o `Never`:

| Politica | Comportamiento |
|----------|---------------|
| `Never` | Si el contenedor falla, se crea un **nuevo Pod** (no se reinicia el existente) |
| `OnFailure` | El contenedor se reinicia **dentro del mismo Pod** si falla |

Para este ejercicio usamos `Never`: si el comando falla, Kubernetes no reintenta en el mismo Pod.

### Ciclo de vida de un Job

1. Se crea el Job con `kubectl apply` o `kubectl create`
2. El Job crea un Pod que ejecuta el comando definido
3. El Pod corre el comando (`sleep 5` en este caso)
4. Al completarse, el Pod pasa a estado `Completed`
5. El Job registra `1/1 COMPLETIONS`

### Configuraciones importantes para produccion

#### backoffLimit

Controla cuantas veces Kubernetes reintenta un Job fallido antes de marcarlo como `Failed`:

```yaml
spec:
  backoffLimit: 4   # Maximo 4 reintentos (default: 6)
```

Kubernetes aplica backoff exponencial entre reintentos: 10s, 20s, 40s, etc.

#### activeDeadlineSeconds

Establece un timeout maximo para el Job. Si no termina en ese tiempo, Kubernetes lo mata:

```yaml
spec:
  activeDeadlineSeconds: 120  # Timeout de 2 minutos
```

- Tiene prioridad sobre `backoffLimit` — si se alcanza el deadline, el Job se detiene sin importar cuantos reintentos quedan
- Util para evitar Jobs que se quedan colgados indefinidamente

#### ttlSecondsAfterFinished

Limpia automaticamente el Job y sus Pods despues de completarse o fallar:

```yaml
spec:
  ttlSecondsAfterFinished: 60  # Se borra 60s despues de terminar
```

- Sin esto, los Jobs en estado `Completed` se acumulan y hay que borrarlos manualmente con `kubectl delete job`
- Aplica tanto a Jobs exitosos como fallidos

#### completions y parallelism

Permiten ejecutar multiples Pods como parte del mismo Job:

```yaml
spec:
  completions: 5    # Necesita 5 Pods exitosos para completarse
  parallelism: 2    # Ejecuta 2 Pods en simultaneo
```

- Por defecto ambos son `1` (un solo Pod, secuencial)
- Util para procesar lotes de trabajo en paralelo
- Con `completions: 5` y `parallelism: 2`, Kubernetes ejecuta 2 Pods a la vez hasta alcanzar 5 completados

#### suspend

Permite crear un Job sin ejecutarlo inmediatamente:

```yaml
spec:
  suspend: true   # Crea el Job pero no lo ejecuta
```

```bash
# Suspender un Job activo
kubectl patch job countdown-devops -p '{"spec":{"suspend":true}}'

# Reanudar
kubectl patch job countdown-devops -p '{"spec":{"suspend":false}}'
```

#### Ejemplo completo con todas las configuraciones

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: countdown-devops
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 60
  ttlSecondsAfterFinished: 120
  template:
    metadata:
      name: countdown-devops
    spec:
      containers:
        - name: container-countdown-devops
          image: ubuntu:latest
          command: ["sleep", "5"]
      restartPolicy: Never
```

## Pasos

1. Crear el manifiesto YAML del Job
2. Aplicar el manifiesto con `kubectl apply`
3. Verificar que el Job y el Pod se crearon correctamente
4. Esperar a que el Pod termine y validar el estado `Completed`

## Comandos / Codigo

### Manifiesto del Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: countdown-devops
spec:
  template:
    metadata:
      name: countdown-devops
    spec:
      containers:
        - name: container-countdown-devops
          image: ubuntu:latest
          command: ["sleep", "5"]
      restartPolicy: Never
```

**Puntos importantes del manifiesto:**

- `apiVersion: batch/v1` — los Jobs pertenecen al grupo `batch`, no a `apps` ni al core
- `command` ejecuta directamente el binario `sleep` con argumento `5`
- `restartPolicy: Never` va a nivel de `spec.template.spec`, al mismo nivel que `containers`
- A diferencia de un CronJob, no hay `jobTemplate` ni `schedule` — el Job se ejecuta inmediatamente

### Estructura del manifiesto explicada

```
Job
└── metadata.name: countdown-devops        # Nombre del Job
    └── spec.template                      # Plantilla del Pod
        ├── metadata.name: countdown-devops # Nombre del Pod template
        └── spec
            ├── containers
            │   └── container-countdown-devops  # Nombre del contenedor
            │       ├── image: ubuntu:latest
            │       └── command: ["sleep", "5"]
            └── restartPolicy: Never
```

### Aplicar el manifiesto

```bash
kubectl apply -f job-countdown-devops.yml
```

```
job.batch/countdown-devops created
```

### Verificar el Job

```bash
kubectl get jobs
```

```
NAME               COMPLETIONS   DURATION   AGE
countdown-devops   0/1           5s         5s
```

Despues de ~5 segundos:

```
NAME               COMPLETIONS   DURATION   AGE
countdown-devops   1/1           7s         10s
```

### Verificar el Pod

```bash
kubectl get pods
```

```
NAME                     READY   STATUS      RESTARTS   AGE
countdown-devops-abc12   0/1     Completed   0          15s
```

El estado `Completed` indica que el comando `sleep 5` termino exitosamente.

### Ver detalle del Job

```bash
kubectl describe job countdown-devops
```

### Inspeccionar Jobs fallidos

```bash
# Ver por que fallo
kubectl describe job countdown-devops

# Ver logs del Pod que fallo
kubectl logs job/countdown-devops

# Ver todos los Pods del Job (incluyendo fallidos)
kubectl get pods --selector=job-name=countdown-devops
```

### Crear el Job de forma imperativa (alternativa)

```bash
kubectl create job countdown-devops \
  --image=ubuntu:latest \
  --restart=Never \
  -- sleep 5
```

Para generar el YAML sin aplicar (dry-run):

```bash
kubectl create job countdown-devops \
  --image=ubuntu:latest \
  --restart=Never \
  --dry-run=client -o yaml \
  -- sleep 5
```

**Nota:** el metodo imperativo no permite definir `metadata.name` en el template del Pod. Para eso se necesita el manifiesto YAML declarativo.

### Diferencia entre `command` y `args`

| Campo | Equivalente en Docker | Uso |
|-------|----------------------|-----|
| `command` | `ENTRYPOINT` | Sobreescribe el punto de entrada del contenedor |
| `args` | `CMD` | Argumentos que se pasan al `command` o al ENTRYPOINT por defecto |

En este caso usamos `command: ["sleep", "5"]` que ejecuta directamente el binario. Alternativa equivalente:

```yaml
command: ["/bin/sh", "-c", "sleep 5"]
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| Pod en `ErrImagePull` o `ImagePullBackOff` | Verificar que la imagen `ubuntu:latest` es accesible desde el cluster. En clusters sin acceso a internet, usar un registry interno |
| Pod queda en `Error` | Revisar logs con `kubectl logs <pod-name>`. Verificar que el comando es valido |
| Job no aparece en `kubectl get jobs` | Verificar que el `apiVersion` es `batch/v1` y el `kind` es `Job` |
| `restartPolicy: Always` causa error | En Jobs solo se permite `Never` o `OnFailure` |
| Pod se crea pero nunca completa | Verificar que el comando termina. Un `sleep` sin argumento o un proceso infinito no completara |

## Recursos

- [Jobs - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Running Automated Tasks with a CronJob](https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/)
- [ubuntu - Docker Hub](https://hub.docker.com/_/ubuntu)
