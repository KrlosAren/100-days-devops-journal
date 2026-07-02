# Día 100 - Create and Configure Alarm Using CloudWatch (observabilidad + alarma métrica + SNS)

> 🎉 **Día 100 de 100.** Último día del reto. Cierra la sección Terraform (94-100) y el journal completo.

## Problema / Desafío

Montar una EC2 y una **alarma de CloudWatch** que monitoree su CPU y notifique vía **SNS**. Con Terraform:

1. **EC2** `xfusion-ec2` con AMI Ubuntu `ami-0c02fb55956c7d316`
2. **CloudWatch alarm** `xfusion-alarm` con:
   - **Statistic**: `Average`
   - **Metric**: CPU Utilization
   - **Threshold**: `>= 90%` por **1** período consecutivo de **5 minutos**
   - **Alarm Actions**: notificar al SNS topic **`xfusion-sns-topic`** (ya creado)
3. Actualizar `main.tf` (no otro `.tf`) para la EC2 y la alarma
4. **`outputs.tf`**: `KKE_instance_name`, `KKE_alarm_name`
5. `terraform plan` debe devolver **"No changes"** antes de entregar

Directorio `/home/bob/terraform`.

> Cierre perfecto para el reto: **observabilidad**. Tras crear y configurar infra (VPC, EC2, IAM, DynamoDB), el último paso es **monitorearla** — el ciclo completo de un recurso en producción.

## Conceptos clave

### CloudWatch — la observabilidad de AWS

CloudWatch recolecta **métricas** de los servicios AWS (CPU, red, disco, etc.) y permite definir **alarmas** que disparan **acciones** cuando una métrica cruza un umbral. Es la capa de monitoreo estándar de AWS.

Una alarma tiene tres estados:

| Estado              | Significado                                                     |
| ------------------- | -------------------------------------------------------------- |
| `OK`                | La métrica está dentro del umbral                              |
| `ALARM`             | La métrica cruzó el umbral (dispara `alarm_actions`)          |
| `INSUFFICIENT_DATA` | No hay datos suficientes para evaluar                          |

### ★ El mapeo especificación → campos (el corazón del lab)

Cada frase del requisito se traduce a un campo exacto de `aws_cloudwatch_metric_alarm`. Este es el ejercicio central:

| Especificación                          | Campo Terraform                                    | Valor                          |
| --------------------------------------- | -------------------------------------------------- | ------------------------------ |
| "**>= 90%**"                            | `comparison_operator` + `threshold`                | `GreaterThanOrEqualToThreshold` + `90` |
| "período de **5 minutos**"              | `period` (en **segundos**)                         | `300`                          |
| "**1** período consecutivo"             | `evaluation_periods`                               | `1`                            |
| "**Average**"                           | `statistic`                                        | `Average`                      |
| "**CPU Utilization**"                   | `metric_name` + `namespace`                        | `CPUUtilization` + `AWS/EC2`   |
| "notificar al SNS topic"                | `alarm_actions`                                    | `[<arn del topic>]`            |

Tres campos juntos forman la **condición completa** de disparo: `comparison_operator` (el operador), `threshold` (el valor), `period` × `evaluation_periods` (la ventana temporal). "1 período de 5 min" = `period=300` + `evaluation_periods=1`. Si fuera "3 períodos consecutivos", sería `evaluation_periods=3` (la alarma dispararía solo tras 15 min sobre el umbral).

> Detalles fáciles de errar: `period` va en **segundos** (300, no 5); `metric_name` es **`CPUUtilization`** (una palabra, como lo publica CloudWatch); `namespace` es **`AWS/EC2`** (las métricas nativas de EC2 viven ahí, sin configuración extra).

### `dimensions` — a qué recurso mira la alarma

Sin `dimensions`, la alarma no sabría **qué** instancia monitorear (`CPUUtilization` en `AWS/EC2` es una métrica genérica). La dimensión `InstanceId` la ata a la instancia concreta:

```hcl
dimensions = {
  InstanceId = aws_instance.xfusion_ec2.id    # scoped a xfusion-ec2
}
```

Referenciar `.id` (no un literal) crea la dependencia: la instancia se crea antes que la alarma (grafo del Día 96).

### SNS — el canal de notificación

SNS (Simple Notification Service) es el sistema de **publish/subscribe** de AWS. La alarma **publica** en el topic cuando entra en `ALARM`; los **suscriptores** del topic (email, SMS, Lambda, colas SQS) reciben el mensaje.

```hcl
alarm_actions = [aws_sns_topic.sns_topic.arn]
```

Separación de responsabilidades: la **alarma** decide *cuándo* disparar; **SNS** decide *a dónde* va la notificación. Igual patrón que el role-vs-policy del Día 99.

