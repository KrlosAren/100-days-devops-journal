# Día 62 - Manejo de Secrets en Kubernetes

## Problema / Desafío

El equipo de Nautilus va a desplegar herramientas que requieren **información sensible** (licencias, passwords, tokens) y necesita almacenarla de forma controlada en el cluster — no en el manifest del Deployment, no en ConfigMaps planos, no horneada en la imagen.

- Existe el archivo `/opt/media.txt` con el password / número de licencia
- Crear un **Secret genérico** llamado `media` cuyo contenido sea el archivo `media.txt`
- Crear un Pod llamado `secret-devops` con:
  - Container `secret-container-devops`
  - Imagen `debian:latest` (tag explícito)
  - Comando `sleep` para mantenerlo en `Running`
  - El Secret montado en `/opt/cluster`
- Verificar con `kubectl exec` que el archivo del secret aparece bajo el `mountPath` y se puede leer

El patrón conceptual es el mismo del Día 57 (env vars con ConfigMap) y del Día 60 (volúmenes persistentes), pero la **fuente** del dato es un Secret — que tiene reglas de manejo distintas (codificación, almacenamiento en memoria, RBAC más estricto por convención).

## Conceptos clave

### Qué es un Secret

Un Secret es un objeto de Kubernetes pensado para almacenar **datos sensibles** que un Pod va a consumir. La diferencia operativa con un ConfigMap es chica en el manifest pero importante en la práctica:

| Aspecto                            | ConfigMap                                          | Secret                                                                        |
| ---------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------- |
| Propósito                          | Config no sensible                                 | Datos sensibles (passwords, tokens, certs, llaves)                            |
| Codificación de valores            | Plano (string)                                     | **base64** en el manifest y al hacer `get -o yaml`                            |
| Montaje como volumen               | Disco normal del nodo                              | **tmpfs** (memoria) — nunca toca disco del nodo                               |
| Tamaño máximo                      | 1 MiB                                              | 1 MiB                                                                         |
| Visibilidad en logs / describe     | `describe` muestra los valores                     | `describe` muestra **las claves pero no los valores**                         |
| RBAC típico                        | Más permisivo                                      | Suele restringirse más en políticas reales                                    |
| Encryption-at-rest                 | Sin encriptación por defecto                       | Sin encriptación por defecto **(misma situación, mismo etcd)**                |

> **Aclaración crítica**: base64 **no es encryption** — es solo codificación, perfectamente reversible con `base64 -d`. La protección real viene de tres lugares: (1) RBAC restrictivo sobre el recurso `secrets`, (2) habilitar `EncryptionConfiguration` en el kube-apiserver para cifrar en etcd, y (3) integraciones externas como Sealed Secrets, SOPS, HashiCorp Vault o cloud providers (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault).

### Tipos de Secret (built-in types)

K8s reconoce varios `type` que validan la estructura del campo `data`. Cada tipo tiene un contrato distinto:

| `type`                                     | Uso                                                    | Claves obligatorias en `data`             |
| ------------------------------------------ | ------------------------------------------------------ | ----------------------------------------- |
| `Opaque` *(default y el del lab)*          | Datos arbitrarios definidos por el usuario             | Ninguna (libre)                           |
| `kubernetes.io/service-account-token`      | Token del ServiceAccount (lo crea el control plane)    | `token`, `ca.crt`, `namespace`            |
| `kubernetes.io/dockercfg`                  | Equivalente al viejo `~/.dockercfg`                    | `.dockercfg`                              |
| `kubernetes.io/dockerconfigjson`           | Equivalente al moderno `~/.docker/config.json`         | `.dockerconfigjson`                       |
| `kubernetes.io/basic-auth`                 | Credenciales para HTTP Basic Auth                      | `username`, `password`                    |
| `kubernetes.io/ssh-auth`                   | Llave privada SSH                                      | `ssh-privatekey`                          |
| `kubernetes.io/tls`                        | Certificado TLS (cliente o servidor)                   | `tls.crt`, `tls.key`                      |
| `bootstrap.kubernetes.io/token`            | Token de bootstrap para nodos uniendose al cluster     | Varios campos del flujo de bootstrap      |

