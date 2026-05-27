# kubectl — Guía de referencia

`kubectl` es la interfaz universal con un cluster de Kubernetes. Todo comando tiene la forma:

```
kubectl <verbo> <recurso> [<selector>] [opciones]
```

Esta guía está organizada en secciones temáticas. Cada una cubre una pregunta operacional que aparece todo el tiempo al trabajar con un cluster.

## Índice

| Sección                                                    | Cubre                                                                                                |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| [Seleccionar componentes](seleccionar.md)                  | Cómo identificar Pods, Deployments, containers, namespaces. Labels, field selectors, jsonpath, watch |
| [Editar componentes](editar.md)                            | `edit`, `apply`, `patch`, `set`, `replace`, `scale`, `label`, `rollout` — cuándo usar cada uno       |
| [Volúmenes (PV / PVC / hostPath)](volumenes.md)            | Tipos de volumen, persistentes y efímeros, casos de uso, troubleshooting de mount                    |
| [Config y Secretos (Opaque / stringData / ConfigMap)](config-y-secretos.md) | ConfigMaps, Secrets, formas de consumirlos (env vs volumen), tipos de Secret built-in                |

## Convenciones de esta guía

- Cada sección incluye una **tabla de decisión** al inicio: "quiero X → usar Y".
- Los comandos van con su output esperado cuando es relevante.
- Las trampas comunes están en una sección de **Troubleshooting** al final de cada página.
- Cross-refs a los días del journal donde apareció el concepto en la práctica.

## Cheatsheet maestro

```bash
# === SELECCIÓN ===
kubectl get pod <name>                                  # Por nombre
kubectl get pods -l app=nginx                           # Por label
kubectl get pods -n kube-system                         # En un namespace
kubectl get pods -A                                     # Todos los namespaces
kubectl get pods --field-selector status.phase=Failed   # Por field
kubectl logs my-pod -c my-container                     # Container específico
kubectl get pod my-pod -o jsonpath='{.status.podIP}'    # Campo específico
kubectl explain deployment.spec.strategy                # Documentación en vivo

# === EDICIÓN ===
kubectl edit deployment my-app                          # Interactivo
kubectl apply -f manifest.yaml                          # Declarativo
kubectl set image deployment/my-app c=img:v2            # Cambiar imagen
kubectl scale deployment/my-app --replicas=5            # Cambiar replicas
kubectl rollout restart deployment/my-app               # Forzar recrear pods
kubectl rollout undo deployment/my-app                  # Rollback

# === VOLÚMENES ===
kubectl get pv                                          # PVs del cluster
kubectl get pvc -n <ns>                                 # PVCs de un namespace
kubectl describe pvc <name>                             # Diagnosticar binding

# === CONFIG Y SECRETOS ===
kubectl create configmap <name> --from-literal=KEY=val  # ConfigMap rápido
kubectl create secret generic <name> --from-file=path   # Secret desde archivo
kubectl get secret <name> -o jsonpath='{.data.KEY}' | base64 -d  # Decodificar

# === DEBUG ===
kubectl events <resource>                               # Timeline del recurso (1.27+)
kubectl describe <resource> <name>                      # Vista completa
kubectl logs <pod> -c <container> --previous            # Logs del container anterior
kubectl exec -it <pod> -- /bin/sh                       # Shell dentro del Pod
```

## Recursos generales

- [`kubectl` Cheat Sheet (oficial)](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Commands reference (oficial)](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands)
- [Concepts (oficial)](https://kubernetes.io/docs/concepts/)
- [`k9s` — TUI para kubectl](https://k9scli.io/)
- [`stern` — multi-pod log streaming](https://github.com/stern/stern)
