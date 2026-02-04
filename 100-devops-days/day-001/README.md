# Día 01 - Crear usuarios de servicio sin shell interactiva

## Problema / Desafío

Los usuarios de servicios no deben acceder al sistema usando una shell interactiva. Es necesario crear usuarios que no tengan acceso a una shell, garantizando que solo puedan ejecutar el servicio para el cual fueron creados, sin posibilidad de login interactivo.

## Conceptos clave

- **Shell interactiva**: Es la interfaz de línea de comandos que permite a un usuario ejecutar comandos de forma manual (ej: `/bin/bash`, `/bin/sh`).
- **Usuario de servicio**: Usuario del sistema creado exclusivamente para ejecutar un servicio o proceso específico (ej: `nginx`, `mysql`, `www-data`).
- `/sbin/nologin`: Shell especial que impide el login interactivo. Si alguien intenta iniciar sesión con este usuario, muestra el mensaje "This account is currently not available" y cierra la sesión. En algunas distros la ruta es `/usr/sbin/nologin` (en muchas distros modernas `/sbin` es un symlink a `/usr/sbin`, por lo que ambas rutas funcionan igual).
- `/bin/false`: Alternativa a `nologin`. Simplemente retorna un código de salida 1 (fallo), cerrando la sesión inmediatamente sin mostrar mensaje.
- **`--system`**: Flag de `useradd` que crea un usuario de sistema con UID bajo (normalmente < 1000), sin directorio home por defecto y sin contraseña.

## Pasos

1. Verificar las shells disponibles en el sistema
2. Crear un usuario de servicio usando `useradd` con la shell `/sbin/nologin`
3. Verificar que el usuario fue creado correctamente en `/etc/passwd`
4. Intentar hacer login con el usuario para confirmar que no tiene acceso interactivo

## Comandos / Código

### Solución utilizada

```bash
# Crear usuario sin shell interactiva
sudo useradd -s /sbin/nologin mi-servicio
```

### Verificación

```bash
# Ver las shells disponibles en el sistema
cat /etc/shells

# Verificar el usuario creado en /etc/passwd
grep mi-servicio /etc/passwd

# Intentar hacer login con el usuario (debe fallar)
sudo su - mi-servicio
# Salida esperada: "This account is currently not available."
```

### Alternativas

```bash
# Usando /bin/false como shell
sudo useradd -s /bin/false mi-servicio

# Creando un usuario de sistema (UID bajo, sin home)
sudo useradd --system --no-create-home -s /sbin/nologin mi-servicio

# Si el usuario ya existe y se quiere cambiar su shell
sudo usermod -s /sbin/nologin usuario-existente
```

## Comparación: usuario regular vs usuario de sistema

Usar `useradd -s /sbin/nologin` (sin `--system`) cumple el objetivo de bloquear la shell interactiva, pero crea un usuario "regular". Con `--system` se crea un usuario de sistema puro. Las diferencias son:

| Aspecto | `useradd -s /sbin/nologin` | `useradd --system --no-create-home -s /sbin/nologin` |
|---------|----------------------------|------------------------------------------------------|
| **Rango de UID** | UID alto (>= 1000), rango de usuarios normales | UID bajo (< 1000), rango reservado para servicios |
| **Directorio home** | Se puede crear `/home/usuario` (depende de la config de `/etc/login.defs`) | No se crea por defecto |
| **Aparece en login screen** | Sí, puede aparecer en pantallas de login de escritorio | No, los UID < 1000 se ocultan |
| **Expiración** | Puede tener política de expiración de cuenta | No expira nunca |
| **Grupo** | Se crea un grupo con el mismo nombre | Se asigna al grupo `nogroup` o `nobody` (varía por distro) |

**Nota sobre `--no-create-home`:** Sin `--system`, `useradd` puede crear `/home/usuario` dependiendo de cómo esté configurado `CREATE_HOME` en `/etc/login.defs`. El flag `--no-create-home` lo previene explícitamente. Con `--system` ya viene desactivado por defecto, así que es redundante pero más explícito.

**Recomendación:** Para usuarios destinados a ejecutar servicios (nginx, apps, daemons), usar `--system` es la práctica recomendada porque los marca como usuarios de sistema a nivel de UID y evita crear recursos innecesarios.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| `/sbin/nologin` no existe en el sistema | Verificar con `which nologin` la ruta correcta, o usar `/bin/false` como alternativa |
| El usuario ya tiene shell interactiva | Usar `sudo usermod -s /sbin/nologin usuario` para cambiarla |
| Se necesita ejecutar un comando como el usuario de servicio | Usar `sudo -u mi-servicio comando` en lugar de hacer login |

## Recursos

- [useradd - Manual de Linux](https://man7.org/linux/man-pages/man8/useradd.8.html)
- [nologin - Manual de Linux](https://man7.org/linux/man-pages/man8/nologin.8.html)
- [Diferencia entre /sbin/nologin y /bin/false](https://unix.stackexchange.com/questions/10852/whats-the-difference-between-sbin-nologin-and-bin-false)
