# Día 42 - Crear una Docker Network

## Problema / Desafío

El equipo de Nautilus necesita preparar redes Docker para distintas aplicaciones en App Server 1 (`stapp01`). Requisitos:

- Crear una red llamada `media`
- Usar el driver `macvlan`
- Subnet: `172.28.0.0/24`
- IP range: `172.28.0.0/24`

## Conceptos clave

### Redes en Docker

Por defecto Docker crea tres redes al instalarse:

```bash
docker network ls
```

```
NETWORK ID     NAME      DRIVER    SCOPE
f88061aba780   bridge    bridge    local
3322bc5649f9   host      host      local
7b2dcdf057c2   none      null      local
```

| Red | Driver | Comportamiento |
|-----|--------|---------------|
| `bridge` | bridge | Red virtual privada. Los contenedores se comunican entre sí; el host actúa como gateway con NAT hacia el exterior. Es el default. |
| `host` | host | El contenedor comparte el stack de red del host directamente. Sin aislamiento de red. |
| `none` | null | Sin ninguna interfaz de red. El contenedor está completamente aislado. |

### Drivers de red disponibles

| Driver | Descripción | Cuándo usarlo |
|--------|-------------|---------------|
| `bridge` | Driver por default. Crea una red virtual privada; los contenedores se comunican entre sí y el host actúa como gateway con NAT hacia el exterior. | Comunicación entre contenedores del mismo host. |
| `host` | El contenedor usa directamente el stack de red del host. Sin NAT, sin interfaces virtuales. | Máximo rendimiento de red o cuando la app necesita escuchar en puertos del host sin overhead de traducción. |
| `macvlan` | Asigna una dirección MAC propia a cada contenedor, haciéndolo aparecer como un dispositivo físico en la red. | Cuando el contenedor necesita ser accesible directamente en la LAN sin publicar puertos. |
| `ipvlan` | Similar a macvlan pero todos los contenedores comparten la MAC del host — el switch solo ve una MAC con múltiples IPs. Puede operar en modo L2 o L3. | Entornos cloud o switches que limitan el número de MACs por puerto físico. |
| `overlay` | Conecta múltiples daemons de Docker, habilitando comunicación entre nodos en Docker Swarm. | Comunicación entre contenedores distribuidos en distintos hosts (Swarm). |
| `none` | Sin interfaces de red. Aislamiento total del contenedor. | Contenedores que no deben tener ningún acceso de red. |

### macvlan

`macvlan` asigna una dirección MAC única a cada contenedor, haciéndolo aparecer como un dispositivo físico en la red. El tráfico llega directamente al contenedor sin pasar por NAT ni por el host como intermediario.

```
Red física
    │
    ├── Host (stapp01)        MAC: aa:bb:cc:dd:ee:01
    ├── Contenedor A          MAC: aa:bb:cc:dd:ee:02  (macvlan)
    └── Contenedor B          MAC: aa:bb:cc:dd:ee:03  (macvlan)
```

Ventaja: los contenedores son accesibles directamente en la LAN sin publicar puertos.
Limitación: el host no puede comunicarse directamente con sus propios contenedores macvlan (el tráfico macvlan bypassa el stack de red del host).

### subnet vs ip-range

Ambos parámetros definen rangos de IPs pero con propósitos distintos:

| Parámetro | Define | Ejemplo |
|-----------|--------|---------|
| `--subnet` | El bloque de red completo — la dirección de red y su máscara | `172.28.0.0/24` → IPs de `.1` a `.254` |
| `--ip-range` | El subconjunto de IPs que Docker puede asignar automáticamente a contenedores | `172.28.0.0/24` → mismo rango en este lab |

Cuando `ip-range` es más pequeño que `subnet`, se reservan IPs fuera del range para asignarlas manualmente (útil cuando otras máquinas físicas ya usan parte del bloque).

## Pasos

1. Verificar las redes existentes con `docker network ls`
2. Crear la red con los parámetros requeridos
3. Verificar que la red fue creada correctamente

## Comandos / Código

### 1. Verificar redes existentes

```bash
docker network ls
```

```
NETWORK ID     NAME      DRIVER    SCOPE
f88061aba780   bridge    bridge    local
3322bc5649f9   host      host      local
7b2dcdf057c2   none      null      local
```

### 2. Crear la red

```bash
docker network create media \
  -d macvlan \
  --subnet=172.28.0.0/24 \
  --ip-range=172.28.0.0/24
```

```
f1f856ac5a8f54e50712c5ceef436513bd6590b654b1859591d5282756b7094f
```

### 3. Verificar la red creada

```bash
docker network ls
docker network inspect media
```

`docker network inspect` muestra la configuración completa: driver, subnet, ip-range, contenedores conectados, etc.

### Referencia: sintaxis completa

```bash
docker network create <nombre> \
  -d <driver> \
  --subnet=<cidr> \
  --ip-range=<cidr> \
  --gateway=<ip>        # opcional: IP del gateway
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `network with name media already exists` | La red ya existe — verificar con `docker network ls` y eliminar con `docker network rm media` si es necesario |
| `Error response from daemon: invalid pool request` | El subnet solicitado se superpone con una red existente — usar un rango diferente |
| Contenedores macvlan no accesibles desde el host | Comportamiento esperado — macvlan bypassa el stack de red del host. Usar un bridge auxiliar si se necesita comunicación host↔contenedor |

## Recursos

- [docker network create - documentación oficial](https://docs.docker.com/engine/reference/commandline/network_create/)
- [Networking overview - Docker docs](https://docs.docker.com/network/)
- [Macvlan network driver](https://docs.docker.com/network/macvlan/)
