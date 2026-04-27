# Documentation Standards — BootcampPeru IaC Workshops

> **Audience:** A new Claude agent applying the documentation strategy from `ScrambledBits/taller-iac` to the `ScrambledBits/taller-observabilidad` project (or any future workshop project).
> **Source of truth:** The fully documented `taller-iac` repository, specifically its final state after PR #3 was merged.

---

## 1. Philosophy

### Core Principle: Explain the WHY, Not the WHAT

Well-named identifiers already explain what code does. Comments explain why a decision was made, what constraint forced a particular approach, what would break if you changed it, and what the production equivalent looks like.

```hcl
# BAD — restates the identifier:
# Creates a NAT Gateway
resource "aws_nat_gateway" "principal" { ... }

# GOOD — explains the architectural reason:
# NAT Gateway en la subnet pública: permite que las instancias privadas accedan
# a internet para instalar paquetes (apt, pip), sin exponer una IP pública propia.
# El tráfico sale por el NAT (que sí tiene IP pública), pero las conexiones entrantes
# desde internet no pueden iniciarse hacia las instancias privadas.
resource "aws_nat_gateway" "principal" { ... }
```

### Target Audience

These are DevOps students, typically with 1-3 years of experience in adjacent fields (sysadmin, development, or cloud), learning IaC practices for the first time. They understand basic Linux and networking but may not know:
- The difference between an IGW and a NAT Gateway
- What IMDSv2 is or why it matters
- What SSRF attacks are
- Why Terraform state needs to be remote
- Why ansible-lint needs FQCN module names
- Why GitHub Actions jobs are separated instead of monolithic

Every comment should be written assuming the reader has never seen this pattern before.

### Documentation Density

Not every line needs a comment. The rule:
- **File header** — always, for every file
- **Each resource/task** — always, unless it is self-evident from context (rare)
- **Non-obvious parameter values** — always
- **Design decisions with alternatives** — always, explaining why this option was chosen
- **Production vs. workshop differences** — always, flagged explicitly
- **Cross-component dependencies** — always, explaining where data comes from

---

## 2. Language Specification

### Use Spanish Neutro

All comments, documentation, and user-facing text in the code must be in **Spanish neutro** — the neutral, international Spanish used in formal technical writing. It should be understandable by a DevOps student from Mexico, Colombia, Argentina, Spain, or Peru without adjustment.

### Terms to NEVER Use

| Avoid | Reason |
|-------|--------|
| `vos`, `che` | Argentine regional |
| `tío`, `tronco` | Spanish regional |
| `wey`, `güey`, `neta` | Mexican colloquial |
| `tío/a` as filler | Spanish regional |
| `bacano`, `chévere` (in formal context) | Colombian/Venezuelan informal |
| `macanudo` | Argentine regional |

### Acceptable Informal Markers

In comments, conversational but neutral Spanish is fine:
- "es decir", "es más", "por lo tanto", "sin embargo" — acceptable connectors
- Imperative mood ("ejecutar", "verificar", "añadir") — preferred over passive
- Second person singular ("puedes", "si cambias") — acceptable when addressing the student directly

### Technical Terms: English vs. Spanish

Keep technical proper nouns in English. Translate everything else.

| Keep in English | Translate to Spanish |
|----------------|---------------------|
| Terraform, Ansible, nginx, Flask | "archivo de estado" (state file) |
| provider, backend, module | "proveedor", "módulo" |
| subnet, VPC, IGW, NAT | "subred" acceptable, but "subnet" also OK |
| security group | "grupo de seguridad" in prose, "SG" in shorthand |
| SSH, HTTP, TCP, UDP | always keep as-is |
| ansible-lint, TFLint, Checkov | always keep as-is |
| handler, play, role, task | keep in English (Ansible DSL terms) |
| workflow, job, step, runner | keep in English (GitHub Actions DSL terms) |

### First-Mention Rule

