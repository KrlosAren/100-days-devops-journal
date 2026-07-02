# Día 98 - Launch EC2 in Private VPC Subnet (multi-file + variables + outputs + red privada)

## Problema / Desafío

El equipo Nautilus necesita una **VPC privada** con una subnet, y una EC2 dentro, accesible **solo desde dentro de la VPC**. Requisitos:

1. VPC **`datacenter-priv-vpc`**, CIDR **`10.0.0.0/16`**
2. Subnet **`datacenter-priv-subnet`** en la VPC, CIDR **`10.0.1.0/24`**, con **auto-assign IP deshabilitado**
3. EC2 **`datacenter-priv-ec2`** dentro de la subnet, tipo **`t2.micro`**
4. El **security group** debe permitir acceso **solo desde el CIDR de la VPC**
5. `main.tf` para VPC + subnet + EC2 (no otro `.tf` para los recursos)
6. **`variables.tf`** con: `KKE_VPC_CIDR`, `KKE_SUBNET_CIDR`
7. **`outputs.tf`** con: `KKE_vpc_name`, `KKE_subnet_name`, `KKE_ec2_private`
8. **`terraform plan` debe devolver "No changes"** antes de entregar

Directorio `/home/bob/terraform`.

> Día 5 de Terraform y el más completo: primer proyecto **multi-archivo** (main + variables + outputs), 4 recursos encadenados, **variables de entrada** y **outputs**, más el requisito explícito de **idempotencia** (`plan` sin cambios).

## Conceptos clave

### Multi-archivo — Terraform carga TODOS los `.tf` del directorio

El requisito separa el código en tres archivos. No hay que "importar" ni enlazarlos: Terraform **concatena automáticamente** todos los `.tf` del directorio de trabajo como si fueran uno solo.

| Archivo        | Convención (qué suele ir)                                    |
| -------------- | ------------------------------------------------------------ |
| `main.tf`      | Los `resource` y `data` (la infra)                           |
| `variables.tf` | Las declaraciones `variable` (entradas)                      |
| `outputs.tf`   | Las declaraciones `output` (salidas)                         |
| `providers.tf` | El bloque `provider` / `terraform { required_providers }`    |

Es **solo organización** — Terraform no distingue por nombre de archivo. Se podría poner todo en `main.tf`; separar mejora la legibilidad y es la convención de la comunidad. El orden entre archivos no importa (el grafo de dependencias decide el orden real, Día 96).

### Variables de entrada — parametrizar el código

Un bloque `variable` declara una **entrada** del módulo, con tipo, descripción y valor por defecto:

```hcl
variable "KKE_VPC_CIDR" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
```

| Campo         | Función                                                                |
| ------------- | ---------------------------------------------------------------------- |
| `type`        | Tipo esperado (`string`, `number`, `bool`, `list`, `map`, `object`)    |
| `default`     | Valor si no se pasa otro (opcional; sin default, es obligatoria)       |
| `description` | Documentación de la variable                                           |

Se referencian con **`var.<nombre>`**:

```hcl
resource "aws_vpc" "this" {
  cidr_block = var.KKE_VPC_CIDR     # ← usa la variable, no el literal
}
```

Ventaja: el CIDR se define **una vez** y se reutiliza (en la VPC y en el ingress del SG). Cambiarlo en un solo lugar afecta todo. Sin default, Terraform lo pediría interactivo o por `-var`/`terraform.tfvars`.

### Outputs — exponer valores después del `apply`

Un bloque `output` publica un valor al terminar el `apply` (y queda consultable con `terraform output`):

```hcl
output "KKE_vpc_name" {
  description = "vpc name"
  value       = aws_vpc.this.tags.Name     # lee el tag Name del recurso
}
```

Para qué sirven los outputs:

- **Mostrar** datos útiles tras aplicar (IPs, IDs, nombres) sin buscarlos en la consola.
- **Pasar valores entre módulos**: el output de un módulo es la entrada de otro.
- **Consumo por scripts/CI**: `terraform output -raw KKE_vpc_name`.

Acá los tres outputs leen el `tags.Name` de cada recurso, que es lo que pide el enunciado ("name of the VPC/subnet/EC2").

### La arquitectura: VPC → subnet → EC2 (red privada)

Los 4 recursos se encadenan por referencias (grafo del Día 96):

