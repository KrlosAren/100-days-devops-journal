# Día 97 - Create IAM Policy Using Terraform (IAM + policy document + JSON policy language)

## Problema / Desafío

IAM (Identity and Access Management) es de lo primero que se configura en AWS. La tarea:

- Crear una **IAM policy** llamada **`iampolicy_james`** en `us-east-1` con Terraform.
- Debe permitir **acceso de solo lectura a la consola EC2**: ver todas las **instancias**, **AMIs** y **snapshots**.

Directorio `/home/bob/terraform`. Crear `main.tf` (no otro `.tf`).

> Día 4 de Terraform. Introduce **IAM** (el servicio de permisos de AWS), el **lenguaje JSON de policies**, y el patrón **`aws_iam_policy_document`** para generar ese JSON de forma validada.

## Conceptos clave

### IAM — quién puede hacer qué en AWS

IAM controla el acceso a todos los recursos de AWS. Sus piezas:

| Recurso IAM | Qué es                                                              |
| ----------- | ------------------------------------------------------------------ |
| **User**    | Una identidad (persona o app) con credenciales                     |
| **Group**   | Conjunto de users que comparten permisos                           |
| **Role**    | Identidad asumible temporalmente (por servicios, otras cuentas)    |
| **Policy**  | Documento JSON que **define los permisos** (allow/deny)            |

Una **policy** por sí sola no hace nada hasta que se **adjunta** a un user, group o role. La de hoy es una **managed policy standalone** (existe sola, lista para adjuntar). El state lo muestra: `attachment_count = 0` — creada pero aún no asignada a nadie.

### IAM es global, pero el provider necesita región

IAM **no es regional**: una policy existe a nivel de cuenta, no de región. Su ARN lo confirma — no lleva región:

```
arn:aws:iam::000000000000:policy/iampolicy_james
#          ▲ sin región (compárese con un SG: arn:aws:ec2:us-east-1:...)
```

Aun así se fija `region = "us-east-1"` en el provider porque:

1. El enunciado lo pide.
2. El **provider** necesita una región para autenticar las llamadas a la API, aunque el recurso IAM no sea regional.

### Anatomía de una IAM policy (lenguaje JSON)

