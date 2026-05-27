# Día 58 - Deployment + Service NodePort para Grafana — autopsia de labels y selectors

## Problema / Desafío

El equipo de Nautilus quiere instalar Grafana en el cluster para análisis de telemetría. Lo deployamos con:

- **Deployment:** `grafana-deployment-datacenter`, imagen oficial `grafana/grafana`
- **Service:** tipo `NodePort` con `nodePort: 32000`
- **Validación:** la página de login de Grafana debe responder por el NodePort

El ejercicio no introduce conceptos nuevos respecto al Día 56, así que el foco del día es **entender exactamente qué hace cada bloque de labels/selectors** en el manifest — el punto que más confunde al principio.

## Conceptos clave

### Los 4 lugares donde aparecen labels (y por qué no son lo mismo)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana-deployment-datacenter
  labels:                                       # ① labels del objeto Deployment (decorativo)
    app: grafana-deployment-datacenter
spec:
  replicas: 1
  selector:                                     # ② matching rule del ReplicaSet (CRÍTICO)
    matchLabels:
      app: grafana-deployment-datacenter
  template:
    metadata:
      labels:                                   # ③ labels que se ESTAMPAN en los pods creados
        app: grafana-deployment-datacenter
    spec:
      containers:
        - name: grafana
          image: grafana/grafana
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-deployment-svc
spec:
  selector:                                     # ④ matching rule para construir endpoints
    app: grafana-deployment-datacenter
  ...
```

Aunque las 4 ocurrencias usan el mismo valor `app: grafana-deployment-datacenter`, **tienen roles completamente distintos**:

| # | Dónde                                      | Rol                                                                      | Lo usa quién                                                                  |
| - | ------------------------------------------ | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| ① | `Deployment.metadata.labels`               | **Decora** al objeto Deployment en sí                                    | `kubectl get deployments -l app=X` para filtrar deployments. **No afecta** a pods |
| ② | `Deployment.spec.selector.matchLabels`     | Regla con la que el **ReplicaSet** reconoce sus pods                     | El RS controller — busca pods con estos labels y los considera "suyos"        |
| ③ | `Deployment.spec.template.metadata.labels` | **Estampa** estos labels en cada pod que el RS crea                       | kubelet — al crear el pod le pone estas labels en su `metadata`               |
| ④ | `Service.spec.selector`                    | Regla con la que el **Service** elige qué pods incluir en sus endpoints  | El endpoints controller — busca pods con estos labels y arma la lista          |

### Por qué (②) y (③) deben coincidir — la condición OBLIGATORIA

Esta es la única coincidencia **forzosa por el API server**:

- El Deployment crea un ReplicaSet con `selector = ②`
- El RS crea pods con `labels = ③`
- El RS busca sus pods filtrando con `selector = ②`
- **Si ② y ③ no coinciden**, el RS crea pods, no los reconoce como suyos (porque no matchean su selector), y vuelve a crear más → loop infinito

Por eso desde K8s 1.16 el API server **valida al deploy** que `selector.matchLabels` ⊆ `template.metadata.labels`. Si no coinciden:

```
The Deployment "..." is invalid: spec.template.metadata.labels: Invalid value: ...
selector does not match template labels
```

Más aún, `spec.selector` es **inmutable** después de creado. Para cambiar el selector, hay que borrar el Deployment entero y recrearlo.

### Por qué (③) y (④) coinciden — por **convención**, no obligación

El Service usa `selector = ④` para construir su lista de endpoints. Para que el Service envíe tráfico a estos pods, sus labels (③) deben matchear los del selector (④).

Pero **no es obligatorio que sean iguales**: se pueden diseñar pods con MÁS labels que los que el Service matchea, y el Service igualmente los incluiría. Por ejemplo:

```yaml
# Pods tienen 3 labels
template:
  metadata:
    labels:
      app: grafana-deployment-datacenter
      tier: monitoring
      env: prod

# Service solo matchea por uno — incluye igual los pods
Service:
  selector:
    tier: monitoring   # ← matchea cualquier pod con este label, no importa los demás
