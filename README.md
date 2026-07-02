# 100 Days DevOps Journal

Reto personal de 100 días para aprender y practicar DevOps. Cada día se documenta un desafío, concepto o práctica relacionada con el mundo DevOps.

## 🎉 Reto completado — 100/100 días

El reto está terminado. El recorrido atravesó cuatro grandes bloques, cada uno construyendo sobre el anterior:

| Bloque | Días | Foco | Días representativos |
| ------ | ---- | ---- | -------------------- |
| **Fundamentos Linux** | 1 – 47 | Usuarios, permisos, servicios, SSH, scripting, redes | — |
| **Kubernetes** | 48 – 67 | Pods, Deployments, Services, ConfigMaps/Secrets, volúmenes, stacks multi-componente | [Día 55 (sidecars)](100-devops-days/day-055/README.md) · [Día 66 (stack MySQL)](100-devops-days/day-066/README.md) |
| **CI/CD (Jenkins)** | 68 – 81 | Setup, plugins, RBAC, jobs parametrizados, pipelines declarativos, chained builds | [Día 77 (deploy pipeline)](100-devops-days/day-077/README.md) · [Día 81 (multistage + test)](100-devops-days/day-081/README.md) |
| **Ansible** | 82 – 93 | Inventarios, playbooks, módulos (`copy`/`file`/`yum`/`service`/`acl`/`lineinfile`/`template`), roles, condicionales | [Día 92 (roles + Jinja2)](100-devops-days/day-092/README.md) · [Día 93 (`when`)](100-devops-days/day-093/README.md) |
| **Terraform / IaC** | 94 – 100 | VPC, SG, EC2, IAM, DynamoDB, CloudWatch; state, variables, outputs, idempotencia | [Día 96 (EC2 + grafo)](100-devops-days/day-096/README.md) · [Día 100 (CloudWatch)](100-devops-days/day-100/README.md) |

**El hilo que conecta todo — el modelo declarativo.** Kubernetes (`kind: Deployment`), Ansible (`state: present`) y Terraform (`resource`) son la misma idea en tres dialectos: se declara el **estado deseado** y la herramienta calcula las acciones para alcanzarlo, de forma **idempotente**. Volver a aplicar no rompe nada; el criterio de "terminado" no es "el comando corrió" sino "la realidad coincide con lo declarado" (el `terraform plan` = *No changes*, el `changed=0` de Ansible).

