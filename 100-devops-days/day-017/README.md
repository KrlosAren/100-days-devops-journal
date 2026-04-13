# Dia 17 - Configurar PostgreSQL: Crear usuario y base de datos

## Problema / Desafio

El equipo de desarrollo va a desplegar una aplicacion que usa PostgreSQL. El servidor de base de datos ya esta instalado. Se necesita:

1. Crear un usuario `kodekloud_pop` con password `YchZHRcLkL`
2. Crear una base de datos `kodekloud_db10`
3. Otorgar permisos completos al usuario `kodekloud_pop` sobre la base de datos `kodekloud_db10`

## Conceptos clave

### PostgreSQL

PostgreSQL (o Postgres) es un sistema de base de datos relacional open source. Es conocido por ser robusto, extensible y cumplir con los estandares SQL.

| Caracteristica | PostgreSQL | MySQL/MariaDB |
|----------------|-----------|---------------|
| Cumplimiento SQL | Muy alto | Parcial |
| Tipos de datos | Muy extenso (JSON, arrays, hstore) | Basico |
| Concurrencia | MVCC nativo | Depende del engine |
| Extensibilidad | Muy alta (tipos, operadores, funciones) | Limitada |
| Caso de uso | Aplicaciones complejas, data warehousing | Web apps, CMS |

### Arquitectura de permisos en PostgreSQL

PostgreSQL maneja permisos en tres niveles:

```
Cluster (instancia de PostgreSQL)
└── Roles (usuarios/grupos)      ← CREATE USER / CREATE ROLE
    └── Databases                ← CREATE DATABASE
        └── Schemas              ← Por defecto: public
            └── Tablas, vistas, secuencias  ← GRANT
```

### Roles vs Usuarios

En PostgreSQL, **usuarios y roles son lo mismo**. `CREATE USER` es un alias de `CREATE ROLE WITH LOGIN`:

| Comando | Equivalente | Diferencia |
|---------|-------------|-----------|
| `CREATE USER kodekloud_pop` | `CREATE ROLE kodekloud_pop WITH LOGIN` | `CREATE USER` incluye `LOGIN` por defecto |
| `CREATE ROLE admin` | — | No puede hacer login por defecto |

### psql — Cliente de linea de comandos

`psql` es el cliente interactivo de PostgreSQL. Permite ejecutar SQL y comandos administrativos:

```bash
# Conectarse como usuario postgres (superusuario por defecto)
psql -U postgres
```

El usuario `postgres` es el superusuario creado automaticamente al instalar PostgreSQL. Es equivalente a `root` en Linux.

### Meta-comandos de psql

Los comandos que empiezan con `\` son **meta-comandos** de psql (no son SQL):

| Comando | Funcion |
|---------|---------|
| `\l` | Listar todas las bases de datos |
| `\du` | Listar todos los roles/usuarios |
| `\dt` | Listar tablas en la base de datos actual |
| `\c dbname` | Conectarse a otra base de datos |
| `\q` | Salir de psql |
| `\?` | Ayuda de meta-comandos |
| `\h CREATE` | Ayuda SQL para un comando especifico |

## Pasos

1. Conectarse al servidor de base de datos por SSH
2. Acceder a PostgreSQL con `psql`
3. Crear el usuario con password
4. Crear la base de datos
5. Otorgar permisos completos al usuario sobre la base de datos
6. Verificar la configuracion

## Comandos / Codigo

### 1. Conectarse al servidor

```bash
ssh peter@stdb01
```

### 2. Acceder a PostgreSQL

```bash
psql -U postgres
```

```
psql (13.x)
Type "help" for help.

postgres=#
```

El prompt `postgres=#` indica que estas conectado como superusuario (`#` = superuser, `>` = usuario normal).

### 3. Crear el usuario

```sql
CREATE USER kodekloud_pop WITH ENCRYPTED PASSWORD 'YchZHRcLkL';
```

```
CREATE ROLE
```

**`ENCRYPTED` vs sin encriptar:**

| Opcion | Almacenamiento del password |
|--------|---------------------------|
| `WITH PASSWORD 'xxx'` | En PostgreSQL 10+, se encripta por defecto |
| `WITH ENCRYPTED PASSWORD 'xxx'` | Explicitamente encriptado (recomendado para claridad) |
| `WITH UNENCRYPTED PASSWORD 'xxx'` | Texto plano — **eliminado** en PostgreSQL 10+ |

En la practica ambas son equivalentes en versiones modernas, pero `ENCRYPTED` hace explicita la intencion.

Verificar:

```sql
\du
```

```
                             List of roles
   Role name    |                   Attributes
----------------+------------------------------------------------
 kodekloud_pop  |
 postgres       | Superuser, Create role, Create DB, Replication
```

### 4. Crear la base de datos

```sql
CREATE DATABASE kodekloud_db10;
```

```
CREATE DATABASE
```

Verificar:

```sql
\l
```

```
                              List of databases
     Name       |  Owner   | Encoding |   Collate   |    Ctype
----------------+----------+----------+-------------+------------
 kodekloud_db10 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8
 postgres       | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8
 template0      | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8
 template1      | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8
```

