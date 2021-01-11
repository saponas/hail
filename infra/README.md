This is a work in progress to use Terraform to manage our cloud
infrastructure.

Instructions:

- You will need a GCP project.  Configure `gcloud` to point at your project:

   ```
   gcloud config set project <gcp-project-id>
   gcloud config set compute/zone <gcp-zone>
   ```

- Delete the default network if it exists.

- Create a service account for Terraform with Owner role, create a
  service account key and place it in
  `$HOME/.hail/terraform_sa_key.json`.

- Enable the the GCP services needed by Hail:

   ```
   gcloud services enable \
       compute.googleapis.com \
       cloudresourcemanager.googleapis.com \
       servicenetworking.googleapis.com \
       sqladmin.googleapis.com \
       container.googleapis.com \
       serviceusage.googleapis.com \
       dns.googleapis.com \
       logging.googleapis.com \
       cloudprofiler.googleapis.com
   ```

- Install terraform.

- Create `$HOME/.hail/global.tfvars` that looks like:

   ```
   gsuite_organization = "<gsuite-organization>"
   # batch_gcp_regions is a JSON array of string, the names of the gcp
   # regions to schedule over in Batch.
   batch_gcp_regions = "<batch-gcp-regions>"
   gcp_project = "<gcp-project-id>"
   # gcp_location is the bucket location that spans the regions you're
   # going to schedule across in Batch.  If you are running on one
   # region, it can just be that region.
   gcp_location = "<gcp-location>"
   gcp_region = "<gcp-region>"
   gcp_zone = "<gcp-zone>"
   domain = "<domain>"
   ```

- Run `terraform init`.

- Run `terraform apply -var-file="$HOME/.hail/global.tfvars"`.
  Terraform has created a GKE cluster named `vdc`.  Configure
  `kubectl` to point at the vdc cluster:

  ```
  gcloud container clusters get-credentials --zone <gcp-zone> vdc
  ```

- Go to the Google Cloud console, VPC networks > internal > Private
  service connection > Private connections to services, and enable
  Export custom routes to both connections.

You can now install Hail:

- Create a VM on the internal network, 100GB, Ubuntu 20.04 TLS, allow
  full access to all Cloud APIs.  10GB will run out of space.  We
  assume the rest of the commands are run on the VM.

- Standardize file permissions.  This is for docker, which considers
  permissions for caching.  Run `echo 'umask 022' > ~/.profile`.  You
  will need to log out/in or run `umask 022`.

- Clone the Hail Github repository:

  ```
  git clone https://github.com/hail-is/hail.git
  ```

- Install some dependencies on the VM:

  ```
  sudo apt update
  sudo apt install -y docker.io python3-pip openjdk-8-jre-headless jq
  sudo snap install --classic kubectl
  sudo usermod -a -G docker $USER
  gcloud -q auth configure-docker
  gcloud container clusters get-credentials --zone <gcp-zone> vdc
  python3 -m pip install -r $HOME/hail/docker/requirements.txt
  ```

  You will have to log out/in for the usermod to take effect.

- Update $HAIL/config.mk with your infrastructure settings.  You can
  get settings from the default/global-config secret:

  ```
  kubectl -n default get secret global-config -o json | jq '.data | map_values(@base64d)'
  ```

- In `$HAIL/docker/third-party` run:

  ```
  PROJECT=<gc-project-id> ./copy_images.sh
  ```

  This copies some base images from Dockerhub (which now has rate
  limits) to GCR.

- Generate TLS certificates.  See ../dev-docs/tls-cookbook.md.

- Run `kubectl -n default apply -f $HAIL/ci/bootstrap.yaml`.

- Build the CI utils image.  Run `make push-ci-utils` in $HAIL/ci.

- Deploy the bootstrap gateway.  Run `make deploy` in
  $HAIL/bootstrap-gateway.

- Create Let's Encrypt certs. Run `make run` in $HAIL/letsencrypt.

- Deploy the gateway.  Run `make deploy` in $HAIL/gateway.

- Deploy the internal-gateway.  Run `make deploy` in $HAIL/internal-gateway.

- Go to the Google Cloud console, API & Services, Credentials.
  Configure the consent screen.  Add the scope:
  https://www.googleapis.com/auth/userinfo.email.  Create an OAuth
  client ID.  Authorize the redirect URI:
  https://auth.<domain>/oauth2callback.  Download the client secret
  as client_secret.json.  Create the auth-oauth2-client-secret secret
  with:

  ```
  kubectl -n default create secret generic auth-oauth2-client-secret --from-file=./client_secret.json
  ```

- Create the batch worker image.  In `$HAIL/batch`, run:

  ```
  make create-build-worker-image-instance
  ```

  Wait for the `build-batch-worker-image` instance to be stopped.  Then run:

  ```
  make create-worker-image
  ```

- Bootstrap the cluster by running:

  ```
  HAIL_CI_UTILS_IMAGE=gcr.io/<gcp-project>/ci-utils:latest \
    HAIL_CI_BUCKET_NAME=dummy \
    KUBERNETES_SERVER_URL='<k8s-server-url>' \
    HAIL_DEFAULT_NAMESPACE='default' \
    HAIL_DOMAIN=<domain> \
    HAIL_GCP_ZONE=<gcp-zone> \
    HAIL_GCP_PROJECT=<gcp-project> \
    PYTHONPATH=$HOME/hail/ci:$HOME/hail/batch:$HOME/hail/hail/python \
    python3 $HAIL/ci/bootstrap.py hail-is/hail:main $(git rev-parse HEAD) test_batch_0
  ```

- Create the initial (developer) user:

  ```
  HAIL_CI_UTILS_IMAGE=gcr.io/<gcp-project>/ci-utils:latest \
    HAIL_CI_BUCKET_NAME=dummy \
    KUBERNETES_SERVER_URL='<k8s-server-url>' \
    HAIL_DEFAULT_NAMESPACE='default' \
    HAIL_DOMAIN=<domain> \
    HAIL_GCP_ZONE=<gcp-zone> \
    HAIL_GCP_PROJECT=<gcp-project> \
    PYTHONPATH=$HOME/hail/ci:$HOME/hail/batch:$HOME/hail/hail/python \
    python3 $HAIL/ci/bootstrap.py --extra-code-config '{"username":"<username>","email":"<email>"}' hail-is/hail:main $(git rev-parse HEAD) create_initial_user
  ```

  Additional users can be added by the intial user by going to auth.hail.is/users.