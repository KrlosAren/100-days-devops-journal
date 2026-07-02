# Terraform — Guía de referencia

Terraform es la herramienta de **Infrastructure as Code (IaC)** de HashiCorp: se declara la infraestructura deseada en **HCL** y Terraform calcula y ejecuta las acciones para que la nube coincida. A diferencia de Ansible (configura servidores que ya existen) o Kubernetes (orquesta containers), Terraform **provisiona la infraestructura misma** — VPCs, subnets, instancias, IAM, bases de datos.

Los comandos principales:

```
terraform init       # Descarga providers e inicializa el directorio (obligatorio primero)
terraform plan       # Muestra el diff (crear/cambiar/destruir) SIN aplicar nada
terraform apply      # Ejecuta el plan (pide confirmación 'yes')
terraform destroy    # Destruye toda la infra gestionada por el state
terraform state list # Lista los recursos en el state
terraform output     # Muestra los outputs definidos
terraform fmt        # Formatea los .tf al estilo canónico
terraform validate   # Valida la sintaxis sin tocar la nube
```

Esta guía está organizada en secciones temáticas. Cada una cubre una pregunta operacional que aparece al trabajar con Terraform.

## Índice

| Sección                                    | Cubre                                                                                        |
| ------------------------------------------ | -------------------------------------------------------------------------------------------- |
| [CIDR y redes](cidr.md)                    | Notación CIDR, cálculo `2^(32−N)`, rangos RFC 1918, solapamiento, subnets dentro de VPC       |

> Más secciones se irán agregando a medida que aparezcan los temas en el journal (state remoto, modules, `for_each`/`count`, workspaces, etc.).

## Conceptos fundamentales — vocabulario base

| Término            | Definición                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| **HCL**            | *HashiCorp Configuration Language* — el lenguaje declarativo de los archivos `.tf`               |
| **Provider**       | Plugin que traduce el código a llamadas API de una plataforma (`aws`, `tls`, `local`, `gcp`, …)  |
| **Resource**       | Un objeto de infraestructura que Terraform **crea y gestiona** (`aws_vpc`, `aws_instance`, …)     |
| **Data source**    | Bloque que **lee** infra existente (o genera datos) sin crearla (`data "aws_vpc"`)               |
| **State**          | `terraform.tfstate` — mapea el código a los objetos reales creados; base de diffs e idempotencia |
| **Plan**           | El diff calculado (add/change/destroy) que se muestra antes de aplicar                           |
| **Apply**          | Ejecuta el plan contra la API del provider                                                        |
| **Variable**       | Entrada parametrizable (`variable`), referida con `var.X`; valores en `default`/tfvars/`-var`     |
| **Output**         | Valor expuesto tras el apply (`output`), consultable con `terraform output`                       |
| **Local name**     | El nombre interno de un recurso en el código (`aws_vpc.this`) — no existe en la nube              |
| **Drift**          | Diferencia entre el state y la realidad (cambios hechos por fuera de Terraform)                  |
| **Dependency graph** | El DAG que Terraform arma con las referencias para ordenar y paralelizar la creación           |

## El ciclo de trabajo

```
escribir .tf  →  terraform init  →  terraform plan  →  terraform apply  →  (verificar)  →  terraform plan = "No changes"
```

- `init` descarga los providers referenciados. Obligatorio antes de `plan`/`apply`.
- `apply` corre un `plan` internamente y lo muestra antes de pedir `yes`.
- **Idempotencia**: tras un `apply`, `terraform plan` debe devolver **"No changes. Your infrastructure matches the configuration."** — la definición de "terminado" en IaC (mejor criterio que "el apply pasó").

## Anatomía de un `resource`

```hcl
resource "aws_vpc" "this" {          # TIPO (lo define el provider) + NOMBRE LOCAL (ref interna)
  cidr_block = var.KKE_VPC_CIDR       # argumento (puede referenciar variables u otros recursos)
  tags = { Name = "xfusion-vpc" }     # el tag Name = lo que se ve en la consola AWS
}
# Se referencia: aws_vpc.this.id, aws_vpc.this.arn, aws_vpc.this.tags.Name
```

