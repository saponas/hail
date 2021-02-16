PROJECT := hail-295901
REGION := australia-southeast1
ZONE := australia-southeast1-b
DOCKER_ROOT_IMAGE := $(REGION)-docker.pkg.dev/$(PROJECT)/hail/ubuntu:18.04
DOMAIN := hail.populationgenomics.org.au
INTERNAL_IP := 10.152.0.2
IP := 35.201.29.236
KUBERNETES_SERVER_URL := https://34.87.199.41
ifeq ($(NAMESPACE),default)
SCOPE = deploy
DEPLOY = true
else
SCOPE = dev
DEPLOY = false
endif
