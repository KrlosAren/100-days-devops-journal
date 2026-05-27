# kubectl · Config y Secretos (ConfigMap / Secret / data vs stringData)

Cómo inyectar configuración y credenciales en los Pods sin hornearlas en la imagen. K8s tiene dos primitivas para esto: **ConfigMap** (datos no sensibles) y **Secret** (datos sensibles). La mecánica es similar pero las reglas operativas difieren.

## Tabla de decisión: ConfigMap o Secret

| Tipo de dato                                  | Recurso       | Por qué                                                                       |
| --------------------------------------------- | ------------- | ----------------------------------------------------------------------------- |
| Config de app (log level, hostnames, flags)   | **ConfigMap** | No sensible, base64 sería overhead innecesario                                |
| Archivos de config (`nginx.conf`, `app.properties`) | **ConfigMap** | Igual razón                                                                   |
| URLs públicas, endpoints, puertos             | **ConfigMap** | No sensible                                                                   |
| Passwords, API keys, tokens                   | **Secret**    | Sensible — montado como tmpfs, RBAC más restrictivo, no aparece en describe   |
| Certificados TLS                              | **Secret** (`type: kubernetes.io/tls`) | Tipo específico que valida estructura                                          |
| Credenciales de registry privado              | **Secret** (`type: kubernetes.io/dockerconfigjson`) | Lo usa `imagePullSecrets`                                                     |
| Llave SSH privada                             | **Secret** (`type: kubernetes.io/ssh-auth`)        | Tipo específico                                                               |

> Importante: usar Secret **no encripta nada**. Los Secrets en etcd están en base64 (codificación trivial). La protección real viene de RBAC, encryption-at-rest de etcd, y/o herramientas externas (Sealed Secrets, SOPS, External Secrets Operator).

## Tabla de decisión: cómo consumirlos en un Pod

| Forma                                       | Cuándo conviene                                                       | Pitfall típico                                                                  |
| ------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **Env var individual** (`valueFrom`)        | Cuando la app espera UNA variable específica del environment           | Las env vars se ven con `ps`, `proc/<pid>/environ`, dumps de error              |
| **Todas las claves como env vars** (`envFrom`) | Cuando la app espera muchas vars y todas vienen del mismo objeto    | Cualquier conflicto de nombres se resuelve silenciosamente                      |
| **Volume mount**                            | Cuando la app **lee un archivo** (TLS certs, archivos de licencia, kubeconfigs) | Si la app no soporta hot-reload, un cambio en el ConfigMap/Secret no se aplica hasta restart |
| **`imagePullSecrets`** en el Pod spec (solo Secrets de tipo `dockerconfigjson`) | Credenciales para pullear imágenes de registries privados             | Confundirse en el tipo de Secret da error                                       |

## ConfigMap

### Crear un ConfigMap (3 formas)

```bash
# Desde literales
kubectl create configmap nginx-config \
  --from-literal=LOG_LEVEL=info \
  --from-literal=WORKER_COUNT=4

# Desde un archivo (key = nombre del archivo)
kubectl create configmap nginx-config --from-file=nginx.conf

# Desde un archivo con key personalizada
kubectl create configmap nginx-config --from-file=config.conf=./local-nginx.conf

# Desde un .env file
kubectl create configmap app-env --from-env-file=.env

# Manifest declarativo
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  LOG_LEVEL: "info"
  WORKER_COUNT: "4"
  nginx.conf: |
    server {
      listen 80;
      ...
    }
EOF
```

### Diferencia entre `data` y `binaryData`

| Campo        | Espera                                       | Cuándo usar                                       |
| ------------ | -------------------------------------------- | ------------------------------------------------- |
| `data`       | Valores **string** (UTF-8 plano)             | Default — config legible                          |
| `binaryData` | Valores **base64** de contenido binario      | Imágenes, binarios, archivos no-UTF8              |

### Consumir un ConfigMap

```yaml
# Como env var individual
env:
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef:
        name: nginx-config
        key: LOG_LEVEL

# Como todas las env vars del ConfigMap (envFrom)
envFrom:
  - configMapRef:
      name: nginx-config

# Como volumen (cada key = un archivo)
volumes:
  - name: config
    configMap:
      name: nginx-config
containers:
  - volumeMounts:
      - name: config
        mountPath: /etc/nginx/conf.d
```

