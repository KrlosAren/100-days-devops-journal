# Día 01 - Crear un Pod en Kubernetes

## Problema / Desafío

Se pide crear un pod con el nombre `pod-httpd`, usando la imagen `httpd` con el tag `:latest`, que tenga como label `httpd_app` y el contenedor se llame `httpd-container`.

## Solución

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-httpd
  labels:
    app: httpd_app
spec:
  containers:
    - name: httpd-container
      image: httpd:latest
```

### Desglose del manifiesto

**`metadata`**: Es la sección donde definimos información de identificación del recurso. Aquí se asigna el `name`, que es el nombre único del pod dentro del namespace. Kubernetes usa este nombre para referenciar, buscar y gestionar el recurso.

**`labels`**: Son pares clave-valor que se asignan a los recursos para organizarlos y filtrarlos. A nivel de manifiesto (en `metadata.labels`), permiten agrupar y seleccionar pods con `kubectl get pods -l app=httpd_app` o vincularlos con otros recursos como Services o Deployments mediante selectores. Los contenedores dentro de `spec.containers` no tienen labels propios; los labels siempre se definen a nivel del recurso en `metadata`.

**`containers`**: Es la lista de contenedores que correrán dentro del pod. Cada contenedor define:
- `name`: Identificador del contenedor dentro del pod, útil para referenciarlo en logs (`kubectl logs pod-httpd -c httpd-container`) o al ejecutar comandos dentro de él.
- `image`: La imagen y su tag. El formato es `imagen:tag`, en este caso `httpd:latest`.

### Aplicar y verificar

```bash
kubectl apply -f pod.yaml

# Ver estado del pod
kubectl get pod pod-httpd

# Ver detalles completos
kubectl describe pod pod-httpd

# Filtrar pods por label
kubectl get pods -l app=httpd_app
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| Pod en estado `ImagePullBackOff` | Verificar que la imagen `httpd:latest` existe y que el nodo tiene acceso al registry |
| Pod en estado `Pending` | Revisar recursos disponibles con `kubectl describe pod pod-httpd` |
| Error de sintaxis YAML | Validar antes de aplicar con `kubectl apply --dry-run=client -f pod.yaml` |

## Recursos

- [Documentación oficial de Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
