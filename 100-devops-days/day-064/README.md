# Día 64 - Troubleshooting de Python Flask App en Kubernetes (dos bugs simultáneos)

## Problema / Desafío

Un ingeniero del equipo desplegó una app Python (Flask) en Kubernetes pero la aplicación **no arranca**. El Deployment y el Service ya están creados; hay que diagnosticar y reparar lo que esté roto. La app debe quedar accesible en el NodePort especificado.

- **Deployment:** `python-deployment-datacenter`, imagen `poroko/flask-demo-app`
- **NodePort esperado:** `32345`
- **targetPort esperado:** puerto default de Flask (`5000`)

El estado inicial muestra dos síntomas claros:

```
NAME                                           READY   STATUS         RESTARTS   AGE
python-deployment-datacenter-65648dc9d-trmx8   0/1     ErrImagePull   0          30s
```

```
NAME                        TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
python-service-datacenter   NodePort    10.43.128.88   <none>        8080:32345/TCP   65s
```

Dos pistas inmediatas: el Pod no puede pullear la imagen (`ErrImagePull`) **y** el Service apunta a `8080` cuando el container expone `5000`.

## Conceptos clave

### Anatomía de un troubleshooting con múltiples bugs

Cuando un sistema falla por **más de una causa simultáneamente**, arreglar una sin la otra **no mejora visiblemente** el resultado — la app sigue rota. El reflejo correcto es:

1. **Listar todos los síntomas antes de tocar nada** (`get pods`, `get svc`, `describe` de cada recurso involucrado)
2. **Mapear cada síntoma a una causa hipotética** (sin asumir que un solo arreglo va a curar todo)
3. **Aplicar fixes uno por uno**, validando después de cada cambio que el síntoma asociado desapareció
4. Si después de un fix no hay mejora visible **pero el síntoma específico desapareció**, no significa que el fix esté mal — puede haber otra causa enmascarándolo

El error típico en este tipo de labs es **fixear el primero, no ver mejora, y empezar a tocar otras cosas al azar**. Eso introduce nuevos bugs y rompe el diagnóstico.

### Las dos causas en este lab

| Síntoma                                                    | Recurso          | Causa real                                                                  |
| ---------------------------------------------------------- | ---------------- | --------------------------------------------------------------------------- |
| `ErrImagePull` en el Pod                                   | Deployment       | Typo en `image`: `poroko/flask-app-demo` ❌ → `poroko/flask-demo-app` ✅     |
| `Endpoints: <none>` + Service responde 502 / no conecta    | Service + Pod    | `port` / `targetPort` del Service en `8080`, pero Flask escucha en `5000`   |

Los dos están **desacoplados** entre sí. El primero impide que el Pod arranque; el segundo impediría que el Service ruteé tráfico correctamente **aunque el Pod estuviera Running**.

### Puerto default de Flask

Cuando una app Flask se inicia con `app.run()` sin argumentos, el server escucha en `127.0.0.1:5000` por default. Eso significa:

- El **container** expone `5000` (`containerPort: 5000`)
- El **Service** debe tener `targetPort: 5000` para redirigir correctamente
- El **port** del Service (cara cluster) puede ser cualquier valor (8080, 80, etc.), pero por convención y simplicidad se suele igualar al targetPort

> **Pitfall sutil**: Si Flask se inicia con `app.run(host='0.0.0.0')` escucha en todas las interfaces (lo que **se necesita** dentro de un container). Si se omite `host`, escucha solo en localhost del container, y el kube-proxy no puede alcanzarlo. La imagen `poroko/flask-demo-app` ya está configurada con `host='0.0.0.0'` — pero es un bug común al hornear apps Flask propias.

### Diferencia entre `port` y `targetPort` en un Service (anclar bien)

| Campo            | Quién lo "habla"                                                              | Ejemplo del lab     |
| ---------------- | ----------------------------------------------------------------------------- | ------------------- |
| `port`           | Lo que ven los **clientes del Service** (otros Pods, vía DNS interno)         | `5000` (debería)    |
| `targetPort`     | Lo que **el container expone** (el `containerPort` del Pod)                   | `5000` (Flask default) |
| `nodePort`       | Lo que el **kube-proxy expone en cada nodo** (solo en `NodePort` / `LoadBalancer`) | `32345`             |

El flujo de un request externo:

```
Cliente → <nodeIP>:32345 (nodePort)
            ↓ kube-proxy
        Service VIP:5000 (port)
            ↓ kube-proxy
        Pod IP:5000 (targetPort = containerPort)
            ↓
        Flask app escuchando en 5000
```

Si **cualquiera** de los tres puertos está mal, el chain se rompe. En este lab el `nodePort` estaba correcto, el `containerPort` estaba correcto (5000), pero `port` y `targetPort` del Service estaban en `8080` — desalineando el chain en el medio.

### Errores típicos al pullear una imagen

| Status                | Significado                                                                              |
| --------------------- | ---------------------------------------------------------------------------------------- |
| `ErrImagePull`        | El pull falló al menos una vez (típicamente porque la imagen no existe en el registry)   |
| `ImagePullBackOff`    | Después de varios reintentos fallidos, el kubelet entra en backoff exponencial            |
| `InvalidImageName`    | El string de la imagen tiene caracteres ilegales (mayúsculas en repo, formato inválido)  |
| `ErrImageNeverPull`   | `imagePullPolicy: Never` y la imagen no existe localmente                                |
| `RegistryUnavailable` | El registry no responde — problema de red o el registry está caído                       |

Para el typo del lab, el status fue `ErrImagePull` porque `poroko/flask-app-demo` **simplemente no existe** en Docker Hub. La imagen real es `poroko/flask-demo-app` (el orden de las palabras).

### Por qué un Service sin endpoints no devuelve "connection refused" sino otra cosa

Cuando el `Endpoints` del Service está vacío (sin Pods que matcheen), el comportamiento depende del cliente:

| Cliente / situación                                         | Respuesta esperada                              |
| ----------------------------------------------------------- | ----------------------------------------------- |
| `curl localhost:<nodePort>` desde el nodo                   | `Connection refused` (no hay regla iptables aún) |
| `curl <serviceName>:<port>` desde otro Pod                  | El connect cuelga hasta timeout                  |
| `curl https://<kodekloud-proxy>:<nodePort>/`                | `502 Bad Gateway` (el proxy externo no obtiene respuesta del cluster) |

El `502` que se vio en este lab antes del fix es el resultado del **proxy externo de KodeKloud** que intenta forwardear al nodePort y no recibe respuesta válida (porque el Service no tiene endpoints).

## Pasos

1. Inspeccionar el estado actual con `kubectl get pods` y `kubectl get svc`
2. Hacer `kubectl describe deployment/python-deployment-datacenter` para ver el `containerPort` y la imagen configurada
3. Hacer `kubectl describe svc python-service-datacenter` para ver `port` / `targetPort` actuales
4. Identificar los **dos** bugs antes de fixear nada
5. Fix 1: corregir `port` y `targetPort` del Service vía `kubectl edit svc` (de 8080 → 5000)
6. Fix 2: corregir el nombre de la imagen del Deployment vía `kubectl edit deploy` (`poroko/flask-app-demo` → `poroko/flask-demo-app`)
7. Esperar a que el Pod nuevo del rolling update arranque en `Running`
8. Validar con `curl` al NodePort que devuelve `200 OK`

## Comandos / Código

### Diagnóstico inicial

```bash
kubectl get pods
```

```
NAME                                           READY   STATUS         RESTARTS   AGE
python-deployment-datacenter-65648dc9d-trmx8   0/1     ErrImagePull   0          30s
```

```bash
kubectl get svc
```

```
NAME                        TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
python-service-datacenter   NodePort    10.43.128.88   <none>        8080:32345/TCP   65s
```

> Dos pistas en dos comandos: `ErrImagePull` (bug 1) y `8080` cuando esperaríamos `5000` (bug 2).

```bash
kubectl describe deployment/python-deployment-datacenter
```

Bloque relevante:

```
Pod Template:
  Labels:  app=python_app
  Containers:
   python-container-datacenter:
    Image:         poroko/flask-app-demo        ← TYPO (debería ser poroko/flask-demo-app)
    Port:          5000/TCP                     ← OK, este es el containerPort correcto
```

```bash
kubectl describe svc python-service-datacenter
```

```
Selector:                 app=python_app
Type:                     NodePort
Port:                     <unset>  8080/TCP     ← MAL (debería ser 5000)
TargetPort:               8080/TCP              ← MAL (debería ser 5000, el containerPort del Pod)
NodePort:                 <unset>  32345/TCP    ← OK
Endpoints:                                       ← VACÍO (no hay Pods Running con el label correcto)
```

