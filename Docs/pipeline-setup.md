# CI/CD Pipeline Setup — Taller de Observabilidad

> **Audience:** A new Claude agent implementing the CI/CD pipeline and local tooling for this project in a fresh session.
> **Source of patterns:** `ScrambledBits/taller-iac` — the complete reference implementation.
> **Do not assume:** Every decision in this document is explicit. If something is unclear, check the source project before proceeding.

---

## 1. What Was Built in the Source Project (taller-iac)

The `ScrambledBits/taller-iac` repository went from a broken, incomplete pipeline to a fully working CI/CD system. Here is what was created:

### Local Developer Tooling
| File | Purpose |
|------|---------|
| `Makefile` | `make check` runs all linters in sequence; individual targets for each tool |
| `terraform/.tflint.hcl` | TFLint configuration with AWS ruleset plugin v0.40.0 |
| `.ansible-lint.yaml` | ansible-lint profile and skip list for workshop-appropriate relaxations |
| `.checkov.yaml` | Checkov security scan configuration with documented skip list |
| `~/.terraformrc` | **User-level** file: `disable_checkpoint = true` (prevents terraform from hanging on network calls) |

### GitHub Actions Workflows
| File | Trigger | Purpose |
|------|---------|---------|
| `pipeline.yaml` | push/PR to main | 5 jobs: lint-TF, scan-TF, lint-Ansible, plan (PR only), apply (push to main only) |
| `destruir.yaml` | workflow_dispatch | Manual destroy with typed confirmation + environment gate |

### Pipeline Job Structure (taller-iac)
```
push to main  → lint-terraform + escanear-terraform + validar-ansible → desplegar
PR to main    → lint-terraform + escanear-terraform + validar-ansible → planificar-terraform
workflow_dispatch → lint-terraform + escanear-terraform + validar-ansible → desplegar
```

---

## 2. This Project: observabilidad

### Key Facts
| Aspect | Value |
|--------|-------|
| GitHub remote | `git@github.com:ScrambledBits/taller-observabilidad.git` |
| IaC stack | Terraform + Ansible (same as taller-iac) |
| AWS provider | hashicorp/aws 6.37.0 (same S3 backend pattern) |
| Ansible roles | 7 roles: common, node_exporter, prometheus, loki, grafana, alertmanager, promtail |
| Ubuntu version | 24.04 (taller-iac used 22.04) |
| EC2 topology | Single monitoring EC2 (public subnet) — not two-tier |
| Existing Makefile | Yes — 6 targets: `ayuda`, `inventario`, `ping`, `provision`, `open`, `tf-destroy` |
| Existing CI/CD | None — no `.github/` directory |
| Linting configs | None — starting from scratch |

### Critical Difference: Cross-Stack Remote State

`terraform/state.tf` reads Terraform outputs from the `taller-iac` stack (`bootcamperu.tfstate` in S3) to get the VPC ID, subnet IDs, and security group references. This means:

- `terraform validate -no-color` (with `-backend=false`) → **safe, works in CI without credentials**
- `terraform plan` → **requires taller-iac to be deployed first**, otherwise fails because the cross-stack data sources cannot resolve
- `terraform apply` → same requirement as plan

**Therefore: `terraform plan` and `terraform apply` are MANUAL-ONLY steps in this project's pipeline.** They are NOT triggered automatically on PR or merge to main. The CI pipeline only runs linting and security scanning automatically. Plan and apply are separate manual workflows.

Document this prominently in comments inside the workflow files.

### Pipeline Job Structure (observabilidad — differs from taller-iac)
```
push to main  → lint-terraform + escanear-terraform + validar-ansible  (no plan, no apply)
PR to main    → lint-terraform + escanear-terraform + validar-ansible  (no plan, no apply)
workflow_dispatch "planificar"  → full terraform plan
workflow_dispatch "aplicar"     → full terraform apply (with Ansible)
workflow_dispatch "destruir"    → full terraform destroy
```

---

## 3. Prerequisites

### Tools Required (verify with `make install-tools` after creating Makefile)

| Tool | Version | Install |
|------|---------|---------|
| terraform | ≥ 1.14.8 | `mise use terraform@1.14.9` |
| tflint | 0.61.0 | `mise use tflint@0.61.0` |
| checkov | ≥ 3.2.520 | `brew install checkov` |
| ansible | core ≥ 2.20 | `brew install ansible` |
| ansible-lint | ≥ 24.x | `brew install ansible-lint` |