### 5. Otorgar permisos completos

```sql
GRANT ALL PRIVILEGES ON DATABASE kodekloud_db10 TO kodekloud_pop;
```

```
GRANT
```

**Que incluye `ALL PRIVILEGES` a nivel de base de datos:**

| Privilegio | Permite |
|-----------|---------|
| `CREATE` | Crear schemas y tablas dentro de la base de datos |
| `CONNECT` | Conectarse a la base de datos |
| `TEMPORARY` | Crear tablas temporales |

Para permisos completos sobre las **tablas** dentro de la base de datos (si ya existen):

```sql
-- Conectarse a la base de datos
\c kodekloud_db10

-- Otorgar permisos sobre todas las tablas del schema public
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO kodekloud_pop;

-- Otorgar permisos sobre todas las secuencias
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO kodekloud_pop;
```

### 6. Verificar la configuracion

```sql
-- Ver los permisos de la base de datos
\l kodekloud_db10
```

```
                                     List of databases
     Name       |  Owner   | Encoding |   Collate   |    Ctype    |    Access privileges
----------------+----------+----------+-------------+-------------+------------------------
 kodekloud_db10 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =Tc/postgres          +
                |          |          |             |             | postgres=CTc/postgres  +
                |          |          |             |             | kodekloud_pop=CTc/postgres
```

La columna `Access privileges` muestra que `kodekloud_pop` tiene `CTc` (Create, Temporary, connect).

### 7. Salir de psql

```sql
\q
```

## Alternativa: crear todo con un solo script

```sql
-- Crear usuario
CREATE USER kodekloud_pop WITH PASSWORD 'YchZHRcLkL';

-- Crear base de datos con el usuario como owner (alternativa)
CREATE DATABASE kodekloud_db10 OWNER kodekloud_pop;
```

Con `OWNER kodekloud_pop`, el usuario es dueno de la base de datos y automaticamente tiene todos los permisos. No se necesita `GRANT` adicional.

## Crear usuario y base de datos desde la linea de comandos (sin entrar a psql)

```bash
# Crear usuario
sudo -u postgres createuser kodekloud_pop -P
# -P solicita el password interactivamente

# Crear base de datos
sudo -u postgres createdb kodekloud_db10 -O kodekloud_pop
# -O asigna el owner

# Ejecutar SQL directo
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE kodekloud_db10 TO kodekloud_pop;"
```

## Niveles de permisos en PostgreSQL

```
GRANT ... ON DATABASE    → Permisos a nivel de base de datos (CONNECT, CREATE, TEMP)
GRANT ... ON SCHEMA      → Permisos a nivel de schema (CREATE, USAGE)
GRANT ... ON TABLE       → Permisos a nivel de tabla (SELECT, INSERT, UPDATE, DELETE)
GRANT ... ON SEQUENCE    → Permisos a nivel de secuencia (USAGE, SELECT, UPDATE)
```

```sql
-- Ejemplo completo de permisos granulares
GRANT CONNECT ON DATABASE kodekloud_db10 TO kodekloud_pop;
GRANT USAGE ON SCHEMA public TO kodekloud_pop;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO kodekloud_pop;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO kodekloud_pop;
```

| Nivel | Permisos comunes |
|-------|-----------------|
| DATABASE | `CONNECT`, `CREATE`, `TEMPORARY` |
| SCHEMA | `CREATE`, `USAGE` |
| TABLE | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER` |
| SEQUENCE | `USAGE`, `SELECT`, `UPDATE` |
| ALL PRIVILEGES | Todos los permisos del nivel correspondiente |

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `psql: FATAL: role "root" does not exist` | Conectarse como usuario postgres: `psql -U postgres` o `sudo -u postgres psql` |
| `psql: FATAL: Peer authentication failed` | Editar `/var/lib/pgsql/data/pg_hba.conf` y cambiar `peer` a `md5` o `trust` para el usuario. Reiniciar PostgreSQL |
| `CREATE DATABASE: permission denied` | Solo superusuarios o roles con `CREATEDB` pueden crear bases de datos |
| `FATAL: database "kodekloud_db10" does not exist` | La base de datos aun no se creo. Crear con `CREATE DATABASE` primero |
| El usuario no puede crear tablas | Falta `GRANT CREATE ON SCHEMA public TO usuario;` o hacer al usuario owner de la base de datos |
| Password no funciona | Verificar que `pg_hba.conf` usa `md5` (password) y no `peer` (autenticacion por usuario del sistema) |

## Recursos

- [PostgreSQL - CREATE USER](https://www.postgresql.org/docs/current/sql-createuser.html)
- [PostgreSQL - CREATE DATABASE](https://www.postgresql.org/docs/current/sql-createdatabase.html)
- [PostgreSQL - GRANT](https://www.postgresql.org/docs/current/sql-grant.html)
- [PostgreSQL - psql](https://www.postgresql.org/docs/current/app-psql.html)
