# CIDR y redes — elegir y validar rangos de IP

Referencia transversal que aparece en toda la sección Terraform (Días 94, 95, 98): cómo elegir el bloque CIDR de una VPC/subnet, calcular su tamaño, y evitar solapamientos. Aplica también fuera de AWS (cualquier red IPv4).

## Notación CIDR

Un bloque CIDR se escribe `red/prefijo`, ej. `10.0.0.0/16`. El `/N` es la cantidad de **bits fijos** (la parte de red); los `32 − N` restantes son para hosts.

## El cálculo del tamaño

Una IPv4 tiene **32 bits** (4 octetos × 8). El número de IPs sale de:

```
IPs totales = 2^(32 − N)
```

| CIDR  | `32 − N` (bits host) | `2^(32−N)` | IPs totales | Usables en AWS* |
| ----- | -------------------- | ---------- | ----------- | --------------- |
| `/16` | 16                   | `2^16`     | 65 536      | 65 531          |
| `/20` | 12                   | `2^12`     | 4 096       | 4 091           |
| `/24` | 8                    | `2^8`      | 256         | 251             |
| `/28` | 4                    | `2^4`      | 16          | 11              |

\* AWS **reserva 5 IPs por subnet** (red, gateway, DNS, reservada, broadcast) → usables = totales − 5.

**Atajos mentales**:
- Cada `+4` en el prefijo divide las IPs por 16 (`/16`→65 536, `/20`→4 096, `/24`→256).
- Cada `−1` en el prefijo **duplica** las IPs; cada octeto completo (`−8`) las multiplica por 256.

## Rangos propios para VPC (RFC 1918)

AWS **recomienda** rangos privados (no enrutables en internet):

| Rango           | CIDR             | Tamaño     |
| --------------- | ---------------- | ---------- |
| `10.0.0.0`      | `10.0.0.0/8`     | ~16,7M IPs |
| `172.16.0.0`    | `172.16.0.0/12`  | ~1M IPs    |
| `192.168.0.0`   | `192.168.0.0/16` | 65 536 IPs |

**Restricción de AWS**: el prefijo de una VPC debe estar entre **`/16` (máx) y `/28` (mín)**. Rangos públicos (como `100.0.0.0/16`) son técnicamente aceptados pero **mala práctica**: si esas IPs pertenecen a un servicio real de internet, las instancias no podrían alcanzarlo (el tráfico se enruta dentro de la VPC).

## Subnet dentro de la VPC

Una subnet **debe** ser un sub-rango del CIDR de su VPC (AWS lo exige):

```
VPC    10.0.0.0/16  →  10.0.0.0 – 10.0.255.255   (fija 10.0.x.x)
subnet 10.0.1.0/24  →  10.0.1.0 – 10.0.1.255      (dentro del rango, fija 10.0.1.x)
```

## Solapamiento — cómo saber si dos rangos chocan

Clave para peering/VPN: dos redes con CIDRs que se pisan **no pueden enrutar entre sí**.

**El rango real** de un CIDR va de la primera IP (bits host en 0) a la última (bits host en 1):

```
rango = [ red , red + 2^(32−N) − 1 ]
```

**Truco por octetos** — el prefijo dice cuántos octetos quedan fijos:

- `/8` → fija 1 octeto (`10.x.x.x`)
- `/16` → fija 2 octetos (`10.0.x.x`)
- `/24` → fija 3 octetos (`10.0.0.x`)

Así `10.0.0.0/16` y `10.1.0.0/16` **no** se solapan (difieren en el 2º octeto); pero `10.0.0.0/16` **contiene** a `10.0.5.0/24` → **sí** solapan ("contener" es un caso de solapamiento).

**La regla de oro** — dos rangos A y B chocan si:

```
inicioA ≤ finB   Y   inicioB ≤ finA
```

**El caso no obvio (`/20`, `/12`)** — prefijos que no caen en borde de octeto: un `/20` fija 2 octetos + 4 bits, así que los bloques avanzan **de 16 en 16** en el 3er octeto:

```
10.0.0.0/20   → 10.0.0.0  – 10.0.15.255
10.0.16.0/20  → 10.0.16.0 – 10.0.31.255   (siguiente bloque, NO 10.0.20.0)
```

`10.0.10.0/20` y `10.0.12.0/20` apuntan al **mismo** bloque (`10.0.0.0/20`) → solaparían. Por eso, salvo dominar el cálculo, conviene:

- **Alinear a bordes de octeto** (`/8`, `/16`, `/24`) — el solape se ve a ojo.
- Usar `ipcalc <cidr>` o una calculadora CIDR.
- AWS ayuda: rechaza subnets solapadas dentro de una VPC y peering entre VPCs con CIDRs solapados, con error explícito.

## Cómo elegir el rango en la práctica

1. **Tamaño**: estimar IPs (instancias + subnets + crecimiento). `/16` es el default seguro con margen amplio.
2. **No solaparse**: planificar un esquema (`10.0.0.0/16` prod, `10.1.0.0/16` staging) que no choque con otras VPCs / on-premise / redes de peering.
3. **Dejar espacio para subnets**: la VPC (`/16`) se subdivide en subnets (`/20`–`/24`), típicamente una por AZ.

> El CIDR de una VPC es **inmutable** — cambiarlo implica recrearla. Por eso el esquema de direccionamiento se diseña **antes**, en papel, no después.

## En Terraform

```hcl
variable "KKE_VPC_CIDR"    { default = "10.0.0.0/16" }
variable "KKE_SUBNET_CIDR" { default = "10.0.1.0/24" }

resource "aws_vpc" "this"    { cidr_block = var.KKE_VPC_CIDR }
resource "aws_subnet" "priv" {
  cidr_block = var.KKE_SUBNET_CIDR
  vpc_id     = aws_vpc.this.id
}
```

Reutilizar `var.KKE_VPC_CIDR` (en la VPC y, p. ej., en el `ingress` de un SG que restringe "solo desde dentro de la VPC") mantiene **una sola fuente de verdad** para el rango — mismo principio DRY que las variables de Ansible.