> **El topic "ya está creado"**: el enunciado dice que `xfusion-sns-topic` ya existe. Dos formas de referenciarlo:
> - **Como `resource`** (lo usado): funciona si Terraform ya lo gestiona en su state (el `apply` lo refrescó desde el ARN existente y `plan` quedó limpio).
> - **Como `data source`** (más correcto si lo creó otro): `data "aws_sns_topic" "x" { name = "xfusion-sns-topic" }` — lee el ARN sin intentar gestionarlo. Ver Variantes.

### ★ El error `comparasion_operator` — leer el mensaje

Durante el lab apareció un error real por un typo:

```
Error: Missing required argument
  The argument "comparison_operator" is required, but no definition was found.
Error: Unsupported argument
  An argument named "comparasion_operator" is not expected here.
  Did you mean "comparison_operator"?
```

Dos errores encadenados de una sola causa: `comparasion_operator` (con "a" de más) → Terraform no reconoce ese argumento **y** además reporta que falta el `comparison_operator` obligatorio. La sugerencia "Did you mean" apunta al fix. Lección de cierre del reto: **el `plan`/`apply` valida los nombres de argumento antes de tocar la nube** — a diferencia de los valores (Días 95-97, donde AWS aceptaba valores incorrectos), un **nombre** de argumento mal escrito lo caza Terraform en seco.

## Pasos

1. Abrir terminal en `/home/bob/terraform`
2. Actualizar `main.tf`: EC2 + SNS (ref) + `aws_cloudwatch_metric_alarm`
3. Crear `outputs.tf` (los dos `KKE_*`)
4. `terraform init` → `plan` → `apply` → `yes`
5. Re-correr `terraform plan` → confirmar "No changes"

## Comandos / Código

### `main.tf`

```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_sns_topic" "sns_topic" {
  name = "xfusion-sns-topic"
}

resource "aws_instance" "xfusion_ec2" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"

  tags = {
    Name = "xfusion-ec2"
  }
}

resource "aws_cloudwatch_metric_alarm" "xfusion_alarm" {
  alarm_name          = "xfusion-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 90
  period              = 300               # 5 minutos en segundos
  evaluation_periods  = 1                 # 1 período consecutivo
  statistic           = "Average"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"

  dimensions = {
    InstanceId = aws_instance.xfusion_ec2.id
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_sns_topic.sns_topic.arn]
}
```

### `outputs.tf`

```hcl
output "KKE_instance_name" {
  value = aws_instance.xfusion_ec2.tags.Name
}

output "KKE_alarm_name" {
  value = aws_cloudwatch_metric_alarm.xfusion_alarm.alarm_name
}
```

### Ejecutar y verificar idempotencia

```bash
terraform init
terraform apply     # 'yes'
terraform plan      # ← "No changes"
```

Output real (recortado):

```
aws_cloudwatch_metric_alarm.xfusion_alarm will be created
  + alarm_actions       = ["arn:aws:sns:us-east-1:000000000000:xfusion-sns-topic"]
  + comparison_operator = "GreaterThanOrEqualToThreshold"
  + dimensions          = { "InstanceId" = "i-1189c4ed636321727" }
  + evaluation_periods  = 1
  + metric_name         = "CPUUtilization"
  + namespace           = "AWS/EC2"
  + period              = 300
  + statistic           = "Average"
  + threshold           = 90
  + treat_missing_data  = "missing"

aws_cloudwatch_metric_alarm.xfusion_alarm: Creation complete after 0s [id=xfusion-alarm]

# terraform plan (tras apply):
No changes. Your infrastructure matches the configuration.
```

Outputs:

```
KKE_alarm_name    = "xfusion-alarm"
KKE_instance_name = "xfusion-ec2"
```

Verificación adicional:

```bash
terraform state list
# aws_cloudwatch_metric_alarm.xfusion_alarm
# aws_instance.xfusion_ec2
# aws_sns_topic.sns_topic

aws sns list-topics --region us-east-1 \
  --query "Topics[?contains(TopicArn, 'xfusion-sns-topic')]" --output text
# arn:aws:sns:us-east-1:000000000000:xfusion-sns-topic
```

## Variantes (referencia)

### SNS topic ya existente — como data source

```hcl
data "aws_sns_topic" "existing" {
  name = "xfusion-sns-topic"
}

resource "aws_cloudwatch_metric_alarm" "xfusion_alarm" {
  # ...
  alarm_actions = [data.aws_sns_topic.existing.arn]
}
```

### Acción también al volver a OK