```
aws_vpc.this  (10.0.0.0/16)
   │
   ├── aws_subnet.private_subnet  (10.0.1.0/24, dentro del CIDR de la VPC)
   │       │
   │       └── aws_instance.this  (subnet_id → nace en esta subnet)
   │
   └── aws_security_group.priv_sg  (vpc_id → ingress solo desde 10.0.0.0/16)
              │
              └── aws_instance.this  (vpc_security_group_ids)
```

| Recurso       | Referencia clave                          | Efecto                                  |
| ------------- | ----------------------------------------- | --------------------------------------- |
| subnet        | `vpc_id = aws_vpc.this.id`                | la subnet vive en la VPC                |
| instance      | `subnet_id = aws_subnet...id`             | la instancia nace en esa subnet         |
| instance      | `vpc_security_group_ids = [sg.id]`        | aplica el SG privado                    |

### El CIDR de la subnet vive **dentro** del CIDR de la VPC

`10.0.1.0/24` está **contenido** en `10.0.0.0/16` (Día 94: `/16` fija `10.0.x.x`, `/24` fija `10.0.1.x`). Una subnet **debe** ser un sub-rango de su VPC — si el CIDR de la subnet cae fuera del de la VPC, AWS rechaza la creación.

```
VPC    10.0.0.0/16  →  10.0.0.0 – 10.0.255.255   (65 536 IPs)
subnet 10.0.1.0/24  →  10.0.1.0 – 10.0.1.255      (256 IPs, dentro del rango VPC)
```

### `map_public_ip_on_launch = false` — qué hace "privada" a la subnet

```hcl
resource "aws_subnet" "private_subnet" {
  map_public_ip_on_launch = false     # ← "auto-assign IP must not be enabled"
}
```

Este es el punto 2 del lab. Cuando es `false`, las instancias que nacen en la subnet **no reciben una IP pública automática** → no son alcanzables desde internet. Es lo que la consola de AWS llama "Auto-assign public IPv4 address".

> En una subnet **custom** el default ya es `false`, pero dejarlo **explícito** lo hace inequívoco ante el validador. Una subnet con esto en `false` (y sin route a un Internet Gateway) es, de hecho, una **subnet privada**.

### El SG "solo desde dentro de la VPC"

El punto 4 se cumple poniendo el **CIDR de la VPC** como único origen del ingress:

```hcl
ingress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"                  # -1 = todo el tráfico (todos los protocolos)
  cidr_blocks = [var.KKE_VPC_CIDR]    # 10.0.0.0/16 → solo IPs internas de la VPC
}
```

- `protocol = "-1"` + `from_port/to_port = 0`: **todo el tráfico** (no se limita a un puerto).
- `cidr_blocks = [10.0.0.0/16]`: solo responde a IPs **dentro** de la VPC. Nada de `0.0.0.0/0` en entrada → no se expone a internet.

Contraste con el Día 95 (SG con `0.0.0.0/0` en HTTP/SSH, abierto al mundo): hoy el SG es **restringido por diseño**. Reutilizar `var.KKE_VPC_CIDR` garantiza que el SG y la VPC siempre coincidan, aunque cambie el CIDR.

### ★ El requisito de idempotencia: `plan` sin cambios

El lab exige que, tras aplicar, `terraform plan` devuelva:

```
No changes. Your infrastructure matches the configuration.
```

Esto es **la garantía central de la IaC**: el código describe el estado deseado, y si la realidad ya coincide, no hay nada que hacer. Un `plan` "limpio" confirma que:

- No hay **drift** (nadie cambió la infra por fuera).
- El código no tiene cambios pendientes sin aplicar.
- Volver a aplicar es **seguro** (no recrea ni modifica nada).

> Si `plan` mostrara cambios tras un `apply`, sería señal de un problema: un atributo que AWS normaliza distinto a como se escribió, un valor `(known after apply)` que no se estabiliza, o drift real. Para este lab, los 4 recursos quedan estables → `plan` limpio.

### ★ `(known after apply)` ambiguo — referencia vs no-seteado

En el plan de la instancia aparece:

```
subnet_id              = (known after apply)
vpc_security_group_ids = (known after apply)
```

Acá `(known after apply)` **no** significa "no lo seté" (como sí pasaba en el Día 96 con `key_name`). Significa que el valor **referencia el `.id` de un recurso que aún no existe** (`aws_subnet.private_subnet.id`) — Terraform no conoce ese `id` hasta crear la subnet, por eso lo difiere.

| `(known after apply)` aparece porque…       | ¿Es problema? |
| ------------------------------------------- | ------------- |
| El argumento **no se seteó** (Día 96)       | **Sí** — falta el valor |
| Referencia un atributo computado (`.id`, `.arn`) de un recurso que se crea en el mismo apply | No — es normal |

