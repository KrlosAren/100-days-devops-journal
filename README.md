# 100 Days DevOps Journal

Reto personal de 100 días para aprender y practicar DevOps. Cada día se documenta un desafío, concepto o práctica relacionada con el mundo DevOps.

## Reglas del reto

1. Dedicar tiempo cada día a un tema de DevOps
2. Documentar lo aprendido en el README del día correspondiente
3. Incluir comandos, código y recursos utilizados
4. Registrar problemas encontrados y sus soluciones
5. Cada día se guarda en `days/day-XX/` con su propio `README.md`

## Progreso - DevOps General

| Día | Tema | Estado |
|-----|------|--------|
| [Día 01](100-devops-days/day-001/README.md) | Crear usuarios de servicio sin shell interactiva | Completado |
| [Día 02](100-devops-days/day-002/README.md) | Crear un usuario con fecha de expiración | Completado |
| [Día 03](100-devops-days/day-003/README.md) | Deshabilitar el acceso SSH directo como root | Completado |
| [Día 04](100-devops-days/day-004/README.md) | Permisos de ejecución y propiedad de archivos | Completado |
| [Día 05](100-devops-days/day-005/README.md) | SELinux | Completado |
| [Día 06](100-devops-days/day-006/README.md) | Crear un Cron Job con Cronie | Completado |
| [Día 07](100-devops-days/day-007/README.md) | Autenticación SSH sin contraseña (password-less) | Completado |
| [Día 08](100-devops-days/day-008/README.md) | Instalar Ansible con pip3 disponible para todos los usuarios | Completado |
| [Día 09](100-devops-days/day-009/README.md) | Troubleshooting: MariaDB no inicia por directorio faltante | Completado |

## Progreso - Kubernetes

| Día | Tema | Estado |
|-----|------|--------|
| [Día 01](kubernetes-journal/days/day-01/README.md) | Crear un Pod en Kubernetes | Completado |
| [Día 02](kubernetes-journal/day-002/README.md) | Crear un Deployment en Kubernetes | Completado |
| [Día 03](kubernetes-journal/day-003/README.md) | Crear un Namespace y desplegar un Pod en él | Completado |
| [Día 04](kubernetes-journal/day-004/README.md) | Resource Requests y Limits | Completado |
| [Día 05](kubernetes-journal/day-005/README.md) | Rolling Update de un Deployment | Completado |
| [Día 06](kubernetes-journal/day-006/README.md) | Rollback de un Deployment a una revisión previa | Completado |

## Progreso - Ansible

| Día | Tema | Estado |
|-----|------|--------|
| [Día 01](ansible-journal/days/day-01/README.md) | Crear un archivo vacío con Ansible | Completado |
| [Día 02](ansible-journal/day-002/README.md) | Instalar e iniciar httpd con Ansible | Completado |
| [Día 03](ansible-journal/day-003/README.md) | — | Completado |
| [Día 04](ansible-journal/day-004/README.md) | Copiar archivos a servidores de aplicación | Completado |
| [Día 05](ansible-journal/day-005/README.md) | Crear archivos con permisos y propietario específico | Completado |

## Estructura del repositorio

```
100-days-devops-journal/
├── README.md
├── 100-devops-days/
│   ├── template.md
│   └── day-XXX/
│       └── README.md
├── kubernetes-journal/
│   ├── template.md
│   └── days/
│       └── day-XX/
│           └── README.md
└── ansible-journal/
    ├── template.md
    └── days/
        └── day-XX/
            └── README.md
```

- Cada journal tiene su propia carpeta con la misma estructura de `days/`
- Los scripts o archivos de código del día se guardan junto al README en la misma carpeta
- Se usa `template.md` de cada journal como plantilla para crear nuevos días
