# Día 99 - Attach IAM Policy for DynamoDB Access (IAM role + trust policy + attachment + least privilege)

## Problema / Desafío

Crear una tabla DynamoDB segura con control de acceso fino vía IAM, para acceso restringido desde servicios AWS de confianza. Con Terraform:

1. **DynamoDB table** `datacenter-table` con configuración mínima
2. **IAM role** `datacenter-role` que podrá acceder a la tabla
3. **IAM policy** `datacenter-readonly-policy` que otorgue acceso **solo lectura** (`GetItem`, `Scan`, `Query`) a **esa tabla específica**, y **adjuntarla** al role
4. `main.tf` para table + role + policy (no otro `.tf` de recursos)
5. **`variables.tf`**: `KKE_TABLE_NAME`, `KKE_ROLE_NAME`, `KKE_POLICY_NAME`
6. **`outputs.tf`**: `kke_dynamodb_table`, `kke_iam_role_name`, `kke_iam_policy_name`
7. Definir los valores en **`terraform.tfvars`**
8. `terraform plan` debe devolver **"No changes"** antes de entregar

Directorio `/home/bob/terraform`.

> Cierra el arco de IAM: el Día 97 creó una policy **suelta** (nunca adjuntada, `attachment_count = 0`). Hoy aparecen las piezas que faltaban — un **role** con su **trust policy**, y el **attachment** que conecta policy ↔ role — más **least privilege** real (scope al ARN de la tabla).

## Conceptos clave

### DynamoDB — tabla NoSQL con configuración mínima

DynamoDB es la base NoSQL gestionada de AWS (clave-valor / documentos). Lo mínimo para una tabla:

```hcl
resource "aws_dynamodb_table" "this" {
  name         = var.KKE_TABLE_NAME
  billing_mode = "PAY_PER_REQUEST"   # ← minimal: sin read/write capacity
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"                       # S=String, N=Number, B=Binary
  }
}
```

| Campo          | Función                                                                    |
| -------------- | ------------------------------------------------------------------------- |
| `hash_key`     | La **partition key** (clave primaria); obligatoria                        |
| `attribute`    | Declara el **tipo** de cada key usada (solo las keys, no todos los campos)|
| `billing_mode` | `PAY_PER_REQUEST` (on-demand, sin capacity) o `PROVISIONED` (con capacity)|

> Con `PROVISIONED` habría que declarar `read_capacity`/`write_capacity`. `PAY_PER_REQUEST` es lo más simple y encaja con "minimal configuration". DynamoDB es **schemaless** salvo las keys: solo se declara el `attribute` de las claves, no de los demás campos.

### IAM role vs policy suelta (Día 97) — el role necesita una trust policy

Un **role** es una identidad que otras entidades **asumen** temporalmente (un servicio AWS, una instancia EC2, otra cuenta). A diferencia de un user, no tiene credenciales fijas. Todo role necesita una **trust policy** (`assume_role_policy`): define **quién puede asumirlo**.

```hcl
resource "aws_iam_role" "this" {
  name = var.KKE_ROLE_NAME

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }   # ← quién puede "ponerse" el role
    }]
  })
}
```

### ★ Las dos policies de un role — dos preguntas distintas

Este es el concepto central del día. Un role tiene **dos** tipos de policy que responden cosas diferentes:

| Policy                      | Responde                                  | Dónde vive                        |
| --------------------------- | ----------------------------------------- | --------------------------------- |
| **Trust policy** (`assume_role_policy`) | ¿**quién** puede asumir el role?    | Dentro del `aws_iam_role`         |
| **Permission policy** (adjunta)         | ¿**qué** puede hacer el role?       | `aws_iam_policy` + attachment     |

`sts:AssumeRole` en la trust policy = "el principal indicado puede ponerse este sombrero". La policy adjunta = "lo que el sombrero permite hacer". Son independientes: se puede poder asumir un role que no permite nada, o tener permisos definidos que nadie puede asumir.