### One-Time Local Fix (apply immediately if not already done)

Create `~/.terraformrc` with:
```hcl
disable_checkpoint = true
```

Without this, `terraform fmt` and other commands may hang for 30-120 seconds waiting for a network call to `checkpoint.hashicorp.com`. The file must be at the user's home directory (not the project directory).

Verify: `time terraform fmt --version` should complete in under 1 second.

### GitHub Repository Setup (do after creating workflow files)

1. **Repository Secrets** (Settings → Secrets and variables → Actions):
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. **Environment** (Settings → Environments → New environment):
   - Name: `production`
   - Add required reviewers to gate the apply and destroy workflows

3. **Branch Protection** (Settings → Branches → Add rule for `main`):
   - Require pull request before merging
   - Require status checks: `Revisar el código Terraform`, `Escanear seguridad de Terraform`, `Revisar el código Ansible`
   - Require branches to be up to date before merging

---

## 4. Implementation Checklist

Work through these phases in order. Each phase has a verification step before moving on.

---

### Phase 0: Orientation (already done — summary below)

The project structure at the time of this writing:
```
observabilidad/
├── .gitignore
├── CLAUDE.md
├── Makefile              ← EXISTS, must extend (not replace)
├── README.md
├── Docs/
│   ├── Quickstart.md
│   ├── targets.md
│   └── troubleshooting.md
├── terraform/
│   ├── .terraform.lock.hcl  ← tracked in git (provider pins)
│   ├── proveedores.tf
│   ├── state.tf              ← reads remote state from taller-iac
│   ├── instancias.tf
│   ├── seguridad.tf
│   ├── ssh.tf
│   ├── variables.tf
│   ├── salidas.tf
│   ├── aprovisionamiento.tf  ← generates Ansible inventory + local-exec
│   └── user_data/monitoring.sh
└── ansible/
    ├── site.yaml
    ├── group_vars/all.yaml
    ├── inventario_terraform.yaml  ← git-ignored, generated by Terraform
    └── roles/
        ├── common/
        ├── node_exporter/
        ├── prometheus/
        ├── loki/
        ├── grafana/
        ├── alertmanager/
        └── promtail/
```

---

### Phase 1: Discover Actual Linting Issues Before Writing Configs

**This step is mandatory.** Do not copy the skip lists from taller-iac — the skip lists are project-specific. Discover what actually fails in this project first.

#### 1a. TFLint Discovery

```bash
cd /Users/admin/Projects/Clases/talleres/observabilidad/terraform
tflint --init  # uses default config (no AWS plugin yet)
tflint -f compact
```

Note any failures. These will inform whether the default AWS plugin ruleset has issues with this project's resources.

#### 1b. Checkov Discovery

```bash
cd /Users/admin/Projects/Clases/talleres/observabilidad
checkov --directory terraform --framework terraform --download-external-modules false 2>&1 | grep -E "FAILED|Passed|Failed"
checkov --directory terraform --framework terraform --download-external-modules false 2>&1 | grep "FAILED for resource" -A3
```

Record every failing check ID and its reason. Build the skip list only from checks that are intentionally relaxed for the workshop context (open monitoring ports, no EBS encryption, etc.). Do not skip checks that could be fixed in code.

The `--download-external-modules false` flag is critical — without it, Checkov may hang downloading provider schemas.

#### 1c. ansible-lint Discovery

```bash
cd /Users/admin/Projects/Clases/talleres/observabilidad
ansible-lint ansible/site.yaml 2>&1
```