## Referencias y dependencias

Referenciar un atributo de otro recurso (`aws_subnet.x.id`, `aws_iam_policy.y.arn`) hace dos cosas a la vez:

1. **Usa el valor** (que puede ser `(known after apply)` si el recurso aún no existe).
2. **Crea una dependencia implícita** → Terraform ordena la creación (el referenciado primero).

Para forzar orden sin referencia directa: `depends_on = [otro_recurso]`.

## `(known after apply)` — es ambiguo

En un `plan`, `(known after apply)` puede significar dos cosas distintas — hay que mirar el código para saber cuál:

| Aparece porque…                                                       | ¿Problema? |
| --------------------------------------------------------------------- | ---------- |
| El argumento **no se seteó** en el `.tf`                              | **Sí** — falta el valor (ej. `key_name` olvidado) |
| Referencia un atributo computado (`.id`, `.arn`) de un recurso del mismo apply | No — normal, se resuelve al crear |

## Patrones y lecciones ancladas (Días 94-100)

### "El apply exitoso ≠ resultado correcto"

AWS/IAM aceptan valores que no cumplen el requisito. Un `apply` verde **no** garantiza que se hizo lo pedido:

| Día | El apply pasó, pero…                                                              |
| --- | -------------------------------------------------------------------------------- |
| 94  | el tag `Name` era `nautilus-vpc` en vez de `xfusion-vpc`                          |
| 95  | faltó el argumento `name` → el SG quedó con GroupName autogenerado `terraform-…` |
| 96  | faltó `key_name` → la instancia se creó sin llave (no se puede SSH)              |
| 97  | `ec2:Describe` sin `*` → la policy no concede nada (IAM no valida action names)  |

**Hábito de revisión**: comparar el `state`/`plan` **campo por campo** contra el requisito literal; y usar `terraform plan = "No changes"` como criterio de cierre.

### El "nombre" según el recurso

- **VPC / EC2 / subnet**: no tienen atributo `name` nativo → su nombre visible es el **tag `Name`**.
- **Security group / IAM / key pair**: tienen un `name`/`key_name`/GroupName **nativo** además de tags.
- Regla: leer la doc del recurso para saber **qué campo** es "el nombre".

### Inmutabilidad → replace

Algunos atributos no se pueden modificar in-place; cambiarlos fuerza `-/+` (destroy + create): `name`/`description` de un SG, `key_name` de una instancia, `cidr_block` de una VPC. El `plan` lo marca con `-/+` o "must be replaced" — leerlo antes del `yes`.

### El state es sensible

Secretos (llaves privadas de `tls_private_key`, passwords) se guardan **en texto plano** en `terraform.tfstate`. Por eso: nunca commitear el state, y en equipo usar un **backend remoto cifrado** (S3 + DynamoDB lock).

### Least privilege = scope del `Resource`

En IAM, limitar el `Action` no basta; hay que acotar el `Resource` al ARN concreto (no `"*"`) cuando la acción lo soporta (ej. DynamoDB `GetItem`/`Scan`/`Query` sobre el ARN de la tabla, Día 99).

## Providers vistos en el journal

| Provider | Recursos usados                                                      | Día   |
| -------- | ------------------------------------------------------------------- | ----- |
| `aws`    | `aws_vpc`, `aws_subnet`, `aws_security_group`, `aws_instance`, `aws_key_pair`, `aws_iam_policy`, `aws_iam_role`, `aws_iam_role_policy_attachment`, `aws_dynamodb_table`, `aws_cloudwatch_metric_alarm`, `aws_sns_topic` | 94-100 |
| `tls`    | `tls_private_key` (generar par RSA)                                 | 96    |
| `local`  | `local_file` (guardar el `.pem`)                                    | 96    |

## Recursos

- [Terraform docs](https://developer.hashicorp.com/terraform/docs)
- [AWS provider — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform: state](https://developer.hashicorp.com/terraform/language/state)
- [Input variables / Outputs](https://developer.hashicorp.com/terraform/language/values)
- [Style guide (HCL)](https://developer.hashicorp.com/terraform/language/style)
