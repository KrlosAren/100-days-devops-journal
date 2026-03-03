# Dia 12 - Actualizar Deployment y Service en Kubernetes sin eliminarlos

## Problema / Desafio

Una aplicacion desplegada en Kubernetes necesita actualizaciones. Ya existe un Deployment `nginx-deployment` y un Service `nginx-service`. Se deben hacer los siguientes cambios **sin eliminar** el Deployment ni el Service:

1. Cambiar el NodePort del Service de **30008** a **32165**
2. Cambiar las replicas del Deployment de **1** a **5**
3. Actualizar la imagen de **nginx:1.17** a **nginx:latest**

## Conceptos clave

### Editar recursos en caliente

Kubernetes permite modificar recursos que ya estan corriendo sin necesidad de eliminarlos y recrearlos. Esto es fundamental en produccion donde no se puede tener downtime.

### NodePort

Un Service de tipo `NodePort` expone un puerto en todos los nodos del cluster, permitiendo acceso externo:

```
Cliente → Nodo:NodePort → Service:Port → Pod:TargetPort
Cliente → Nodo:32165    → Service:80   → Pod:80
```

El rango valido de NodePort es **30000-32767**.

### Rolling Update

Cuando se cambia la imagen de un Deployment, Kubernetes hace un **rolling update**: crea Pods nuevos con la imagen actualizada y elimina los viejos progresivamente, manteniendo la aplicacion disponible durante todo el proceso.

```
Antes:  [Pod nginx:1.17] [Pod nginx:1.17] [Pod nginx:1.17]
         ↓ nuevo          ↓ nuevo          ↓ nuevo
Despues: [Pod nginx:latest] [Pod nginx:latest] [Pod nginx:latest]
```

## Pasos

1. Verificar el estado actual del Deployment, Service y Pods
2. Editar el Service para cambiar el NodePort
3. Editar el Deployment para cambiar replicas e imagen
4. Verificar que todos los cambios se aplicaron correctamente

## Comandos / Codigo

### 1. Verificar el estado actual

```bash
kubectl get svc
```

```
NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
kubernetes      ClusterIP   10.96.0.1      <none>        443/TCP        6m19s
nginx-service   NodePort    10.96.254.53   <none>        80:30008/TCP   51s
```

El Service tiene NodePort **30008** — necesita cambiar a **32165**.

```bash
kubectl get deployment
```

```
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deployment   1/1     1            1           73s
```

El Deployment tiene **1** replica — necesita cambiar a **5**.

```bash
kubectl get pods
```

```
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-5dd558cf95-sp5sq   1/1     Running   0          78s
```

Solo 1 Pod corriendo.

### 2. Editar el Service — cambiar NodePort

```bash
kubectl edit svc nginx-service
```

Buscar la seccion `ports` y cambiar el `nodePort`:

```yaml
# Antes
ports:
  - nodePort: 30008
    port: 80
    targetPort: 80

# Despues
ports:
  - nodePort: 32165
    port: 80
    targetPort: 80
```

Guardar y salir (`:wq`).

**Alternativas sin abrir editor:**

```bash
# Con kubectl patch
kubectl patch svc nginx-service --type=json \
  -p '[{"op":"replace","path":"/spec/ports/0/nodePort","value":32165}]'

# Con kubectl patch (merge)
kubectl patch svc nginx-service -p '{"spec":{"ports":[{"port":80,"nodePort":32165}]}}'
```

### 3. Editar el Deployment — cambiar replicas e imagen

```bash
kubectl edit deployment nginx-deployment
```

Cambiar dos cosas en el manifiesto:

```yaml
# Cambiar replicas
spec:
  replicas: 5       # era 1

# Cambiar imagen del contenedor
spec:
  template:
    spec:
      containers:
        - name: nginx-container
          image: nginx:latest    # era nginx:1.17
```

Guardar y salir (`:wq`). Kubernetes inicia el rolling update automaticamente.

**Alternativas sin abrir editor:**

```bash
# Cambiar replicas
kubectl scale deployment nginx-deployment --replicas=5

# Cambiar imagen
kubectl set image deployment/nginx-deployment nginx-container=nginx:latest

# Ambos con patch en un solo comando
kubectl patch deployment nginx-deployment -p '{"spec":{"replicas":5,"template":{"spec":{"containers":[{"name":"nginx-container","image":"nginx:latest"}]}}}}'
```

### 4. Verificar los cambios