Categorize each failure:
- **Fix in code** (non-skippable rules, real issues): e.g., `schema[meta]` — `min_ansible_version: 2.2` must be `"2.2"` (string, not float) in every `roles/*/meta/main.yml`
- **Skip in config** (intentional/cosmetic): style rules, workshop-appropriate patterns
- **Warn in config** (report but don't fail): casing, truthy values in Spanish-named tasks

---

### Phase 2: Create Configuration Files

#### 2a. `terraform/.tflint.hcl`

This file can be copied verbatim from taller-iac — same TFLint version, same AWS provider, same options:

```hcl
# TFLint: linter estático para Terraform. Detecta errores que 'terraform validate' no encuentra:
# tipos de instancia inválidos, regiones inexistentes, parámetros obsoletos, y malas prácticas
# específicas de cada proveedor. Funciona leyendo el código HCL sin conectarse a AWS.
#
# Ejecutar localmente:
#   tflint --config=.tflint.hcl --init   # descarga los plugins definidos aquí (solo la primera vez)
#   tflint --config=.tflint.hcl          # analiza todos los archivos .tf del directorio
#
# El pipeline de CI/CD (pipeline.yaml) lo ejecuta automáticamente en cada push y PR.

# Plugin AWS: añade reglas específicas de AWS al análisis.
# Sin este plugin, TFLint solo verifica sintaxis HCL genérica.
# Con él, detecta cosas como: tipo de instancia inexistente en la región, AMI ID con
# formato incorrecto, o parámetros deprecados del provider de AWS.
#
# version = "0.40.0": versión fijada para garantizar resultados reproducibles en todos
# los entornos (local, CI/CD). El plugin 0.40.x es la última versión compatible con TFLint 0.61.x.
# (0.41.x requiere TFLint 0.62+; no actualizar uno sin actualizar el otro.)
plugin "aws" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  # call_module_type = "none": indica a TFLint que no intente analizar módulos externos.
  # Sin esta opción, TFLint intentaría descargar y analizar módulos referenciados con
  # 'source = "..."', lo que fallaría en el CI/CD si no hay acceso a internet o si el
  # módulo requiere autenticación. Este proyecto no usa módulos externos.
  call_module_type = "none"
}
```

After writing: `tflint --config=terraform/.tflint.hcl --chdir=terraform --init && tflint --config=terraform/.tflint.hcl --chdir=terraform -f compact`

#### 2b. `.ansible-lint.yaml`

Start with this template, then adjust the `skip_list` based on what you discovered in Phase 1c:

```yaml
profile: basic

exclude_paths:
  - ansible/inventario_terraform.yaml   # generated by Terraform, never edit manually
  - ansible/roles/common/tests/
  - ansible/roles/node_exporter/tests/
  - ansible/roles/prometheus/tests/
  - ansible/roles/loki/tests/
  - ansible/roles/grafana/tests/
  - ansible/roles/alertmanager/tests/
  - ansible/roles/promtail/tests/

warn_list:
  - yaml[truthy]     # 'yes/no' common in legacy Ansible content
  - name[casing]     # task names in Spanish don't follow English capitalization

skip_list:
  - package-latest   # VERIFY: check if any role uses state:latest intentionally
  - yaml[line-length]  # long Jinja2 expressions in templates are unavoidable
  # ADD MORE based on Phase 1c discovery

use_default_rules: true
```

**Important:** `schema[meta]` violations (if any) cannot be skipped — they must be fixed in code. For each `roles/*/meta/main.yml` that has `min_ansible_version: 2.2`, change it to `min_ansible_version: "2.2"` (string). Use sed: `sed -i '' 's/min_ansible_version: 2.2/min_ansible_version: "2.2"/' ansible/roles/*/meta/main.yml`

After writing: `ansible-lint ansible/site.yaml` — must exit 0.

#### 2c. `.checkov.yaml`

Start with this template, then populate `skip-check` based on what you discovered in Phase 1b:

```yaml
soft-fail: false

directory:
  - terraform

framework:
  - terraform

# Speeds up local runs significantly.
download-external-modules: false

# Rules skipped for intentional workshop relaxations.
# Each entry must have a comment explaining WHY.
# Revisit this list before any production use.
skip-check:
  # ADD entries here based on Phase 1b discovery.
  # Expected skips for this project (verify IDs):
  #   - Monitoring ports open from 0.0.0.0/0 (Prometheus :9090, Grafana :3000,
  #     Alertmanager :9093, Loki :3100) — workshop requires open access
  #   - SSH from 0.0.0.0/0 — workshop SSH access
  #   - No EBS encryption — training cost control
  #   - EC2 without IAM role — no instance profile needed for monitoring
  #   - No VPC flow logs — training cost control
```

**Note:** Check IDs differ between Checkov versions. After the first CI run, check the logs — the CI runner uses a newer Checkov than local and may find additional failing checks. Add those to the skip list with documentation.

After writing: `checkov --config-file .checkov.yaml` — must show `Failed checks: 0`.

---

### Phase 3: Extend the Existing Makefile

**Do NOT replace the existing Makefile.** The project already has targets that students use (`inventario`, `ping`, `provision`, `open`, `tf-destroy`). Add the linting targets to the existing file.

Read the current Makefile first, then add these sections. Insert the new targets **after the existing variables** and **before the first existing target**:

```makefile
# ── Variables para linting (añadidas para el pipeline CI/CD) ─────────────
TFLINT_CONFIG  := terraform/.tflint.hcl
CHECKOV_CONFIG := .checkov.yaml

# .DEFAULT_GOAL: define el target que se ejecuta cuando se corre 'make' sin argumentos.
# Si el Makefile original no tiene .DEFAULT_GOAL, considera si añadirlo rompe el flujo
# esperado por los estudiantes. Puede omitirse si ya hay un default definido.
# .DEFAULT_GOAL := check
```

And add these targets (at the end of the file, after existing targets):

```makefile
# ── Targets de linting y seguridad ────────────────────────────────────────

# check: corre todos los checks de calidad en secuencia.
# Si cualquiera falla, Make se detiene. Correr antes de hacer 'git push'.
check: lint-terraform scan-terraform lint-ansible
	@printf ">>> Todos los checks pasaron.\n"

lint-terraform:
	@printf ">>> terraform fmt\n"
	terraform -chdir=terraform fmt -check -recursive
	@printf ">>> terraform init (sin backend)\n"
	terraform -chdir=terraform init -backend=false -input=false -reconfigure
	@printf ">>> terraform validate\n"
	terraform -chdir=terraform validate -no-color
	@printf ">>> tflint init\n"
	tflint --config=$(TFLINT_CONFIG) --chdir=terraform --init
	@printf ">>> tflint run\n"
	tflint --config=$(TFLINT_CONFIG) --chdir=terraform -f compact

scan-terraform:
	@printf ">>> checkov\n"
	checkov --config-file $(CHECKOV_CONFIG)

lint-ansible:
	@printf ">>> ansible-lint\n"
	ansible-lint ansible/site.yaml

install-tools:
	@printf "\nHerramientas requeridas para el pipeline CI/CD:\n"
	@printf "  terraform   : IaC (mise use terraform@1.14.9)\n"
	@printf "  tflint      : linter de Terraform (mise use tflint@0.61.0)\n"
	@printf "  checkov     : escáner de seguridad IaC (brew install checkov)\n"
	@printf "  ansible     : configuración de servidores (brew install ansible)\n"
	@printf "  ansible-lint: linter de Ansible (brew install ansible-lint)\n\n"
	@command -v terraform    >/dev/null 2>&1 || { printf "MISSING: terraform\n";    exit 1; }
	@command -v tflint       >/dev/null 2>&1 || { printf "MISSING: tflint\n";       exit 1; }
	@command -v checkov      >/dev/null 2>&1 || { printf "MISSING: checkov\n";      exit 1; }
	@command -v ansible      >/dev/null 2>&1 || { printf "MISSING: ansible\n";      exit 1; }
	@command -v ansible-lint >/dev/null 2>&1 || { printf "MISSING: ansible-lint\n"; exit 1; }
	@printf "Todas las herramientas están instaladas.\n"

.PHONY: check lint-terraform scan-terraform lint-ansible install-tools
```

After writing: `make check` — must exit 0 with no errors.

---

### Phase 4: Create GitHub Actions Workflows

Create the directory first: `mkdir -p .github/workflows`

#### 4a. `.github/workflows/pipeline.yaml` — Lint/Scan (Automatic)

This workflow runs on every push and PR. It does NOT include plan or apply — those are manual only.

```yaml
# Pipeline de CI/CD para el taller de Observabilidad de BootcampPeru.
#
# ESTRUCTURA: 3 jobs de validación que corren en paralelo en cada push y PR.
# No hay terraform plan ni terraform apply automáticos en este pipeline.
#
# RAZÓN: Este proyecto lee estado remoto de Terraform del stack de aplicaciones
# (taller-iac / bootcamperu.tfstate). El terraform plan requiere que ese stack
# esté desplegado para poder resolver las referencias cruzadas (VPC ID, subnets,
# security groups). Por eso, plan y apply son pasos manuales independientes.
#
# Para ejecutar plan, apply o destroy: ver planificar.yaml, desplegar.yaml, destruir.yaml.

name: Pipeline IaC Observabilidad

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

# Cancela ejecuciones anteriores en la misma rama para evitar runs simultáneos.
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  # ── Job 1: Lint de Terraform ─────────────────────────────────────────────
  # Usa -backend=false: descarga providers del registry público sin conectarse
  # al backend S3 ni resolver el estado remoto cruzado. Sin credenciales AWS.
  validar-terraform:
    name: Revisar el código Terraform
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
        working-directory: ./terraform

    steps:
      - uses: actions/checkout@v4

      - name: Instalar Terraform
        uses: hashicorp/setup-terraform@v4
        with:
          terraform_version: "1.14.9"

      - name: Terraform fmt
        run: terraform fmt -check -recursive

      - name: Terraform Init (sin backend)
        run: terraform init -backend=false -input=false

      - name: Terraform Validate
        run: terraform validate -no-color

      # setup-tflint@v4 es la versión mayor correcta. @v6 no existe para esta action.
      - name: Instalar TFLint
        uses: terraform-linters/setup-tflint@v4
        with:
          tflint_version: v0.61.0

      - name: TFLint Init
        run: tflint --config=.tflint.hcl --init
        env:
          GITHUB_TOKEN: ${{ github.token }}

      - name: TFLint Run
        run: tflint --config=.tflint.hcl -f compact

  # ── Job 2: Escaneo de seguridad de Terraform ─────────────────────────────
  # Lee .checkov.yaml para las exclusiones documentadas del taller.
  escanear-terraform:
    name: Escanear seguridad de Terraform
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Checkov
        uses: bridgecrewio/checkov-action@v12
        with:
          config_file: .checkov.yaml

  # ── Job 3: Lint de Ansible ────────────────────────────────────────────────
  # Verifica los 7 roles (common, node_exporter, prometheus, loki, grafana,
  # alertmanager, promtail) con el perfil 'basic' definido en .ansible-lint.yaml.
  validar-ansible:
    name: Revisar el código Ansible
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Configurar Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Instalar ansible-lint
        run: pip install "ansible-lint[community,yamllint]" "ansible-core>=2.20"

      - name: Ejecutar ansible-lint
        run: ansible-lint ansible/site.yaml
```

#### 4b. `.github/workflows/planificar.yaml` — Terraform Plan (Manual Only)

```yaml
# Workflow manual para ejecutar terraform plan y revisar los cambios propuestos.
#
# REQUISITO: El stack de aplicaciones (taller-iac) debe estar desplegado antes
# de ejecutar este workflow. terraform plan leerá el estado remoto de ese stack
# para resolver las referencias cruzadas (VPC, subnets, security groups).
# Si ese estado no existe, el plan fallará con un error de data source.
#
# CÓMO EJECUTAR: Actions → "Planificar infraestructura" → Run workflow → "planificar"

name: Planificar infraestructura

on:
  workflow_dispatch:
    inputs:
      confirmacion:
        description: 'Escribe "planificar" para ejecutar terraform plan'
        required: true

jobs:
  planificar:
    name: Terraform Plan
    runs-on: ubuntu-latest
    environment: production
    if: github.event.inputs.confirmacion == 'planificar'
    defaults:
      run:
        shell: bash
        working-directory: ./terraform

    steps:
      - uses: actions/checkout@v4

      - name: Configurar credenciales AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: us-east-1
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Instalar Terraform
        uses: hashicorp/setup-terraform@v4
        with:
          terraform_version: "1.14.9"

      - name: Terraform Init
        run: terraform init -input=false

      - name: Terraform Plan
        run: terraform plan -no-color -input=false
```

#### 4c. `.github/workflows/desplegar.yaml` — Terraform Apply + Ansible (Manual Only)

```yaml
# Workflow manual para desplegar la infraestructura de monitoreo.
#
# REQUISITO: El stack de aplicaciones (taller-iac) debe estar desplegado.
# Este workflow crea la EC2 de monitoreo y la configura con Ansible (7 roles).
#
# Instala Ansible porque aprovisionamiento.tf usa local-exec para ejecutar
# ansible-playbook. El runner de CI actúa como nodo de control de Ansible.
#
# CÓMO EJECUTAR: Actions → "Desplegar infraestructura" → Run workflow → "aplicar"

name: Desplegar infraestructura

on:
  workflow_dispatch:
    inputs:
      confirmacion:
        description: 'Escribe "aplicar" para ejecutar terraform apply'
        required: true

jobs:
  desplegar:
    name: Terraform Apply + Ansible
    runs-on: ubuntu-latest
    environment: production
    if: github.event.inputs.confirmacion == 'aplicar'
    defaults:
      run:
        shell: bash
        working-directory: ./terraform

    steps:
      - uses: actions/checkout@v4

      - name: Configurar credenciales AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: us-east-1
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Instalar Terraform
        uses: hashicorp/setup-terraform@v4
        with:
          terraform_version: "1.14.9"

      - name: Configurar Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Instalar Ansible
        run: pip install "ansible-core>=2.20"

      - name: Verificar ansible-playbook
        run: ansible-playbook --version

      - name: Terraform Init
        run: terraform init -input=false

      - name: Crear plan
        run: terraform plan -no-color -input=false -out=pipeline.tfplan

      - name: Aplicar el plan de Terraform
        run: terraform apply -auto-approve pipeline.tfplan
```

#### 4d. `.github/workflows/destruir.yaml` — Destroy (Manual Only)

```yaml
# Workflow para destruir TODA la infraestructura de monitoreo.
#
# ADVERTENCIA: Esta acción es IRREVERSIBLE. Elimina:
#   - La instancia EC2 de monitoreo y todos sus datos
#   - El Security Group, la subnet association, el Key Pair de SSH
#   - El estado de Terraform en S3 NO se elimina
#
# USO PREVISTO: Apagar el entorno al terminar el taller.
# La EC2 genera cargos por hora aunque no haya tráfico.
#
# CÓMO EJECUTAR: Actions → "Destruir infraestructura" → Run workflow → "destruir"

name: Destruir infraestructura

on:
  workflow_dispatch:
    inputs:
      confirmacion:
        description: 'Escribe "destruir" para confirmar la eliminación'
        required: true

jobs:
  destruir:
    name: Terraform Destroy
    runs-on: ubuntu-latest
    environment: production
    if: github.event.inputs.confirmacion == 'destruir'
    defaults:
      run:
        shell: bash
        working-directory: ./terraform

    steps:
      - uses: actions/checkout@v4

      - name: Configurar credenciales AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: us-east-1
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Instalar Terraform
        uses: hashicorp/setup-terraform@v4
        with:
          terraform_version: "1.14.9"

      - name: Terraform Init
        run: terraform init -input=false

      - name: Terraform Destroy
        run: terraform destroy -auto-approve -input=false
```

---

### Phase 5: Validate Locally

```bash
# Run full check
make check

# Should output:
# >>> terraform fmt        → (no output = files are formatted)
# >>> terraform init (sin backend) → Terraform has been successfully initialized
# >>> terraform validate   → Success! The configuration is valid.
# >>> tflint init          → All plugins are already installed
# >>> tflint run           → (no output = no issues)
# >>> checkov              → Passed checks: N, Failed checks: 0
# >>> ansible-lint         → Passed: 0 failure(s), N warning(s)
# >>> Todos los checks pasaron.
```

If `terraform fmt` fails, run `terraform -chdir=terraform fmt -recursive` to auto-fix formatting.

---

### Phase 6: Commit, Push, and Open PR

```bash
git checkout -b feat/pipeline-ci-cd

git add terraform/.tflint.hcl .ansible-lint.yaml .checkov.yaml Makefile \
        .github/workflows/pipeline.yaml .github/workflows/planificar.yaml \
        .github/workflows/desplegar.yaml .github/workflows/destruir.yaml \
        ansible/roles/*/meta/main.yml  # if schema[meta] was fixed

git commit -m "feat: añadir pipeline CI/CD con linting, escaneo de seguridad y workflows manuales"

git push -u origin feat/pipeline-ci-cd
gh pr create --title "feat: pipeline CI/CD — lint/scan automático, plan/apply manual" \
             --base main --head feat/pipeline-ci-cd
```

Then monitor with:
```bash
gh pr checks <PR_NUMBER> --watch
```

**Expected on PR:** 3 jobs run (`validar-terraform`, `escanear-terraform`, `validar-ansible`). No `planificar` or `desplegar` job — those are manual only.

---

## 5. Lessons Learned — Critical Pitfalls

These are hard-won insights from the taller-iac implementation. Most will apply here too.

### L1: Checkov Version Mismatch Between Local and CI

`bridgecrewio/checkov-action@v12` installs a newer Checkov than what's installed locally. New security checks added in the CI version may fail even though local passes. **Always check the CI logs after the first run** and add any new failing check IDs to `.checkov.yaml`.

Pattern: first CI run → identify new failing check IDs in logs → add to `skip-check` with documented reason → push fix.

### L2: Checkov Config Uses Hyphens, Not Underscores

The `.checkov.yaml` keys must use hyphens:
```yaml
soft-fail: false      ✅
skip-check: [...]     ✅

soft_fail: false      ❌ (Checkov parses this as unknown CLI flag)
skip_check: [...]     ❌
```

### L3: `terraform fmt` Hangs Without `~/.terraformrc`

Terraform makes a network call to `checkpoint.hashicorp.com` on many commands, including `fmt`. If the network is filtered or slow, this blocks for 30-120 seconds. Fix: create `~/.terraformrc` with `disable_checkpoint = true`. This is a **user-level** file, not committed to the repo.

Test before concluding a command is hung: `CHECKPOINT_DISABLE=1 terraform -chdir=terraform fmt -check -recursive`

### L4: TFLint Action Version

The correct action tag is `terraform-linters/setup-tflint@v4`. The tag `@v6` does not exist for this action and will fail silently or use an unexpected version. Always use `@v4`.

### L5: ansible-lint `schema[meta]` Is Non-Skippable

If any role's `meta/main.yml` has `min_ansible_version: 2.2` (YAML float), ansible-lint will report a `schema[meta]` error and **refuse to continue processing the file**. This cannot be added to `skip_list`. Fix it in code:

```bash
sed -i '' 's/min_ansible_version: 2.2/min_ansible_version: "2.2"/' ansible/roles/*/meta/main.yml
```

Verify with `grep "min_ansible_version" ansible/roles/*/meta/main.yml`.

### L6: TFLint Config Path With `--chdir`

When using `tflint --chdir=terraform`, the `--config` path is resolved relative to the new working directory (inside `terraform/`). The correct invocation from the project root is:

```bash
tflint --config=.tflint.hcl --chdir=terraform  # looks for terraform/.tflint.hcl ✅
tflint --config=terraform/.tflint.hcl --chdir=terraform  # looks for terraform/terraform/.tflint.hcl ❌
```

### L7: Makefile Recipe Lines Must Use Tabs

Make requires real tab characters in recipe lines. If you use spaces, Make will print `Makefile:N: *** missing separator. Stop.` The `Write` tool in Claude Code preserves tabs correctly, but editors may convert them.

### L8: `download-external-modules: false` in `.checkov.yaml`

Without this flag, Checkov will attempt to download and parse Terraform provider schemas on every run, which can take 30-60 seconds or hang on slow networks. Add it to `.checkov.yaml`:

```yaml
download-external-modules: false
```

### L9: `terraform validate` Works With `-backend=false` Even With Cross-Stack References

`terraform validate` checks syntax and resource schema only — it does NOT resolve remote state data sources. Running `terraform init -backend=false && terraform validate` is safe in the lint job and does not require the taller-iac stack to be deployed.

### L10: `ansible-lint` Discover-First Workflow

Never copy skip lists from another project. Always run `ansible-lint` first with zero config, observe all failures, then categorize:

1. `schema[*]` → must fix in code (non-skippable)
2. Real bugs (wrong module usage, missing handlers) → fix in code
3. Style/cosmetic (casing, yaml formatting, role prefix naming) → skip or warn in config
4. Intentional patterns (package-latest for apt upgrade role) → skip in config with comment

---

## 6. Observabilidad-Specific Notes

### Monitoring Port Security Groups

The `seguridad.tf` in this project opens monitoring ports from `0.0.0.0/0` for workshop access:
- **:9090** — Prometheus
- **:3000** — Grafana
- **:9093** — Alertmanager
- **:3100** — Loki
- **:22** — SSH

These will trigger Checkov rules for unrestricted ingress. They must be in the `skip-check` list. Discover the exact check IDs by running Checkov locally (Phase 1b) — do not assume they match the taller-iac IDs, as different resource types trigger different check IDs.

### Ubuntu 24.04 vs 22.04

The Terraform AMI filter in `instancias.tf` likely uses Ubuntu 24.04 (Jammy vs Noble). Verify the AMI filter before assuming the TFLint/Checkov results match taller-iac.

### The Ansible Playbook Entry Point

In taller-iac the playbook was `ansible/playbook.yaml`. In this project it is `ansible/site.yaml`. Update all references accordingly:
- Makefile: `ansible-lint ansible/site.yaml`
- `aprovisionamiento.tf`: check the `local-exec` command for the playbook path
- Pipeline yaml: `run: ansible-lint ansible/site.yaml`

### The Cross-Stack State: What Fails and What Doesn't

| Command | Needs taller-iac deployed? | Safe in CI lint job? |
|---------|---------------------------|---------------------|
| `terraform init -backend=false` | No | Yes ✅ |
| `terraform validate -no-color` (after `-backend=false` init) | No | Yes ✅ |
| `tflint -f compact` | No | Yes ✅ |
| `checkov --directory terraform` | No | Yes ✅ |
| `terraform init` (with backend) | No (only needs S3 bucket) | With creds ✅ |
| `terraform plan` | **Yes — needs taller-iac tfstate** | Manual only ⚠️ |
| `terraform apply` | **Yes** | Manual only ⚠️ |

### aprovisionamiento.tf Verification

Before finalizing the `desplegar.yaml` workflow, read `aprovisionamiento.tf` and verify:
1. Does it use `local-exec` to call `ansible-playbook`? If yes, the deploy runner needs Ansible.
2. What is the exact playbook path in the `local-exec` command? (Should be `ansible/site.yaml`)
3. Does it pass `--extra-vars`? If so, which variables?

---

## 7. Files Reference: Complete Contents from taller-iac

These are the exact final versions from the source project for reference. Adapt as needed.

### `terraform/.tflint.hcl` — Copy verbatim

```hcl
plugin "aws" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  call_module_type = "none"
}
```

### `.ansible-lint.yaml` — Adapt skip_list after discovery

```yaml
profile: basic

exclude_paths:
  - ansible/inventario_terraform.yaml
  - ansible/inventario_terraform.ejemplo.yaml
  # Add role test directories

warn_list:
  - yaml[truthy]
  - name[casing]

skip_list:
  - package-latest    # if any role uses state:latest intentionally
  - yaml[line-length] # long Jinja2/ProxyCommand strings
  - yaml[comments]    # ansible-galaxy generated files use bare # comments
  - yaml[colons]      # alignment spacing in defaults files
  - var-naming[no-role-prefix]  # only if variables are shared across templates

use_default_rules: true
```

### `.checkov.yaml` — Adapt skip-check after discovery

```yaml
soft-fail: false

directory:
  - terraform

framework:
  - terraform

download-external-modules: false

skip-check:
  # Populate from Phase 1b discovery
  # Document each entry with a comment explaining why it is skipped
```

### `Makefile` additions

```makefile
TFLINT_CONFIG  := terraform/.tflint.hcl
CHECKOV_CONFIG := .checkov.yaml

check: lint-terraform scan-terraform lint-ansible
	@printf ">>> Todos los checks pasaron.\n"

lint-terraform:
	@printf ">>> terraform fmt\n"
	terraform -chdir=terraform fmt -check -recursive
	@printf ">>> terraform init (sin backend)\n"
	terraform -chdir=terraform init -backend=false -input=false -reconfigure
	@printf ">>> terraform validate\n"
	terraform -chdir=terraform validate -no-color
	@printf ">>> tflint init\n"
	tflint --config=.tflint.hcl --chdir=terraform --init
	@printf ">>> tflint run\n"
	tflint --config=.tflint.hcl --chdir=terraform -f compact

scan-terraform:
	@printf ">>> checkov\n"
	checkov --config-file $(CHECKOV_CONFIG)

lint-ansible:
	@printf ">>> ansible-lint\n"
	ansible-lint ansible/site.yaml

.PHONY: check lint-terraform scan-terraform lint-ansible
```

---

## 8. Workflow Action Versions — Reference Table

These were validated in production in the taller-iac implementation:

| Action | Correct Version | Notes |
|--------|----------------|-------|
| `actions/checkout` | `@v4` | Standard |
| `hashicorp/setup-terraform` | `@v4` | Latest major |
| `terraform-linters/setup-tflint` | `@v4` | `@v6` does NOT exist |
| `bridgecrewio/checkov-action` | `@v12` | Major version tag |
| `actions/setup-python` | `@v5` | For ansible-lint install |
| `aws-actions/configure-aws-credentials` | `@v4` | NOT `@v6.1.0` |

---

## 9. Verification Checklist Before Merging PR

- [ ] `make check` exits 0 locally with no failures (only warnings allowed)
- [ ] `git diff --stat` shows only new files + Makefile additions (no logic changes)
- [ ] PR CI shows exactly 3 jobs: `Revisar el código Terraform`, `Escanear seguridad de Terraform`, `Revisar el código Ansible`
- [ ] No `planificar` or `desplegar` job appears in the PR checks
- [ ] GitHub Secrets `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set
- [ ] GitHub Environment `production` exists in repo settings
- [ ] After merge: manual trigger of `planificar.yaml` with "planificar" works (requires taller-iac deployed)

---

*Document written: 2026-04-26. Source project: ScrambledBits/taller-iac PR #3.*
