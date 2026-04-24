SHELL := bash
.SHELLFLAGS := -o errexit -o nounset -o pipefail -c

TERRAFORM_DIR := terraform
ANSIBLE_DIR   := ansible
INVENTORY     := $(ANSIBLE_DIR)/inventario_terraform.yaml

.PHONY: inventario ping provision open tf-destroy ayuda

ayuda: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*##"}; {printf "  %-15s %s\n", $$1, $$2}'

inventario: ## Regenera el inventario de Ansible desde los outputs de Terraform
	@cd $(TERRAFORM_DIR) && terraform apply -target=local_file.ansible_inventory -auto-approve
	@printf "✓ Inventario generado en %s\n" "$(INVENTORY)"

ping: inventario ## Verifica conectividad SSH con el nodo de monitoreo
	@ansible -i $(INVENTORY) all -m ping

provision: inventario ## Ejecuta el playbook completo de Ansible (~5-8 min)
	@ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/site.yaml

open: ## Abre Grafana, Prometheus y Alertmanager en el navegador
	@IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw monitoring_public_ip); \
	  printf "Grafana:      http://$$IP:3000\n"; \
	  printf "Prometheus:   http://$$IP:9090\n"; \
	  printf "Alertmanager: http://$$IP:9093\n"; \
	  open "http://$$IP:3000" 2>/dev/null || xdg-open "http://$$IP:3000"

tf-destroy: ## Destruye toda la infraestructura (¡ejecutar al finalizar el taller!)
	@printf "⚠  Destruyendo infraestructura — se dejarán de consumir créditos AWS\n"
	@cd $(TERRAFORM_DIR) && terraform destroy -auto-approve
