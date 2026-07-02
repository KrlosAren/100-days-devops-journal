# Día 96 - Create EC2 Instance Using Terraform (multi-provider + key pairs + grafo de dependencias)

## Problema / Desafío

Tercer paso de la migración: lanzar una **instancia EC2** con Terraform. Requisitos:

1. Tag **`Name`** = **`xfusion-ec2`** (nombre de la instancia en AWS)
2. AMI Amazon Linux **`ami-0c101f26f147fa7fd`**
3. Tipo de instancia **`t2.micro`**
4. Crear una **RSA key** nueva llamada **`xfusion-kp`**
5. Adjuntar el **security group default** (el disponible por defecto)

Región `us-east-1`. Directorio `/home/bob/terraform`. Crear `main.tf` (no otro `.tf`).

> Día 3 de Terraform y el más rico hasta ahora: usa **tres providers** (`aws`, `tls`, `local`), genera un **par de llaves RSA**, y construye un **grafo de dependencias** entre 4 recursos que Terraform ordena solo.

## Conceptos clave

### Múltiples providers — más allá de la nube

Hasta ahora solo se usó el provider `aws`. Este lab introduce dos más:

| Provider | Para qué                                          | Recurso usado            |
| -------- | ------------------------------------------------- | ------------------------ |
| `aws`    | Recursos en AWS                                   | `aws_instance`, `aws_key_pair` |
| `tls`    | Generar material criptográfico (llaves, certs)    | `tls_private_key`        |
| `local`  | Manipular archivos en la máquina local            | `local_file`             |

Un **provider** no tiene por qué ser una nube — es cualquier plugin que Terraform sabe manejar. `tls` y `local` corren **localmente** (no llaman a AWS). Los tres se descargan automáticamente en `terraform init`.

### El flujo de un key pair — criptografía asimétrica

Un par de llaves SSH es **asimétrico**: una llave **privada** (secreta, se queda en local) y una **pública** (se comparte). Lo que cifra una, lo descifra la otra. Para SSH a una instancia EC2:

- La llave **pública** va a AWS y se instala en la instancia (`~/.ssh/authorized_keys`)
- La llave **privada** se queda local y se usa para conectarse (`ssh -i xfusion-kp.pem`)

El lab pide "crear una RSA key". El flujo en Terraform son **tres recursos encadenados**:

```hcl
# 1. Genera el par RSA (pública + privada) — provider tls, local
resource "tls_private_key" "xfusion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. Sube SOLO la parte pública a AWS con el nombre exacto — provider aws
resource "aws_key_pair" "xfusion_kp" {
  key_name   = "xfusion-kp"
  public_key = tls_private_key.xfusion.public_key_openssh
}

# 3. Guarda la privada localmente con permisos 0400 — provider local
resource "local_file" "xfusion_pem" {
  content         = tls_private_key.xfusion.private_key_pem
  filename        = "/home/bob/terraform/xfusion-kp.pem"
  file_permission = "0400"
}
```

| Recurso             | Qué produce                          | Dónde vive                |
| ------------------- | ------------------------------------ | ------------------------- |
| `tls_private_key`   | El par RSA completo (pub + priv)     | En el **state** (sensible)|
| `aws_key_pair`      | La pública, registrada en AWS        | AWS                       |
| `local_file`        | La privada, en `.pem` con `0400`     | Disco local               |

> El `local_file` es **opcional** para que el lab pase (si solo valida que exista el key pair en AWS), pero es lo que hace la llave **usable** después — sin guardar la privada, no se podría hacer SSH. `0400` = solo lectura para el dueño (SSH rechaza llaves con permisos más abiertos).

### ★ El gotcha del día: `key_name` debe estar EN la instancia

Crear el key pair **no lo conecta** a la instancia. Para que la instancia lo use, hay que referenciarlo con el argumento **`key_name`** dentro de `aws_instance`:

```hcl
resource "aws_instance" "main" {
  ami           = "ami-0c101f26f147fa7fd"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.xfusion_kp.key_name    # ← ESTA línea conecta la llave
  ...
}
```

