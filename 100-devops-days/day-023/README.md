# Dia 23 - Fork de un repositorio Git en Gitea

## Problema / Desafio

Un nuevo desarrollador (Jon) se unio al equipo del proyecto Nautilus y necesita comenzar a trabajar en un proyecto existente:

1. Acceder a la interfaz web de Gitea
2. Iniciar sesion con el usuario `jon` (password: `Jon_pass123`)
3. Localizar el repositorio `sarah/story-blog` y hacer un fork bajo el usuario `jon`

## Conceptos clave

### Que es un Fork

Un fork es una **copia completa** de un repositorio bajo tu propia cuenta. A diferencia de un clone (que es una copia local), el fork vive en el servidor Git y te permite:

- Trabajar de forma independiente sin afectar el repositorio original
- Proponer cambios al repositorio original mediante Pull Requests
- Experimentar libremente con el codigo

```
Repositorio original:              Fork:
sarah/story-blog                   jon/story-blog
├── README.md                      ├── README.md        ← copia exacta
├── posts/                         ├── posts/
└── .git/                          └── .git/
    (sarah es owner)                   (jon es owner)
```

### Fork vs Clone vs Branch

| Concepto | Donde vive | Proposito | Relacion con el original |
|----------|:----------:|-----------|--------------------------|
| **Fork** | Servidor (otra cuenta) | Copia independiente para contribuir | Mantiene referencia al upstream |
| **Clone** | Maquina local | Copia de trabajo local | Mantiene referencia al origin |
| **Branch** | Mismo repositorio | Linea de desarrollo paralela | Mismo repositorio |

```
Fork + Clone (flujo tipico de contribucion):

  [sarah/story-blog]  ←── Pull Request ──  [jon/story-blog]    (servidor)
        │                                        │
        │ clone                                  │ clone
        ↓                                        ↓
  (copia local sarah)                      (copia local jon)    (local)
```

### Flujo de trabajo con Fork

El flujo tipico de contribucion con forks:

```
1. Fork      →  Copiar el repo a tu cuenta
2. Clone     →  Descargar tu fork a tu maquina local
3. Branch    →  Crear un branch para tus cambios
4. Commit    →  Hacer cambios y commits
5. Push      →  Subir cambios a tu fork
6. PR        →  Crear Pull Request al repo original
```

### Gitea — plataforma Git self-hosted

Gitea es una plataforma Git self-hosted ligera, similar a GitHub o GitLab pero diseñada para ser:

- **Ligera** — consume pocos recursos (puede correr en una Raspberry Pi)
- **Facil de instalar** — un solo binario o contenedor Docker
- **Compatible** — API compatible con GitHub, soporta webhooks, CI/CD, etc.

| Caracteristica | GitHub | GitLab | Gitea |
|----------------|:------:|:------:|:-----:|
| Self-hosted | No (Enterprise si) | Si | Si |
| Recursos minimos | N/A | ~4GB RAM | ~256MB RAM |
| Open source | No | Community Edition | Si (MIT) |
| CI/CD integrado | GitHub Actions | GitLab CI | Gitea Actions (desde v1.19) |
| Lenguaje | Ruby/Go | Ruby/Go | Go |

## Pasos

### 1. Acceder a Gitea

Hacer click en el boton **Gitea UI** en la barra superior del entorno de laboratorio para abrir la interfaz web.

### 2. Iniciar sesion como Jon

- **Username:** `jon`
- **Password:** `Jon_pass123`

### 3. Localizar el repositorio

Navegar al repositorio `sarah/story-blog`. Se puede encontrar de varias formas:

- Usar la barra de busqueda y buscar `story-blog`
- Ir directamente a la URL: `http://<gitea-server>/sarah/story-blog`
- Ir a **Explore** > **Repositories** y buscar el repositorio

### 4. Hacer Fork del repositorio