Una policy es un documento JSON con una estructura fija:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Ec2ReadOnlyConsole",
      "Effect": "Allow",
      "Action": "ec2:Describe*",
      "Resource": "*"
    }
  ]
}
```

| Campo       | Función                                                                       |
| ----------- | ----------------------------------------------------------------------------- |
| `Version`   | Versión del lenguaje de policy (siempre `2012-10-17`, no es una fecha real)   |
| `Statement` | Lista de reglas (cada una un permiso)                                         |
| `Sid`       | *Statement ID* — etiqueta opcional para identificar la regla                  |
| `Effect`    | `Allow` o `Deny`                                                              |
| `Action`    | Las operaciones permitidas (`servicio:Operacion`, admite wildcard `*`)        |
| `Resource`  | A qué recursos aplica (ARN o `*` = todos)                                     |

### ★ El gotcha del día: `ec2:Describe*` (con wildcard), no `ec2:Describe`

El requisito pide "ver instancias, AMIs y snapshots". Esas son operaciones distintas:

- `ec2:DescribeInstances` → instancias
- `ec2:DescribeImages` → AMIs
- `ec2:DescribeSnapshots` → snapshots
- …y muchas más (`DescribeVolumes`, `DescribeSecurityGroups`, etc.)

El wildcard **`ec2:Describe*`** las cubre **todas** con una sola entrada — es exactamente la acción que usa AWS en su policy de ejemplo "read-only access to the EC2 console".

> **El error de este lab**: la `main.tf` aplicada usó `"ec2:Describe"` **sin** el asterisco. Pero **no existe** una acción llamada literalmente `ec2:Describe` — sin el `*`, el string no matchea **ninguna** operación. La policy se crea (IAM **no valida** que los nombres de acción existan), pero **no concede nada**. El state lo delata:
>
> ```
> Action = "ec2:Describe"      ← sin *, no matchea nada → policy vacía en la práctica
> ```
>
> La solución: `actions = ["ec2:Describe*"]`. IAM acepta cualquier string en `Action`, así que el `apply` exitoso **no garantiza** que la policy funcione — hay que poner la acción correcta.

### Por qué `resources = ["*"]`

Las acciones `ec2:Describe*` **no soportan permisos a nivel de recurso** — son operaciones de listado/lectura que devuelven conjuntos, no actúan sobre un ARN específico. Por eso van con `Resource = "*"`. Ponerle un ARN concreto (ej. una instancia específica) haría que la policy **no funcione** (AWS la ignora o falla). Es una característica de las acciones `Describe`, documentada por servicio en la *Service Authorization Reference* de AWS.

### El patrón `aws_iam_policy_document` + `.json`

En vez de escribir el JSON a mano, se usa un **data source** que lo construye en HCL y lo **valida en `plan`**:

```hcl
data "aws_iam_policy_document" "ec2_readonly" {
  statement {
    sid       = "Ec2ReadOnlyConsole"
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "iampolicyjames" {
  name   = "iampolicy_james"
  policy = data.aws_iam_policy_document.ec2_readonly.json   # ← .json renderiza a string
}
```

Ventajas sobre escribir JSON crudo:

- **Validación en `plan`**: si la estructura está mal, Terraform falla antes de aplicar.
- **Legible y componible**: múltiples `statement {}`, condiciones, principals, sin pelear con comas y comillas del JSON.

### ★ El error `.json` — object vs string

Primer intento del lab (real):

```
Error: Incorrect attribute value type
  policy = data.aws_iam_policy_document.ec2_readonly
  │ ... is object with 10 attributes
  │ Inappropriate value for attribute "policy": string required.
```

Causa: `data.aws_iam_policy_document.ec2_readonly` es un **objeto** (tiene varios atributos: `json`, `id`, etc.). El argumento `policy` de `aws_iam_policy` espera un **string** (el JSON renderizado). La solución es el atributo **`.json`**, que devuelve el documento como string:

```hcl
policy = data.aws_iam_policy_document.ec2_readonly.json
#                                                   ▲ el atributo que renderiza a JSON string
```

Esto refuerza un patrón general de Terraform: un data source/resource es un objeto; para usar un valor concreto se accede a **un atributo** suyo (`.json`, `.id`, `.arn`, `.key_name`…), no al objeto entero.

## Pasos

1. Abrir terminal en `/home/bob/terraform`
2. Escribir `main.tf`: provider + `data "aws_iam_policy_document"` (con `ec2:Describe*`) + `resource "aws_iam_policy"` (con `.policy = ....json`)
3. `terraform init`
4. `terraform plan` — revisar el JSON renderizado
5. `terraform apply` → `yes`
6. Verificar con `terraform state show`

## Comandos / Código

### `main.tf` (solución corregida)

```hcl
# /home/bob/terraform/main.tf
provider "aws" {
  region = "us-east-1"
}

data "aws_iam_policy_document" "ec2_readonly" {
  statement {
    sid       = "Ec2ReadOnlyConsole"
    effect    = "Allow"
    actions   = ["ec2:Describe*"]      # ← con wildcard: cubre instancias, AMIs, snapshots
    resources = ["*"]
  }
}

resource "aws_iam_policy" "iampolicyjames" {
  name        = "iampolicy_james"
  description = "Allow EC2 describe (read-only console)"
  policy      = data.aws_iam_policy_document.ec2_readonly.json   # ← .json = string
}
```

> **Dos diferencias con el primer intento**:
> 1. `policy = ....json` (no el objeto pelado) — resolvió el `Error: string required`.
> 2. `actions = ["ec2:Describe*"]` (con `*`) — sin el asterisco la policy no concede nada.

### Ejecutar

```bash
terraform init
terraform plan
terraform apply     # confirmar con 'yes'
```

Output real del `apply` (recortado):

```
  # aws_iam_policy.iampolicyjames will be created
  + resource "aws_iam_policy" "iampolicyjames" {
      + name   = "iampolicy_james"
      + policy = jsonencode({
            Statement = [{
                Action   = "ec2:Describe*"
                Effect   = "Allow"
                Resource = "*"
                Sid      = "Ec2ReadOnlyConsole"
            }]
            Version = "2012-10-17"
        })
    }

Plan: 1 to add, 0 to change, 0 to destroy.
  Enter a value: yes

aws_iam_policy.iampolicyjames: Creation complete after 1s [id=arn:aws:iam::000000000000:policy/iampolicy_james]
```

> En el plan, Terraform muestra la policy como `jsonencode({...})` — su forma de renderizar el JSON del data source. `Version = "2012-10-17"` lo agrega el data source automáticamente.

### Verificación

```bash
# Desde el state
terraform state show aws_iam_policy.iampolicyjames

# Con el CLI de AWS — ver la policy y su documento
aws iam get-policy --policy-arn arn:aws:iam::<account>:policy/iampolicy_james
aws iam get-policy-version \
  --policy-arn arn:aws:iam::<account>:policy/iampolicy_james \
  --version-id v1 --query "PolicyVersion.Document"
```

## Variantes (referencia)

### JSON inline con `jsonencode` (sin data source)

```hcl
resource "aws_iam_policy" "iampolicyjames" {
  name = "iampolicy_james"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "Ec2ReadOnlyConsole"
      Effect   = "Allow"
      Action   = "ec2:Describe*"
      Resource = "*"
    }]
  })
}
```

### JSON crudo con heredoc

```hcl
resource "aws_iam_policy" "iampolicyjames" {
  name   = "iampolicy_james"
  policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Sid": "Ec2ReadOnlyConsole",
        "Effect": "Allow",
        "Action": "ec2:Describe*",
        "Resource": "*"
      }]
    }
  EOT
}
```

> Las tres formas (data source / `jsonencode` / heredoc) producen lo mismo. El data source valida en `plan`; `jsonencode` es conciso y type-safe; el heredoc es JSON literal (sin validación de estructura por Terraform).

### Adjuntar la policy a un user

```hcl
resource "aws_iam_user_policy_attachment" "james" {
  user       = aws_iam_user.james.name
  policy_arn = aws_iam_policy.iampolicyjames.arn
}
```

### Usar la AWS managed policy en vez de una custom

```hcl
# AWS ya provee una read-only de EC2 lista para usar
data "aws_iam_policy" "ec2_readonly" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| La policy no concede acceso aunque se creó                       | `Action = "ec2:Describe"` sin `*` → no matchea ninguna acción                  | Usar `actions = ["ec2:Describe*"]` (con wildcard)                              |
| `Error: ... policy: string required` (object)                   | Se pasó el objeto `data....` en vez de su atributo string                      | Usar `data.aws_iam_policy_document.x.json`                                     |
| `MalformedPolicyDocument` al aplicar JSON crudo                  | JSON inválido (coma, comilla, campo mal)                                       | Usar `aws_iam_policy_document` o `jsonencode` (validan estructura)            |
| `Resource ... not supported` / la policy no funciona            | Se puso un ARN específico en acciones `Describe*` que no soportan recurso      | `resources = ["*"]` para acciones de listado                                   |
| `EntityAlreadyExists: policy iampolicy_james already exists`     | Ya existe una policy con ese nombre                                            | Borrar la vieja o usar otro nombre; los nombres de policy son únicos por cuenta|
| `Error: No valid credential sources found`                       | Falta región/credenciales en el provider                                      | `region = "us-east-1"` aunque IAM sea global; verificar credenciales          |
| Cambiar la policy crea una nueva versión inesperada             | IAM versiona los documentos de policy                                          | Normal; AWS guarda hasta 5 versiones, Terraform gestiona la default           |

