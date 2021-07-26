PROJECT := hailtest0
REGION := westus2
ZONE := westus2
DOCKER_PREFIX := hailtest0acr.azurecr.io
DOCKER_ROOT_IMAGE := hailtest0acr.azurecr.io/ubuntu:18.04
DOMAIN := azhailtest0.net
INTERNAL_IP := 10.1.63.254
IP := 20.83.89.39
KUBERNETES_SERVER_URL := https://hailtest0vdc-17bac1fd.hcp.westus2.azmk8s.io
ADMIN_EMAIL := gregsmi@microsoft.com
ifeq ($(NAMESPACE),default)
SCOPE = deploy
DEPLOY = true
else
SCOPE = dev
DEPLOY = false
endif