**Lecciones transversales ancladas**:
- *"Verde ≠ correcto"* — un `apply`/build exitoso no garantiza cumplir el requisito (K8s validadores, IAM aceptando acciones vacías); verificar el estado final campo por campo.
- *Traducir el requisito literal* al campo exacto (tag `Name`, `key_name`, `ec2:Describe*`, `comparison_operator`).
- *Idempotencia* como propiedad central: `copy` por checksum, `yum state: present`, `terraform plan` limpio.

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
| [Día 10](100-devops-days/day-010/README.md) | Script de backup para sitio web estatico | Completado |
| [Día 11](100-devops-days/day-011/README.md) | Instalar y configurar Apache Tomcat | Completado |
| [Día 12](100-devops-days/day-012/README.md) | Troubleshooting de Apache: Puerto ocupado por otro proceso + Guia iptables | Completado |
| [Día 13](100-devops-days/day-013/README.md) | Implementar iptables para restringir acceso a Apache | Completado |
| [Día 14](100-devops-days/day-014/README.md) | Troubleshooting de Apache: Servicio caido por conflicto de puerto | Completado |
| [Día 15](100-devops-days/day-015/README.md) | Instalar y configurar Nginx con SSL (Self-Signed Certificate) | Completado |
| [Día 16](100-devops-days/day-016/README.md) | Configurar Nginx como Load Balancer | Completado |
| [Día 17](100-devops-days/day-017/README.md) | Configurar PostgreSQL: Crear usuario y base de datos | Completado |
| [Día 18](100-devops-days/day-018/README.md) | Instalar y configurar LAMP Stack (Linux, Apache, MariaDB, PHP) | Completado |
| [Día 19](100-devops-days/day-019/README.md) | Configurar Apache para servir múltiples sitios con Alias | Completado |
| [Día 20](100-devops-days/day-020/README.md) | Configurar Nginx + PHP-FPM para servir una aplicacion PHP | Completado |
| [Día 21](100-devops-days/day-021/README.md) | Crear un repositorio Git bare en un servidor | Completado |
| [Día 22](100-devops-days/day-022/README.md) | Clonar un repositorio Git bare en el mismo servidor | Completado |
| [Día 23](100-devops-days/day-023/README.md) | Fork de un repositorio Git en Gitea | Completado |
| [Día 24](100-devops-days/day-024/README.md) | Crear branches en un repositorio Git | Completado |
| [Día 25](100-devops-days/day-025/README.md) | Flujo completo de branch: crear, commitear, mergear y pushear | Completado |
| [Día 26](100-devops-days/day-026/README.md) | Agregar un remote adicional en Git y pushear a él | Completado |
| [Día 27](100-devops-days/day-027/README.md) | Revertir el último commit con git revert | Completado |
| [Día 28](100-devops-days/day-028/README.md) | Cherry-pick: copiar un commit específico entre branches | Completado |
| [Día 29](100-devops-days/day-029/README.md) | Flujo de Pull Request en Gitea: rama feature → master | Completado |
| [Día 30](100-devops-days/day-030/README.md) | Limpiar historial de commits con git reset | Completado |
| [Día 31](100-devops-days/day-031/README.md) | Restaurar un stash específico con git stash apply | Completado |
| [Día 32](100-devops-days/day-032/README.md) | Rebase de feature branch sobre master | Completado |
| [Día 33](100-devops-days/day-033/README.md) | Resolver conflictos de merge durante git pull --rebase | Completado |
| [Día 34](100-devops-days/day-034/README.md) | Crear un post-update hook para tagging automático en Git | Completado |
| [Día 35](100-devops-days/day-035/README.md) | Instalar Docker CE e iniciar el servicio | Completado |
| [Día 36](100-devops-days/day-036/README.md) | Desplegar contenedor Nginx con Docker | Completado |
| [Día 37](100-devops-days/day-037/README.md) | Copiar archivos a un contenedor con docker cp | Completado |
| [Día 38](100-devops-days/day-038/README.md) | Pull de imagen Docker y re-tagging | Completado |
| [Día 39](100-devops-days/day-039/README.md) | Crear imagen Docker desde un contenedor | Completado |
| [Día 40](100-devops-days/day-040/README.md) | Docker EXEC: instalar y configurar Apache en un contenedor | Completado |
| [Día 41](100-devops-days/day-041/README.md) | Escribir un Dockerfile | Completado |
| [Día 42](100-devops-days/day-042/README.md) | Crear una Docker Network | Completado |
| [Día 43](100-devops-days/day-043/README.md) | Docker Port Mapping | Completado |
| [Día 44](100-devops-days/day-044/README.md) | Escribir un Docker Compose File | Completado |
| [Día 45](100-devops-days/day-045/README.md) | Resolver errores en un Dockerfile | Completado |
| [Día 46](100-devops-days/day-046/README.md) | Desplegar PHP + MariaDB con Docker Compose | Completado |
| [Día 47](100-devops-days/day-047/README.md) | Dockerizar una app Flask en Python | Completado |
| [Día 48](100-devops-days/day-048/README.md) | Desplegar un Pod en un cluster de Kubernetes | Completado |
| [Día 49](100-devops-days/day-049/README.md) | Desplegar aplicaciones con Deployments en Kubernetes | Completado |
| [Día 50](100-devops-days/day-050/README.md) | Resource Requests y Limits en Pods de Kubernetes | Completado |
| [Día 51](100-devops-days/day-051/README.md) | Rolling Update en Kubernetes Deployments | Completado |
| [Día 52](100-devops-days/day-052/README.md) | Rollback de un Deployment a la versión anterior | Completado |
| [Día 53](100-devops-days/day-053/README.md) | Troubleshooting: VolumeMount mal alineado en Nginx + PHP-FPM | Completado |
| [Día 54](100-devops-days/day-054/README.md) | Shared Volumes en Kubernetes (emptyDir) | Completado |
| [Día 55](100-devops-days/day-055/README.md) | Sidecar Containers (patrón native con initContainers) | Completado |
| [Día 56](100-devops-days/day-056/README.md) | Deployment + Service NodePort para nginx | Completado |
| [Día 57](100-devops-days/day-057/README.md) | Variables de entorno en Pods y `$(VAR)` substitution | Completado |
| [Día 58](100-devops-days/day-058/README.md) | Deployment Grafana — autopsia de labels y selectors | Completado |
| [Día 59](100-devops-days/day-059/README.md) | Troubleshooting Deployment: typo en image + ConfigMap inexistente | Completado |
| [Día 60](100-devops-days/day-060/README.md) | Persistent Volumes en Kubernetes (PV + PVC + Pod + Service) | Completado |
| [Día 61](100-devops-days/day-061/README.md) | Init Containers en Kubernetes | Completado |
| [Día 62](100-devops-days/day-062/README.md) | Manejo de Secrets en Kubernetes | Completado |
| [Día 63](100-devops-days/day-063/README.md) | Deploy Iron Gallery — stack multi-componente (app + DB + 2 services + namespace) | Completado |
| [Día 64](100-devops-days/day-064/README.md) | Troubleshooting Python Flask en K8s — dos bugs simultáneos (image typo + port mismatch) | Completado |
| [Día 65](100-devops-days/day-065/README.md) | Deploy de Redis en K8s con ConfigMap montado como volumen | Completado |
| [Día 66](100-devops-days/day-066/README.md) | Deploy de MySQL en K8s — stack completo (PV + PVC + Secrets + env vars + Deployment + Service NodePort) | Completado |
| [Día 67](100-devops-days/day-067/README.md) | Deploy Guestbook App — 3 Deployments + 4 Services (PHP frontend + Redis master/slave) + DNS discovery | Completado |
| [Día 68](100-devops-days/day-068/README.md) | Set Up Jenkins Server — instalación con apt + Java 21 + setup wizard (transición a CI/CD) | Completado |
| [Día 69](100-devops-days/day-069/README.md) | Install Jenkins Plugins — Git + GitLab vía Update Center + restart con drain | Completado |
| [Día 70](100-devops-days/day-070/README.md) | Configure Jenkins User Access — Project-based Matrix Authorization (user `anita` con Overall Read global + Job Read por-proyecto) | Completado |
| [Día 71](100-devops-days/day-071/README.md) | Jenkins Job: Package Installation — Freestyle + String Parameter + SSH remoto + yum install (fix de key mismatch) | Completado |
| [Día 72](100-devops-days/day-072/README.md) | Jenkins Parameterized Builds — String Parameter + Choice Parameter + echo en shell | Completado |
| [Día 73](100-devops-days/day-073/README.md) | Jenkins Scheduled Jobs — cron trigger `*/3 * * * *` + scp multi-server (Jenkins → stapp02 → ststor01) | Completado |
| [Día 74](100-devops-days/day-074/README.md) | Jenkins Database Backup Job — mysqldump + Credentials Manager (Secret text + binding) + cron `*/10` | Completado |
| [Día 75](100-devops-days/day-075/README.md) | Jenkins Slave Nodes — Controller + 3 Agents (inbound JNLP/WebSocket, Java 17, labels stapp01/02/03) | Completado |
| [Día 76](100-devops-days/day-076/README.md) | Jenkins Project Security — Project-based Matrix con Inheritance Strategy (sam + rohan sobre job Packages) | Completado |
| [Día 77](100-devops-days/day-077/README.md) | Jenkins Deploy Pipeline — primer Declarative Pipeline (git pull deploy via agent corriendo como sarah) | Completado |
| [Día 78](100-devops-days/day-078/README.md) | Jenkins Conditional Pipeline — parameters + `script { if/else }` para deploy por branch (master/feature) | Completado |
| [Día 79](100-devops-days/day-079/README.md) | Jenkins Deployment Job — Freestyle + Poll SCM + sudo NOPASSWD + cp deploy + auto-trigger por git push | Completado |
| [Día 80](100-devops-days/day-080/README.md) | Jenkins Chained Builds — upstream `devops-app-deployment` → downstream `manage-services` con "trigger only if stable" | Completado |
| [Día 81](100-devops-days/day-081/README.md) | Jenkins Multistage Pipeline — Deploy + Test con `curl -fsS \| grep -q` + agent via Launch via SSH | Completado |
| [Día 82](100-devops-days/day-082/README.md) | Ansible Inventory para App Server Testing — primer lab de Ansible en el journal principal, formato INI con `stapp03` | Completado |
| [Día 83](100-devops-days/day-083/README.md) | Troubleshoot and Create Ansible Playbook — corregir inventario + primer playbook con módulo `file` + `state: touch` | Completado |
| [Día 84](100-devops-days/day-084/README.md) | Copy Data to App Servers using Ansible — `hosts: all` + módulo `copy` + `become: true` a los 3 app servers | Completado |
| [Día 85](100-devops-days/day-085/README.md) | Create Files on App Servers using Ansible — módulo `file` + `mode: '0777'` + `owner: "{{ ansible_user }}"` por host | Completado |
| [Día 86](100-devops-days/day-086/README.md) | Ansible Ping Module Usage — passwordless SSH (`ssh-keygen` + `ssh-copy-id`) + módulo `ping` (SSH+Python, no ICMP) | Completado |
| [Día 87](100-devops-days/day-087/README.md) | Ansible Install Package — módulo `yum` con `state: present` + idempotencia + `become: true` en los 3 app servers | Completado |
| [Día 88](100-devops-days/day-088/README.md) | Ansible Blockinfile Module — instalar `httpd` + `service` started/enabled + `blockinfile` con marcadores por defecto, `create: yes`, owner/group `apache`, `mode '0655'` | Completado |
| [Día 89](100-devops-days/day-089/README.md) | Ansible Manage Services — módulo `service` en profundidad: `started` (idempotente) vs `restarted` (siempre), `enabled: yes` (boot), handlers/`notify`, `service` vs `systemd` | Completado |
| [Día 90](100-devops-days/day-090/README.md) | Managing ACLs Using Ansible — módulo `acl` (`entity`/`etype`/`permissions`) + POSIX ACLs (`getfacl`/mask) para dar acceso a un tercero sin cambiar owner; primer playbook **multi-play** (un play por host) | Completado |
| [Día 91](100-devops-days/day-091/README.md) | Ansible Lineinfile Module — `httpd` + `service` + `lineinfile` (`line`/`insertbefore: BOF`/`regexp`); idempotente sobre la línea completa; `state: touch` **no trunca** (sobrevive contenido pre-sembrado); perms `0744` | Completado |
| [Día 92](100-devops-days/day-092/README.md) | Managing Jinja2 Templates — primer **role** (estructura `tasks/templates/...`) + módulo `template` (renderiza Jinja2) + `inventory_hostname` (vs `ansible_hostname`) + templating lazy por host; owner `ansible_user`, perms `0777` | Completado |
| [Día 93](100-devops-days/day-093/README.md) | Using Ansible Conditionals — `hosts: all` + `when: ansible_nodename == ...` por task (tercera forma de routing host→archivo vs multi-play día 90); `when` produce `skipped`; fact obliga `gather_facts`; owner `ansible_user`, perms `0777` | Completado |
| [Día 94](100-devops-days/day-094/README.md) | **Create VPC Using Terraform** — inicio sección IaC/Terraform: `provider` (region `us-east-1`) + `resource "aws_vpc"` (tag `Name`), ciclo `init`/`plan`/`apply`, concepto de **state** y drift; provisioning vs configuration management | Completado |
| [Día 95](100-devops-days/day-095/README.md) | Create Security Group Using Terraform — `data "aws_vpc"` (leer vs crear) + `aws_security_group` con reglas `ingress` (HTTP 80 / SSH 22, `0.0.0.0/0`); gotcha **`name` (GroupName real) vs tag `Name`** — inverso al día 94; `name`/`description` inmutables (replace) | Completado |
| [Día 96](100-devops-days/day-096/README.md) | Create EC2 Instance Using Terraform — **multi-provider** (`aws`/`tls`/`local`): `tls_private_key` + `aws_key_pair` + `local_file` (`.pem` 0400) + `aws_instance`; **grafo de dependencias** implícito (`key_name` referencia); `vpc_security_group_ids` (id) vs `security_groups` (legacy); secretos en el state | Completado |
| [Día 97](100-devops-days/day-097/README.md) | Create IAM Policy Using Terraform — `aws_iam_policy` + data source `aws_iam_policy_document` (`.json`); lenguaje JSON de policies (Version/Statement/Effect/Action/Resource); gotcha **`ec2:Describe*`** (con wildcard) y `.json` (object vs string); IAM global pero provider necesita región | Completado |
| [Día 98](100-devops-days/day-098/README.md) | Launch EC2 in Private VPC Subnet — primer proyecto **multi-archivo** (`main`/`variables`/`outputs`): VPC + subnet (`map_public_ip_on_launch=false`) + SG (ingress solo CIDR VPC) + EC2; `variable`/`var.X` + `output`; requisito de **idempotencia** (`plan` "No changes"); `(known after apply)` referencia vs no-seteado | Completado |
| [Día 99](100-devops-days/day-099/README.md) | Attach IAM Policy for DynamoDB Access — `aws_dynamodb_table` (minimal, `PAY_PER_REQUEST`) + **IAM role** (`assume_role_policy`/trust) + policy read-only **scoped al ARN** + `aws_iam_role_policy_attachment`; cierra el arco IAM del día 97; `terraform.tfvars` | Completado |
| [Día 100](100-devops-days/day-100/README.md) | 🎉 **Create and Configure CloudWatch Alarm** — cierre del reto: `aws_instance` + `aws_cloudwatch_metric_alarm` (mapeo spec→campos: `comparison_operator`/`threshold`/`period 300`/`evaluation_periods`) + `dimensions.InstanceId` + `alarm_actions` a SNS; observabilidad como paso final del ciclo IaC | Completado |

