PROJECT := mwtftest-rg
REGION := westus2
ZONE := westus2
DOCKER_PREFIX := mwtftestacr.azurecr.io
DOCKER_ROOT_IMAGE := $(DOCKER_PREFIX)/ubuntu:18.04
DOMAIN := mwtftest.azurewebsites.net
INTERNAL_IP := 20.190.44.219
IP := 52.151.53.179
KUBERNETES_SERVER_URL := https://mwtftestvdc-d70e2049.hcp.westus2.azmk8s.io
ifeq ($(NAMESPACE),default)
SCOPE = deploy
DEPLOY = true
else
SCOPE = dev
DEPLOY = false
endif
