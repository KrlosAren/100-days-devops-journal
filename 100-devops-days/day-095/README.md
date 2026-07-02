# Día 95 - Create Security Group Using Terraform (data sources + ingress + `name` vs tag `Name`)

## Problema / Desafío

Segundo paso de la migración a AWS: crear un **security group** en la **default VPC** con Terraform. Requisitos:

1. El **nombre** del security group debe ser **`nautilus-sg`**
2. La **descripción** debe ser **`Security group for Nautilus App Servers`**
3. Regla de entrada (inbound) tipo **HTTP**, puerto **80**, source CIDR **`0.0.0.0/0`**
4. Otra regla de entrada tipo **SSH**, puerto **22**, source CIDR **`0.0.0.0/0`**

Región `us-east-1`. Directorio `/home/bob/terraform`. Crear `main.tf` (no otro `.tf`).

> Día 2 de Terraform. Introduce dos conceptos nuevos: **data sources** (leer infra existente, no crearla) y las **reglas `ingress`** de un security group. Y esconde un gotcha clave sobre qué es "el nombre" de un security group.

## Conceptos clave

### `data` source — leer infraestructura existente (no crearla)

Hasta ahora se usó `resource` (crea cosas). Un **`data` source** hace lo opuesto: **consulta** infraestructura que ya existe (creada por fuera, o en otro lugar) para usar sus atributos:

```hcl
data "aws_vpc" "default" {
  default = true          # ← filtro: la VPC marcada como default de la cuenta
}
```

| Bloque       | Qué hace                                  | Modifica infra |
| ------------ | ----------------------------------------- | -------------- |
| `resource`   | **Crea/gestiona** un objeto               | **Sí**         |
| `data`       | **Lee** un objeto existente (solo lectura)| No             |

El security group necesita saber en qué VPC vivir. Como la default VPC **ya existe** (AWS la crea por cuenta/región), no se crea — se **lee** con un data source y se referencia su `id`:

```hcl
vpc_id = data.aws_vpc.default.id
#        └── sintaxis: data.<tipo>.<nombre_local>.<atributo>
```

En el `plan` esto se ve como `data.aws_vpc.default: Reading...` → `Read complete [id=vpc-19c0...]`. La lectura ocurre **antes** de calcular el plan, porque Terraform necesita ese `id` para armar el resto.

### Qué es un security group — firewall virtual stateful

Un security group (SG) es un **firewall a nivel de instancia** en AWS. Controla qué tráfico entra (`ingress`) y sale (`egress`):

| Característica        | Comportamiento                                                              |
| -------------------- | -------------------------------------------------------------------------- |
| **Stateful**         | Si se permite el tráfico de entrada, la **respuesta sale automáticamente** (no hace falta regla de egress para la respuesta) |
| **Allow-only**       | Solo se definen reglas de **permitir**; todo lo no permitido se **deniega** por defecto |
| **Default egress**   | AWS agrega por defecto una regla que permite **todo el tráfico saliente**   |
| Asociable            | Una instancia puede tener varios SGs; un SG sirve a muchas instancias       |

### ★ El gotcha del día: `name` vs tag `Name`

El requisito (1) dice "el **nombre** debe ser `nautilus-sg`". Acá hay dos cosas distintas que se llaman parecido:

```hcl
resource "aws_security_group" "nautilus_sg" {
  name = "nautilus-sg"              # ← el GroupName REAL de AWS (lo que pide el lab)
  tags = { Name = "nautilus-sg" }   # ← un tag, distinto del name
}
```

| Atributo     | Qué es                                                      | ¿Lo valida el lab? |
| ------------ | ---------------------------------------------------------- | ------------------ |
| `name`       | El **GroupName** real del SG en AWS (atributo nativo)      | **Sí** (requisito 1)|
| `tags.Name`  | Una etiqueta más, opcional                                  | No (es extra)      |

> **El error de este lab**: si se pone **solo** el tag `Name` y se omite el argumento `name`, Terraform **autogenera** un nombre aleatorio. El state lo delata:
>
> ```
> name        = "terraform-20260627160515863400000001"   ← autogenerado!
> name_prefix = "terraform-"
> tags        = { "Name" = "nautilus-sg" }                ← solo el tag
> ```
>
> El SG se creó, pero su `name` real **no** es `nautilus-sg` → la validación falla. La solución: agregar `name = "nautilus-sg"` al resource.

### ★ Contraste con el Día 94: cuándo el tag SÍ es el nombre

Esto es **lo opuesto** del Día 94 (VPC):

| Recurso        | ¿Tiene atributo `name` nativo? | Qué chequea la validación |
| -------------- | ------------------------------ | ------------------------- |
| `aws_vpc`      | **No** — solo tags             | el tag `Name`             |
| `aws_security_group` | **Sí** — `name`/GroupName | el argumento `name`       |

Una VPC no tiene un campo "nombre" propio; su identidad visible **es** el tag `Name`. Un security group **sí** tiene un `name` (GroupName) además de los tags. Misma palabra, mecanismo distinto según el recurso. Lección: leer la doc del recurso para saber **qué campo** es "el nombre".

