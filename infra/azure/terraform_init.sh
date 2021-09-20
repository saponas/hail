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
# Create a Resource Group in Azure.
# Arguments:
#   Name for the Resource Group
#   Azure location to create the Resource Group.
# Returns:
#   0 If Resource Group is created.
#######################################
create_resource_group() {
  local resource_group_name="$1"
  local location="$2"

  echo "Checking if resource group ${resource_group_name} exists."
  
  # When a resource group doesn't exist, the `az group exists` command returns an authorization error.
  local rg_exists
  rg_exists=$(az group exists -n "${resource_group_name}")
  
  if [[ $? -ne 0 ]]; then
    err "Failed to check for existence of resource group ${resource_group_name}. Probably a permissions issue."
    return 1
  fi

  if [[ ${rg_exists} == "true" ]]; then
    echo "Resource group ${resource_group_name} already exists."
    return 1
  else
    echo "Resource group ${resource_group_name} does not exist - creating..."
    1>/dev/null az group create --name "${resource_group_name}" --location "${location}"
    if [[ $? -ne 0 ]]; then
      err "Failed to create resource group ${resource_group_name}"
      return 1
    else
      return 0
    fi
  fi
}

#######################################
# Create a Storage Account in Azure.
# Arguments:
#   Name for the Storage Account
#   Name of the Resource Group
#   Azure location to create the Resource Group.
# Returns:
#   0 If Storage Account is created.
#######################################
create_storage_account() {
  local storage_account_name="$1"
  local resource_group_name="$2"
  local location="$3"
  # Uses jq to parse the json output and grab the "reason" field. -r for raw so there aren't quotes in the string.
  echo "Checking if storage account ${storage_account_name} exists."
  local sa_reason
  sa_reason=$(az storage account check-name -n "${storage_account_name}" | jq -r .reason)
  # TODO This is probably checking the exit code of jq
  # TODO, storage account names need to be globally unique, should add a random string here.
  if [[ $? -ne 0 ]]; then
    err "Failed to check for existence of storage account ${storage_account_name}. Probably a permissions issue."
  fi
  if [[ ${sa_reason} == "AlreadyExists" ]]; then
    echo "Storage account ${storage_account_name} exists."
  else
    echo "Storage account ${storage_account_name} does not exist - creating..."
    1>/dev/null az storage account create --name "${storage_account_name}" --resource-group "${resource_group_name}" --location "${location}"
    if [[ $? -ne 0 ]]; then
      err "Failed to create storage group ${storage_account_name}"
    fi
  fi
}

#######################################
# Create a Storage Container in Azure.
# Arguments:
#   Name for the Storage Container
#   Name of the Storage Account
# Returns:
#   0 If the Storage Container is created.
#######################################
create_storage_container() {
  local container_name="$1"
  local storage_account_name="$2"
  # User should have "Storage Blob Data Contributor" role.
  # Uses jq to parse the json output and grab the "exists" field.
  container_exists=$(az storage container exists -n "${container_name}" --account-name "${storage_account_name}" --auth-mode login | jq .exists)
  # TODO This is probably checking the exit code of jq
  if [[ $? -ne 0 ]]; then
    err "Failed to check for existence of container ${container_name} in storage account ${storage_account_name}. Probably a permissions issue."
  fi
  if [[ ${container_exists} == "false" ]]; then
      echo "Creating container ${container_name}"
      1>/dev/null az storage container create -n "${container_name}" --account-name "${storage_account_name}" --auth-mode login
      if [[ $? -ne 0 ]]; then
        err "Failed to create storage container ${container_name}"
      fi
      # Wait for storage container to create, TODO consider polling.
      sleep 5
  else
      echo "Container ${container_name} exists."
  fi
}

#######################################
# Create TFVARS file for use in Terraform operations  
# Arguments:
#   Name of the deployment
#   Name of the main resource group
#######################################
make_tfvars() {
  local deployment_name="$1"
  local resource_group_name="$2"
  local admin_email="$3"

  # Write out new default tfvars file.
  cat << EOF > terraform.tfvars
deployment_name     = "${deployment_name}"
resource_group_name = "${resource_group_name}"
admin_email         = "${admin_email}"
EOF

  echo "Variable file terraform.tfvars created."
}

