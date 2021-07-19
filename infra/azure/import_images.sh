#!/bin/bash

# USAGE
# ./import_images <myacr>

# Assume logged into AZ and ACR.
# TODO, check status of login
# TODO, check validity of ACR passed as argument.

# Import base images to the ACR.
images=$(cat ../../docker/third-party/images.txt)
for image in ${images}
do
  if [[ $image =~ "/" ]]; then
    # Keep the specific namespace.
    az acr import -n $1 --source "docker.io/${image}"
  else
    # Remove the library namespace.
    az acr import -n $1 --source "docker.io/library/${image}" --image $image
  fi
done

  