```hcl
resource "aws_cloudwatch_metric_alarm" "xfusion_alarm" {
  # ...
  alarm_actions = [aws_sns_topic.sns_topic.arn]   # al entrar en ALARM
  ok_actions    = [aws_sns_topic.sns_topic.arn]   # al volver a OK (recuperación)
}
```

### Suscribir un email al topic

```hcl
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.sns_topic.arn
  protocol  = "email"
  endpoint  = "devops@xfusion.com"
}
```

### Alarma más robusta (multi-período + missing data)

```hcl
evaluation_periods = 3                    # 3 períodos → 15 min sobre umbral
treat_missing_data = "notBreaching"       # datos faltantes NO disparan
```

## Troubleshooting

| Problema                                                          | Causa                                                                          | Solución                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `Did you mean "comparison_operator"?`                            | Typo en el nombre del argumento (`comparasion_operator`)                       | Corregir el nombre; Terraform valida nombres de argumento en `plan`            |
| `Missing required argument comparison_operator`                  | Falta el operador (o estaba mal escrito y no se reconoció)                     | Definir `comparison_operator`                                                  |
| La alarma no dispara nunca                                       | `period`/`threshold`/`evaluation_periods` mal, o `dimensions` sin `InstanceId`| Revisar el mapeo spec→campos; scoped por `InstanceId`                          |
| `period` interpretado mal                                        | Se puso `5` (minutos) en vez de `300` (segundos)                              | `period` va en **segundos**                                                    |
| La notificación no llega                                         | `alarm_actions` sin el ARN del topic, o topic sin suscriptores                | `alarm_actions = [<arn>]` + suscribir un endpoint al topic                     |
| `plan` muestra cambios en el SNS topic                           | Se gestiona como `resource` un topic creado por fuera                          | Usar `data "aws_sns_topic"` si lo creó otro; o importarlo al state             |
| `metric_name` no matchea                                         | Se escribió `CPU Utilization` con espacio                                     | Es `CPUUtilization` (una palabra), namespace `AWS/EC2`                          |

## Conexión con días anteriores

- **Toda la sección Terraform (94-100)**: el arco completo — crear red (94-95, 98), cómputo (96), permisos (97, 99), y hoy **monitorearlo** (100). El ciclo de vida entero de infra como código.
- **Día 96 (grafo)**: `dimensions.InstanceId = aws_instance...id` y `alarm_actions = [sns.arn]` encadenan instancia → alarma y topic → alarma.
- **Día 99 (separación de responsabilidades)**: alarma (cuándo) vs SNS (a dónde), como role (quién) vs policy (qué).
- **Jenkins/K8s (monitoreo previo)**: en CI/CD y K8s se vio health checks y readiness; CloudWatch es el equivalente gestionado a nivel de infra AWS.
- **Idempotencia (Días 98, 99)**: el `plan` limpio como definición de "terminado" — el criterio con el que se cierra el reto entero.

## Reflexión: cerrar el ciclo (observabilidad) y el reto de 100 días

<!-- TODO(human): Reflexión de cierre. Este es el DÍA 100 — vale una reflexión doble:

SOBRE EL LAB:
- el mapeo spec→campos: "≥90% por 1 período de 5 min" se volvió comparison_operator + threshold + period + evaluation_periods. ¿Traducir requisitos en lenguaje natural a campos exactos es la habilidad central de IaC? ¿En qué se parece a lo que hacías con los validadores de K8s/Ansible?
- observabilidad como último paso: crear infra sin monitoreo es dejar el trabajo a medias. ¿Cambia tu forma de pensar un recurso "terminado" saber que necesita alarma + notificación?
- el typo comparasion_operator: Terraform cazó el NOMBRE mal escrito (a diferencia de valores incorrectos que AWS aceptaba, días 95-97). ¿Qué te dice esto sobre dónde está y dónde no está la red de seguridad?

SOBRE EL RETO COMPLETO (100 días):
- el recorrido: Linux/usuarios → K8s (48-67) → CI/CD Jenkins (68-81) → Ansible (82-93) → Terraform/AWS (94-100). ¿Qué hilo conecta todo? (pista: declarativo, idempotencia, estado deseado aparecen en K8s, Ansible Y Terraform)
- ¿qué concepto te costó más y cuál "hizo click" de golpe?
- si empezaras de nuevo, ¿qué harías distinto en cómo documentaste o practicaste?

2–10 líneas (o más, es el día 100). Tono directo, primera persona implícita. Evitar voseo. -->

## Recursos

- [`aws_cloudwatch_metric_alarm` resource — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm)
- [`aws_sns_topic` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic)
- [`aws_sns_topic_subscription` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription)
- [EC2 CloudWatch metrics — AWS docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/viewing_metrics_with_cloudwatch.html)
- [Using Amazon CloudWatch alarms — AWS docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
