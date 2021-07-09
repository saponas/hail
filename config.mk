PROJECT := azhaildev2-rg
REGION := westus2
ZONE := westus2
DOCKER_PREFIX := azhaildev2acr.azurecr.io
DOCKER_ROOT_IMAGE := $(DOCKER_PREFIX)/ubuntu:18.04
DOMAIN := azhaildev2.azurewebsites.net
INTERNAL_IP := 52.148.164.36
IP := 40.91.87.11
KUBERNETES_SERVER_URL := https://azhaildev2vdc-ab81f4ac.hcp.westus2.azmk8s.io
ifeq ($(NAMESPACE),default)
SCOPE = deploy
DEPLOY = true
else
SCOPE = dev
DEPLOY = false
endif