```

Esto es útil para crear Services "multi-deployment" — un Service que envía tráfico a pods de varios Deployments distintos que comparten un label común.

### Por qué (①) está y para qué sirve

`metadata.labels` del **Deployment en sí mismo** (no del template) es **puramente decorativo**. No afecta a pods ni a ReplicaSets — solo le pone labels al objeto Deployment para que lo encuentres con queries:

```bash
kubectl get deployments -l app=grafana-deployment-datacenter
kubectl get deployments -l env=prod,tier=monitoring
```

Al omitirlo, el Deployment funciona igual — solo no aparecerá en queries por label. Por convención se le ponen los mismos labels que al template para consistencia, pero técnicamente podría tener labels completamente distintos:

```yaml
metadata:
  name: grafana-deployment-datacenter
  labels:                          # solo decorativo
    purpose: graphing
    cost-center: platform-team
spec:
  selector:
    matchLabels:
      app: grafana                 # ← lo que importa para matchear pods
  template:
    metadata:
      labels:
        app: grafana               # ← lo que matchea el selector de arriba
```

### `matchLabels` vs `matchExpressions`

Hay **dos formas** de escribir un selector en K8s:

```yaml
# Forma simple (igualdad estricta, AND entre las keys)
selector:
  matchLabels:
    app: grafana
    tier: monitoring

# Forma avanzada (operadores set-based)
selector:
  matchExpressions:
    - { key: app, operator: In, values: [grafana, prometheus] }
    - { key: tier, operator: NotIn, values: [dev] }
    - { key: env, operator: Exists }
```

| Operador        | Significado                                          |
| --------------- | ---------------------------------------------------- |
| `In`            | El valor del label está en la lista                  |
| `NotIn`         | El valor del label NO está en la lista               |
| `Exists`        | El label existe (cualquier valor)                    |
| `DoesNotExist`  | El label NO existe                                   |

Las dos formas son combinables — al usar las dos en el mismo selector, K8s las evalúa con AND.

> **Una limitación clave:** `spec.selector` de un **Service** solo acepta `matchLabels`-style (igualdad), NO `matchExpressions`. Por eso en la práctica casi siempre usamos `matchLabels` (es lo más compatible). Para un Service con selectores complejos, hay que crear un Service "headless" + EndpointSlices manuales.

### ¿Y si NO uso labels? — Las alternativas

Para conectar **pods a pods** o **pods al Service**, la respuesta corta es "no hay alternativa razonable". Pero hay matices según el caso:

#### Caso 1: Deployment → Pods

**No hay alternativa**. El RS controller está hardcodeado para usar labels. No se puede cambiar. Para un agrupamiento sin labels, no es un Deployment — es un Pod stand-alone.

#### Caso 2: Service → Pods

Hay **2 alternativas** al selector por labels:

##### a) Service "manual" sin selector + Endpoints/EndpointSlice manual

```yaml
# Service sin selector — K8s no construye endpoints automáticamente
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  ports:
    - port: 5432
      targetPort: 5432
# (sin selector:)
---
# Endpoints manual — las IPs y puertos se definen a mano
apiVersion: v1
kind: Endpoints
metadata:
  name: external-db   # ← mismo nombre que el Service
subsets:
  - addresses:
      - { ip: 10.0.0.50 }
      - { ip: 10.0.0.51 }
    ports:
      - { port: 5432 }
```

Esto es útil cuando los "endpoints" **no son pods de K8s**: una DB Postgres corriendo en una VPC distinta, un mainframe legacy, un servicio en otro datacenter. K8s no puede labelear esas máquinas — entonces los endpoints se declaran a mano.

##### b) Service tipo `ExternalName`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: github-api
spec:
  type: ExternalName
  externalName: api.github.com
```

Crea un CNAME en el DNS del cluster: `github-api.default.svc.cluster.local` → `api.github.com`. No usa labels, no tiene endpoints — es un alias DNS puro. Útil para apuntar a servicios externos por su nombre lógico (y poder cambiar el destino sin re-deployar la app).

