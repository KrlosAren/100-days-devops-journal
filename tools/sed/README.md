# sed — Stream Editor

`sed` es un editor de texto no interactivo que procesa texto línea por línea. Lee desde un archivo o stdin, aplica transformaciones, y escribe el resultado a stdout (o modifica el archivo directamente con `-i`).

Es una herramienta fundamental en DevOps para automatizar ediciones de archivos de configuración sin abrir un editor interactivo.

---

## Sintaxis base

```bash
sed [opciones] 'instrucción' archivo
```

La instrucción más usada es el comando de sustitución `s`:

```bash
sed 's/patrón/reemplazo/' archivo
```

`sed` lee el archivo línea por línea y, en cada línea que coincide con el patrón, aplica el reemplazo. El resultado se imprime en stdout — **el archivo original no se modifica** a menos que uses `-i`.

---

## Flags del comando **s**

```bash
sed 's/patrón/reemplazo/flags'
```

| Flag | Significado | Ejemplo |
|------|-------------|---------|
| *(sin flag)* | Solo reemplaza la primera ocurrencia en cada línea | `s/foo/bar/` |
| `g` | Reemplaza **todas** las ocurrencias en cada línea | `s/foo/bar/g` |
| `2` | Reemplaza solo la segunda ocurrencia | `s/foo/bar/2` |
| `I` | Insensible a mayúsculas/minúsculas (GNU sed) | `s/foo/bar/I` |
| `p` | Imprime la línea si hubo sustitución (útil con `-n`) | `s/foo/bar/p` |

```bash
echo "foo foo foo" | sed 's/foo/bar/'    # bar foo foo
echo "foo foo foo" | sed 's/foo/bar/g'   # bar bar bar
echo "foo foo foo" | sed 's/foo/bar/2'   # foo bar foo
```

---

## Opciones de línea de comando

| Opción | Efecto |
|--------|--------|
| `-i` | Edita el archivo **in-place** (modifica el archivo en disco) |
| `-i.bak` | Edita in-place y guarda un backup con extensión `.bak` |
| `-n` | Suprime la salida automática (solo imprime líneas que tengan `p`) |
| `-e` | Permite encadenar múltiples instrucciones |
| `-E` | Usa expresiones regulares extendidas (ERE) — equivalente a `grep -E` |

### -i vs pipes

```bash
# ❌ Incompatible: -i necesita un archivo, no stdin
cat archivo.conf | sed -i 's/80/6300/'

# ✅ In-place: modifica el archivo directamente
sed -i 's/Listen 80/Listen 6300/' /etc/apache2/ports.conf

# ✅ Stream: lee el archivo, imprime resultado a stdout
sed 's/Listen 80/Listen 6300/' /etc/apache2/ports.conf

# ✅ Con backup antes de modificar
sed -i.bak 's/Listen 80/Listen 6300/' /etc/apache2/ports.conf
# Crea ports.conf.bak con el contenido original
```

---

## Rangos de direcciones

Por defecto, `sed` aplica la instrucción a **todas** las líneas. Se puede restringir a líneas específicas:

```bash
# Por número de línea
sed '3s/foo/bar/'        # solo línea 3
sed '2,5s/foo/bar/'      # líneas 2 a 5
sed '2,$s/foo/bar/'      # desde línea 2 hasta el final

# Por patrón
sed '/error/s/foo/bar/'          # solo líneas que contengan "error"
sed '/inicio/,/fin/s/foo/bar/'   # entre la línea con "inicio" y la de "fin"
```

---

## Múltiples instrucciones con -e

```bash
# Aplicar varios cambios en una sola ejecución
sed -i \
  -e 's/Listen 80/Listen 6300/' \
  -e 's/ServerName localhost/ServerName miservidor/' \
  /etc/apache2/ports.conf
```

Equivalente a ejecutar `sed` dos veces sobre el mismo archivo, pero más eficiente.

---

## Otros comandos útiles de sed

Además de `s`, sed tiene otros comandos:

```bash
# d — eliminar líneas
sed '/^#/d' archivo.conf          # eliminar líneas que empiezan con #
sed '/^$/d' archivo.conf          # eliminar líneas vacías

# p — imprimir líneas específicas (con -n)
sed -n '5,10p' archivo.log        # imprimir solo líneas 5 a 10
sed -n '/ERROR/p' archivo.log     # imprimir solo líneas con ERROR

# a — agregar línea después del match
sed '/Listen 6300/a # Puerto personalizado' ports.conf

# i — insertar línea antes del match
sed '/Listen 6300/i # Configuración de red' ports.conf
```

---

## Caracteres especiales en patrones

Algunos caracteres tienen significado especial en regex y deben escaparse con `\` si se quieren usar como literales:

| Carácter | Significado en regex | Para usarlo literal |
|----------|---------------------|---------------------|
| `.` | Cualquier carácter | `\.` |
| `*` | Cero o más del anterior | `\*` |
| `[` | Inicio de clase | `\[` |
| `/` | Separador de sed | Usar otro separador |

### Cambiar el separador

Cuando el patrón o el reemplazo contienen `/`, se puede usar cualquier otro carácter como separador:

```bash
# ❌ Confuso con rutas que contienen /
sed 's/\/etc\/apache2/\/etc\/nginx/'

# ✅ Usando | como separador
sed 's|/etc/apache2|/etc/nginx|'

# ✅ Usando # como separador
sed 's#/etc/apache2#/etc/nginx#'
```

---

## Casos de uso frecuentes en DevOps

```bash
# Cambiar un puerto en un archivo de configuración
sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf

# Comentar una línea que contiene un patrón
sed -i 's/^def func/#def func/' /app/main.py

# Descomentar una línea (eliminar el # inicial)
sed -i 's/^#def func/def func/' /app/main.py

# Reemplazar una variable de entorno en un archivo .env
sed -i 's/^TAG=.*/TAG=production-latest/' /app/.env

# Eliminar líneas en blanco y comentarios de un archivo
sed -i '/^$/d; /^#/d' /etc/apache2/ports.conf
```

---

## Diferencia entre sed, awk y grep

| Herramienta | Uso principal |
|-------------|--------------|
| `grep` | Buscar y filtrar líneas que coinciden con un patrón |
| `sed` | Transformar texto: sustituir, eliminar, insertar líneas |
| `awk` | Procesar texto estructurado por columnas/campos |

La regla general: si necesitas **encontrar** → `grep`. Si necesitas **editar** → `sed`. Si necesitas **procesar columnas** → `awk`.
