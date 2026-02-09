# 100 Days DevOps Journey

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

## Progreso - Kubernetes

| Día | Tema | Estado |
|-----|------|--------|
| [Día 01](kubernetes-journey/days/day-01/README.md) | Crear un Pod en Kubernetes | Completado |
| [Día 02](kubernetes-journey/day-002/README.md) | Crear un Deployment en Kubernetes | Completado |
| [Día 03](kubernetes-journey/day-003/README.md) | Crear un Namespace y desplegar un Pod en él | Completado |

## Progreso - Ansible

| Día | Tema | Estado |
|-----|------|--------|
| [Día 01](ansible-journey/days/day-01/README.md) | Crear un archivo vacío con Ansible | Completado |
| [Día 02](ansible-journey/day-002/README.md) | Instalar e iniciar httpd con Ansible | Completado |

## Estructura del repositorio

```
100-days-devops-journey/
├── README.md
├── 100-devops-days/
│   ├── template.md
│   └── day-XXX/
│       └── README.md
├── kubernetes-journey/
│   ├── template.md
│   └── days/
│       └── day-XX/
│           └── README.md
└── ansible-journey/
    ├── template.md
    └── days/
        └── day-XX/
            └── README.md
```

- Cada journey tiene su propia carpeta con la misma estructura de `days/`
- Los scripts o archivos de código del día se guardan junto al README en la misma carpeta
- Se usa `template.md` de cada journey como plantilla para crear nuevos días
