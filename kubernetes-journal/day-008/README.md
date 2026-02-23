# Dia 08 - Crear un CronJob en Kubernetes

## Problema / Desafio

Se necesita crear un CronJob en Kubernetes que ejecute un comando dummy de forma periodica. El CronJob debe llamarse `datacenter`, ejecutarse cada 3 minutos, usar la imagen `httpd:latest` y ejecutar un comando `echo`.

## Conceptos clave

### CronJob

Un CronJob en Kubernetes crea Jobs de forma periodica segun un schedule definido en formato cron. Es util para tareas programadas como backups, limpieza de datos, envio de reportes o cualquier tarea recurrente.

### Estructura de un CronJob

```
CronJob
└── spec.schedule          # Cuando se ejecuta (formato cron)
    └── jobTemplate        # Plantilla del Job que se crea
        └── spec.template  # Plantilla del Pod que ejecuta el Job
```

Un CronJob crea un **Job** en cada ejecucion programada, y cada Job crea un **Pod** que ejecuta la tarea.

### Formato cron

```
┌───────────── minuto (0 - 59)
│ ┌───────────── hora (0 - 23)
│ │ ┌───────────── dia del mes (1 - 31)
│ │ │ ┌───────────── mes (1 - 12)
│ │ │ │ ┌───────────── dia de la semana (0 - 6, domingo = 0)
│ │ │ │ │
* * * * *
```

| Expresion | Significado |
|-----------|-------------|
| `*/3 * * * *` | Cada 3 minutos |
| `0 * * * *` | Cada hora |
| `0 0 * * *` | Cada dia a medianoche |
| `0 0 * * 0` | Cada domingo a medianoche |

### Que es un Job

Un **Job** es un recurso de Kubernetes que ejecuta uno o mas Pods hasta que **completen una tarea** y terminen exitosamente. A diferencia de un Deployment (que mantiene Pods corriendo indefinidamente), un Job esta disenado para ejecutar algo y finalizar.

| | Job | Deployment |
|---|-----|------------|
| Objetivo | Ejecutar y **terminar** | Correr **indefinidamente** |
| Estado final del Pod | `Completed` | `Running` |
| Caso de uso | Tareas puntuales | Servicios/APIs |

Casos de uso tipicos: migraciones de base de datos, procesamiento de archivos, backups, envio de reportes.

**La relacion es:**

```
CronJob  →  crea Jobs automaticamente segun el schedule
Job      →  crea Pods que ejecutan la tarea y terminan
```

Un CronJob es basicamente un Job con un reloj. Si solo necesitas ejecutar algo **una vez**, usas un Job directo. Si necesitas que se repita en un horario, usas un CronJob.

### Flujo de ejecucion de un CronJob

El CronJob **no mantiene un Pod corriendo** permanentemente:

1. El CronJob solo existe como un "scheduler" — espera a que llegue el momento definido en el `schedule`
2. Cuando toca (cada 3 min en este caso), crea un **Job**
3. El Job crea un **Pod** que ejecuta el comando
4. El Pod termina (`Completed`) y queda en estado finalizado
5. En el siguiente ciclo, se crea un **nuevo** Job y Pod

Lo que siempre vas a ver:

```bash
# El CronJob siempre esta visible con su schedule
kubectl get cronjob
```

```
NAME         SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
datacenter   */3 * * * *   False     0        3m              10m
```

```bash
# Los Jobs creados por el CronJob (historial)
kubectl get jobs
```

```
NAME                    COMPLETIONS   DURATION   AGE
datacenter-28456789     1/1           5s         6m
datacenter-28456792     1/1           4s         3m
```

```bash
# Los Pods estaran en estado Completed, no Running
kubectl get pods
```

```
NAME                          READY   STATUS      RESTARTS   AGE
datacenter-28456789-abc12     0/1     Completed   0          6m
datacenter-28456792-def34     0/1     Completed   0          3m
```

El CronJob (schedule) siempre es visible, pero los Pods solo existen brevemente para ejecutar la tarea y luego quedan como `Completed`. Por defecto Kubernetes guarda los ultimos 3 Jobs exitosos y 1 fallido (configurable con `successfulJobsHistoryLimit` y `failedJobsHistoryLimit`).

