# Día 03 - Crear un Namespace y desplegar un Pod en él

## Problema / Desafío

Crear un Namespace llamado `dev` y desplegar un Pod llamado `dev-nginx-pod` con la imagen `nginx:latest` dentro de ese Namespace.

## Solución

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: dev
  labels:
    name: dev

---
apiVersion: v1
kind: Pod
metadata:
  name: dev-nginx-pod
  namespace: dev
  labels:
    name: dev-nginx-pod
spec:
  containers:
    - name: dev-nginx-pod
      image: nginx:latest
```

### Desglose del manifiesto

Este archivo define **dos recursos** separados por `---`, que es el separador de documentos en YAML. Kubernetes los procesa en orden: primero crea el Namespace y luego el Pod dentro de él.

**Recurso 1: Namespace**

**`kind: Namespace`**: Un Namespace es un mecanismo de Kubernetes para dividir los recursos del clúster en grupos lógicos aislados. Funciona como una "carpeta virtual" que permite organizar, aislar y controlar el acceso a los recursos.

**`metadata.name: dev`**: El nombre del Namespace. Se usa como referencia en otros recursos con el campo `namespace:`.

**`metadata.labels`**: Labels asignados al Namespace. Los labels son pares clave-valor que permiten identificar y filtrar recursos. En este caso `name: dev` permite buscar el Namespace con selectores como `kubectl get ns -l name=dev`.

**Recurso 2: Pod**

**`metadata.namespace: dev`**: Indica que este Pod se crea dentro del Namespace `dev`. Sin este campo, el Pod se crearía en el Namespace `default`.

**`metadata.labels`**: Labels del Pod. A diferencia del Namespace, estos labels se usan para que controladores como Deployments o Services identifiquen y seleccionen este Pod.

**`spec.containers`**: Lista de contenedores que corren dentro del Pod. Cada contenedor necesita un `name` y una `image`.

### ¿Qué es un Namespace y para qué sirve?

Los Namespaces resuelven el problema de organizar recursos en clústeres compartidos por múltiples equipos o ambientes:

| Caso de uso | Ejemplo |
|-------------|---------|
| Separar ambientes | `dev`, `staging`, `production` |
| Separar equipos | `team-backend`, `team-frontend` |
| Aislar aplicaciones | `app-payments`, `app-auth` |
| Aplicar políticas | Resource Quotas, Network Policies por Namespace |

Kubernetes crea estos Namespaces por defecto:

| Namespace | Propósito |
|-----------|-----------|
| `default` | Donde se crean los recursos si no se especifica un Namespace |
| `kube-system` | Componentes internos de Kubernetes (API server, scheduler, etc.) |
| `kube-public` | Recursos accesibles públicamente sin autenticación |
| `kube-node-lease` | Objetos Lease para heartbeats de los nodos |

### ¿Por qué usar un solo archivo con `---`?

El separador `---` permite definir múltiples recursos en un solo archivo YAML. Kubernetes los aplica en orden secuencial, lo cual es útil cuando un recurso depende de otro (el Pod necesita que el Namespace exista primero).

La alternativa sería tener archivos separados:

```
namespace-dev.yml      # Solo el Namespace
pod-dev-nginx.yml      # Solo el Pod
```

Ambos enfoques son válidos. Un solo archivo es más práctico cuando los recursos están relacionados y se despliegan juntos.

### Aplicar y verificar

```bash
# Aplicar el manifiesto (crea Namespace y Pod)
kubectl apply -f namespace-dev-pod.yml

# Ver los namespaces
kubectl get namespaces

# Ver el Pod en el namespace dev
kubectl get pods -n dev

# Ver detalles del Pod
kubectl describe pod dev-nginx-pod -n dev

# Ver todos los recursos en el namespace dev
kubectl get all -n dev
```

La flag `-n dev` es necesaria para ver recursos dentro del Namespace `dev`. Sin ella, `kubectl` solo muestra recursos del Namespace `default`.

### Comandos imperativos equivalentes

```bash
# Crear el namespace
kubectl create namespace dev

# Crear el pod en el namespace dev
kubectl run dev-nginx-pod --image=nginx:latest -n dev
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `Error: namespaces "dev" not found` al crear el Pod | Asegurar que el Namespace se define antes del Pod en el archivo, o crearlo primero con `kubectl create namespace dev` |
| El Pod no aparece con `kubectl get pods` | Agregar `-n dev` al comando. Sin `-n`, solo muestra el Namespace `default` |
| Pod en estado `ImagePullBackOff` | Verificar que la imagen `nginx:latest` existe y que el nodo tiene acceso al registry |
| Pod en estado `Pending` | Verificar recursos disponibles con `kubectl describe pod dev-nginx-pod -n dev` y revisar la sección Events |

## Recursos

- [Documentación oficial de Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
- [Documentación oficial de Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [YAML Multi-document en Kubernetes](https://kubernetes.io/docs/concepts/cluster-administration/manage-deployment/#organizing-resource-configurations)