El uso de un `type` específico **no encripta nada** — solo le da a K8s la información para validar la estructura y para que componentes que esperan un tipo determinado lo encuentren. Por ejemplo, `kubectl` usa `dockerconfigjson` cuando se lo referencia desde `imagePullSecrets`.

En el lab de hoy se usa el tipo `Opaque` (implícito al usar `kubectl create secret generic`).

### Tres formas de consumir un Secret en un Pod

| Forma                                       | Cuándo conviene                                                       | Pitfall típico                                                                  |
| ------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **Volume mount** (el del lab)               | Cuando la app **lee un archivo** (TLS certs, archivos de licencia, kubeconfigs) | Si la app no soporta hot-reload, un cambio en el secret no se aplica hasta restart |
| **Variables de entorno** (`valueFrom.secretKeyRef`) | Cuando la app espera la config por env (12-factor)                    | Las env vars se ven con `ps`, `proc/<pid>/environ`, dumps de error              |
| **`imagePullSecrets`** en el Pod spec       | Credenciales para pullear imágenes de registries privados             | Usa el tipo `dockerconfigjson`, no `Opaque` — confundirse en el tipo da error    |

Volume mount es la **forma más segura** porque el dato no aparece en el environment del proceso ni en dumps. Por eso es la que se usa cuando hay opción — y por eso el lab lo plantea así.

### Glosario rápido del manifest

| Campo                                      | Significado                                                                                  |
| ------------------------------------------ | -------------------------------------------------------------------------------------------- |
| `spec.volumes[].secret.secretName`         | Apunta al Secret de K8s que se va a exponer como volumen                                     |
| `spec.volumes[].secret.items`              | (Opcional) Selecciona claves específicas del Secret y las renombra en el filesystem          |
| `spec.volumes[].secret.defaultMode`        | (Opcional) Permisos de los archivos montados, octal (default `0644`)                         |
| `spec.volumes[].secret.optional`           | Si `true`, el Pod arranca aunque el Secret no exista (riesgoso, usar consciente)             |
| `spec.containers[].volumeMounts[].mountPath` | Ruta absoluta dentro del container donde aparece el contenido del Secret                    |
| `spec.containers[].volumeMounts[].readOnly` | Default `true` para volúmenes Secret (el filesystem es read-only)                            |

### Comportamiento del montaje — qué se ve dentro del container

Cuando un Secret se monta como volumen, K8s **crea un archivo por cada clave** del Secret en el `mountPath`. En este lab:

- El Secret `media` tiene una sola clave: `media.txt` (porque se creó con `--from-file=/opt/media.txt`)
- El `mountPath` es `/opt/cluster`
- Resultado: aparece el archivo `/opt/cluster/media.txt` dentro del container con el contenido decodificado del Secret

Si el Secret tuviera más claves, cada una se materializa como archivo en ese directorio. Si querés **renombrar** o **filtrar** claves al montarlas, se usa `volumes[].secret.items`.

## Pasos

1. Crear el Secret genérico desde el archivo:
   ```bash
   kubectl create secret generic media --from-file=/opt/media.txt
   ```
2. Verificar que el Secret quedó creado y revisar su contenido (en base64):
   ```bash
   kubectl get secret media -o yaml
   ```
3. Escribir el manifest del Pod con el container `secret-container-devops`, imagen `debian:latest`, comando `sleep 3600`, y volumen referenciando el Secret
4. Aplicar el manifest:
   ```bash
   kubectl apply -f pod.yml
   ```
5. Esperar a que el Pod quede `Running` y validar que el archivo está montado:
   ```bash
   kubectl exec -it secret-devops -- ls /opt/cluster
   kubectl exec -it secret-devops -- cat /opt/cluster/media.txt
   ```

