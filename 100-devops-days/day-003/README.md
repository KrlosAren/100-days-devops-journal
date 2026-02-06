# Día 03 - Deshabilitar el acceso SSH directo como root

## Problema / Desafío

Deshabilitar el login SSH directo como root en todos los servidores de la aplicación. Esto es una práctica de seguridad fundamental: el acceso root directo por SSH expone al servidor a ataques de fuerza bruta contra una cuenta con privilegios totales.

## Conceptos clave

- **`root` es el objetivo #1 de ataques de fuerza bruta**: Los bots escanean servidores constantemente intentando combinaciones de contraseña contra el usuario `root`, porque es el único usuario que existe garantizado en todo sistema Linux y tiene privilegios totales.
- **Principio de menor privilegio**: Ningún usuario debería operar con más permisos de los necesarios. Acceder como usuario normal y elevar con `sudo` solo cuando se requiere reduce el riesgo de errores destructivos y limita el daño si la cuenta se compromete.
- **Trazabilidad**: Si todos acceden como `root`, no hay forma de saber quién ejecutó qué. Con usuarios individuales, cada acción queda asociada a una persona en los logs (`/var/log/auth.log` o `/var/log/secure`).
- **Defensa en profundidad**: Deshabilitar root por SSH es una capa más de seguridad. Un atacante necesitaría primero adivinar un nombre de usuario válido, luego su contraseña, y después escalar a root — tres barreras en lugar de una.
- **`PermitRootLogin`**: Directiva en `/etc/ssh/sshd_config` que controla si el usuario root puede autenticarse por SSH. Sus posibles valores son:

| Valor | Efecto |
|-------|--------|
| `yes` | Root puede hacer login con contraseña o clave SSH. Es el valor por defecto en muchas distribuciones y el menos seguro, ya que no pone ninguna restricción. |
| `no` | Root no puede hacer login por SSH de ninguna forma. Es la opción más segura y la recomendada para servidores en producción. |
| `prohibit-password` | Root solo puede autenticarse con clave SSH, se bloquea el acceso por contraseña. Útil cuando se necesita acceso root remoto para automatización pero se quiere eliminar el riesgo de fuerza bruta. |
| `forced-commands-only` | Root solo puede autenticarse con clave SSH y únicamente para ejecutar comandos específicos definidos en `authorized_keys`. Es la opción más restrictiva que aún permite algún acceso root, ideal para tareas puntuales como backups remotos. |

## Solución

```bash
# Editar la configuración de SSH
sudo vi /etc/ssh/sshd_config
```

Buscar la línea `PermitRootLogin` y cambiarla a:

```
PermitRootLogin no
```

Si la línea está comentada (con `#`), descomentarla y establecer el valor en `no`.

Luego reiniciar el servicio SSH para aplicar los cambios:

```bash
sudo systemctl restart sshd
```

### Desglose de la configuración

**`/etc/ssh/sshd_config`**: Archivo de configuración del daemon SSH (`sshd`). Controla cómo el servidor acepta conexiones SSH entrantes.

**`PermitRootLogin`**: Directiva que controla si el usuario root puede autenticarse directamente por SSH. Sus valores posibles son:

| Valor | Comportamiento |
|-------|---------------|
| `yes` | Root puede hacer login con contraseña o clave SSH (por defecto en muchas distros) |
| `no` | Root no puede hacer login por SSH de ninguna forma |
| `prohibit-password` | Root solo puede usar claves SSH, no contraseña |
| `forced-commands-only` | Root solo puede usar claves SSH y solo para ejecutar comandos específicos definidos en `authorized_keys` |

**`systemctl restart sshd`**: Reinicia el daemon SSH para que lea la nueva configuración. Las sesiones SSH activas no se desconectan al reiniciar el servicio.

### Aplicar en todos los servidores

Si hay múltiples servidores, ejecutar en cada uno:

```bash
# Usando sed para modificar la configuración directamente
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Reiniciar el servicio
sudo systemctl restart sshd
```

El comando `sed` busca cualquier línea que empiece con `PermitRootLogin` (comentada o no, gracias a `#*`) y la reemplaza por `PermitRootLogin no`.

### Verificación

```bash
# Confirmar que la directiva está configurada correctamente
grep -i "^PermitRootLogin" /etc/ssh/sshd_config
# Salida esperada: PermitRootLogin no

# Intentar conectar como root (debe fallar)
ssh root@<IP_DEL_SERVIDOR>
# Salida esperada: Permission denied, please try again.

# Verificar que el servicio SSH está activo
sudo systemctl status sshd
```

## Troubleshooting

| Problema | Solución |
|----------|----------|
| El cambio no toma efecto después de editar el archivo | Reiniciar el servicio con `sudo systemctl restart sshd` |
| Se pierde acceso al servidor después del cambio | Asegurar que existe otro usuario con acceso SSH y permisos de `sudo` antes de deshabilitar root |
| Hay líneas duplicadas de `PermitRootLogin` | Verificar que solo exista una línea activa (sin `#`) con `grep -n "PermitRootLogin" /etc/ssh/sshd_config` |
| `sshd` no arranca después del cambio | Validar la configuración con `sudo sshd -t` para detectar errores de sintaxis |

## Recursos

- [sshd_config - Manual de Linux](https://man7.org/linux/man-pages/man5/sshd_config.5.html)
- [Guía de hardening SSH - CIS Benchmarks](https://www.cisecurity.org/benchmark/distribution_independent_linux)
- [Buenas prácticas de seguridad SSH](https://www.ssh.com/academy/ssh/sshd_config)