> **El error de este lab**: si `aws_instance` **no** tiene `key_name`, la instancia se crea **sin** llave — no se podría hacer SSH aunque el `.pem` exista. El plan lo delata:
>
> ```
> + key_name = (known after apply)    ← señal de que key_name NO se seteó en el config
> ```
>
> Si se hubiera referenciado `key_name = aws_key_pair.xfusion_kp.key_name`, el plan mostraría `key_name = "xfusion-kp"` (un valor literal conocido), no `(known after apply)`. La solución: agregar la línea `key_name` al resource de la instancia.

### ★ El grafo de dependencias — implícito vs explícito

Terraform no ejecuta los recursos en el orden en que están escritos. Construye un **DAG** (grafo dirigido acíclico) a partir de las **referencias** entre recursos, y de ahí deduce el orden y qué paralelizar.

Cuando un recurso menciona a otro (`tls_private_key.xfusion.public_key_openssh`), Terraform crea una **dependencia implícita**: el referenciado se crea **primero**. La cadena de este lab:

```
tls_private_key.xfusion          (genera el par)
        │
        ├──> aws_key_pair.xfusion_kp     (usa la pública)
        │            │
        │            └──> aws_instance.main   (usa key_name → espera al key_pair)
        │
        └──> local_file.xfusion_pem      (usa la privada)
```

El output del `apply` refleja este orden:

```
tls_private_key.xfusion: Creating...       ← primero (nadie depende de menos que él)
tls_private_key.xfusion: Creation complete
local_file.xfusion_pem: Creating...        ← en paralelo: ambos dependen solo del tls
aws_key_pair.xfusion_kp: Creating...
aws_key_pair.xfusion_kp: Creation complete
aws_instance.main: Creating...             ← último (depende del key_pair vía key_name)
aws_instance.main: Creation complete after 10s
```

| Tipo de dependencia | Cómo se crea                                          |
| ------------------- | ----------------------------------------------------- |
| **Implícita**       | Referenciar un atributo de otro recurso (lo normal)   |
| **Explícita**       | `depends_on = [otro_recurso]` cuando no hay referencia directa |

> Por eso conviene referenciar `aws_key_pair.xfusion_kp.key_name` en vez del string literal `"xfusion-kp"`: además de evitar repetir el nombre, **crea la dependencia** que garantiza que el key pair exista antes de lanzar la instancia.

### `security_groups` vs `vpc_security_group_ids` — usar el ID en VPC

Para adjuntar el SG default, primero se lee con un data source y luego se pasa **por id**:

```hcl
data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
  name   = "default"
}

resource "aws_instance" "main" {
  vpc_security_group_ids = [data.aws_security_group.default.id]   # ← por ID, lista
}
```

| Argumento                 | Espera          | Cuándo usarlo                          |
| ------------------------- | --------------- | -------------------------------------- |
| `vpc_security_group_ids`  | Lista de **IDs**| **Correcto en VPC** (lo normal hoy)    |
| `security_groups`         | Lista de **nombres** | Legacy EC2-Classic / default VPC; evitar |

En una VPC moderna se usa **`vpc_security_group_ids`** con el `id` del SG. El argumento `security_groups` (por nombre) es de la era EC2-Classic y puede causar recreaciones innecesarias.

### Valores `(sensitive value)` — secretos en el state

El plan marca la llave privada como `(sensitive value)`:

```
private_key_pem = (sensitive value)
content         = (sensitive value)
```

Terraform **oculta** los valores sensibles en el output de la consola, pero **los guarda en texto plano en `terraform.tfstate`**. Esto conecta con la nota del Día 94: el state es sensible. Quien tenga acceso al `terraform.tfstate` tiene la llave privada. Por eso en equipos el state va a un **backend remoto cifrado** (S3 con encryption + acceso restringido), nunca a git.

### AMI, tipo y región — los parámetros de la instancia

| Argumento       | Valor del lab            | Qué es                                                   |
| --------------- | ------------------------ | ------------------------------------------------------- |
| `ami`           | `ami-0c101f26f147fa7fd`  | Imagen base (Amazon Linux); **es específica por región**|
| `instance_type` | `t2.micro`               | Tamaño (1 vCPU, 1 GB RAM); elegible para free tier      |