> El `Endpoints` vacío es **consecuencia** del Pod no arrancar — no es un bug independiente del label. El selector `app=python_app` matchearía bien al Pod si éste estuviera `Running`.

### Fix 1 — corregir port y targetPort del Service

```bash
kubectl edit svc python-service-datacenter
```

Cambiar las dos líneas:

```yaml
  ports:
  - nodePort: 32345
    port: 5000          # antes: 8080
    protocol: TCP
    targetPort: 5000    # antes: 8080
```

```
service/python-service-datacenter edited
```

Verificar:

```bash
kubectl describe svc python-service-datacenter
```

```
Port:                     <unset>  5000/TCP
TargetPort:               5000/TCP
NodePort:                 <unset>  32345/TCP
Endpoints:                                      ← sigue vacío (el Pod aún no arranca por el bug 2)
```

### Fix 2 — corregir el typo en el nombre de la imagen

```bash
kubectl edit deployment/python-deployment-datacenter
```

Cambiar la línea del `image`:

```yaml
spec:
  containers:
    - name: python-container-datacenter
      image: poroko/flask-demo-app   # antes: poroko/flask-app-demo
```

Al guardar, el Deployment dispara un **rolling update** (RS nuevo, Pod nuevo):

```bash
kubectl get pods -o wide
```

```
NAME                                            READY   STATUS    RESTARTS   AGE   IP           NODE        NOMINATED NODE   READINESS GATES
python-deployment-datacenter-57d654488b-x2bx7   1/1     Running   0          9s    10.22.0.11   jump-host   <none>           <none>
```

> Notar que el `pod-template-hash` cambió (de `65648dc9d` a `57d654488b`) — confirmación de que el rolling update creó un Pod nuevo con la spec corregida, no que reusó el viejo.

### Validación

```bash
kubectl describe svc python-service-datacenter
```

```
Endpoints:                10.22.0.11:5000     ← ahora poblado
```

```bash
curl -I https://32345-port-lg22xwbfiqa2g2wc.labs.kodekloud.com/
```

```
HTTP/2 200
content-type: text/html; charset=utf-8
content-length: 19
```

App accesible ✅.

### Alternativa — fix declarativo (preferible en producción)

`kubectl edit` es cómodo para labs pero **no deja rastro** del cambio. En un entorno con GitOps, el fix sería:

1. Editar el manifest local (`deployment.yml`, `service.yml`)
2. `kubectl apply -f deployment.yml -f service.yml`
3. Commit del fix al repo, así queda auditado

Otra opción es `kubectl set image`:

```bash
kubectl set image deployment/python-deployment-datacenter \
  python-container-datacenter=poroko/flask-demo-app
```

Para Services no hay `kubectl set port` — la edición debe pasar por `edit`, `patch`, o `apply` con manifest actualizado:

```bash
kubectl patch svc python-service-datacenter --type='json' -p='[
  {"op": "replace", "path": "/spec/ports/0/port", "value": 5000},
  {"op": "replace", "path": "/spec/ports/0/targetPort", "value": 5000}
]'
```

## Conexión con días anteriores

- **Día 59 (troubleshooting con typo en image + ConfigMap)**: patrón **idéntico** — dos bugs independientes que requieren dos fixes. La lección de Día 59 ("listar todos los síntomas antes de fixear") se vuelve a aplicar acá.
- **Día 53 (volumeMount mal alineado)**: misma clase de bug — un valor (path, puerto, nombre) que está bien por separado en cada recurso pero **desalineado entre ellos**. El fix requiere mirar la relación, no el recurso aislado.
- **Día 56 (Deployment + NodePort)**: introdujo `port` / `targetPort` / `nodePort`. Hoy fue la primera vez que el lab los pone como **bug a diagnosticar**, no solo a configurar.
- **Día 58 (autopsia de labels)**: la regla "verificar que el selector del Service matchea los labels del Pod" sigue válida — pero hoy el selector estaba bien, el bug era ortogonal (en los puertos y la imagen). La lección: no asumir cuál de los 4 puntos de la cadena está roto sin mirar.
- **Día 63 (stack multi-componente)**: refuerza la misma idea de la cadena `Service → Pod` via labels + ports. Acá vimos lo que pasa cuando la cadena se rompe en dos eslabones a la vez.