> Además, `name` en un SG es **inmutable**: cambiarlo en un SG existente fuerza un **replace** (`-/+`, destruye y recrea con nuevo `sg-id`), no un update in-place como el tag de la VPC del Día 94.

### Las reglas `ingress` — `type` es azúcar visual

La consola de AWS muestra "Type: HTTP/SSH", pero eso es solo presentación. En Terraform una regla se define por **protocolo + rango de puertos**:

```hcl
ingress {
  description = "HTTP"
  from_port   = 80          # ← inicio del rango de puertos
  to_port     = 80          # ← fin del rango (igual = un solo puerto)
  protocol    = "tcp"       # ← "HTTP" en realidad es TCP/80
  cidr_blocks = ["0.0.0.0/0"]
}
```

| Campo         | Función                                                                 |
| ------------- | ---------------------------------------------------------------------- |
| `from_port`   | Puerto inicial del rango                                                |
| `to_port`     | Puerto final (`from_port == to_port` → un único puerto)               |
| `protocol`    | `tcp`, `udp`, `icmp`, o `-1` (todos)                                   |
| `cidr_blocks` | Lista de orígenes permitidos (IPv4)                                    |

"HTTP" = TCP puerto 80; "SSH" = TCP puerto 22. El `type` de la consola se traduce a esa combinación. Para un rango real se usaría `from_port = 8000`, `to_port = 8100`.

### ⚠ `0.0.0.0/0` — abrir al mundo entero

`0.0.0.0/0` significa **cualquier IP de internet** (el CIDR que engloba todo, prefijo `/0` = 0 bits fijos, Día 94). El lab lo pide para ambas reglas, pero en producción:

- **HTTP (80) desde `0.0.0.0/0`**: razonable para un servidor web público.
- **SSH (22) desde `0.0.0.0/0`**: **anti-patrón de seguridad** — expone SSH a toda internet (escaneos, fuerza bruta). En producción se restringe a la IP de la oficina/VPN (ej. `203.0.113.0/24`) o se usa un bastion host / SSM Session Manager.

Para el lab se cumple el requisito literal; en la reflexión vale pensar el costo de seguridad.

### `egress` con reglas inline — el gotcha silencioso

Cuando se definen reglas `ingress` **inline** (dentro del resource) y **no** se declara `egress`, según la versión del provider Terraform puede **remover la regla default de egress** (allow-all saliente) que AWS agrega. Resultado: las instancias no podrían hacer conexiones salientes.

Para evitar sorpresas, declarar el egress explícito:

```hcl
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"          # -1 = todos los protocolos
  cidr_blocks = ["0.0.0.0/0"]
}
```

En este lab el `plan` mostró `egress = (known after apply)`, así que AWS gestionó el default; aun así, declararlo es la práctica robusta.

## Pasos

1. Abrir terminal en `/home/bob/terraform`
2. Escribir `main.tf`: `data "aws_vpc" "default"` + `resource "aws_security_group"` con `name`, `description`, dos `ingress`
3. `terraform init` (si es la primera vez en el dir)
4. `terraform plan` — revisar el diff (incluye `data ... Reading`)
5. `terraform apply` → `yes`
6. Verificar con `terraform state show`

## Comandos / Código

### `main.tf` (solución corregida)

```hcl
# /home/bob/terraform/main.tf
provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "nautilus_sg" {
  name        = "nautilus-sg"                              # ← requisito (1): el name REAL
  description = "Security group for Nautilus App Servers"  # ← requisito (2)
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nautilus-sg"
  }
}
```

> **Diferencia con el intento inicial**: el primer `main.tf` tenía solo `tags = { Name = "nautilus-sg" }` y **omitía** `name`. Por eso el SG quedó con `name = "terraform-2026..."` autogenerado. La línea `name = "nautilus-sg"` es la que cumple el requisito (1).

### Ejecutar

```bash
terraform init
terraform plan
terraform apply      # confirmar con 'yes'
```

Output real del `apply` (recortado):

```
data.aws_vpc.default: Reading...
data.aws_vpc.default: Read complete after 0s [id=vpc-19c0cdbcca64ba9fd]

  # aws_security_group.nautilus_sg will be created
  + resource "aws_security_group" "nautilus_sg" {
      + description = "Security group for Nautilus App Servers"
      + ingress     = [ { ... HTTP 80 ... }, { ... SSH 22 ... } ]
      + vpc_id      = "vpc-19c0cdbcca64ba9fd"
      + tags        = { "Name" = "nautilus-sg" }
    }

Plan: 1 to add, 0 to change, 0 to destroy.
  Enter a value: yes

aws_security_group.nautilus_sg: Creating...
aws_security_group.nautilus_sg: Creation complete after 0s [id=sg-46c28efca0bf48676]
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

### Verificación

```bash
terraform state show aws_security_group.nautilus_sg | grep -E "^    name |description|from_port"
```

```
    name        = "nautilus-sg"                              ← corregido (antes: terraform-2026...)
    description = "Security group for Nautilus App Servers"
            from_port   = 80
            from_port   = 22
