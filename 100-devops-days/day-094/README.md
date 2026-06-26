# Día 94 - Create VPC Using Terraform (primer día de IaC: providers, resources, state, plan/apply)

## Problema / Desafío

El equipo Nautilus está migrando parte de su infraestructura a AWS de forma incremental, en pasos pequeños y controlados. Primer paso:

- Crear una **VPC** llamada **`xfusion-vpc`** en la región **`us-east-1`** con cualquier bloque CIDR IPv4, **usando Terraform**.
- Directorio de trabajo: `/home/bob/terraform`. Crear el archivo **`main.tf`** (no crear otro `.tf`).

> **Cambio de sección**: termina la racha de Ansible (Días 82-93) y arranca **Terraform / Infrastructure as Code**. Si Ansible es *configuration management* (configura servidores que ya existen), Terraform es *provisioning* (crea la infraestructura misma — VPCs, subnets, instancias).

## Conceptos clave

### Qué problema resuelve la IaC (Infrastructure as Code)

Crear infraestructura "a mano" (clickeando en la consola de AWS) no escala: no queda registro de **qué** se creó ni **por qué**, no es reproducible, y no hay forma de versionar o revisar cambios. La **IaC** resuelve esto: se escribe la infraestructura como **código declarativo**, lo que permite:

- **Versionar** la infra en git (revisar diffs, hacer PRs, rollback)
- **Reproducir** entornos idénticos (dev/staging/prod)
- **Automatizar** cambios y testearlos antes de aplicarlos
- **Gestionar el ciclo de vida** completo (crear → modificar → destruir)

Herramientas: **Terraform**, Pulumi, AWS CloudFormation, OpenTofu. Hoy se usa Terraform.

### Declarativo vs imperativo — el mismo salto mental que Ansible

| Enfoque        | Se describe…                              | Ejemplo                          |
| -------------- | ----------------------------------------- | -------------------------------- |
| **Imperativo** | Los **pasos** para llegar al estado       | `aws ec2 create-vpc --cidr ...`  |
| **Declarativo**| El **estado deseado** final               | `resource "aws_vpc" { ... }`     |

Terraform es declarativo: se declara "quiero una VPC con este CIDR" y Terraform calcula **qué acciones** ejecutar (crear, modificar o destruir) para que la realidad coincida con lo declarado. Mismo principio que `state: present` en Ansible, pero para infraestructura completa.

### Los conceptos núcleo de Terraform

| Concepto       | Qué es                                                                          |
| -------------- | ------------------------------------------------------------------------------- |
| **HCL**        | *HashiCorp Configuration Language* — el lenguaje declarativo de los `.tf`        |
| **Provider**   | Plugin que traduce el código a llamadas a la API de una nube (aws, gcp, azure)  |
| **Resource**   | Un objeto de infraestructura a gestionar (`aws_vpc`, `aws_instance`, …)         |
| **State**      | Archivo (`terraform.tfstate`) que mapea el código a los objetos reales creados  |
| **Plan**       | El diff calculado: qué se va a crear/cambiar/destruir antes de tocar nada       |
| **Apply**      | Ejecuta el plan contra la API del provider                                       |

El flujo: se escribe **HCL** → el **provider** traduce a llamadas API → se crean **resources** → Terraform guarda el resultado en el **state**.