1. Dentro del repositorio `sarah/story-blog`, hacer click en el boton **Fork** (esquina superior derecha)
2. Seleccionar el usuario **jon** como destino del fork
3. Click en **Fork Repository**

Despues del fork, se redirige automaticamente a `jon/story-blog` — la copia del repositorio bajo la cuenta de Jon.

### 5. Verificar el fork

Confirmar que:
- El repositorio aparece como `jon/story-blog`
- Se muestra la etiqueta **"forked from sarah/story-blog"** debajo del nombre
- El contenido (archivos, commits) es identico al repositorio original

## Comandos / Codigo

### Trabajar con el fork despues de crearlo (opcional)

Una vez creado el fork en Gitea, Jon puede clonarlo localmente para empezar a trabajar:

```bash
# Clonar el fork
git clone http://<gitea-server>/jon/story-blog.git
cd story-blog

# Verificar el remote (apunta al fork)
git remote -v
```

```
origin  http://<gitea-server>/jon/story-blog.git (fetch)
origin  http://<gitea-server>/jon/story-blog.git (push)
```

### Configurar el upstream (repositorio original)

Para mantener el fork sincronizado con el repositorio original de Sarah:

```bash
# Agregar el repositorio original como upstream
git remote add upstream http://<gitea-server>/sarah/story-blog.git

# Verificar ambos remotes
git remote -v
```

```
origin    http://<gitea-server>/jon/story-blog.git (fetch)
origin    http://<gitea-server>/jon/story-blog.git (push)
upstream  http://<gitea-server>/sarah/story-blog.git (fetch)
upstream  http://<gitea-server>/sarah/story-blog.git (push)
```

### Sincronizar el fork con el upstream

```bash
# Obtener cambios del repositorio original
git fetch upstream

# Fusionar cambios de upstream/main en tu branch local
git checkout main
git merge upstream/main

# Subir los cambios sincronizados a tu fork
git push origin main
```

```
upstream (sarah/story-blog)
    │
    │ git fetch upstream
    ↓
tu repo local (main)
    │
    │ git push origin main
    ↓
origin (jon/story-blog)
```

### Fork via API de Gitea

Gitea tambien permite hacer fork via su API REST:

```bash
# Fork usando la API de Gitea
curl -X POST "http://<gitea-server>/api/v1/repos/sarah/story-blog/forks" \
  -H "Content-Type: application/json" \
  -u "jon:Jon_pass123"
```

```json
{
  "id": 2,
  "name": "story-blog",
  "full_name": "jon/story-blog",
  "fork": true,
  "parent": {
    "full_name": "sarah/story-blog"
  }
}
```

## Fork en Gitea vs GitHub

La interfaz es muy similar, pero hay algunas diferencias menores:

| Accion | GitHub | Gitea |
|--------|--------|-------|
| Boton de Fork | Esquina superior derecha | Esquina superior derecha |
| Seleccionar destino | Popup con cuentas/orgs | Pagina de configuracion |
| Cambiar nombre al fork | Si (desde 2022) | Si |
| Fork de repos privados | Si (con permisos) | Si (con permisos) |
| Sincronizar fork | Boton "Sync fork" | Manual o via API |

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| No aparece el boton Fork | Verificar que estas logueado. No puedes hacer fork de tu propio repositorio |
| Error "repository already exists" | Ya existe un fork previo. Ir a `jon/story-blog` o eliminarlo primero |
| No se encuentra `sarah/story-blog` | Verificar que el repositorio existe y es publico (o que jon tiene permisos de lectura) |
| Error de permisos al clonar el fork | Verificar las credenciales: `git clone http://jon:Jon_pass123@<server>/jon/story-blog.git` |

## Recursos

- [Gitea - Fork a Repository](https://docs.gitea.com/usage/fork-a-repo)
- [Gitea API Documentation](https://docs.gitea.com/development/api-usage)
- [Git - Contributing to a Project (Pro Git Book)](https://git-scm.com/book/en/v2/GitHub-Contributing-to-a-Project)
