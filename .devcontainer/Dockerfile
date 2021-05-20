# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.177.0/containers/ubuntu/.devcontainer/base.Dockerfile

# [Choice] Ubuntu version: bionic, focal
ARG VARIANT="focal"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

# [Optional] Uncomment this section to install additional OS packages.
RUN sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2
RUN curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
RUN echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends docker.io python3-pip openjdk-8-jre-headless jq kubectl azure-cli wget unzip 

RUN wget https://releases.hashicorp.com/terraform/0.15.4/terraform_0.15.4_linux_amd64.zip
RUN unzip terraform_0.15.4_linux_amd64.zip
RUN sudo mv terraform /usr/local/bin/

# Install pip packages
#COPY docker/requirements.txt /tmp/scripts/requirements.txt
#WORKDIR /tmp/scripts/
#RUN python3 -m pip install -r requirements.txt