> Al montar como volumen, **cada clave del `data` se convierte en un archivo** en el `mountPath`. Para `nginx-config` del ejemplo, aparecerían `/etc/nginx/conf.d/LOG_LEVEL`, `/etc/nginx/conf.d/WORKER_COUNT`, `/etc/nginx/conf.d/nginx.conf`.

### Filtrar y renombrar claves al montar

```yaml
volumes:
  - name: config
    configMap:
      name: nginx-config
      items:                          # solo monta estas keys
        - key: nginx.conf
          path: nginx.conf            # con este nombre de archivo
```

## Secret

### Tipos built-in de Secret

K8s reconoce varios `type` que validan la estructura del campo `data`:

| `type`                                     | Uso                                                    | Claves obligatorias en `data`             |
| ------------------------------------------ | ------------------------------------------------------ | ----------------------------------------- |
| `Opaque` *(default, el más común)*         | Datos arbitrarios definidos por el usuario             | Ninguna (libre)                           |
| `kubernetes.io/service-account-token`      | Token del ServiceAccount (lo crea el control plane)    | `token`, `ca.crt`, `namespace`            |
| `kubernetes.io/dockercfg`                  | Equivalente al viejo `~/.dockercfg`                    | `.dockercfg`                              |
| `kubernetes.io/dockerconfigjson`           | Equivalente al moderno `~/.docker/config.json`         | `.dockerconfigjson`                       |
| `kubernetes.io/basic-auth`                 | Credenciales para HTTP Basic Auth                      | `username`, `password`                    |
| `kubernetes.io/ssh-auth`                   | Llave privada SSH                                      | `ssh-privatekey`                          |
| `kubernetes.io/tls`                        | Certificado TLS (cliente o servidor)                   | `tls.crt`, `tls.key`                      |
| `bootstrap.kubernetes.io/token`            | Token de bootstrap para nodos uniendose al cluster     | Varios campos del flujo de bootstrap      |

> El tipo no encripta nada — solo le da a K8s la información para validar la estructura. Por ejemplo, `kubectl` busca `dockerconfigjson` cuando se referencia desde `imagePullSecrets`.

### Crear un Secret (3 formas)

```bash
# Desde literales
kubectl create secret generic db-pass \
  --from-literal=password=YUIidhb667

# Desde un archivo (key = nombre del archivo)
kubectl create secret generic media --from-file=/opt/media.txt

# Con tipo específico
kubectl create secret tls my-tls \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem

kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  --docker-email=user@example.com

# Manifest declarativo (ver siguiente sección sobre data vs stringData)
```

### `data` vs `stringData` — la diferencia que más confunde

| Campo            | Qué espera           | Quién codifica          | Cuándo usar                                                 |
| ---------------- | -------------------- | ----------------------- | ----------------------------------------------------------- |
| `data:`          | Valores **ya en base64** | El que escribe el YAML  | Cuando los valores ya están codificados (export de otro cluster) |
| `stringData:`    | Valores **planos**       | K8s al hacer apply      | Al escribir el YAML a mano (el caso más común)              |

```yaml
# ❌ Mal — data espera base64
apiVersion: v1
kind: Secret
metadata:
  name: db-pass
type: Opaque
data:
  password: YUIidhb667           # error: illegal base64 data
```

```yaml
# ✅ Bien — opción 1: stringData (K8s codifica)
apiVersion: v1
kind: Secret
metadata:
  name: db-pass
type: Opaque
stringData:
  password: YUIidhb667
```

```yaml
# ✅ Bien — opción 2: data con valor ya codificado
apiVersion: v1
kind: Secret
metadata:
  name: db-pass
type: Opaque
data:
  password: WVVJaWRoYjY2Nw==     # echo -n 'YUIidhb667' | base64
```

> **Nunca usar los dos a la vez sobre la misma clave** — `stringData` gana y silenciosamente sobrescribe.

### Consumir un Secret

