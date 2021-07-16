#!/bin/bash

# ANSI escape codes for coloring.
readonly ANSI_RED="\033[0;31m"
readonly ANSI_GREEN="\033[0;32m"
readonly ANSI_RESET="\033[0;0m"

#######################################
# Print error message and exit
# Arguments:
#   Message to print.
#######################################
err() {
  echo -e "${ANSI_RED}ERROR: $*${ANSI_RESET}" >&2
  exit 1
}

#######################################
# Login to Azure using the specified tenant 
# and set the specified subscription.
# Arguments:
#   ID of a tenant to login to.
#   ID of subscription to set.
#######################################
login_azure() {
  local aad_tenant="$1"
  local az_subscription="$2"

  # Check if already logged in by trying to get an access token with the specified tenant.
  2>/dev/null az account get-access-token --tenant "${aad_tenant}" --output none
  if [[ $? -ne 0 ]] ; then
    echo "Login required to authenticate with Azure."
    echo "Attempting to login to Tenant: ${aad_tenant}"
    az login --output none --tenant "${aad_tenant}"
    if [[ $? -ne 0 ]]; then
      err "Failed to authenticate with Azure"
    fi
  fi

  local sub_name=$(az account show --subscription "${az_subscription}" | jq -r .name)
  # Set the subscription so future commands don't need to specify it.
  echo "Setting subscription to $sub_name (${az_subscription})."
  az account set --subscription "${az_subscription}"
}

#######################################
# Create global makefile config from Terraform outputs  
# Arguments:
#   Path to config file
#######################################
make_configmk() {
  local cfg_path="$1"
  local location=$(terraform output -raw location)
  local deployment_name=$(terraform output -raw deployment_name)
  local container_registry=$(terraform output -raw container_registry)
  local k8s_server_url=$(terraform output -json global_config | jq -r '.kubernetes_server_url // empty')
  local docker_root_image=$(terraform output -json global_config | jq -r '.docker_root_image // empty')
  local ip=$(terraform output -json global_config | jq -r '.ip // empty')
  local internal_ip=$(terraform output -json global_config | jq -r '.internal_ip // empty')
  if [ -z "$location" ] || [ -z "$deployment_name" ] || [ -z "$container_registry" ] || 
     [ -z "$k8s_server_url" ] || [ -z "$docker_root_image" ] || [ -z "$ip" ] || [ -z "$internal_ip" ]; then
    err "Missing Terraform outputs (make sure state is in sync)"
  fi

  # Write out new "config.mk".
  cat << EOF > ${cfg_path}
PROJECT := ${deployment_name}
REGION := ${location}
ZONE := ${location}
DOCKER_PREFIX := ${container_registry}
DOCKER_ROOT_IMAGE := ${docker_root_image}
DOMAIN := ${deployment_name}.azurewebsites.net
INTERNAL_IP := ${internal_ip}
IP := ${ip}
KUBERNETES_SERVER_URL := ${k8s_server_url}
ifeq (\$(NAMESPACE),default)
SCOPE = deploy
DEPLOY = true
else
SCOPE = dev
DEPLOY = false
endif
EOF

  echo "Config.mk file updated."
}

main() {
  # Load variables we need from a .env file if specified. Sourcing it as a script.
  if [ -f .env ]; then
    echo "Found .env file - sourcing it..."
    source ".env"
  fi

  if [ -z "$AAD_TENANT" ]; then
    err "Missing variable AAD_TENANT (specify via environment or '.env' file)"
  fi
  if [ -z "$AZURE_SUBSCRIPTION" ]; then
    err "Missing variable AZURE_SUBSCRIPTION (specify via environment or '.env' file)"
  fi

  local RESOURCE_GROUP_NAME=$(terraform output -raw resource_group)
  local K8S_CLUSTER_NAME=$(terraform output -raw k8sname)
  if [ -z "$RESOURCE_GROUP_NAME" ] || [ -z "$K8S_CLUSTER_NAME" ]; then
    err "Missing Terraform outputs (make sure state is in sync)"
  fi
  echo "RESOURCE_GROUP_NAME = $RESOURCE_GROUP_NAME, K8S_CLUSTER_NAME = $K8S_CLUSTER_NAME"
  
  # Login to Azure using the specified tenant if not already logged in.
  # Note, terraform recomments authenticating to az cli manually when running terraform locally,
  # see: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/managed_service_identity
  login_azure "${AAD_TENANT}" "${AZURE_SUBSCRIPTION}"

  # Connect kubectl to newly created k8s cluster.
  az aks get-credentials -g ${RESOURCE_GROUP_NAME} -n "${K8S_CLUSTER_NAME}"

  # Create config.mk file for hail build from terraform outputs.
  make_configmk "../../config.mk"
}

# Run main.
main "$@"