## Progreso - Kubernetes

| Día | Tema | Estado |
|-----|------|--------|
| [Día 01](kubernetes-journal/days/day-01/README.md) | Crear un Pod en Kubernetes | Completado |
| [Día 02](kubernetes-journal/day-002/README.md) | Crear un Deployment en Kubernetes | Completado |
| [Día 03](kubernetes-journal/day-003/README.md) | Crear un Namespace y desplegar un Pod en él | Completado |
| [Día 04](kubernetes-journal/day-004/README.md) | Resource Requests y Limits | Completado |
| [Día 05](kubernetes-journal/day-005/README.md) | Rolling Update de un Deployment | Completado |
| [Día 06](kubernetes-journal/day-006/README.md) | Rollback de un Deployment a una revisión previa | Completado |
| [Día 07](kubernetes-journal/day-007/README.md) | Crear un ReplicaSet con httpd | Completado |
| [Día 08](kubernetes-journal/day-008/README.md) | Crear un CronJob en Kubernetes | Completado |
| [Día 09](kubernetes-journal/day-009/README.md) | Crear un Job Countdown en Kubernetes | Completado |
| [Día 10](kubernetes-journal/day-010/README.md) | Pod con ConfigMap, Variable de Entorno y Volume Mount | Completado |
| [Día 11](kubernetes-journal/day-011/README.md) | Troubleshooting de Pod: ImagePullBackOff | Completado |
| [Día 12](kubernetes-journal/day-012/README.md) | Actualizar Deployment y Service sin eliminarlos | Completado |
| [Día 13](kubernetes-journal/day-013/README.md) | Crear un ReplicationController | Completado |
| [Día 14](kubernetes-journal/day-014/README.md) | Troubleshooting Nginx + PHP-FPM en Kubernetes | Completado |

## Progreso - Ansible

| Día | Tema | Estado |
|-----|------|--------|
| [Día 01](ansible-journal/days/day-01/README.md) | Crear un archivo vacío con Ansible | Completado |
| [Día 02](ansible-journal/day-002/README.md) | Instalar e iniciar httpd con Ansible | Completado |
| [Día 03](ansible-journal/day-003/README.md) | — | Completado |
| [Día 04](ansible-journal/day-004/README.md) | Copiar archivos a servidores de aplicación | Completado |
| [Día 05](ansible-journal/day-005/README.md) | Crear archivos con permisos y propietario específico | Completado |

## Herramientas

| Herramienta | Descripción |
|-------------|-------------|
| [sed](tools/sed/README.md) | Stream Editor — sustitución, filtrado y edición de texto en línea de comandos |
| [kubectl](tools/kubectl/README.md) | Guía de Kubernetes: seleccionar, editar componentes, volúmenes, config y secretos |
| [ansible](tools/ansible/README.md) | Guía de Ansible: inventarios, conceptos fundamentales, comandos básicos |
| [terraform](tools/terraform/README.md) | Guía de Terraform/IaC: providers, resources, state, ciclo init/plan/apply, CIDR y redes |

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
