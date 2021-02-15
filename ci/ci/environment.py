import os

GCP_PROJECT = os.environ['HAIL_GCP_PROJECT']
assert GCP_PROJECT != ''
GCP_ZONE = os.environ['HAIL_GCP_ZONE']
assert GCP_ZONE != ''
GCP_REGION = '-'.join(GCP_ZONE.split('-')[:-1])  # us-west1-a -> us-west1
DOMAIN = os.environ['HAIL_DOMAIN']
assert DOMAIN != ''
IP = os.environ.get('HAIL_IP')
CI_UTILS_IMAGE = os.environ.get(
    'HAIL_CI_UTILS_IMAGE',
    f'{GCP_REGION}-docker.pkg.dev/hail-vdc/hail/ci-utils:latest'
)
DEFAULT_NAMESPACE = os.environ['HAIL_DEFAULT_NAMESPACE']
KUBERNETES_SERVER_URL = os.environ['KUBERNETES_SERVER_URL']
BUCKET = os.environ['HAIL_CI_BUCKET_NAME']