Every technical concept that a DevOps student might not know must be explained the first time it appears in each file. Do not assume knowledge carries over between files — each file should be readable independently.

Examples of concepts requiring explanation on first mention:
- IMDSv2 / SSRF
- CIDR notation
- RFC 1918
- ProxyJump vs. ProxyCommand
- NAT (Network Address Translation)
- FQCN (Fully Qualified Collection Name) in Ansible
- `local-exec` / `remote-exec` provisioners
- `depends_on` in Terraform
- Handler idempotency in Ansible
- `environment:` gates in GitHub Actions
- Concurrency groups in GitHub Actions

### Production vs. Workshop Flag

Whenever a configuration is intentionally relaxed for the workshop, say so explicitly and state the production alternative. Use this pattern:

```hcl
# Permite SSH desde cualquier IP. En producción se restringiría a IPs conocidas
# o se eliminaría en favor de AWS Systems Manager Session Manager.
```

```yaml
# state: latest actualiza todos los paquetes a la versión más reciente.
# En producción se fijarían versiones específicas para reproducibilidad.
```

---

## 3. Terraform File Documentation Patterns

### File Header

Every `.tf` file starts with a multi-line comment block explaining:
1. What this file is responsible for
2. Why this file exists as a separate unit (what principle drove the separation)
3. Any key constraints or operational notes
4. Commands relevant to this file (if applicable)

```hcl
# Define los providers que Terraform necesita y configura el backend de estado remoto en S3.
# Este archivo es el punto de partida de cualquier módulo de Terraform: sin él, Terraform
# no sabe con qué API hablar ni dónde guardar el registro de la infraestructura creada.
#
# Ejecutar 'terraform init' después de cualquier cambio aquí para que Terraform descargue
# o actualice los providers y reconecte con el backend S3.
```

### Resource Comments

Every `resource`, `data`, `locals`, and `output` block has a comment above it explaining its purpose and its WHY. The comment sits immediately above the resource with no blank line between comment and resource.

```hcl
# Consulta dinámica de la AMI más reciente. Usar 'data' en lugar de un AMI ID fijo
# garantiza que se usa la imagen más actualizada sin necesidad de actualizar el código
# cuando el proveedor publica parches de seguridad.
data "aws_ami" "ubuntu" { ... }
```

### Variable Documentation

Variables need two layers:
- `description` field: one line, explains what the variable controls
- Block comment above: explains WHY the default was chosen (if the reasoning is non-obvious)

```hcl
# t3.small (2 vCPU con créditos, 2 GB RAM) es el mínimo cómodo para este taller:
# t3.micro puede quedarse sin memoria si varios servicios corren simultáneamente.
variable "instance_type" {
  type        = string
  description = "Tipo de instancia EC2"
  default     = "t3.small"
}
```

Do NOT add a block comment above variables whose default needs no justification (e.g., a region name, a project name).

### Inline Parameter Comments

Use inline comments for non-obvious parameter values inside resource blocks:

```hcl
resource "aws_nat_gateway" "principal" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.publica.id  # el NAT debe estar en la subnet pública para tener salida a internet

  depends_on = [aws_internet_gateway.igw_principal]  # el NAT necesita el IGW para funcionar
}
```

### Comment Format

- Use `#` with one space. Never use `/* */` blocks.
- No maximum line length for comments (readability matters more than column count).
- Blank line between the comment block and the previous resource — no blank line between the comment and its resource.
- Use `→` for option/value explanations inside a list:

```hcl
# most_recent = true  → si hay varias imágenes, usa la más nueva
# owners              → ID de Canonical; evita AMIs de terceros no verificados
# filter name         → hvm-ssd: virtualización HVM con almacenamiento SSD
```

---

## 4. Ansible File Documentation Patterns

### File Header Convention

Every Ansible YAML file starts with:
```yaml
#SPDX-License-Identifier: MIT-0
---
# [Comment block explaining the file's purpose]
```