## Pasos

1. Escribir el manifest con Deployment + Service en el mismo YAML (separados por `---`)
2. `kubectl apply -f`
3. `describe deployment` → confirmar que el RS arrancó con 1 replica
4. `describe service` → confirmar que `Endpoints:` tiene la IP del pod
5. `curl localhost:32000` → debe redirigir a `/login` (Grafana redirige sin sesión)

## Comandos / Código

### Manifest completo

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana-deployment-datacenter
  labels:
    app: grafana-deployment-datacenter         # ① decorativo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana-deployment-datacenter       # ② matching rule del RS
  template:
    metadata:
      labels:
        app: grafana-deployment-datacenter     # ③ labels estampadas en pods
    spec:
      containers:
        - name: grafana
          image: grafana/grafana
          ports:
            - containerPort: 3000              # informacional — Grafana escucha en 3000

---

apiVersion: v1
kind: Service
metadata:
  name: grafana-deployment-svc
spec:
  type: NodePort
  selector:
    app: grafana-deployment-datacenter         # ④ matching rule para endpoints
  ports:
    - port: 3000
      targetPort: 3000
      nodePort: 32000
```

> **Por qué `containerPort: 3000`**: Grafana escucha en el puerto 3000 por default (ver [docs](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#http_port)). El campo `containerPort` en sí es informacional — kubelet no abre el puerto basándose en él — pero documenta y sirve a herramientas tipo `kubectl describe`.

### Aplicar

```bash
kubectl apply -f deployment.yml
```

```
deployment.apps/grafana-deployment-datacenter created
service/grafana-deployment-svc created
```

### Confirmar el Deployment

```bash
kubectl describe deployment/grafana-deployment-datacenter
```

```
Name:                   grafana-deployment-datacenter
Labels:                 app=grafana-deployment-datacenter           ← (①)
Annotations:            deployment.kubernetes.io/revision: 1
Selector:               app=grafana-deployment-datacenter           ← (②)
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
Pod Template:
  Labels:  app=grafana-deployment-datacenter                        ← (③)
  Containers:
   grafana:
    Image:         grafana/grafana
    Port:          3000/TCP
NewReplicaSet:   grafana-deployment-datacenter-b9d47789c (1/1 replicas created)
Events:
  Normal  ScalingReplicaSet  28s  deployment-controller  Scaled up replica set grafana-deployment-datacenter-b9d47789c from 0 to 1