```

O con el CLI de AWS:

```bash
aws ec2 describe-security-groups --region us-east-1 \
  --filters "Name=group-name,Values=nautilus-sg" \
  --query "SecurityGroups[].GroupName" --output text
```

## Variantes (referencia)

### Reglas como recursos separados (patrón moderno)

Las reglas inline son cómodas pero tienen limitaciones (no se pueden gestionar individualmente, el gotcha del egress). El patrón recomendado en provider AWS v5+ es usar recursos dedicados:

```hcl
resource "aws_security_group" "nautilus_sg" {
  name        = "nautilus-sg"
  description = "Security group for Nautilus App Servers"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.nautilus_sg.id
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.nautilus_sg.id
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}
```

Ventaja: cada regla es un recurso independiente (se agrega/quita sin tocar las demás) y no interfiere con el egress default.

### SSH restringido a una IP (producción)

```hcl
ingress {
  description = "SSH desde oficina"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["203.0.113.10/32"]    # /32 = una sola IP
}
```

### Referenciar otro SG como origen (en vez de CIDR)

```hcl
ingress {
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  security_groups = [aws_security_group.app.id]   # solo desde el SG de la app
}
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Validación falla aunque el SG se creó                            | Se puso solo `tags.Name`; el `name` real quedó `terraform-2026...`            | Agregar `name = "nautilus-sg"` al resource                                      |
| `Error: ... name ... cannot be updated. Resource must be replaced`| `name` es inmutable; cambiarlo recrea el SG                                    | Aceptar el replace (`-/+`) o `terraform destroy` + recrear                      |
| `InvalidGroup.Duplicate: ... already exists`                    | Ya existe un SG con ese `name` en la VPC                                       | Borrar el viejo o usar otro name; los SG name son únicos por VPC               |
| `data.aws_vpc.default: no matching VPC found`                    | La cuenta/región no tiene default VPC                                          | Crear una, o referenciar una VPC por `id`/tag en el data source                |
| Las instancias no pueden salir a internet                       | El egress default se removió al usar ingress inline sin egress                 | Declarar un bloque `egress` explícito (allow-all o lo necesario)               |
| `description ... cannot be empty` / cambia y recrea             | `description` también es inmutable en un SG                                    | Definirla bien la primera vez; cambiarla fuerza replace                         |
| Regla no permite el tráfico esperado                            | `protocol`/`from_port`/`to_port` mal, o CIDR equivocado                        | Revisar que `protocol: tcp` y el puerto coincidan con el servicio              |
| Funciona pero SSH abierto al mundo                              | `0.0.0.0/0` en puerto 22 (lo pide el lab, riesgo real)                         | En prod restringir a IP/VPN; en el lab es el requisito                          |

## Conexión con días anteriores

- **Día 94 (VPC, tag `Name`)**: el contraste central — una VPC se identifica por el tag `Name` (no tiene `name` nativo); un SG **sí** tiene `name`. Misma palabra, campo distinto. Recordar revisar qué campo es "el nombre" por recurso.
- **Día 94 (state, update vs replace)**: cambiar el tag de la VPC fue update in-place; cambiar el `name` del SG sería **replace** (inmutable). El `plan` avisa con `-/+`.
- **Día 94 (CIDR `0.0.0.0/0`)**: `/0` = 0 bits fijos = toda internet. Hoy se usa como origen de las reglas; conecta con el cálculo de rangos del día anterior.
- **Ansible (firewalld, hardening)**: en Ansible se gestionaban reglas de firewall a nivel de SO; el SG es el equivalente en la capa de red de AWS, declarado como código.

## Reflexión: data sources, el "nombre" según el recurso, y abrir puertos al mundo

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- name vs tag Name: día 94 el tag ERA el nombre (VPC), día 95 el name real es otro campo (SG). ¿Cómo evitas este tipo de error en el futuro? ¿La lección es "siempre leer la doc del recurso" o hay una heurística mejor? ¿Por qué AWS diseñó VPC y SG distinto?
- data source vs resource: leer la default VPC en vez de crearla. ¿Cuándo conviene depender de algo que no gestionas con Terraform (la default VPC)? ¿Es frágil construir sobre infra que no está en tu state?
- 0.0.0.0/0 en SSH: el lab lo pide, pero es un agujero real. ¿Documentarías una excepción/nota cuando un requisito de lab choca con buenas prácticas? ¿Cómo balanceas "cumplir el requisito" vs "lo correcto"?
- inline ingress vs recursos separados (aws_vpc_security_group_ingress_rule): el patrón moderno desacopla las reglas. ¿Vale la complejidad extra, o inline está bien para algo simple? ¿El gotcha del egress te haría preferir el patrón separado?
- el SG name inmutable: a diferencia del tag, no se puede cambiar sin recrear. ¿Qué implica para nombrar recursos desde el día 1? ¿Conviene una convención de nombres pensada antes de aplicar?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`aws_security_group` resource — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
- [`aws_vpc_security_group_ingress_rule` (patrón moderno)](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule)
- [`aws_vpc` data source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc)
- [Data sources — Terraform docs](https://developer.hashicorp.com/terraform/language/data-sources)
- [Security groups for your VPC — AWS docs](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html)