The `#SPDX-License-Identifier: MIT-0` is on line 1 with no space after `#` (this is the standard SPDX format). The `---` document separator is on line 2. The comment block starts on line 3.

Note: ansible-lint will flag `yaml[comments]` for comments without a leading space. Add `yaml[comments]` to the `skip_list` in `.ansible-lint.yaml` to suppress this for SPDX headers.

### Playbook Header

The main playbook file explains the execution flow and where its input data comes from:

```yaml
#SPDX-License-Identifier: MIT-0
---
# Playbook principal. Define N plays independientes: uno por cada grupo de hosts.
# Los grupos y sus hosts están definidos en el inventario generado por Terraform.
#
# Flujo completo de datos:
#   1. 'terraform apply' crea las instancias EC2 y obtiene sus IPs.
#   2. Terraform escribe inventario_terraform.yaml con esas IPs.
#   3. Terraform llama a este playbook pasando variables_clave=<valor> mediante --extra-vars.
#
# 'become: true' indica que las tareas se ejecutan con privilegios de superusuario (sudo).
# El orden de la lista de roles importa: Ansible los ejecuta de arriba a abajo.
```

### Tasks File (`tasks/main.yml`)

Each task block needs a comment explaining:
- What it does (if not obvious from the `name:` field)
- WHY this order matters (if sequence is significant)
- What each non-obvious parameter does

```yaml
- name: Instalar nginx
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: true  # equivale a 'apt update': refresca la lista de paquetes disponibles
```

When a task's name is already fully descriptive and the parameters are standard, no comment is needed.

### Defaults File (`defaults/main.yml`)

Always explain:
1. The Ansible variable precedence system
2. What each variable controls
3. If a variable is injected externally (not defined here), where it comes from

```yaml
#SPDX-License-Identifier: MIT-0
---
# Variables con precedencia baja (defaults). Pueden sobreescribirse sin modificar el rol.
# La prioridad de variables en Ansible va de menor a mayor:
#   defaults → vars del rol → group_vars → host_vars → --extra-vars

nombre_servicio: mi-servicio   # nombre del servicio systemd (genera mi-servicio.service)

# NOTA: la variable 'variable_externa' NO se define aquí.
# Se inyecta por Terraform mediante --extra-vars al llamar ansible-playbook.
# Ver: terraform/aprovisionamiento.tf → provisioner "local-exec"
```

### Handlers File (`handlers/main.yml`)

Explain the handler mechanism: when they run, why they run only once, and what the `enabled: yes` flag does.

```yaml
#SPDX-License-Identifier: MIT-0
---
# Los handlers se ejecutan una sola vez al final del play, solo si fueron notificados
# por alguna tarea que introdujo un cambio. Si tres tareas notifican el mismo handler,
# el servicio se reinicia una sola vez — no tres.
```

### Templates (`templates/*.j2`)

Comment the Jinja2 variables and any non-obvious nginx/systemd/config directives:

```jinja
# {{ variable_name }}: viene de defaults/main.yml. Ver también aprovisionamiento.tf.
```

For nginx templates: explain proxy_pass behavior (with vs. without trailing slash), and what each `proxy_set_header` is for.

For systemd templates: explain `After=`, `Restart=`, `RestartSec=`, `WantedBy=`, and `PYTHONUNBUFFERED=1` (or equivalent).

---

## 5. GitHub Actions Workflow Documentation Patterns

### Workflow File Header

Every workflow file starts with a multi-line comment before the `name:` field explaining:
1. What this workflow does and when it runs
2. The overall job structure
3. Any special requirements or constraints
4. How to trigger it (for manual workflows)

```yaml
# Pipeline de CI/CD para el taller de [Nombre].
#
# ESTRUCTURA: N jobs con responsabilidades separadas.
# [Explain why jobs are separate — parallel execution, clear failure attribution]
#
# FLUJO SEGÚN EL EVENTO:
#   push a main  → [jobs that run]
#   pull_request → [jobs that run]
#   [etc.]
#
# [Any special notes, constraints, or prerequisites]
```