La lección: `(known after apply)` es **ambiguo**. Para distinguir, mirar el código: si el argumento **está** en el `.tf` y referencia un `.id`, es normal; si **no está**, es un olvido.

## Pasos

1. Abrir terminal en `/home/bob/terraform`
2. Crear `variables.tf` (las dos `KKE_*_CIDR`)
3. Crear `main.tf` (VPC + subnet + SG + EC2)
4. Crear `outputs.tf` (los tres `KKE_*`)
5. `terraform init` → `terraform plan` → `terraform apply` → `yes`
6. **Re-correr `terraform plan`** y confirmar "No changes"

## Comandos / Código

### `variables.tf`

```hcl
variable "KKE_VPC_CIDR" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "KKE_SUBNET_CIDR" {
  description = "CIDR block for subnet"
  type        = string
  default     = "10.0.1.0/24"
}
```

### `main.tf`

```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "this" {
  cidr_block = var.KKE_VPC_CIDR
  tags = { Name = "datacenter-priv-vpc" }
}

resource "aws_subnet" "private_subnet" {
  cidr_block              = var.KKE_SUBNET_CIDR
  vpc_id                  = aws_vpc.this.id
  map_public_ip_on_launch = false              # auto-assign IP deshabilitado
  tags = { Name = "datacenter-priv-subnet" }
}

resource "aws_security_group" "priv_sg" {
  name        = "datacenter-priv-sg"
  vpc_id      = aws_vpc.this.id
  description = "allow only within vpc resources"

  ingress {
    description = "allow only inside vpc"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.KKE_VPC_CIDR]           # solo desde dentro de la VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "datacenter-priv-sg" }
}

resource "aws_instance" "this" {
  ami                    = "ami-0c101f26f147fa7fd"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.priv_sg.id]
  tags = { Name = "datacenter-priv-ec2" }
}
```

### `outputs.tf`

```hcl
output "KKE_vpc_name" {
  description = "vpc name"
  value       = aws_vpc.this.tags.Name
}

output "KKE_subnet_name" {
  description = "subnet name"
  value       = aws_subnet.private_subnet.tags.Name
}

output "KKE_ec2_private" {
  description = "ec2 name"                     # (el valor es el Name, como pide el lab)
  value       = aws_instance.this.tags.Name
}
```

### Ejecutar y verificar idempotencia

```bash
terraform init
terraform apply        # 'yes' → 4 to add
terraform plan         # ← debe decir "No changes"
```

Output real del `apply` (recortado):

```
Plan: 4 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + KKE_ec2_private = "datacenter-priv-ec2"
  + KKE_subnet_name = "datacenter-priv-subnet"
  + KKE_vpc_name    = "datacenter-priv-vpc"

aws_vpc.this: Creation complete after 1s [id=vpc-17e69d33...]
aws_subnet.private_subnet: Creation complete after 0s [id=subnet-e9b05e8f...]
aws_security_group.priv_sg: Creation complete after 0s [id=sg-866c6997...]
aws_instance.this: Creation complete after 10s [id=i-c81231af...]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
KKE_ec2_private = "datacenter-priv-ec2"
KKE_subnet_name = "datacenter-priv-subnet"
KKE_vpc_name    = "datacenter-priv-vpc"
```

Verificación de la subnet privada y el state:

```bash
terraform state list
# aws_instance.this
# aws_security_group.priv_sg
# aws_subnet.private_subnet
# aws_vpc.this

terraform state show aws_subnet.private_subnet | grep map_public_ip_on_launch
#     map_public_ip_on_launch = false      ← auto-assign IP deshabilitado ✓

terraform output                            # los tres KKE_*
```

## Variantes (referencia)

### Pasar variables sin default (tfvars)

```hcl
# terraform.tfvars
KKE_VPC_CIDR    = "172.16.0.0/16"
KKE_SUBNET_CIDR = "172.16.1.0/24"
```

```bash
terraform apply                          # toma terraform.tfvars automáticamente
terraform apply -var="KKE_VPC_CIDR=10.5.0.0/16"   # o por flag
```

### Output del ID/IP real (no solo el nombre)

```hcl
output "ec2_private_ip" {
  value = aws_instance.this.private_ip    # la IP privada real, no el tag
}
output "vpc_id" {
  value = aws_vpc.this.id
}
```

### Validación de variables