```yaml
# Como env var individual
env:
  - name: MYSQL_ROOT_PASSWORD
    valueFrom:
      secretKeyRef:
        name: mysql-root-pass
        key: password

# Como todas las env vars del Secret (envFrom)
envFrom:
  - secretRef:
      name: mysql-creds

# Como volumen
volumes:
  - name: secret-volume
    secret:
      secretName: media
containers:
  - volumeMounts:
      - name: secret-volume
        mountPath: /opt/cluster
        readOnly: true
```

### Decodificar un Secret

```bash
# Ver el secret (en base64)
kubectl get secret db-pass -o yaml

# Decodificar una clave específica
kubectl get secret db-pass -o jsonpath='{.data.password}' | base64 -d

# Decodificar TODAS las claves a la vez (jq)
kubectl get secret db-pass -o json | jq '.data | map_values(@base64d)'
```

## Comparación lado a lado

```yaml
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
data:
  log-level: info        # plano, legible

---
# Secret (con stringData)
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
stringData:
  password: s3cr3t       # plano al escribir, K8s lo codifica

---
# Secret (con data)
apiVersion: v1
kind: Secret
metadata:
  name: my-secret-2
type: Opaque
data:
  password: czNjcjN0     # ya en base64
```

Diferencias operativas:

| Aspecto                            | ConfigMap                                          | Secret                                                                        |
| ---------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------- |
| Propósito                          | Config no sensible                                 | Datos sensibles                                                               |
| Codificación de valores            | Plano (string)                                     | base64 en el manifest y al hacer `get -o yaml`                                |
| Montaje como volumen               | Disco normal del nodo                              | **tmpfs** (memoria) — nunca toca disco del nodo                               |
| Visibilidad en `describe`          | Muestra los valores                                | Muestra **las claves pero no los valores**                                    |
| Tamaño máximo                      | 1 MiB                                              | 1 MiB                                                                         |

## Actualización en vivo

Los **mounted ConfigMaps/Secrets se actualizan en vivo** — el kubelet refresca el contenido del filesystem cuando el objeto cambia. Pero hay sutilezas:

| Forma de consumo                      | Update se propaga a Pods existentes      |
| ------------------------------------- | ---------------------------------------- |
| **Env var (`valueFrom`)**             | ❌ Nunca. Requiere recrear el Pod        |
| **`envFrom`**                         | ❌ Nunca. Requiere recrear el Pod        |
| **Volumen montado**                   | ✅ Eventualmente (~1 min de delay)       |

Aunque el volumen se actualice, la **app tiene que releer el archivo** para ver el cambio. Apps que cachean el archivo al startup necesitan un restart.

Para forzar restart sin cambiar nada de spec:

```bash
kubectl rollout restart deployment/my-app
```

## Comandos útiles

```bash
# Listar ConfigMaps y Secrets
kubectl get cm
kubectl get secrets

# Ver claves de un ConfigMap
kubectl get cm my-config -o jsonpath='{.data}' | jq

# Ver claves de un Secret (sin decodificar)
kubectl get secret my-secret -o jsonpath='{.data}' | jq 'keys'

# Decodificar todas las claves de un Secret
kubectl get secret my-secret -o json | jq '.data | map_values(@base64d)'

# Crear ConfigMap desde múltiples archivos en un directorio
kubectl create configmap nginx-files --from-file=./conf.d/

# Editar interactivamente (cuidado con secrets — el editor puede dejar swap files)
kubectl edit cm my-config

# Ver qué Pods están usando un ConfigMap/Secret (jsonpath manual)
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{": "}{range .spec.volumes[*]}{.configMap.name}{" "}{end}{"\n"}{end}' | grep <cm-name>
```

## Buenas prácticas

### Para ConfigMaps

- Usar nombres **descriptivos** y prefijados con el nombre de la app: `nginx-config`, `redis-config`
- Versionar los manifests en git — todo lo demás es lo mismo
- Si el ConfigMap es grande (>10KB), considerar partirlo o usar un volume montado
- **No poner secretos** en un ConfigMap "por comodidad"

### Para Secrets