> La AMI es **region-specific**: el mismo ID no existe en otra región. Por eso el lab da el ID exacto para `us-east-1`. En código real se suele resolver con un `data "aws_ami"` que filtra por nombre/owner en vez de hardcodear el ID.

## Pasos

1. Abrir terminal en `/home/bob/terraform`
2. Escribir `main.tf`: providers + `tls_private_key` + `aws_key_pair` + `local_file` + data sources (VPC y SG default) + `aws_instance` con `key_name`
3. `terraform init` (descarga aws, tls, local)
4. `terraform plan` — revisar el grafo (4 to add)
5. `terraform apply` → `yes`
6. Verificar la instancia y el key pair

## Comandos / Código

### `main.tf` (solución corregida)

```hcl
# /home/bob/terraform/main.tf
provider "aws" {
  region = "us-east-1"
}

# --- Par de llaves RSA ---
resource "tls_private_key" "xfusion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "xfusion_kp" {
  key_name   = "xfusion-kp"
  public_key = tls_private_key.xfusion.public_key_openssh
}

resource "local_file" "xfusion_pem" {
  content         = tls_private_key.xfusion.private_key_pem
  filename        = "/home/bob/terraform/xfusion-kp.pem"
  file_permission = "0400"
}

# --- Data sources: default VPC y su SG default ---
data "aws_vpc" "default" {
  default = true
}

data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
  name   = "default"
}

# --- La instancia EC2 ---
resource "aws_instance" "main" {
  ami                    = "ami-0c101f26f147fa7fd"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.xfusion_kp.key_name     # ← conecta la llave
  vpc_security_group_ids = [data.aws_security_group.default.id]

  tags = {
    Name = "xfusion-ec2"
  }
}
```

> **Diferencia con el intento inicial**: faltaba `key_name` en `aws_instance`. Sin esa línea, el plan mostró `key_name = (known after apply)` y la instancia quedó **sin llave**. La línea `key_name = aws_key_pair.xfusion_kp.key_name` la conecta y crea la dependencia implícita.

### Ejecutar

```bash
terraform init      # descarga aws + tls + local
terraform plan
terraform apply     # confirmar con 'yes'
```

Output real del `apply` (recortado):

```
Plan: 4 to add, 0 to change, 0 to destroy.
  Enter a value: yes

tls_private_key.xfusion: Creation complete after 0s [id=a229e923...]
local_file.xfusion_pem: Creation complete after 0s [id=47f00e3b...]
aws_key_pair.xfusion_kp: Creating...
aws_key_pair.xfusion_kp: Creation complete after 0s [id=xfusion-kp]
aws_instance.main: Creating...
aws_instance.main: Still creating... [10s elapsed]
aws_instance.main: Creation complete after 10s [id=i-e578a88887b54a1d2]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

> `4 to add`: los tres recursos del key pair + la instancia. El orden de creación lo decide el grafo, no el orden del archivo.

### Verificación

```bash
# La instancia, su tag Name, tipo y key
aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:Name,Values=xfusion-ec2" \
  --query "Reservations[].Instances[].[InstanceId,InstanceType,KeyName,State.Name]" \
  --output table

# El key pair
aws ec2 describe-key-pairs --region us-east-1 \
  --key-names xfusion-kp --query "KeyPairs[].KeyName" --output text