### Job Comments

Each job has a comment block (inside `jobs:`, above the job key) explaining:
- What it does
- When it runs (its trigger condition if it has an `if:`)
- Why it needs (or doesn't need) AWS credentials
- Any `needs:` dependencies and why they exist

```yaml
  # JOB 2: Escaneo de seguridad de Terraform.
  # Analiza los archivos .tf buscando configuraciones inseguras.
  # Lee .checkov.yaml para las exclusiones documentadas del taller.
  # Corre en paralelo con los otros jobs de validación.
  escanear-terraform:
```

### Step Comments

Add inline comments for non-obvious steps. Steps whose `name:` is already fully descriptive do not need comments.

```yaml
      # setup-tflint@v4 es la versión mayor correcta. @v6 no existe para esta action.
      - name: Instalar TFLint
        uses: terraform-linters/setup-tflint@v4
```

### Concurrency Block

Always comment the `concurrency` block:

```yaml
# Cancela ejecuciones anteriores en la misma rama para evitar applies simultáneos.
# Dos 'terraform apply' al mismo tiempo sobre el mismo estado pueden corromperse mutuamente.
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

### Manual Workflows

For `workflow_dispatch` workflows, always document:
- The exact trigger path (Actions → Name → Run workflow)
- What gets destroyed/created/changed
- Any prerequisites
- The confirmation mechanism and why it exists

---

## 6. Makefile Documentation Patterns

### Variables Block

Document variables that are not self-explanatory:

```makefile
# .DEFAULT_GOAL: define el target que se ejecuta cuando se corre 'make' sin argumentos.
.DEFAULT_GOAL := check
```

### Target Comments

Each target has a comment above it if the name is not self-explanatory, or if the sequence/behavior needs explanation:

```makefile
# check: corre todos los checks en secuencia. Si uno falla, Make se detiene.
# Correr antes de hacer 'git push' para verificar que el CI pasará.
check: lint-terraform scan-terraform lint-ansible
```

### `install-tools` Target

Must print a description of each tool alongside its install command. The output is for humans reading it — not just yes/no:

```makefile
install-tools:
	@printf "\nHerramientas requeridas:\n"
	@printf "  terraform   : gestión de infraestructura como código\n"
	@printf "  tflint      : linter estático para archivos .tf\n"
```

---

## 7. Quality Config File Documentation Patterns

### `.tflint.hcl`

Document:
1. What TFLint is and what it catches that `terraform validate` misses
2. The plugin source, version, and version-compatibility constraints
3. What `call_module_type = "none"` does and why it's set

### `.ansible-lint.yaml`

Document:
1. What the selected profile means (what rules are active)
2. Every `exclude_paths` entry — why is this file/directory excluded?
3. Every `skip_list` entry — why is this rule skipped, is it intentional or temporary?
4. Every `warn_list` entry — what would change if moved to `skip_list` vs. left as warning?

```yaml
skip_list:
  - package-latest   # roles/common/tasks/main.yaml usa state:latest intencionalmente (full apt upgrade)
  - yaml[comments]   # archivos generados por ansible-galaxy usan comentarios sin espacio inicial
```

### `.checkov.yaml`

Document:
1. The scan scope (directory + framework)
2. Every `skip-check` entry with: the check name, what it detects, and why it's skipped for this project:

```yaml
skip-check:
  - CKV_AWS_25   # SSH :22 desde 0.0.0.0/0: acceso SSH abierto necesario para el taller
  - CKV_AWS_126  # EC2 detailed monitoring: costo innecesario en entorno de entrenamiento
```

---

## 8. What NOT to Document

These patterns produce noise and should be avoided:

| Anti-pattern | Example | Why to avoid |
|-------------|---------|-------------|
| Restating the identifier | `# Creates the VPC` above `resource "aws_vpc"` | The resource type already says this |
| Describing what the parameter does when it's obvious | `# Sets the region` above `region = var.region` | Redundant |
| Referencing the current task/PR/issue | `# Added for issue #42` | Rots immediately, belongs in git history |
| Explaining stable framework behavior | `# Ansible connects via SSH` | Documentation noise |
| Commenting closing braces | `} # end of resource` | HCL indentation already shows this |
| Multi-paragraph docstrings | Long block above a simple variable | Excessive; one to three lines max per resource |
| Translating English errors | `# Error: resource not found means X` | Belongs in troubleshooting docs, not code |

---

## 9. Special Documentation Patterns

### Cross-Component Variable Flow

When a value originates in one tool and arrives in another (the most common case: Terraform outputs used as Ansible variables), document both ends.

**In Terraform** (`aprovisionamiento.tf` or equivalent):
```hcl
# Se pasa la IP privada como variable para que nginx pueda configurar el proxy_pass.
# Este es el puente entre la capa de infraestructura (Terraform) y la de
# configuración (Ansible): Terraform conoce la IP porque la creó; Ansible la necesita.
provisioner "local-exec" {
  command = "ansible-playbook ... --extra-vars 'app_private_ip=${...}'"
}
```

**In Ansible** (`defaults/main.yml` of the consuming role):
```yaml
# NOTA: 'app_private_ip' NO se define aquí. La inyecta Terraform mediante
# --extra-vars al llamar ansible-playbook. Ver: terraform/aprovisionamiento.tf
```

### ProxyJump vs. ProxyCommand Pattern

When SSH tunneling through a bastion is used, document both the reason and the subtle behavioral difference:

```hcl
# ProxyCommand pasa la llave explícitamente al salto (bastion).
# Con -o ProxyJump=, Ansible no propaga ansible_ssh_private_key_file al salto,
# lo que causa "Connection closed by UNKNOWN port 65535".
```

And separately, if outputs include a human-use SSH command:
```hcl
# Para SSH interactivo se usa ProxyJump (OpenSSH lo maneja transparentemente).
# Ansible usa ProxyCommand en el inventario porque necesita pasar la llave al salto.
# Los dos enfoques coexisten: uno para humanos, otro para Ansible.
```

### IMDSv2 / Metadata Service Pattern

When EC2 instances enforce IMDSv2, always explain the security rationale:

```hcl
# http_tokens = "required": activa IMDSv2.
# IMDSv2 protege contra ataques SSRF (Server-Side Request Forgery): si una aplicación
# reenvía peticiones HTTP al endpoint de metadatos (169.254.169.254), con IMDSv1 un atacante
# remoto podría robar credenciales IAM. IMDSv2 requiere un token de sesión previo que
# los proxies SSRF no pueden obtener de forma transparente.
```

### Remote State / Cross-Stack Dependencies

When Terraform reads state from another stack, always document what data is being read and why that stack must exist first:

```hcl
# Este archivo lee outputs del stack de aplicaciones (taller-iac / bootcamperu.tfstate).
# El stack de aplicaciones DEBE estar desplegado antes de ejecutar 'terraform plan' aquí:
# este módulo necesita el VPC ID, las subnets y los security groups que ese stack creó.
# 'terraform validate' con -backend=false NO requiere que ese estado exista.
```

---

## 10. Required Documentation Files

Every project must have these files. Read the existing ones before modifying them.

### `README.md`

Must contain:
- **Project description**: one paragraph on what this workshop deploys and why
- **Architecture diagram**: Mermaid or ASCII showing the deployed components and their relationships
- **Prerequisites**: tools required with versions and install commands
- **Quick start**: the minimum commands to deploy from scratch
- **Key commands reference**: the most-used commands during the workshop
- **Cost note**: what incurs cost (NAT Gateway, EC2) and how to stop charges

Recommended Mermaid diagram type: `graph TD` for infrastructure topology, `sequenceDiagram` for deployment flow.

### `CLAUDE.md`

A guidance file for the Claude Code AI tool. This file is not student-facing — it's for the AI assistant. Must contain:
- Project overview (2-3 sentences)
- Common commands (terraform, ansible, make targets)
- Architecture summary (key files and what they do)
- Key constraints (S3 bucket must pre-exist, git-ignored files, etc.)

Write this in English (the AI tool's primary language) or follow the convention of the existing file if it already exists in the project.

### `CHANGELOG.md`

Track changes in reverse chronological order. Must always exist even if initially empty. Format:

```markdown
# Changelog

## [Unreleased]

## [1.0.0] — YYYY-MM-DD
### Added
- Initial workshop infrastructure
```

---

## 11. Observabilidad Project — Implementation Guide

### Current State Assessment

Before starting, read each file and assess documentation quality:

| File | Expected state | Priority |
|------|---------------|----------|
| `terraform/proveedores.tf` | Good (has headers) | Check + enhance |
| `terraform/state.tf` | Likely thin | **High — cross-stack dependency must be documented** |
| `terraform/instancias.tf` | Variable | High — IMDSv2 explanation needed |
| `terraform/seguridad.tf` | Variable | High — monitoring port rationale needed |
| `terraform/ssh.tf` | Variable | Medium — RSA 4096 rationale |
| `terraform/variables.tf` | Variable | Medium — add WHY to defaults |
| `terraform/salidas.tf` | Variable | Medium |
| `terraform/aprovisionamiento.tf` | Variable | **High — cross-stack + Terraform→Ansible bridge** |
| `ansible/site.yaml` | Variable | High — explain 7-role execution order |
| `ansible/roles/*/tasks/main.yaml` | Variable | Medium — explain each role's function |
| `ansible/roles/*/defaults/main.yaml` | Likely thin | Medium — add precedence explanation |
| `ansible/roles/*/handlers/main.yaml` | Likely thin | Medium — handler mechanics |
| `ansible/roles/prometheus/templates/prometheus.yml.j2` | Likely no comments | High — scrape configs are complex |
| `ansible/roles/grafana/templates/*` | Likely no comments | Medium |
| `.github/workflows/pipeline.yaml` | New — create with full docs | High |
| `.github/workflows/planificar.yaml` | New — create with full docs | High |
| `.github/workflows/desplegar.yaml` | New — create with full docs | High |
| `.github/workflows/destruir.yaml` | New — create with full docs | High |
| `Makefile` | Exists — extend with comments | Medium |

### File-Specific Documentation Priorities for Observabilidad

#### `terraform/state.tf` — Critical

This file is unique to this project. It reads remote state from the taller-iac stack. Document:
- What it reads and why (VPC, subnets, security groups from the apps stack)
- The deployment prerequisite (apps stack must be deployed first)
- That `terraform validate` is safe without this, but `terraform plan` is not

```hcl
# Este módulo lee el estado remoto del stack de aplicaciones (taller-iac).
# El stack de aplicaciones despliega la VPC, subnets y security groups base.
# La instancia de monitoreo se conecta a esa misma red para poder scrapearse
# a sí misma y a los targets (frontend, backend) sin tráfico público.
#
# PRERREQUISITO: El stack de aplicaciones debe estar desplegado antes de ejecutar
# 'terraform plan' o 'terraform apply' en este módulo. Sin ese estado, las referencias
# a vpc_id, subnet_id, etc. no podrán resolverse.
# 'terraform validate -no-color' (con -backend=false) es seguro sin este prerrequisito.
```

#### `terraform/seguridad.tf` — High

Document why monitoring ports are open from 0.0.0.0/0 and the production alternative:

```hcl
# Prometheus :9090 abierto desde internet para que los estudiantes puedan acceder
# directamente desde el navegador durante el taller. En producción se restringiría
# a la IP del equipo de operaciones o se accedería vía VPN / AWS Systems Manager.
```

#### `ansible/site.yaml` — High

Document the 7-role execution order and why `common` runs first:

```yaml
# Playbook principal para el stack de observabilidad completo.
# Configura una única instancia EC2 con 7 componentes en secuencia:
#
#   common        → usuario del sistema, paquetes base, configuración de journald
#   node_exporter → métricas del sistema operativo (CPU, RAM, disco, red)
#   prometheus    → motor de métricas, scraping y almacenamiento de series temporales
#   loki          → motor de logs, recibe entradas de promtail
#   grafana       → visualización: dashboards para métricas (Prometheus) y logs (Loki)
#   alertmanager  → enrutamiento de alertas generadas por las reglas de Prometheus
#   promtail      → agente de logs, reenvía el journal de systemd a Loki
#
# El orden importa: prometheus debe estar instalado antes de alertmanager (alertmanager
# lee la configuración de Prometheus para validar el endpoint). Loki debe estar antes
# de promtail (promtail necesita el endpoint de Loki para arrancar sin error).
```

#### Prometheus Template (`prometheus.yml.j2`) — High

Prometheus configuration files are complex. Document:
- What `scrape_configs` does
- What `file_sd_configs` is and why it's preferred over `static_configs`
- What `rule_files` does and where the alert rules come from
- The `alerting` section and its connection to alertmanager

#### Grafana Provisioning Files — Medium

These are auto-provisioned on startup. Document:
- What provisioning means (no manual dashboard import needed)
- The datasource UID convention and why UIDs matter for portability
- Where dashboards come from (files, not the UI)

### Applying the Documentation Iteratively

Follow this workflow for each file:

1. **Read the current file** — understand what it does before adding comments
2. **Identify gaps** — what decisions are unexplained? What would confuse a student?
3. **Write file header** — if missing or thin
4. **Add resource/task comments** — working top to bottom
5. **Add inline comments** — for non-obvious parameter values
6. **Flag production differences** — add "En producción..." notes
7. **Verify linting** — Terraform files: `terraform fmt -check`. Ansible files: `ansible-lint`

Do NOT run `terraform fmt` to reformat existing files unless the formatting is clearly broken — it may reorder arguments and create noisy git diffs that obscure documentation changes.

### Comment Density Calibration

For the observabilidad project, the target density is:

- **Terraform files**: 1 comment block per resource + inline comments on non-obvious parameters. Files with complex logic (state.tf, aprovisionamiento.tf) get denser documentation.
- **Ansible tasks files**: 1 comment per task group or per unusual parameter. Standard `ansible.builtin.apt` calls with obvious names don't need comments.
- **Ansible templates**: Comment every configuration section (scrape_configs, alerting, storage, etc.) — these are the most student-unfamiliar files.
- **Workflow files**: Comment every job and every non-obvious step.

---

## 12. Quality Checklist

Before committing documentation changes, verify:

- [ ] Every `.tf` file has a header comment explaining its purpose
- [ ] No resource block is entirely without comment
- [ ] Every variable has a `description` field
- [ ] Variables with non-obvious defaults have a block comment explaining the choice
- [ ] Every `skip-check` entry in `.checkov.yaml` has a comment
- [ ] Every `skip_list` entry in `.ansible-lint.yaml` has a comment
- [ ] Every `exclude_paths` entry in `.ansible-lint.yaml` has a comment
- [ ] Cross-component dependencies are documented on both ends (producer and consumer)
- [ ] Production vs. workshop differences are flagged with "En producción..." notes
- [ ] Technical concepts are explained on first use in each file
- [ ] No comments that merely restate the identifier they're documenting
- [ ] No references to tickets, PRs, or current tasks in comments
- [ ] All text passes a neutral-Spanish review (no regionalisms)
- [ ] `terraform fmt -check -recursive` passes after changes
- [ ] `ansible-lint ansible/site.yaml` passes after changes (zero failures, warnings allowed)

---

*Document written: 2026-04-26. Based on the final documented state of ScrambledBits/taller-iac after PR #3.*