### El attachment — la pieza que faltaba en el Día 97

La `aws_iam_policy` por sí sola **no hace nada** (Día 97: `attachment_count = 0`). El recurso de **attachment** la conecta a un role:

```hcl
resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}
```

| Recurso de attachment              | Adjunta una policy a…          |
| ---------------------------------- | ------------------------------ |
| `aws_iam_role_policy_attachment`   | un **role** (hoy)              |
| `aws_iam_user_policy_attachment`   | un user                        |
| `aws_iam_group_policy_attachment`  | un group                       |
| `aws_iam_policy_attachment`        | varios a la vez (evitar; conflictos)|

### ★ Least privilege — scope al `Resource`, no solo al `Action`

El requisito pide "solo lectura" **y** "restringido a esa tabla específica". Eso son dos dimensiones:

- **Action** limitado a lectura: `dynamodb:GetItem`, `dynamodb:Scan`, `dynamodb:Query` (no `PutItem`, `DeleteItem`, ni `dynamodb:*`).
- **Resource** limitado a la tabla: el **ARN** de `datacenter-table`, no `"*"`.

```
Resource = aws_dynamodb_table.this.arn    # NO "*"
```

Contraste directo con el Día 97, donde `ec2:Describe*` iba con `Resource = "*"` (las acciones Describe no soportan resource-level). Aquí las acciones de DynamoDB **sí** son resource-level, así que el least privilege exige apuntar al ARN concreto. Referenciar `aws_dynamodb_table.this.arn` además crea la dependencia (la tabla se crea antes que la policy).

### `terraform.tfvars` — valores separados de las declaraciones

El Día 98 usó `default` en cada variable. Hoy el lab pide los valores en **`terraform.tfvars`**, un archivo que Terraform **carga automáticamente**:

```hcl
# variables.tf → DECLARA (nombre, tipo)     |  terraform.tfvars → ASIGNA (valor)
variable "KKE_TABLE_NAME" { type = string } |  KKE_TABLE_NAME = "datacenter-table"
```

Precedencia de valores (de mayor a menor): `-var` en CLI → `*.tfvars` → `default` en la declaración. Separar declaración (`variables.tf`) de valores (`terraform.tfvars`) permite el mismo código con distintos valores por entorno (dev/prod), y mantener `terraform.tfvars` fuera de git si trae datos sensibles.

## Pasos

1. Abrir terminal en `/home/bob/terraform`
2. `variables.tf` (las tres `KKE_*`, sin default)
3. `terraform.tfvars` (los valores)
4. `main.tf` (table + role + policy + attachment)
5. `outputs.tf` (los tres `kke_*`)
6. `terraform init` → `plan` → `apply` → `yes`
7. Re-correr `terraform plan` → confirmar "No changes"

## Comandos / Código

### `variables.tf`

```hcl
variable "KKE_TABLE_NAME" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "KKE_ROLE_NAME" {
  description = "Name of the IAM role"
  type        = string
}

variable "KKE_POLICY_NAME" {
  description = "Name of the IAM policy"
  type        = string
}
```

### `terraform.tfvars`

```hcl
KKE_TABLE_NAME  = "datacenter-table"
KKE_ROLE_NAME   = "datacenter-role"
KKE_POLICY_NAME = "datacenter-readonly-policy"
```

### `outputs.tf`

```hcl
output "kke_dynamodb_table" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.this.name
}

output "kke_iam_role_name" {
  description = "IAM role name"
  value       = aws_iam_role.this.name
}

output "kke_iam_policy_name" {
  description = "IAM policy name"
  value       = aws_iam_policy.this.name
}
```

### `main.tf`

