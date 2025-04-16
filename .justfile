set export
set dotenv-filename := '.env.secrets'
set dotenv-load

KIND_CLUSTER_NAME := 'devsecops'
RED := '\033[0;31m'
GREEN := '\033[0;32m'
YELLOW := '\033[1;33m'
BLUE := '\033[0;34m'
NC := '\033[0m'


@_default:
  just --list


# Build the application
@build:
  docker compose build
# Start app container and DB
@start: build
  docker compose up --build -d
# Stop app container and DB
@stop:
  docker compose stop


# Start nodegoat in k8s
start-nodegoat-k8s:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="nodegoat"
  kubectl create ns ${NAMESPACE} || true
  kubectl apply -n ${NAMESPACE} -f k8s/nodegoat/
# Start nodegoat in k8s
stop-nodegoat-k8s:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="nodegoat"
  kubectl delete -n ${NAMESPACE} -f k8s/nodegoat/


# Start sonarqube
start-sonarqube:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="sonarqube"
  kind get clusters |grep -q ${KIND_CLUSTER_NAME} || just _error "You should configure the kubernetes cluster before. See just 'start-kind-cluster'..."
  helm repo update
  helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
  helm upgrade --install sonarqube sonarqube/sonarqube \
    --namespace "${NAMESPACE}" \
    --create-namespace \
  -f k8s/sonarqube/sonarqube-values.yaml
# Stop sonarqube
stop-sonarqube:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="sonarqube"
  helm uninstall sonarqube -n ${NAMESPACE}


# Start dependency-track
start-dependency-track:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="dependencytrack"
  helm repo add dependency-track https://dependencytrack.github.io/helm-charts
  helm repo update
  helm upgrade --install \
    dependencytrack \
    dependency-track/dependency-track \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set frontend.service.type="NodePort" \
    --set frontend.service.nodePort=30801 \
    --set frontend.apiBaseUrl="http://localhost:4001" \
    --set apiServer.persistentVolume.enabled="true" \
    --set apiServer.persistentVolume.size="2Gi" \
    --set apiServer.service.nodePort=30101 \
    --set apiServer.service.type="NodePort" \
    --set apiServer.service.nodePort=30101
# Stop dependency-track
stop-dependency-track:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="dependencytrack"
  helm uninstall dependencytrack -n ${NAMESPACE}


# Start faraday
start-faraday:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="faraday"
  helm upgrade --install \
    faraday \
    charts/faraday \
    --namespace "${NAMESPACE}" \
    --create-namespace
# Stop faraday
stop-faraday:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="faraday"
  helm uninstall faraday -n ${NAMESPACE} || true


# Start archerysec
start-archerysec:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="archerysec"
  kubectl create ns ${NAMESPACE} || true
  kubectl apply -n ${NAMESPACE} -f k8s/archery/
# Start archerysec
stop-archerysec:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="archerysec"
  kubectl delete -n ${NAMESPACE} -f k8s/archery/


# Start all
@start-all: start start-kind-cluster start-sonarqube start-dependency-track start-archerysec
# Stop all
@stop-all: stop stop-kind-cluster


# Create the kubernetes cluster
@deploy-kind-cluster:
  kind create cluster --name ${KIND_CLUSTER_NAME} --config=kind-config.yaml
  just _info "Waiting for the cluster to be ready..."
  sleep 10
  just _info "Deploying metrics-server..."
  kubectl apply -f k8s/metrics-server/
# Delete the kubernetes cluster
@destroy-kind-cluster:
  kind delete cluster --name ${KIND_CLUSTER_NAME}


# Start the kubernetes cluster
@start-kind-cluster:
  docker start $(docker ps -a -q --filter "name=${KIND_CLUSTER_NAME}-")
# Stop the kubernetes cluster
@stop-kind-cluster:
  docker stop $(docker ps -q --filter "name=${KIND_CLUSTER_NAME}-")


# Install github runners
setup-github-runners:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="arc-systems"
  helm upgrade --install arc \
      --namespace "${NAMESPACE}" \
      --create-namespace \
      oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
  NAMESPACE="arc-runners"
  INSTALLATION_NAME="arc-runner-set"
  helm upgrade --install "${INSTALLATION_NAME}" \
      --namespace "${NAMESPACE}" \
      --create-namespace \
      --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
      --set githubConfigSecret="pre-defined-secret" \
      --set containerMode.type="dind" \
      --set minRunners=0 \
      --set maxRunners=10 \
      oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
  kubectl create secret generic pre-defined-secret \
    --namespace=${NAMESPACE} \
    --from-literal=github_token=${GITHUB_PAT} \
    --dry-run=client -o yaml | kubectl apply -f -

# Open important platforms
@open:
  open http://localhost:9000 http://localhost:8081 http://localhost:8083 http://localhost:8084

# Install project dependencies
setup:
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ "{{os()}}" == "macos" ]]; then
    just _info "Installing pre-commit..."
    brew install pre-commit
    just _info "Setting up pre-commit..."
    pre-commit install
    just _info "Installing kind..."
    brew install kind
  elif [[ "{{os()}}" == "linux" ]]; then
    just _info "Installing pre-commit..."
    pip install pre-commit
    just _info "Setting up pre-commit..."
    pre-commit install
    just _info "Installing kind..."
    # For AMD64 / x86_64
    [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64
    # For ARM64
    [ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-arm64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
  else
    just _error "Operating system {{os()}} not supported!"
    exit 1
  fi


_info MESSAGE:
  #!/usr/bin/env bash
  echo -e "${GREEN}[INFO]${NC} {{MESSAGE}}"
_warn MESSAGE:
  #!/usr/bin/env bash
  echo -e "${YELLOW}[WARNING]${NC} {{MESSAGE}}"
_debug MESSAGE:
  #!/usr/bin/env bash
  echo -e "${BLUE}[WARNING]${NC} {{MESSAGE}}"
_error MESSAGE:
  #!/usr/bin/env bash
  echo -e "${RED}[ERROR]${NC} {{MESSAGE}}"
  exit 1