main() {
  # TODO handle failed/partial out of sync deployments, maybe a --destroy command (consistent with the terraform vernacular).
  # If pre-existing azure resources exist that are out of sync with the tf state, then terraform will throw an error stating that 
  # they need to be imported. At the least, we might want to validate that the resources we intend to create can be created before
  # kicking off terraform.

  # Process options.
  while getopts "${GETOPTS_STR}" option; do
    case "${option}" in
      v) is_verbose="true";;
    esac
  done

  # If verbose option, print prereq versions.
  if [[ -n ${is_verbose} ]]; then
    # Report terraform version
    terraform -v
    # Report Azure CLI verison
    az --version
  fi

  # Load variables we need from a .env file if specified. Sourcing it as a script.
  if [ -f .env ]; then
    echo "Found .env file - sourcing it..."
    source ".env"
  fi

  if [ -z "$DEPLOYMENT_NAME" ]; then
    err "Missing variable DEPLOYMENT_NAME (specify via environment or '.env' file)"
  fi
  if [ -z "$LOCATION" ]; then
    err "Missing variable LOCATION (specify via environment or '.env' file)"
  fi
  if [ -z "$AAD_TENANT" ]; then
    err "Missing variable AAD_TENANT (specify via environment or '.env' file)"
  fi
  if [ -z "$AZURE_SUBSCRIPTION" ]; then
    err "Missing variable AZURE_SUBSCRIPTION (specify via environment or '.env' file)"
  fi

  # TODO, deployment name validity check
  echo "DEPLOYMENT_NAME = $DEPLOYMENT_NAME, LOCATION = $LOCATION"
  local RESOURCE_GROUP_NAME="${DEPLOYMENT_NAME}-rg"
  local STORAGE_ACCOUNT="${DEPLOYMENT_NAME}tfsa"

  # Login to Azure using the specified tenant if not already logged in.
  # Note, terraform recomments authenticating to az cli manually when running terraform locally,
  # see: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/managed_service_identity
  login_azure "${AAD_TENANT}" "${AZURE_SUBSCRIPTION}"
  # Create resource group if it doesn't exist.
  create_resource_group "${RESOURCE_GROUP_NAME}" "${LOCATION}"
  # Create storage account for Terraform state if it doesn't exist.
  create_storage_account "${STORAGE_ACCOUNT}" "${RESOURCE_GROUP_NAME}" "${LOCATION}"
  # Create container to store Terraform state if it doesn't exist.
  create_storage_container "tfstate" "${STORAGE_ACCOUNT}"
  # Get an access key to the storage account for Terraform state. Use jq to grab the "value" field of the first key. "-r" option gives raw output without quotes.
  local sa_access_key=$(az storage account keys list --resource-group "${RESOURCE_GROUP_NAME}" --account-name "${STORAGE_ACCOUNT}" --subscription "${AZURE_SUBSCRIPTION}" | jq -r .[0].value)
  if [[ $? -ne 0 ]]; then
    err "Failed to get access key for storage account ${STORAGE_ACCOUNT}"
  fi
  # TODO, might need a check to verify the storage account and container are up and running at this point, script has failed once when needing to create the container, with a ContainerNotFound error message.
  # Configure Terraform backend (azurerm) to use Azure blob container to store state. This configuration is persisted in local tfstate.
  terraform init -reconfigure -upgrade -backend-config="storage_account_name=${STORAGE_ACCOUNT}" -backend-config="container_name=tfstate" -backend-config="access_key=${sa_access_key}" -backend-config="key=hail.tfstate"

  # Create/update Terraform variables file.
  make_tfvars "${DEPLOYMENT_NAME}" "${RESOURCE_GROUP_NAME}" "${ADMIN_EMAIL}"
}

# Run main.
main "$@"