```hcl
provider "aws" {
  region = "us-east-1"
}

# --- DynamoDB table (minimal) ---
resource "aws_dynamodb_table" "this" {
  name         = var.KKE_TABLE_NAME
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# --- IAM role + trust policy (quién puede asumirlo) ---
resource "aws_iam_role" "this" {
  name = var.KKE_ROLE_NAME

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# --- IAM policy: read-only, scoped a la tabla ---
resource "aws_iam_policy" "this" {
  name        = var.KKE_POLICY_NAME
  description = "Read-only access to the datacenter DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:Query",
      ]
      Resource = aws_dynamodb_table.this.arn   # scoped a la tabla, NO "*"
    }]
  })
}

# --- Attachment: conecta la policy al role ---
resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}
```

### Ejecutar y verificar idempotencia

```bash
terraform init
terraform apply        # 'yes' → 4 to add
terraform plan         # ← debe decir "No changes"
```

Output esperado del `apply` (resumen):

```
Plan: 4 to add, 0 to change, 0 to destroy.
...
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
kke_dynamodb_table = "datacenter-table"
kke_iam_role_name  = "datacenter-role"
kke_iam_policy_name = "datacenter-readonly-policy"
```

Verificación:

```bash
terraform state list
# aws_dynamodb_table.this
# aws_iam_policy.this
# aws_iam_role.this
# aws_iam_role_policy_attachment.this

# La policy adjunta al role
aws iam list-attached-role-policies --role-name datacenter-role
# Debe listar datacenter-readonly-policy

# El documento de la policy (confirmar actions + Resource = ARN de la tabla)
terraform state show aws_iam_policy.this
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `plan` muestra cambios tras el `apply`                          | Drift, o un valor que no se estabiliza                                          | El requisito pide `plan` limpio; investigar el diff                            |
| La policy permite más de lo pedido                              | `dynamodb:*` o `Resource = "*"` en vez de scope                                | Solo `GetItem`/`Scan`/`Query` + `Resource = aws_dynamodb_table.this.arn`       |
| `MalformedPolicyDocument`                                        | JSON de la policy mal armado                                                    | Usar `jsonencode({...})` (valida estructura)                                   |
| El role no puede ser asumido                                    | Falta o está mal la `assume_role_policy` (trust)                               | Trust policy con `sts:AssumeRole` + el `Principal` correcto                    |
| La policy no aplica al role                                     | Falta el `aws_iam_role_policy_attachment`                                       | Agregar el attachment (policy suelta no hace nada, como Día 97)                |
| `no value for required variable`                                | Falta el valor en `terraform.tfvars` (variables sin `default`)                 | Definir las tres `KKE_*` en `terraform.tfvars`                                 |
| `attribute ... not defined` en la tabla                        | Se usó un `hash_key` sin su bloque `attribute`                                 | Declarar el `attribute` de cada key usada                                      |

## Conexión con días anteriores

- **Día 97 (IAM policy suelta)**: hoy se completa el arco — ahí la policy quedó sin adjuntar (`attachment_count = 0`); hoy aparecen el **role** y el **attachment** que la conectan. Además, least privilege real: `Resource` = ARN de la tabla, no `"*"`.
- **Día 98 (multi-file, variables, outputs, idempotencia)**: misma estructura de proyecto; hoy se suma **`terraform.tfvars`** (valores separados de las declaraciones) y mismo requisito de `plan` limpio.
- **Día 96 (grafo de dependencias)**: `Resource = aws_dynamodb_table.this.arn` y `policy_arn = aws_iam_policy.this.arn` crean el orden table → policy → attachment implícitamente.
- **Ansible (Día 90 ACLs)**: el mismo principio de "acceso fino a un recurso específico" — allá ACLs POSIX sobre un archivo, hoy IAM least-privilege sobre una tabla.

## Recursos

- [`aws_dynamodb_table` resource — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table)
- [`aws_iam_role` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role)
- [`aws_iam_role_policy_attachment` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment)
- [IAM roles vs policies — AWS docs](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html)
- [Actions/resources/condition keys for DynamoDB](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazondynamodb.html)