### restartPolicy en Jobs

En Jobs y CronJobs, `restartPolicy` solo puede ser `OnFailure` o `Never`:

| Politica | Comportamiento |
|----------|---------------|
| `OnFailure` | El contenedor se reinicia en el mismo Pod si falla |
| `Never` | Se crea un nuevo Pod si el contenedor falla |

No se permite `Always` porque los Jobs estan disenados para completarse, no para correr indefinidamente.

## Pasos

1. Crear el manifiesto YAML del CronJob
2. Aplicar el manifiesto con `kubectl apply`
3. Verificar que el CronJob se creo correctamente
4. Esperar a que se ejecute y verificar los Jobs creados

## Comandos / Codigo

### Manifiesto del CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: datacenter
spec:
  schedule: "*/3 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: cron-datacenter
              image: httpd:latest
              args:
                - /bin/sh
                - -c
                - echo "Welcome to xfusioncorp!"
          restartPolicy: OnFailure
```

**Puntos importantes del manifiesto:**

- `restartPolicy` va al nivel de `spec.template.spec`, no dentro del container
- `args` ejecuta el comando usando `/bin/sh -c` para interpretar el `echo`
- El schedule `*/3 * * * *` ejecuta el Job cada 3 minutos

### Aplicar el manifiesto

```bash
kubectl apply -f cronjob-datacenter.yml
```

```
cronjob.batch/datacenter created
```

### Verificar el CronJob

```bash
kubectl get cronjob
```

```
NAME         SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
datacenter   */3 * * * *   False     0        <none>          10s
```

### Verificar los Jobs creados

Despues de esperar al menos 3 minutos:

```bash
kubectl get jobs
```

```
NAME                    COMPLETIONS   DURATION   AGE
datacenter-28456789     1/1           5s         3m
```

### Ver los logs del Pod

```bash
# Obtener el nombre del Pod creado por el Job
kubectl get pods --selector=job-name=datacenter-28456789

# Ver los logs
kubectl logs <nombre-del-pod>
```

```
Welcome to xfusioncorp!
```

### Ver detalle del CronJob

```bash
kubectl describe cronjob datacenter
```

### Crear el CronJob de forma imperativa (alternativa)

```bash
kubectl create cronjob datacenter \
  --image=httpd:latest \
  --schedule="*/3 * * * *" \
  --restart=OnFailure \
  -- /bin/sh -c 'echo "Welcome to xfusioncorp!"'
```

Para generar el YAML sin aplicar (dry-run):

```bash
kubectl create cronjob datacenter \
  --image=httpd:latest \
  --schedule="*/3 * * * *" \
  --restart=OnFailure \
  --dry-run=client -o yaml \
  -- /bin/sh -c 'echo "Welcome to xfusioncorp!"'
```

## Errores comunes en el manifiesto

| Error | Problema | Correccion |
|-------|----------|------------|
| `restartPolicy` dentro del container | Ubicacion incorrecta | Mover a `spec.template.spec` al mismo nivel que `containers` |
| `restartPolicy: Always` | No permitido en Jobs | Usar `OnFailure` o `Never` |
| Schedule sin comillas | YAML puede interpretarlo mal | Siempre poner el schedule entre comillas: `"*/3 * * * *"` |

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| CronJob no crea Jobs | Verificar que el schedule es correcto con `kubectl describe cronjob datacenter`. Revisar que `suspend` no este en `true` |
| Pod en `ImagePullBackOff` | Verificar que la imagen `httpd:latest` es accesible desde el cluster |
| Job falla repetidamente | Revisar logs con `kubectl logs` del Pod. Verificar que el comando es valido |
| Demasiados Jobs acumulados | Configurar `spec.successfulJobsHistoryLimit` y `spec.failedJobsHistoryLimit` para limitar el historial |
| Pod queda en `CrashLoopBackOff` | Si `restartPolicy: OnFailure`, el Pod se reinicia en loop. Verificar que el comando termina correctamente |

## Recursos

- [CronJob - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Running Automated Tasks with a CronJob](https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/)
- [Cron schedule syntax](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/#schedule-syntax)
- [httpd - Docker Hub](https://hub.docker.com/_/httpd)