### Anatomía de un `resource`

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "xfusion-vpc"
  }
}
#         ▲          ▲
#         │          └── nombre LOCAL (referencia interna en Terraform: aws_vpc.main)
#         └── TIPO de resource (lo define el provider aws)
```

Dos identificadores distintos que conviene no confundir:

- **Nombre local** (`main`): cómo se referencia el resource **dentro** del código Terraform (`aws_vpc.main.id`). No existe en AWS.
- **Tag `Name`** (`xfusion-vpc`): el nombre que aparece **en la consola de AWS**. Es lo que la validación chequea.

> ★ **El gotcha del lab**: la validación busca el tag `Name = "xfusion-vpc"`. Poner `Name = "nautilus-vpc"` (u otro) crea una VPC válida que **falla la validación** — el `apply` tiene éxito pero el requisito no se cumple. Es el mismo patrón "traducir el requisito literal" de los días 65/67/92/93.

### Rangos de IP y CIDR — cómo elegir el bloque de la VPC

El lab dice "any IPv4 CIDR", pero en la práctica el rango **no** es arbitrario. Un bloque CIDR se escribe `red/prefijo`, ej. `10.0.0.0/16`.

**Qué significa el `/N`**: es la cantidad de bits **fijos** (la parte de red). Los bits restantes (`32 - N`) son para hosts. A mayor `/N`, **menos** IPs:

| CIDR  | Bits de host | IPs totales | IPs usables en AWS* | Uso típico                          |
| ----- | ------------ | ----------- | ------------------- | ----------------------------------- |
| `/16` | 16           | 65 536      | 65 531              | VPC grande (lo más común)           |
| `/20` | 12           | 4 096       | 4 091               | VPC mediana / subnet grande         |
| `/24` | 8            | 256         | 251                 | Subnet típica                       |
| `/28` | 4            | 16          | 11                  | Subnet mínima permitida en AWS      |

\* AWS **reserva 5 IPs** por subnet (red, gateway, DNS, futuro, broadcast), por eso "usables" = totales − 5.

Regla mental rápida: cada `+4` en el prefijo **divide** las IPs por 16. `/16` = 65 536 → `/20` = 4 096 → `/24` = 256.

**Restricciones de AWS para el CIDR de una VPC**:

- El prefijo debe estar entre **`/16` (máx, 65 536 IPs) y `/28` (mín, 16 IPs)**. No se puede `/8` ni `/30`.
- AWS **recomienda** usar rangos **privados RFC 1918** (no enrutables en internet):

  | Rango RFC 1918      | CIDR            | Tamaño        |
  | ------------------- | --------------- | ------------- |
  | `10.0.0.0`          | `10.0.0.0/8`    | ~16,7M IPs    |
  | `172.16.0.0`        | `172.16.0.0/12` | ~1M IPs       |
  | `192.168.0.0`       | `192.168.0.0/16`| 65 536 IPs    |

- Técnicamente AWS **acepta** rangos públicos (como el `100.0.0.0/16` del lab), pero es mala práctica: si esas IPs públicas pertenecen a un servicio real de internet, las instancias de la VPC no podrían alcanzarlo (el tráfico se enruta dentro de la VPC). Por eso en producción **siempre RFC 1918**.

**Cómo elegir el rango en la práctica**:

1. **Tamaño**: estimar cuántas IPs hará falta (instancias + subnets + crecimiento). `/16` da margen amplio; es el default seguro.
2. **No solaparse**: el CIDR no debe chocar con otras VPCs, on-premise, o redes con las que se hará **peering/VPN**. Dos redes con CIDRs solapados no pueden enrutar entre sí. Por eso se planifica un esquema (ej. `10.0.0.0/16` para prod, `10.1.0.0/16` para staging).
3. **Dejar espacio para subnets**: la VPC se subdivide luego en subnets (`/24`, `/20`, etc.), una por AZ. El `/16` de la VPC se reparte entre ellas.

### El `provider` — fijar la región en código

```hcl
provider "aws" {
  region = "us-east-1"
}
```

El provider `aws` necesita saber **región** y **credenciales**. En los labs de KodeKloud las credenciales ya vienen por variables de entorno (`AWS_ACCESS_KEY_ID`, etc.) y la región puede venir de `AWS_DEFAULT_REGION`. Por eso un `main.tf` **sin** provider block igual funciona — la región la toma del entorno.

Pero el requisito pide `us-east-1` explícitamente. Fijarla en el `provider` block hace el código **autocontenido y reproducible**: no depende de qué variable de entorno tenga la máquina que corre `terraform`. Y como va en `main.tf`, respeta el "no crear otro `.tf`".

### El state — el corazón de Terraform

Tras `apply`, Terraform escribe `terraform.tfstate`: un JSON que **mapea** cada resource del código al objeto real creado:

```
aws_vpc.main   ↔   vpc-741c865ee3603da53   (+ todos sus atributos)
```

Para qué sirve el state:

- **Saber qué gestiona Terraform**: sin el state, Terraform no sabría que esa VPC es "suya".
- **Calcular diffs**: el próximo `plan` compara código vs state vs realidad, y muestra solo lo que cambió (en vez de recrear todo).
- **Detectar drift**: si alguien cambia algo en la consola de AWS por fuera de Terraform, el `plan` lo detecta como **drift** (deriva). Ahí se decide: incorporar el cambio al código, o dejar que Terraform **sobrescriba** y vuelva al estado declarado.

> El state es sensible (puede contener secretos) y crítico. En equipos se guarda en un **backend remoto** (S3 + DynamoDB lock) en vez del archivo local, para compartirlo y evitar corrupción por escrituras concurrentes.

### El ciclo de trabajo: `init` → `plan` → `apply`

| Comando             | Qué hace                                                                       |
| ------------------- | ------------------------------------------------------------------------------ |
| `terraform init`    | Descarga el provider (aws) e inicializa el directorio. **Obligatorio primero.**|
| `terraform plan`    | Muestra el diff (qué se crearía/cambiaría/destruiría) **sin** aplicar nada     |
| `terraform apply`   | Ejecuta el plan (pide confirmación `yes`); crea/modifica la infra real         |
| `terraform destroy` | Destruye toda la infra gestionada por el state                                 |

`terraform apply` corre un `plan` internamente y lo muestra antes de pedir confirmación — por eso en el output del lab se ve el plan completo seguido del prompt `Enter a value: yes`.

## Pasos

1. Abrir terminal en `/home/bob/terraform` (click derecho en EXPLORER → Open in Integrated Terminal)
2. Crear `main.tf` con el provider (`us-east-1`) y el resource `aws_vpc` (tag `Name = xfusion-vpc`)
3. `terraform init` — inicializar y descargar el provider aws
4. `terraform plan` — revisar el diff
5. `terraform apply` → confirmar con `yes`
6. Verificar el `id` de la VPC creada

## Comandos / Código

### `main.tf` (solución)

```hcl
# /home/bob/terraform/main.tf
provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "xfusion-vpc"
  }
}
```

> El CIDR es libre ("any IPv4 CIDR"). `10.0.0.0/16` es un rango privado RFC 1918 convencional para VPCs (da 65 536 IPs). En el lab se usó `100.0.0.0/16`, que también es válido para una VPC aunque no sea un rango privado clásico.

### Ejecutar el ciclo

```bash
terraform init      # descarga el provider aws (primera vez)
terraform plan      # revisar el diff
terraform apply     # confirmar con 'yes'
```

Output real del primer `apply` (recortado):

```
  # aws_vpc.main will be created
  + resource "aws_vpc" "main" {
      + arn        = (known after apply)
      + cidr_block = "100.0.0.0/16"
      + id         = (known after apply)
      + tags       = {
          + "Name" = "nautilus-vpc"       ← ⚠ debería ser "xfusion-vpc"
        }
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
  Enter a value: yes

aws_vpc.main: Creating...
aws_vpc.main: Creation complete after 0s [id=vpc-741c865ee3603da53]
```

> **`(known after apply)`**: atributos que AWS asigna al crear (como `id`, `arn`). Terraform no los conoce hasta que el recurso existe — por eso no aparecen en el plan.

### ★ Corregir el tag — update in-place, NO recrea

El primer `apply` creó la VPC con `Name = "nautilus-vpc"`, pero el requisito pide `xfusion-vpc`. Al corregir el tag en `main.tf` y volver a `apply`, Terraform **no destruye ni recrea** la VPC: detecta en el `state` que el recurso ya existe y solo **actualiza el tag en sitio** (`~ update in-place`):

```hcl
# main.tf corregido
resource "aws_vpc" "main" {
  cidr_block = "100.0.0.0/16"
  tags = {
    Name = "xfusion-vpc"        # ← era "nautilus-vpc"
  }
}
```

```
  # aws_vpc.main will be updated in-place
  ~ resource "aws_vpc" "main" {
        id   = "vpc-741c865ee3603da53"      ← mismo id: NO se recrea
      ~ tags = {
          ~ "Name" = "nautilus-vpc" -> "xfusion-vpc"
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.       ← 1 to change, no add/destroy
  Enter a value: yes

aws_vpc.main: Modifying... [id=vpc-741c865ee3603da53]
aws_vpc.main: Modifications complete after 1s
```

> Esto es exactamente el poder del **state**: como Terraform sabe que `aws_vpc.main` ↔ `vpc-741c...`, un cambio de tag es un `1 to change` (no `1 to add` + huérfana). El `id` se mantiene. Si se hubiera cambiado el `cidr_block` en cambio, sí sería destroy+create (el CIDR no es modificable en sitio) — por eso conviene revisar siempre el `plan` antes del `yes`.

### Verificación

```bash
# Ver el id y atributos desde el state
terraform show

# O con el CLI de AWS
aws ec2 describe-vpcs --region us-east-1 \
  --filters "Name=tag:Name,Values=xfusion-vpc" \
  --query "Vpcs[].VpcId" --output text
```

## Variantes (referencia)

### VPC con DNS habilitado (común en producción)

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "xfusion-vpc" }
}
```

### Parametrizar con variables

```hcl
variable "vpc_cidr"  { default = "10.0.0.0/16" }
variable "vpc_name"  { default = "xfusion-vpc" }

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = { Name = var.vpc_name }
}
```

### Exponer el id como output

```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}
```

### Fijar versión del provider (buena práctica)

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| La validación falla aunque la VPC se creó                        | El tag `Name` no es `xfusion-vpc` (ej. quedó `nautilus-vpc`)                   | Corregir el tag `Name` y volver a `apply` (Terraform actualiza el tag)         |
| `Error: configuring Terraform AWS Provider: no valid credential` | No hay credenciales en el entorno                                              | Verificar `AWS_ACCESS_KEY_ID`/`SECRET`; en el lab ya vienen seteadas           |
| `Error: Invalid AWS Region`                                      | Región mal escrita o ausente                                                   | `region = "us-east-1"` en el provider block                                    |
| `terraform: command ... Required plugins are not installed`      | No se corrió `terraform init`                                                  | Ejecutar `terraform init` antes de `plan`/`apply`                              |
| `Error: CIDR ... is not a valid CIDR block`                      | Bloque CIDR mal formado                                                        | Usar formato válido, ej. `10.0.0.0/16`                                         |
| El `apply` recrea la VPC en vez de actualizarla                  | Se borró/corrompió `terraform.tfstate`                                         | No borrar el state; usar `terraform import` si se perdió el tracking           |
| Quedó una VPC "huérfana" con el nombre viejo                     | Se creó con un nombre, luego se cambió el local name del resource              | `terraform destroy` lo viejo o limpiar a mano en la consola AWS                |
| `Error: error creating EC2 VPC: VpcLimitExceeded`               | Límite de VPCs por región alcanzado                                            | Borrar VPCs sin uso o pedir aumento de límite                                  |

## Conexión con días anteriores

- **Toda la sección Ansible (82-93)**: Ansible **configura** servidores existentes (paquetes, servicios, archivos). Terraform **crea** la infraestructura donde esos servidores viven. Se complementan: Terraform provisiona la VPC + EC2, Ansible las configura.
- **Declarativo (Días 87, 89)**: `state: present` en Ansible y `resource` en Terraform son el mismo principio — declarar el estado deseado y dejar que la herramienta calcule las acciones. El `plan` de Terraform es como el `--check`/dry-run de Ansible.
- **Idempotencia (Día 84, 87)**: correr `apply` dos veces sin cambios → `0 to add, 0 to change, 0 to destroy`. El state es lo que hace posible esa idempotencia.
- **Patrón "traducir requisito literal" (Días 65, 67, 92, 93)**: el tag `Name` debe ser exactamente `xfusion-vpc` — un `apply` exitoso con otro nombre no cumple el requisito.

## Reflexión: provisioning (Terraform) vs configuration management (Ansible)

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- Terraform crea la infra (VPC, EC2) vs Ansible que la configura: ahora que viste ambos, ¿dónde trazas la línea? ¿Usarías Terraform para instalar httpd o Ansible para crear una VPC? ¿Por qué cada herramienta es mejor en su dominio?
- el state como fuente de verdad: la potencia (diffs, drift) y el riesgo (si se corrompe/borra, Terraform "pierde" la infra). ¿Qué implica que un archivo sea tan crítico? ¿Por qué el backend remoto deja de ser opcional en equipo?
- el apply mostró el plan y pidió confirmación: ese "preview antes de tocar" no existe igual en la consola de AWS. ¿Cómo cambia tu confianza para hacer cambios en producción tener un plan revisable?
- nombre local (main) vs tag Name (xfusion-vpc): dos identificadores para la misma cosa. ¿Confunde tener ambos? ¿Qué pasaría si la validación chequeara el local name en vez del tag?
- declarativo otra vez: tras Ansible, ¿el modelo declarativo ya te resulta natural o todavía piensas en "pasos"? ¿La IaC declarativa escala mejor que scripts imperativos (aws cli en bash) y por qué?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`aws_vpc` resource — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc)
- [AWS provider — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform: state](https://developer.hashicorp.com/terraform/language/state)
- [Terraform CLI: init / plan / apply](https://developer.hashicorp.com/terraform/cli/commands)
- [What is Infrastructure as Code?](https://developer.hashicorp.com/terraform/intro)