## Comandos / Código

### Crear el Secret

```bash
kubectl create secret generic media --from-file=/opt/media.txt
```

```
secret/media created
```

> El nombre del archivo (`media.txt`) se vuelve la **clave** dentro del Secret. El contenido del archivo se **codifica en base64** y se guarda en el campo `data`.

### Inspección del Secret creado

```bash
kubectl get secret media -o yaml
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: media
  namespace: default
type: Opaque
data:
  media.txt: NWVjdXIzCg==
```

Para decodificar y verificar el valor real:

```bash
kubectl get secret media -o jsonpath='{.data.media\.txt}' | base64 -d
# 5ecur3
```

### Manifest del Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-devops
  labels:
    app: secret-devops
spec:
  containers:
    - name: secret-container-devops
      image: debian:latest
      command:
        - sh
        - -c
        - sleep 3600
      volumeMounts:
        - name: secret-volume
          mountPath: /opt/cluster
  volumes:
    - name: secret-volume
      secret:
        secretName: media
```

> El nombre del **volumen** (`secret-volume`) es local al Pod; lo importante es que coincida entre `volumes[].name` y `volumeMounts[].name`. El nombre del **Secret** (`media`) es lo que vincula con el objeto cluster-wide.

### Aplicación y verificación

```bash
kubectl apply -f pod.yml
```

```
pod/secret-devops created
```

```bash
kubectl get pods
```

```
NAME            READY   STATUS    RESTARTS   AGE
secret-devops   1/1     Running   0          16s
```

### Lectura crítica del `describe`

```bash
kubectl describe pod secret-devops
```

Bloques relevantes:

| Bloque                                       | Qué confirma                                                                          |
| -------------------------------------------- | ------------------------------------------------------------------------------------- |
| `Mounts: /opt/cluster from secret-volume (rw)` | El container montó el volumen en el path esperado                                     |
| `Volumes: secret-volume → Secret (...) SecretName: media` | El volumen está vinculado al Secret correcto                                          |
| `Optional: false`                            | Si el Secret no existe, el Pod **no arranca** (semántica estricta — la deseada)       |
| `QoS Class: BestEffort`                      | No se definieron requests/limits — el Pod corre, pero es el primero en ser evicted    |
| Events: `Successfully pulled image "debian:latest"` | La imagen se pulleó correctamente con el tag explícito                               |

### Verificación del contenido montado

```bash
kubectl exec -it secret-devops -- sh -c "ls /opt/cluster"
```

```
media.txt
```

```bash
kubectl exec -it secret-devops -- sh -c "cat /opt/cluster/media.txt"
```

```
5ecur3
```

El archivo se ve en el container con el contenido **ya decodificado** — el kubelet decodifica el base64 al materializar el volumen, la app no necesita saber nada de base64.

### Alternativas para crear el Secret

Vale conocer las tres formas equivalentes, porque cada una aparece en distintos workflows:

#### 1. Desde un archivo (la del lab)

```bash
kubectl create secret generic media --from-file=/opt/media.txt
# Key = nombre del archivo
```

Para renombrar la clave: `--from-file=licencia=/opt/media.txt` (clave `licencia`, archivo de origen `/opt/media.txt`).

#### 2. Desde un literal en línea de comando

```bash
kubectl create secret generic media --from-literal=password=5ecur3
```

> Aparece en el history de shell — útil para scripts efímeros, **mal** para uso interactivo en máquinas compartidas.

#### 3. Desde un YAML declarativo

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: media
type: Opaque
data:
  media.txt: NWVjdXIzCg==     # base64 del valor
# o usar stringData (K8s lo encodea por vos):
# stringData:
#   media.txt: "5ecur3"
```

> `stringData` es **write-only**: cuando hacés `get -o yaml`, K8s te lo muestra ya en `data` codificado. Útil para no tener que correr `base64` a mano al escribir el manifest.

#### Comparación