# El .pem local
ls -l /home/bob/terraform/xfusion-kp.pem    # -r-------- (0400)
```

## Variantes (referencia)

### Resolver la AMI dinámicamente (en vez de hardcodear el ID)

```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "main" {
  ami = data.aws_ami.amazon_linux.id   # ← portable entre regiones
  ...
}
```

### Exponer la IP pública como output

```hcl
output "instance_ip" {
  value = aws_instance.main.public_ip
}
```

### `depends_on` explícito (cuando no hay referencia directa)

```hcl
resource "aws_instance" "main" {
  # ...
  depends_on = [aws_key_pair.xfusion_kp]   # forzar orden sin referenciar un atributo
}
```

### Conectarse por SSH tras el apply

```bash
ssh -i /home/bob/terraform/xfusion-kp.pem ec2-user@<public_ip>
# ec2-user es el usuario default de Amazon Linux
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| No se puede hacer SSH a la instancia                             | Falta `key_name` en `aws_instance` → se creó sin llave                         | Agregar `key_name = aws_key_pair.xfusion_kp.key_name`                           |
| `key_name = (known after apply)` en el plan                     | El argumento `key_name` no está en el config                                   | Referenciar el key pair en `key_name`                                          |
| `InvalidAMIID.NotFound`                                         | El AMI ID no existe en esa región (las AMI son region-specific)               | Usar el ID correcto para `us-east-1`, o `data "aws_ami"`                        |
| `Permissions 0644 for 'xfusion-kp.pem' are too open`            | El `.pem` quedó con permisos abiertos; SSH lo rechaza                          | `file_permission = "0400"` en `local_file`, o `chmod 400`                       |
| `InvalidKeyPair.Duplicate: ... already exists`                 | Ya existe un key pair con ese nombre en AWS                                    | Borrar el viejo o usar otro `key_name`                                          |
| El SG default no se encuentra                                   | El data source filtra mal (name/vpc)                                           | `name = "default"` + `vpc_id = data.aws_vpc.default.id`                         |
| La instancia se recrea al cambiar el SG por nombre              | Se usó `security_groups` (legacy) en vez de `vpc_security_group_ids`           | Usar `vpc_security_group_ids` con el `id`                                       |
| La llave privada aparece en git / es accesible                 | El `.pem` y el `terraform.tfstate` contienen el secreto                        | No commitear `.pem` ni state; backend remoto cifrado; `.gitignore`             |

## Conexión con días anteriores

- **Días 94-95 (data sources)**: hoy se usan **dos** data sources (VPC default + SG default) como insumos de la instancia. Mismo patrón "leer infra existente".
- **Día 95 (`name` vs tag)**: la instancia EC2 (como la VPC del 94) se identifica por el **tag `Name`** — no tiene `name` nativo. Pero el **key pair** sí usa `key_name` (como el SG del 95 usaba `name`). El patrón "qué campo es el nombre" sigue vivo.
- **Día 94 (state sensible)**: hoy se materializa — la llave privada se guarda **en texto plano en el state**. La razón concreta por la que el state necesita protección/backend cifrado.
- **Ansible (Día 86, passwordless SSH)**: en Ansible se generaban llaves con `ssh-keygen` + `ssh-copy-id` imperativamente; hoy Terraform declara el mismo par de llaves como código (`tls_private_key` + `aws_key_pair`).

## Reflexión: el grafo de dependencias y dónde viven los secretos

<!-- TODO(human): Reflexión personal sobre el lab. Posibles direcciones:
- el grafo de dependencias: Terraform ordena 4 recursos solo, a partir de las referencias. ¿Cómo cambia esto vs un script bash donde uno ordena cada paso? ¿Confías en que el grafo haga lo correcto, o prefieres control explícito con depends_on?
- key_name faltante: el key pair existía en AWS pero la instancia no lo usaba. ¿Es un buen ejemplo de "el recurso se creó ≠ está bien conectado"? ¿Cómo lo detectarías sin que te lo señalen (leer el plan, intentar SSH)?
- la llave privada en el state: tls_private_key es cómodo pero deja el secreto en texto plano en terraform.tfstate. ¿Vale la pena vs generar la llave fuera de Terraform (ssh-keygen) y solo subir la pública? ¿Cuándo cada enfoque?
- referenciar (aws_key_pair.xfusion_kp.key_name) vs string literal ("xfusion-kp"): el primero crea la dependencia y evita repetir. ¿Adoptarías como regla "nunca hardcodear lo que puede ser una referencia"? ¿Tiene algún costo?
- multi-provider (tls/local además de aws): Terraform orquesta crypto local + archivos + nube en un solo apply. ¿Es elegante tener todo en un flujo, o mezcla responsabilidades que deberían estar separadas?
2–10 líneas, tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`aws_instance` resource — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance)
- [`aws_key_pair` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair)
- [`tls_private_key` resource](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key)
- [`aws_ami` data source (resolver AMI dinámica)](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami)
- [Resource dependencies — Terraform docs](https://developer.hashicorp.com/terraform/tutorials/configuration-language/dependencies)