#### Verificar el Service

```bash
kubectl get svc nginx-service
```

```
NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
nginx-service   NodePort    10.96.254.53   <none>        80:32165/TCP   5m
```

NodePort cambiado a **32165**.

#### Verificar el Deployment

```bash
kubectl get deployment nginx-deployment
```

```
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deployment   5/5     5            5           5m30s
```

**5/5** replicas corriendo y actualizadas.

#### Verificar los Pods

```bash
kubectl get pods
```

```
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-854ff588b7-758fv   1/1     Running   0          54s
nginx-deployment-854ff588b7-cwcts   1/1     Running   0          54s
nginx-deployment-854ff588b7-dmsc7   1/1     Running   0          88s
nginx-deployment-854ff588b7-fmrxr   1/1     Running   0          54s
nginx-deployment-854ff588b7-kkrj8   1/1     Running   0          54s
```

5 Pods corriendo. Notar que el hash del Deployment cambio (`854ff588b7` vs `5dd558cf95` original) porque la imagen cambio, lo que genero un nuevo ReplicaSet.

#### Verificar la imagen

```bash
kubectl describe pod nginx-deployment-854ff588b7-758fv
```

En la seccion Events:

```
Events:
  Normal  Pulled   78s  kubelet  Container image "nginx:latest" already present on machine
  Normal  Created  77s  kubelet  Created container nginx-container
  Normal  Started  75s  kubelet  Started container nginx-container
```

La imagen `nginx:latest` esta en uso.

Alternativa rapida para verificar la imagen sin `describe`:

```bash
kubectl get pods -o jsonpath='{.items[0].spec.containers[0].image}'
```

```
nginx:latest
```

## Resumen de metodos para editar recursos

| Cambio | `kubectl edit` | Alternativa sin editor |
|--------|---------------|----------------------|
| NodePort del Service | `edit svc` → cambiar `nodePort` | `kubectl patch svc --type=json -p '[{"op":"replace","path":"/spec/ports/0/nodePort","value":32165}]'` |
| Replicas del Deployment | `edit deployment` → cambiar `replicas` | `kubectl scale deployment --replicas=5` |
| Imagen del contenedor | `edit deployment` → cambiar `image` | `kubectl set image deployment/name container=image:tag` |
| Multiples cambios a la vez | `edit` → cambiar todo en una sola sesion | `kubectl patch` con JSON que incluya todos los cambios |

### Cuando usar cada metodo

| Metodo | Mejor para |
|--------|------------|
| `kubectl edit` | Cambios interactivos, cuando necesitas ver el manifiesto completo |
| `kubectl scale` | Cambiar replicas rapidamente |
| `kubectl set image` | Cambiar imagen de un contenedor especifico |
| `kubectl patch` | Scripts, CI/CD, automatizacion |

En este ejercicio, `kubectl edit` fue suficiente porque se hicieron pocos cambios de forma interactiva. En un pipeline de CI/CD se usarian `scale`, `set image` o `patch` para automatizar.

### Ver el historial del rolling update

```bash
# Ver historial de rollouts
kubectl rollout history deployment/nginx-deployment

# Ver estado del rollout actual
kubectl rollout status deployment/nginx-deployment

# Si algo sale mal, hacer rollback
kubectl rollout undo deployment/nginx-deployment
```

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `edit` no guarda cambios | Verificar que no hay errores de sintaxis YAML. Kubernetes rechaza el cambio si el YAML es invalido |
| NodePort `already allocated` | El puerto ya esta en uso por otro Service. Elegir otro puerto en el rango 30000-32767 |
| Pods quedan en `Pending` despues de escalar | No hay suficientes recursos (CPU/memoria) en el cluster. Verificar con `kubectl describe pod` |
| Rolling update se queda a medias | La nueva imagen puede tener problemas. Verificar con `kubectl rollout status`. Hacer rollback con `kubectl rollout undo` |
| Imagen `nginx:latest` no se descarga | Posible problema de red. Verificar con `kubectl describe pod` en la seccion Events |
| `kubectl edit` abre un editor desconocido | Configurar el editor con `export KUBE_EDITOR="vi"` o `export EDITOR="vi"` |

## Recursos

- [Deployments - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Services - Kubernetes Docs](https://kubernetes.io/docs/concepts/services-networking/service/)
- [kubectl scale](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_scale/)
- [kubectl set image](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/kubectl_set_image/)
- [Performing a Rolling Update](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)