| Forma             | Donde queda el dato                          | Cuándo usar                                   |
| ----------------- | -------------------------------------------- | --------------------------------------------- |
| `--from-file`     | En el archivo y en el cluster                | Cuando el secret ya es un archivo (cert, key, license file) |
| `--from-literal`  | En el history del shell + en el cluster      | Scripts efímeros, demos, NO producción manual |
| Manifest YAML     | En el archivo YAML (y en git si lo commiteás — **peligro**) | GitOps con Sealed Secrets / SOPS sobre el YAML |

La regla práctica: **nunca commitear un manifest de Secret con `data` plano a un repo**. Si va a git, debe pasar antes por una capa de cifrado (Sealed Secrets cifra con la pubkey del cluster, SOPS lo encripta simétricamente, o se inyecta desde un secret manager externo en CI/CD).

## Cómo se comparan los tres mecanismos de inyección de config (Días 57, 60, 62)

Tres días, mismo problema base — "cómo le doy datos a un Pod" — con tres respuestas distintas:

| Día     | Fuente del dato            | Forma de consumo en el Pod                | Cuándo es la elección correcta                        |
| ------- | -------------------------- | ----------------------------------------- | ----------------------------------------------------- |
| Día 57  | Variables literales o ConfigMap | Env vars + `$(VAR)` substitution     | Config no sensible, plana, leída desde el environment |
| Día 60  | PV / PVC                   | Volumen persistente montado en path       | Datos persistentes que sobreviven al Pod              |
| Día 62  | Secret                     | Volumen tmpfs montado en path             | Datos sensibles que no deben tocar disco del nodo     |

Los tres usan el mismo bloque `volumes` + `volumeMounts` (cuando se montan), lo que cambia es de dónde sale el contenido del volumen. **La interfaz hacia la app es idéntica** — la app lee archivos en una ruta. Eso permite cambiar la fuente sin tocar la app: hoy ConfigMap, mañana Secret, pasado un PVC con datos prepoblados.

## Conexión con días anteriores

- **Día 57 (env vars + ConfigMap)**: la alternativa "Secret como env var" usaría `valueFrom.secretKeyRef` en lugar de `configMapKeyRef`. Mismo patrón, distinta fuente.
- **Día 59 (typo en ConfigMap)**: el mismo riesgo existe con Secrets — si el `secretName` no matchea exactamente, el Pod queda `ContainerCreating` esperando un objeto que nunca aparece. La diferencia es que con `optional: true` el Pod arrancaría igual, lo cual es casi siempre peor para secrets críticos.
- **Día 60 (PV + PVC)**: misma sintaxis de `volumes` + `volumeMounts`, distinto backend. Un PVC apunta a almacenamiento persistente; un Secret apunta a tmpfs efímero. Ambos son volúmenes desde la perspectiva del container.
- **Día 53 (mountPath mal alineado)**: la regla "verificar que `mountPath` coincide con donde la app lee" se mantiene. Si el lab pidiera `/etc/license` y montás en `/opt/cluster`, la app no lo encuentra.
- **Día 48 (primer Pod)**: cuatro días después aparece el mismo patrón básico — Pod con un container y un volumen — pero con la fuente del volumen siendo un Secret en lugar de nada.

## Reflexión: secrets en K8s vs otros enfoques

Antes de K8s, el manejo de secretos se resolvía con **AWS Secrets Manager** para entornos en la nube y con **archivos `.env`** para mover valores sensibles entre stages locales y de CI. Esos dos mecanismos tienen lógicas distintas — Secrets Manager es un servicio centralizado con auditoría, rotación y RBAC del lado del provider; los `.env` son simples y portables, pero terminan filtrándose con facilidad si alguien comitea sin querer o si quedan en logs de un build.