- **Nunca commitear** un manifest de Secret con `data` plano a un repo
- Si va a git, debe pasar por una capa de cifrado:
  - **Sealed Secrets** (Bitnami): cifra con la pubkey del cluster
  - **SOPS** (Mozilla): cifrado simétrico o con KMS/PGP
  - **External Secrets Operator**: inyecta desde un secret manager externo (AWS Secrets Manager, Vault, GCP Secret Manager)
- Habilitar **encryption-at-rest** en etcd (`EncryptionConfiguration` en el kube-apiserver)
- Usar RBAC restrictivo: pocos usuarios deberían tener `get` sobre Secrets
- Para Secrets críticos en producción, **rotar regularmente**

## Troubleshooting

| Problema                                                                | Causa                                                                                                | Solución                                                                                          |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `Secret in version "v1" cannot be handled: illegal base64 data`         | Usás `data:` con valores planos                                                                      | Cambiar a `stringData:` o codificar manualmente: `echo -n 'valor' \| base64`                      |
| Pod en `CreateContainerError` con `secret "X" not found`                | El nombre del Secret en `secretKeyRef.name` no matchea ningún Secret real                            | `kubectl get secrets -n <ns>` para ver los nombres reales                                         |
| Pod en `CreateContainerError` con `key "X" not found in secret "Y"`     | La clave del `secretKeyRef.key` no existe en el Secret                                               | `kubectl get secret <name> -o yaml` para ver las claves disponibles                               |
| Env var vacía aunque el Secret existe                                   | La key del `secretKeyRef` no matchea ninguna clave del Secret (case-sensitive)                       | Verificar mayúsculas/minúsculas exactas                                                            |
| `MountVolume.SetUp failed for volume "X" : configmap "Y" not found`     | `configMap.name` no matchea ningún ConfigMap real (Día 65)                                           | Corregir el nombre o crear el ConfigMap                                                           |
| Mounted ConfigMap actualizado pero la app no ve el cambio               | La app cachea el archivo al startup; el filesystem se actualizó pero la app no recargó              | `kubectl rollout restart deployment/<name>` para forzar Pods nuevos                               |
| `describe pod` no muestra el valor del Secret                           | **Feature, no bug** — K8s nunca dumpea valores de Secrets en describe                                 | Para verificar: `kubectl get secret <name> -o jsonpath='{.data.<key>}' \| base64 -d`             |
| `kubectl edit secret` deja swap files en disco con el contenido         | Editor (vim) creó archivo `.swp` con el secret decodificado                                          | Cerrar el editor limpiamente, borrar `.swp` antes de cerrar shell                                 |
| Tipo `kubernetes.io/tls` rechazado con `data field not provided`        | Falta `tls.crt` o `tls.key` (campos obligatorios del tipo)                                           | Agregar ambos campos al `data`                                                                    |
| `imagePullSecrets` no funciona aunque el Secret existe                  | El Secret no es de tipo `kubernetes.io/dockerconfigjson`                                             | Crear con `kubectl create secret docker-registry ...`                                             |
| Commiteaste un manifest de Secret con `data` plano a git                | Error operacional — el secret quedó expuesto en el historial                                          | Rotar el secret en su origen, rewrite del git history (`git filter-repo`), revisar accesos        |

## Referencias del journal

| Día     | Cubre                                                                       |
| ------- | --------------------------------------------------------------------------- |
| 57      | env vars en Pods + `$(VAR)` substitution + ConfigMap como env source       |
| 59      | Troubleshooting de ConfigMap referenciado por nombre que no existe         |
| 62      | Secrets como volumen — `Opaque`, tipos built-in, base64, tmpfs              |
| 65      | ConfigMap como volumen, bug de `configMap.name` mal escrito                 |
| 66      | Secrets como `secretKeyRef` en env, `data` vs `stringData` en la práctica   |

## Recursos

- [ConfigMaps (oficial)](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secrets (oficial)](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [Distribute Credentials Securely Using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)
- [Encryption at Rest (etcd)](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [Sealed Secrets (Bitnami)](https://github.com/bitnami-labs/sealed-secrets)
- [External Secrets Operator](https://external-secrets.io/)
- [SOPS (Mozilla)](https://github.com/getsops/sops)
