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

# .PHONY: declara que estos targets NO son nombres de archivos.
# Sin .PHONY, si existiera un archivo llamado "inventario", make pensaría que el
# target ya está "actualizado" y no ejecutaría el recipe.
# Todos los targets que no generan un archivo con su propio nombre deben estar aquí.
.PHONY: inventario ping provision open tf-destroy ayuda

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
