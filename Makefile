# Makefile del taller de observabilidad.
# Proporciona atajos para los comandos más comunes del flujo de trabajo.
#
# USO: make <target>
# Para ver todos los targets disponibles: make ayuda

# --- Configuración del shell ---
# SHELL: usar bash (no sh por defecto) para tener acceso a features de bash.
SHELL := bash

# .SHELLFLAGS: opciones que se pasan a bash antes de ejecutar cada recipe.
# -o errexit  → si un comando falla (sale con código != 0), el script se detiene.
#               Equivalente a `set -e`. Sin esto, un error silencioso podría
#               hacer que el siguiente paso corra sobre una base rota.
# -o nounset  → si se usa una variable sin definir, el script falla con error.
#               Equivalente a `set -u`. Evita errores por typos en nombres de variables.
# -o pipefail → si algún comando en un pipe falla, todo el pipe falla.
#               Sin esto: `cat archivo | grep patron` siempre devuelve 0 aunque
#               cat falle (p. ej., archivo no existe).
# -c          → obligatorio para que SHELL y .SHELLFLAGS funcionen juntos en make.
.SHELLFLAGS := -o errexit -o nounset -o pipefail -c

# Variables del Makefile
TERRAFORM_DIR := terraform
ANSIBLE_DIR   := ansible
INVENTORY     := $(ANSIBLE_DIR)/inventario_terraform.yaml
TFLINT_CONFIG  := terraform/.tflint.hcl
CHECKOV_CONFIG := .checkov.yaml

# .PHONY: declara que estos targets NO son nombres de archivos.
# Sin .PHONY, si existiera un archivo llamado "inventario", make pensaría que el
# target ya está "actualizado" y no ejecutaría el recipe.
# Todos los targets que no generan un archivo con su propio nombre deben estar aquí.
.PHONY: inventario ping provision open tf-destroy ayuda check lint-terraform scan-terraform lint-ansible install-tools

ayuda: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*##"}; {printf "  %-15s %s\n", $$1, $$2}'

# inventario: regenera ansible/inventario_terraform.yaml desde los outputs de Terraform.
# Necesario cuando la IP del nodo cambió (p. ej., después de stop/start de la EC2).
# Usa `-target` para aplicar solo el recurso `local_file.ansible_inventory` sin tocar
# nada más de la infraestructura. El inventario se crea localmente en tu laptop.
inventario: ## Regenera el inventario de Ansible desde los outputs de Terraform
	@cd $(TERRAFORM_DIR) && terraform apply -target=local_file.ansible_inventory -auto-approve
	@printf "✓ Inventario generado en %s\n" "$(INVENTORY)"

# ping: verifica que Ansible puede conectarse al nodo vía SSH.
# Ansible ejecuta el módulo "ping" que no hace ICMP sino una conexión SSH de prueba.
# Si falla aquí, revisa la IP en el inventario y los permisos del archivo .pem.
ping: inventario ## Verifica conectividad SSH con el nodo de monitoreo
	@ansible -i $(INVENTORY) all -m ping

# provision: ejecuta el playbook completo de Ansible en el nodo de monitoreo.
# Instala o actualiza todos los componentes del stack de observabilidad.
# Los roles son idempotentes: si algo ya está instalado y configurado correctamente,
# Ansible no lo toca. Solo aplica los cambios necesarios.
provision: inventario ## Ejecuta el playbook completo de Ansible (~5-8 min)
	@ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/site.yaml

# open: abre las interfaces web en el browser.
# Funciona en macOS (open) y Linux con entorno gráfico (xdg-open).
open: ## Abre Grafana, Prometheus y Alertmanager en el navegador
	@IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw monitoring_public_ip); \
	  printf "Grafana:      http://$$IP:3000\n"; \
	  printf "Prometheus:   http://$$IP:9090\n"; \
	  printf "Alertmanager: http://$$IP:9093\n"; \
	  open "http://$$IP:3000" 2>/dev/null || xdg-open "http://$$IP:3000"

# tf-destroy: destruye TODA la infraestructura creada por Terraform.
# IMPORTANTE: ejecutar al finalizar el taller para no consumir créditos AWS.
# Una instancia t3.small cuesta ~$0.023/hora. Dejándola encendida sin usar,
# en 24 horas son ~$0.55. En una semana, ~$3.86.
tf-destroy: ## Destruye toda la infraestructura (¡ejecutar al finalizar el taller!)
	@printf "⚠  Destruyendo infraestructura — se dejarán de consumir créditos AWS\n"
	@cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

# ── Targets de calidad de código y seguridad ─────────────────────────────────
# Estos targets son adicionales a los del taller (inventario, provision, etc.).
# Uso típico: correr 'make check' antes de hacer 'git push'.

# check: corre todos los checks de calidad en secuencia.
# Si cualquier check falla, Make se detiene. Correr antes de 'git push'.
check: lint-terraform scan-terraform lint-ansible ## Corre todos los checks de linting y seguridad
	@printf ">>> Todos los checks pasaron.\n"

# lint-terraform: valida formato, sintaxis y estilo del código Terraform.
# Usa -backend=false para no requerir credenciales AWS ni el estado remoto.
lint-terraform: ## Lint de Terraform (fmt, validate, tflint)
	@printf ">>> terraform fmt\n"
	terraform -chdir=$(TERRAFORM_DIR) fmt -check -recursive
	@printf ">>> terraform init (sin backend)\n"
	terraform -chdir=$(TERRAFORM_DIR) init -backend=false -input=false -reconfigure
	@printf ">>> terraform validate\n"
	terraform -chdir=$(TERRAFORM_DIR) validate -no-color
	@printf ">>> tflint init\n"
	tflint --config=.tflint.hcl --chdir=$(TERRAFORM_DIR) --init
	@printf ">>> tflint run\n"
	tflint --config=.tflint.hcl --chdir=$(TERRAFORM_DIR) -f compact

# scan-terraform: escanea el código Terraform buscando configuraciones inseguras.
scan-terraform: ## Escaneo de seguridad de Terraform con Checkov
	@printf ">>> checkov\n"
	checkov --config-file $(CHECKOV_CONFIG)

# lint-ansible: valida los playbooks y roles de Ansible.
lint-ansible: ## Lint de Ansible con ansible-lint
	@printf ">>> ansible-lint\n"
	ansible-lint $(ANSIBLE_DIR)/site.yaml

# install-tools: verifica que todas las herramientas necesarias estén instaladas.
# Correr una vez al configurar el entorno de desarrollo.
install-tools: ## Verifica herramientas requeridas para el pipeline CI/CD
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
