# ===========================================================================
# Makefile — Track B (local minikube + ngrok) operational shortcuts.
# ===========================================================================
# Targets:
#   up         Start minikube (docker driver) and enable the nginx ingress addon.
#   down       Stop the minikube cluster (state is preserved).
#   load       Side-load the local insiderdevops:dev image into minikube.
#   deploy     helm upgrade --install the chart into the dev namespace.
#   monitoring Install kube-prometheus-stack via scripts/setup-monitoring.ps1.
#   tunnel     Expose the forwarded port 8080 publicly with ngrok.
#   status     Show pods in the dev and monitoring namespaces.
#   all        Run load -> deploy -> monitoring, in that order.
#
# Requires GNU Make for Windows (see README.md):
#   winget install GnuWin32.Make    # or:  choco install make
#
# NOTE: recipe lines below are TAB-indented — GNU Make requires real tabs,
# not spaces. Do not reformat them to spaces.
# ===========================================================================

.DEFAULT_GOAL := help
.PHONY: help up down load deploy monitoring tunnel status all

help:
	@echo Targets: up down load deploy monitoring tunnel status all
	@echo See the header of this Makefile for what each one does.

up:
	minikube start --driver=docker
	minikube addons enable ingress

down:
	minikube stop

load:
	minikube image load insiderdevops:dev

deploy:
	helm upgrade --install insiderdevops ./charts/insiderdevops -f values-dev.yaml --namespace dev --create-namespace

monitoring:
	powershell -ExecutionPolicy Bypass -File ./scripts/setup-monitoring.ps1

tunnel:
	ngrok http 8080

status:
	kubectl get pods -n dev
	kubectl get pods -n monitoring

# Prerequisites are built left-to-right in a serial (non -j) run, so this
# applies the image, then the chart, then the monitoring stack, in order.
all: load deploy monitoring
	@echo all: image loaded, chart deployed, monitoring installed.