## Conexión con días anteriores

- **Días 95-96 (data sources)**: hoy el data source `aws_iam_policy_document` **no lee** infra existente — **genera** un documento. Es un data source "computacional" (transforma datos), distinto del `aws_vpc`/`aws_security_group` que consultaban AWS.
- **Día 96 (acceder a un atributo)**: el error `.json` es el mismo principio que `aws_key_pair.xfusion_kp.key_name` — un recurso/data es un objeto; se usa **un atributo** suyo, no el objeto entero.
- **Patrón "nota correcta, artefacto con gap" (Días 95, 96, 97)**: tercer lab seguido donde la nota describe la solución correcta (`ec2:Describe*`) pero el `main.tf` aplicado tiene una omisión (faltó el `*`). Releer el state/plan antes de dar por bueno.
- **Ansible (Días 90 ACLs, sudoers)**: en Ansible se daban permisos a nivel de SO (ACLs, sudo); IAM es el equivalente en la capa de la nube — permisos declarados como documento.

## Reflexión: permisos como documento y "el apply exitoso no garantiza correctitud"

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- ec2:Describe vs ec2:Describe*: IAM aceptó un Action que no concede nada, sin error. Es el caso más claro hasta ahora de "apply exitoso ≠ resultado correcto". ¿Cómo verificarías que una policy realmente funciona (simulador de políticas, probar con un user de prueba)? ¿Confiar en el plan basta?
- aws_iam_policy_document vs jsonencode vs heredoc: tres formas del mismo JSON. ¿Cuál adoptarías como estándar y por qué? ¿La validación en plan del data source vale la verbosidad extra, o jsonencode es el punto justo?
- least privilege: el lab pide Describe* + Resource *. ¿Es realmente "read-only seguro" o ya es amplio? ¿Dónde está la tensión entre cumplir el requisito y el principio de menor privilegio?
- custom policy vs AWS managed (AmazonEC2ReadOnlyAccess): AWS ya tiene una read-only lista. ¿Cuándo escribir una propia vs usar la managed? ¿Qué se gana y qué se pierde con cada una?
- el patrón que se repite (95 name, 96 key_name, 97 Describe*): un token chico que falta y rompe el requisito aunque el apply pase. ¿Qué hábito de revisión adoptarías para cazarlos antes (leer el plan campo por campo, diff contra el requisito)?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`aws_iam_policy` resource — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy)
- [`aws_iam_policy_document` data source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document)
- [IAM JSON policy elements reference — AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements.html)
- [Actions, resources, and condition keys for EC2](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonec2.html)
- [AWS managed policy: AmazonEC2ReadOnlyAccess](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEC2ReadOnlyAccess.html)