Mirando ahora el built-in `Secret` de K8s con esa experiencia previa, queda la sensación de que **funciona bien para configuraciones de aplicación que no son críticamente sensibles** — variables que no querés tener planas en el manifest pero cuya filtración no rompe nada serio. Para credenciales reales (passwords de DB de prod, tokens de API con permisos amplios, llaves privadas), apoyarse solo en el built-in se queda corto: el dato vive en etcd sin encriptación por default, y cualquiera con acceso al recurso puede dumpearlo en base64 trivialmente.

**SOPS** es la pieza que más cierra desde este lado: permite encriptar el manifest del Secret antes de meterlo a git, lo que hace viable compartir secretos en repos compartidos sin exponerlos. El secret existe versionado, auditable, y solo quien tiene la llave (KMS, age, PGP) puede leerlo — lo que cubre el gap más importante del built-in (el almacenamiento plano) sin sumar componentes nuevos al cluster. Para escenarios donde el secret debe consultarse en runtime desde un secret manager externo, **External Secrets Operator** sería el siguiente paso natural, pero SOPS resuelve el 80% de los casos con mucho menos overhead.

## Troubleshooting

| Problema                                                          | Causa                                                                                                  | Solución                                                                                                |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| El validador del lab marca el Pod como incorrecto a pesar de estar `Running` | El nombre del Pod no coincide exactamente con la spec del lab (`secret-devops` vs `secrets-devops`)    | Releer el requirement: los validadores comparan strings exactos. Recrear el Pod con el nombre correcto. |
| Pod en `CreateContainerError` o `ContainerCreating` indefinidamente | El Secret referenciado por `secretName` no existe en el namespace                                      | `kubectl get secret -n <ns>` para verificar. Crearlo o corregir el nombre.                              |
| `kubectl exec` muestra el directorio del mount vacío              | El Secret existe pero no tiene claves (`data: {}`), o las claves se filtraron con `items` mal definido | `kubectl get secret <name> -o yaml` y verificar `data:`                                                 |
| El archivo aparece pero con contenido base64 sin decodificar      | (Bug propio si lo armás manual) — probablemente codificaste **doble** el valor en el YAML              | Usar `stringData:` en el manifest, o asegurarse de codificar **una sola vez** con `base64 -w0`         |
| `cat` muestra el valor con un salto de línea extra                | Es esperable — el archivo original tenía `\n` al final, y K8s lo preserva                              | Si la app es estricta con whitespace, usar `--from-literal` o `printf` sin trailing newline             |
| Permission denied al leer el archivo dentro del container         | `defaultMode` del volumen es muy restrictivo, o el container corre con un UID que no matchea           | Ajustar `volumes[].secret.defaultMode` (ej. `0444`) o usar `fsGroup` en `securityContext`               |
| `describe pod` no muestra el valor del Secret                     | **No es un bug — es feature**: K8s nunca dumpea valores de Secrets en describe                          | Para verificar el valor: `kubectl get secret -o jsonpath='{.data.<key>}' \| base64 -d`                  |
| Commiteaste el manifest del Secret con `data` plano a git         | Error operacional — el secret quedó expuesto en el historial                                            | Rotar el secret en su origen, rewrite del git history (`git filter-repo`), revisar logs de acceso       |
| `kubectl create secret generic --from-file=...` falla con permission denied | El usuario no tiene permisos de lectura sobre el archivo en el filesystem del nodo/jumphost            | Verificar `ls -l` del archivo, ajustar permisos o ejecutar el comando como el dueño                     |
| El update del Secret no se refleja en el Pod                      | Mounted secrets se actualizan, pero la app puede tener el archivo cacheado en memoria                  | Reiniciar el Pod (mejor: hacer un rolling restart del Deployment que lo usa)                            |

## Recursos

- [Secrets (oficial)](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Distribute Credentials Securely Using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)
- [Encryption at Rest (etcd)](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [Sealed Secrets (Bitnami)](https://github.com/bitnami-labs/sealed-secrets)
- [External Secrets Operator](https://external-secrets.io/)
- [SOPS (Mozilla)](https://github.com/getsops/sops)