```hcl
variable "KKE_VPC_CIDR" {
  type = string
  validation {
    condition     = can(cidrhost(var.KKE_VPC_CIDR, 0))
    error_message = "Debe ser un CIDR IPv4 válido."
  }
}
```

### Subnet en una AZ específica

```hcl
resource "aws_subnet" "private_subnet" {
  cidr_block        = var.KKE_SUBNET_CIDR
  vpc_id            = aws_vpc.this.id
  availability_zone = "us-east-1a"
}
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `plan` muestra cambios después del `apply`                       | Drift, o un atributo que AWS normaliza distinto                                | Investigar el diff; re-aplicar; el requisito pide `plan` limpio                |
| `InvalidSubnet.Range: ... not within VPC CIDR`                   | El CIDR de la subnet cae fuera del de la VPC                                    | La subnet debe ser sub-rango de la VPC (`10.0.1.0/24` ⊂ `10.0.0.0/16`)         |
| La instancia recibe IP pública igual                             | `map_public_ip_on_launch = true` o default heredado                            | Ponerlo en `false` explícitamente                                              |
| `Error: ... security group ... another VPC`                      | El SG es de otra VPC distinta a la de la subnet                                | SG e instancia deben estar en la misma VPC (referenciar `aws_vpc.this.id`)     |
| `Reference to undeclared input variable`                         | Se usó `var.X` sin declararlo en `variables.tf`                                | Declarar la `variable` (Terraform lee todos los `.tf`, pero debe existir)      |
| `Error: Output refers to ... undeclared`                         | El output referencia un recurso/atributo que no existe                         | Revisar el path (`aws_vpc.this.tags.Name`)                                     |
| `(known after apply)` en subnet_id y parece error               | Normal: referencia el `.id` de un recurso que se crea en el mismo apply        | No es problema; se resuelve al crear la subnet                                 |
| La variable pide valor interactivo                               | No tiene `default` ni se pasó por tfvars/`-var`                                | Agregar `default`, o un `terraform.tfvars`                                     |

## Conexión con días anteriores

- **Día 94 (CIDR)**: hoy se aplica el "contención de rangos" — la subnet `10.0.1.0/24` debe estar dentro de la VPC `10.0.0.0/16`. El cálculo de rangos del 94 se vuelve un requisito de AWS.
- **Día 95 (SG)**: contraste directo — ahí el SG abría `0.0.0.0/0` (público); hoy restringe al CIDR de la VPC (privado). Mismo recurso, intención opuesta.
- **Día 96 (grafo, `(known after apply)`)**: hoy el grafo encadena 4 recursos; y `(known after apply)` aparece de nuevo, pero esta vez como **referencia válida** (`.id`), no como olvido — el contraste aclara qué significa cada caso.
- **Variables vs Ansible**: las `variable`/`var.X` de Terraform son el equivalente de las variables de inventario / `host_vars` de Ansible (Día 85) — parametrizar el código en vez de hardcodear.

## Reflexión: parametrizar, exponer, y la promesa del "plan sin cambios"

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- el "plan sin cambios" como criterio de aceptación: el lab no pide solo "que exista la infra" sino "que el código y la realidad coincidan exactamente". ¿Por qué es una mejor definición de "terminado" que un apply exitoso? ¿Cómo cambia tu forma de dar algo por completo?
- variables + outputs: separar entradas/lógica/salidas en 3 archivos. ¿Aporta claridad real o es ceremonia para un proyecto chico? ¿A partir de qué tamaño lo agradecerías?
- (known after apply) ambiguo: el mismo texto significó "olvido" en el día 96 y "referencia válida" hoy. ¿Cómo lees el plan ahora para distinguir? ¿Esto cambia tu confianza en el plan como herramienta de revisión?
- "privado" como composición de decisiones: no hay un flag "private=true"; lo privado emerge de map_public_ip_on_launch=false + SG restringido + sin IGW. ¿Te resulta más robusto o más frágil que una sola opción? ¿Qué riesgo hay en que "privado" dependa de varias piezas?
- reutilizar var.KKE_VPC_CIDR en la VPC y en el SG: una sola fuente de verdad para el rango. ¿Es el mismo principio DRY que viste en Ansible? ¿Dónde más lo aplicarías en infra?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`aws_subnet` resource — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet)
- [Input variables — Terraform docs](https://developer.hashicorp.com/terraform/language/values/variables)
- [Output values — Terraform docs](https://developer.hashicorp.com/terraform/language/values/outputs)
- [VPC with public and private subnets — AWS](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Scenario2.html)
- [`aws_instance` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance)
