# Día 02 - Crear un usuario con fecha de expiración

## Problema / Desafío

Se necesita crear un usuario en el sistema con una fecha de expiración definida, de forma que la cuenta se deshabilite automáticamente al llegar a esa fecha.

## Solución

```bash
sudo useradd -e 2025-12-31 mi-usuario
```

### Desglose del comando

**`useradd`**: Comando para crear usuarios en Linux.

**`-e` o `--expiredate`**: Define la fecha en la que la cuenta expira y se deshabilita automáticamente. El formato es `YYYY-MM-DD`. A partir de esa fecha, el usuario no podrá iniciar sesión. La cuenta no se elimina, solo se bloquea.

Esta fecha se almacena en `/etc/shadow` como el número de días desde el 1 de enero de 1970 (epoch) hasta la fecha de expiración.

### Verificación

```bash
# Ver la información de expiración de la cuenta
sudo chage -l mi-usuario

# Revisar directamente en /etc/shadow
sudo grep mi-usuario /etc/shadow
```

La salida de `chage -l` mostrará algo como:

```
Account expires        : Dec 31, 2025
```

### Modificar la fecha de expiración de un usuario existente

```bash
# Cambiar la fecha de expiración
sudo usermod -e 2026-06-30 mi-usuario

# O usando chage
sudo chage -E 2026-06-30 mi-usuario

# Eliminar la fecha de expiración (la cuenta no expira)
sudo usermod -e "" mi-usuario
```

### Diferencia entre expiración de cuenta y expiración de contraseña

| Aspecto | Expiración de cuenta (`-e`) | Expiración de contraseña (`chage -M`) |
|---------|----------------------------|---------------------------------------|
| **Qué expira** | La cuenta completa | Solo la contraseña |
| **Efecto** | El usuario no puede hacer login de ninguna forma | El usuario debe cambiar su contraseña para seguir accediendo |
| **Se configura con** | `useradd -e` / `usermod -e` / `chage -E` | `chage -M` (máximo de días de vigencia) |
| **Dónde se almacena** | Campo 8 de `/etc/shadow` | Campo 5 de `/etc/shadow` |

## Troubleshooting

| Problema | Solución |
|----------|----------|
| El usuario sigue accediendo después de la fecha | Verificar la fecha con `chage -l usuario` y confirmar que la fecha del servidor es correcta con `date` |
| Error de formato de fecha | Usar estrictamente el formato `YYYY-MM-DD` |
| Se necesita reactivar una cuenta expirada | Usar `sudo usermod -e "" usuario` para quitar la expiración |

## Recursos

- [useradd - Manual de Linux](https://man7.org/linux/man-pages/man8/useradd.8.html)
- [chage - Manual de Linux](https://man7.org/linux/man-pages/man1/chage.1.html)
- [Campos de /etc/shadow](https://man7.org/linux/man-pages/man5/shadow.5.html)