```

Las 3 ocurrencias de `app=grafana-deployment-datacenter` confirman los puntos ①, ②, ③ del esquema teórico.

### Confirmar el Service y sus endpoints

```bash
kubectl describe service/grafana-deployment-svc
```

```
Name:                     grafana-deployment-svc
Selector:                 app=grafana-deployment-datacenter        ← (④)
Type:                     NodePort
IP:                       10.43.182.147
Port:                     <unset>  3000/TCP
TargetPort:               3000/TCP
NodePort:                 <unset>  32000/TCP
Endpoints:                10.22.0.10:3000                           ← matchó el pod
Session Affinity:         None
External Traffic Policy:  Cluster
```

Lectura crítica:

- **`Selector: app=grafana-deployment-datacenter`** es ④. El Service va a buscar pods con este label.
- **`Endpoints: 10.22.0.10:3000`** es la prueba de que ④ matchea ③ — encontró el pod (IP `10.22.0.10`) y armó el endpoint. Si esa línea estuviera vacía, sabríamos que el selector no matchea.
- **`IP: 10.43.182.147`** es la ClusterIP (estable). `NodePort: 32000` es el puerto expuesto en cada nodo.

### Validar acceso

```bash
curl localhost:32000
```

```
<a href="/login">Found</a>.
```

```bash
curl -I localhost:32000
```

```
HTTP/1.1 302 Found
Cache-Control: no-store
Content-Type: text/html; charset=utf-8
Location: /login
X-Content-Type-Options: nosniff
X-Frame-Options: deny
X-Xss-Protection: 1; mode=block
Date: Mon, 18 May 2026 01:37:55 GMT
```

El `302 Found` con `Location: /login` es **exactamente** lo esperado: Grafana detecta que no hay sesión activa y redirige al login. Esa redirección es el "OK" del lab — la app está viva y respondiendo.

> **Detalle de seguridad de Grafana visible en headers:** `X-Frame-Options: deny`, `X-Content-Type-Options: nosniff`, `X-Xss-Protection: 1; mode=block`. Grafana viene "seguro por default" — clickjacking protection, MIME sniffing off, XSS filter on. Buen ejemplo de app productiva.

## Test extra: verificar el matching pod ↔ Service

Una forma directa de ver el matching es listar los pods con el label que el Service busca:

```bash
kubectl get pods -l app=grafana-deployment-datacenter
```

```
NAME                                            READY   STATUS    RESTARTS   AGE
grafana-deployment-datacenter-b9d47789c-xxxxx   1/1     Running   0          5m
```

Si la lista está vacía, el selector del Service tampoco tendría endpoints. Es el "qué pasaría si el Service fuera kubectl".

## Cambiando los labels — ¿qué se rompe?

Para internalizar el rol de cada label, vale considerar qué pasa al cambiarlos:

| Cambio                                                                | Consecuencia                                                                                  |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Cambiar ① (`Deployment.metadata.labels`)                              | Nada operativo. Solo afecta `kubectl get deployments -l`                                      |
| Cambiar ② (`spec.selector.matchLabels`) post-creación                 | **K8s lo rechaza** — el selector es inmutable                                                 |
| Cambiar ③ (`template.metadata.labels`) sin cambiar ②                  | API server rechaza el update (validation `selector does not match template labels`)           |
| Cambiar ③ Y ② juntos                                                  | Aún así, ② es inmutable → rechazado. Hay que borrar el Deployment entero                      |
| Cambiar ④ (`Service.spec.selector`)                                   | El Service deja de incluir los pods viejos. Si nadie tiene el label nuevo → `Endpoints: <none>` y el Service responde con timeout |
| Agregar un label más en ③ sin cambiar ②                               | OK, los pods quedan con más labels — el selector ② sigue matcheando porque es subset           |

## Troubleshooting

| Problema                                                                    | Causa y solución                                                                                                                              |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `kubectl apply` rechaza el manifest con `selector does not match template labels` | El `selector.matchLabels` no es subset del `template.metadata.labels`. Asegurarse que ② ⊆ ③                                              |
| El Service responde timeout, `Endpoints:` está vacío                       | El `selector` del Service (④) no matchea los pods. Verificar con `kubectl get pods -l <selector>` que devuelva al menos un pod              |
| El Deployment crea pods en loop, miles de pods aparecen                    | ② no matchea ③ (pero K8s 1.16+ debería rechazarlo). En clusters viejos podía ocurrir — el RS no reconoce los pods que él mismo crea         |
| Cambié el `selector` y quiero aplicar — rechazo                            | El selector es inmutable. Solución: `kubectl delete deployment <name>` y recrear con el nuevo selector                                       |
| Cambié las labels del template, pods nuevos no aparecen en el Service       | El Service selecciona por el label viejo. Actualizar también `Service.spec.selector`                                                          |
| Grafana responde pero no llego al login                                     | El pod no terminó de arrancar (Grafana tarda ~5-10s en estar listo). `kubectl logs <pod>` para ver si está listo                            |
| Puerto 32000 ya en uso                                                      | Otro Service tomó ese NodePort. Cambiar a otro en rango 30000-32767 o dejar `nodePort` sin especificar para asignación automática            |

## Recursos

- [Labels and Selectors (oficial)](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Deployment spec — selector immutability](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#selector)
- [Service without selectors (alternativa a labels)](https://kubernetes.io/docs/concepts/services-networking/service/#services-without-selectors)
- [Service type ExternalName](https://kubernetes.io/docs/concepts/services-networking/service/#externalname)
- [Grafana official Docker image](https://hub.docker.com/r/grafana/grafana)
- [Grafana — HTTP server config](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#http_port)
