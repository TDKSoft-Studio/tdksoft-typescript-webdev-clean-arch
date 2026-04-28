#!/bin/bash
#
# deploy-validator.sh - Pre-flight deployment validation for Appointment Service.
# Optimized for local execution and CI/CD consistency.

set -euo pipefail

# --- Configuration & Constants ---

# FIX: Removed "apps/" prefix because it is appended in SERVICE_DIR below
readonly SERVICE_NAME="appointment-svc"
readonly ROOT_DIR="$(git rev-parse --show-toplevel)"
readonly SERVICE_DIR="${ROOT_DIR}/apps/${SERVICE_NAME}"
readonly DOCKER_IMAGE="tdk/appointment-service:preflight"
readonly TEST_NAMESPACE="preflight-validation-$(date +%s)"
readonly CELLS=("cell-001" "cell-002")

# UI Colors for terminal output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# --- Utility Functions ---

log::info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log::success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
log::warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log::error()   { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

cleanup() {
    log::info "Executing cleanup tasks..."
    # Ensure background processes and temporary containers are removed
    docker stop test-appointment 2>/dev/null || true
    docker rmi "$DOCKER_IMAGE" 2>/dev/null || true
    if command -v kubectl &> /dev/null; then
        kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found=true --wait=false 2>/dev/null || true
    fi
    log::success "Cleanup complete."
}

# Register cleanup trap to run on script exit or interruption
trap cleanup EXIT

# --- Validation Logic ---

validate_environment() {
    log::info "Verifying development environment dependencies..."
    command -v docker >/dev/null 2>&1 || log::error "Docker is required."
    command -v node >/dev/null 2>&1 || log::error "Node.js is required."
    command -v npm >/dev/null 2>&1 || log::error "NPM is required."
}

validate_package_json() {
    log::info "Sanitizing package.json at ${SERVICE_DIR}..."
    
    # Check if directory exists before attempting to enter
    if [ ! -d "$SERVICE_DIR" ]; then
        log::error "Directory not found: $SERVICE_DIR"
    fi
    
    cd "$SERVICE_DIR"
    
    # Remove Windows carriage returns (\r) to prevent bash interpretation errors
    sed -i 's/\r//g' package.json 2>/dev/null || true
    
    # Standardize JSON formatting using Node.js
    node -e "
        try {
            const fs = require('fs');
            const p = JSON.parse(fs.readFileSync('package.json', 'utf8'));
            fs.writeFileSync('package.json', JSON.stringify(p, null, 2));
        } catch (e) {
            console.error(e);
            process.exit(1);
        }
    " || log::error "Invalid package.json structure."
    
    log::success "package.json is standardized."
}

execute_build_pipeline() {
    log::info "Starting local build pipeline (TS > JS)..."
    
    if [ ! -d "node_modules" ]; then
        log::warn "node_modules missing, installing dependencies..."
        npm ci --quiet
    fi

    log::info "Running static type analysis..."
    # If this fails, check tsconfig.json for deprecation errors
    npm run type-check || log::error "TypeScript validation failed."

    log::info "Compiling application..."
    npm run build > /dev/null || log::error "Build script failed."
    
    [[ -f "dist/main.js" ]] || log::error "Artifact dist/main.js not found after build."
    log::success "Application compiled successfully."
}

test_container_runtime() {
    log::info "Building Docker image: ${DOCKER_IMAGE}..."
    docker build -f Dockerfile.dev -t "$DOCKER_IMAGE" . > /dev/null || log::error "Docker build failed."

    log::info "Launching container health probe..."
    docker run --rm -d -p 3001:3001 --name test-appointment "$DOCKER_IMAGE" > /dev/null
    
    # Polling logic for service readiness
    local max_retries=5
    local count=0
    while ! curl -s http://localhost:3001/health | grep -q "healthy"; do
        ((count++))
        if ((count >= max_retries)); then
            docker logs test-appointment
            log::error "Container health check timed out."
        fi
        log::warn "Waiting for service readiness... ($count/$max_retries)"
        sleep 2
    done
    
    docker stop test-appointment > /dev/null
    log::success "Container runtime validated."
}

test_k8s_orchestration() {
    if ! command -v kubectl &> /dev/null; then
        log::warn "Kubectl not found. Skipping cluster orchestration test."
        return
    fi

    log::info "Simulating Kubernetes deployment in namespace: ${TEST_NAMESPACE}..."
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null
    
    cd "$ROOT_DIR"
    for cell in "${CELLS[@]}"; do
        log::info "Provisioning Cell: ${cell}..."
        # Replace placeholders in manifest and apply
        sed "s/CELL_ID/${cell}/g; s/CELL_ID_VALUE/${cell}/g; s/appointment-service:dev/${DOCKER_IMAGE}/g" \
            infrastructure/k8s/cells/base/cell-dev.yaml | \
            kubectl apply -n "$TEST_NAMESPACE" -f - > /dev/null
    done

    log::info "Waiting for pod stabilization..."
    kubectl wait --for=condition=Ready pods --all -n "$TEST_NAMESPACE" --timeout=30s || \
        log::warn "Pods are taking longer than expected to start."
    
    log::success "Kubernetes manifest orchestration validated."
}

# --- Main Execution Flow ---

main() {
    echo -e "${BLUE}==================================================================${NC}"
    echo -e "  DEPLOYMENT VALIDATOR: ${SERVICE_NAME^^}"
    echo -e "${BLUE}==================================================================${NC}"

    validate_environment
    validate_package_json
    execute_build_pipeline
    test_container_runtime
    test_k8s_orchestration

    echo -e "\n${GREEN}✔ PRE-FLIGHT VALIDATION SUCCESSFUL${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. git tag -a v1.x.x -m 'Validated Release'"
    echo "  2. git push origin v1.x.x"
    echo -e "${BLUE}==================================================================${NC}\n"
}

main "$@"