## Reflexión: troubleshooting bajo síntomas que se enmascaran

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- La trampa cognitiva de tener dos bugs simultáneos: cuando arreglás el primero y "nada cambia", la tentación es deshacerlo y probar otra cosa. ¿Te pasó? ¿Cómo lo manejaste?
- Tu workflow habitual al debuggear K8s — ¿cuál es tu primer comando? (kubectl get pods, kubectl describe, kubectl logs, kubectl get events)
- El balance entre kubectl edit (rápido, sin auditoría) y editar el YAML + apply (más lento, queda registrado). ¿En qué contextos elegís cuál?
- Si comparás este lab con el Día 59 (otro troubleshooting de dos bugs), ¿qué te resulta más familiar ya — qué patrones empezás a reconocer al primer vistazo?
2-10 líneas, tono directo, primera persona implícita como en Día 61, 62 y 63. -->

## Troubleshooting

| Problema                                                          | Causa                                                                                            | Solución                                                                                          |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `ErrImagePull` persistente                                        | Typo en el nombre de la imagen (caso de este lab) o registry privado sin `imagePullSecrets`     | `kubectl describe pod <name>` y leer el evento exacto: dice si es `manifest unknown` (typo) o `unauthorized` (auth) |
| `kubectl logs <pod>` devuelve `container is waiting to start: trying and failing to pull image` | El container nunca arrancó, no hay logs para mostrar                                             | Es esperable. Los logs aparecen recién cuando el container arranca. Mirar `describe` en su lugar  |
| Service muestra `Endpoints: <none>` y el Pod **sí está Running** | El selector del Service no matchea los labels del Pod                                            | Comparar `service.spec.selector` con `pod.metadata.labels` (case-sensitive)                       |
| Service muestra `Endpoints: <none>` y el Pod **no está Running**  | Es consecuencia, no causa — fixear el Pod primero                                                | Resolver por qué el Pod no arranca; el Endpoints se poblará automáticamente cuando entre Ready    |
| Después de arreglar el image, el Pod viejo sigue en `ErrImagePull` | El RS viejo no se borra inmediatamente — convive con el RS nuevo durante el rolling update      | Esperar a que el rolling termine. El Pod viejo será borrado cuando el nuevo entre Ready           |
| `curl` al nodePort devuelve `502 Bad Gateway` (vía proxy externo) | El Service no tiene endpoints (Pods no Running o selector roto)                                  | Validar endpoints primero: `kubectl get endpoints <svc>`                                          |
| `curl localhost:<nodePort>` devuelve `Connection refused`         | Estás en un nodo donde no hay regla iptables porque el Service aún no tiene endpoints           | Mismo fix: poblar endpoints. O probar desde otro nodo / curl al ClusterIP                          |
| El targetPort no matchea ningún puerto del container              | El container expone `5000` pero el Service apunta a `8080`                                       | `kubectl describe deploy` muestra el `Port:` del container — alinear el `targetPort` del Service  |
| Flask escucha solo en `127.0.0.1` dentro del container            | La app llama a `app.run()` sin `host='0.0.0.0'` — escucha solo en localhost del container        | Modificar el código de la app o pasar `--host 0.0.0.0` por env / args. No es fix de K8s            |
| `kubectl edit` no aplica el cambio                                | Error de YAML al guardar (indentación mal, comilla no cerrada). El editor sale sin error pero el cambio se descarta | Revisar el output de `kubectl edit` — suele dar el error de validación. Reabrir y corregir       |
| El cambio de `kubectl edit` desaparece al rato                    | Hay un controller (ArgoCD, Flux, FluxCD) reconciliando contra el repo                            | El fix debe hacerse en el repo de manifests, no con `edit`. `edit` será sobrescrito                |

## Recursos

- [Kubectl Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Image Pull Policy and Errors](https://kubernetes.io/docs/concepts/containers/images/#image-pull-policy)
- [Service `port` vs `targetPort` vs `nodePort`](https://kubernetes.io/docs/concepts/services-networking/service/#field-spec-ports)
- [Flask quickstart — `app.run()` defaults](https://flask.palletsprojects.com/en/latest/quickstart/)
- [kubectl edit vs declarative apply](https://kubernetes.io/docs/concepts/cluster-administration/manage-deployment/)
