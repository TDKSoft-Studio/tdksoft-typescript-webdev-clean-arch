#!/bin/bash
#
# deploy-validator.sh - High-resiliency pre-flight validator.
# Purpose: Ensures code quality, build integrity, and container readiness.
# Usage: ./scripts/deploy-validator.sh

set -euo pipefail

# --- Configuration ---
readonly SERVICE_NAME="appointment-svc"
readonly ROOT_DIR="$(git rev-parse --show-toplevel)"
readonly SERVICE_DIR="${ROOT_DIR}/apps/${SERVICE_NAME}"
readonly DOCKER_IMAGE="tdk/appointment-service:preflight"
readonly TEST_NAMESPACE="preflight-validation-$(date +%s)"
readonly HEALTH_URL="http://localhost:3001/health"

# UI Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# --- Internal State ---
LOG_FILE=$(mktemp /tmp/deploy-validator.XXXXXX.log)

# --- Logging Utilities ---
log::section() { echo -e "\n${PURPLE}===> $*${NC}"; }
log::info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log::success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
log::warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log::error()   { 
    echo -e "${RED}[FAIL]${NC}  $*" >&2
    if [[ -s "$LOG_FILE" ]]; then
        echo -e "${YELLOW}--- Last Execution Log Trace ---${NC}"
        cat "$LOG_FILE"
    fi
    exit 1 
}

# Silent execution wrapper that reveals logs only on error
utils::execute() {
    local label=$1
    shift
    log::info "Executing: $label..."
    if ! "$@" > "$LOG_FILE" 2>&1; then
        log::error "Command '$label' failed."
    fi
}

cleanup() {
    log::section "CLEANUP"
    log::info "Removing test containers and temporary artifacts..."
    docker stop test-appointment >/dev/null 2>&1 || true
    docker rmi "$DOCKER_IMAGE" >/dev/null 2>&1 || true
    if command -v kubectl &> /dev/null; then
        kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
    fi
    rm -f "$LOG_FILE"
    log::success "Cleanup complete."
}

# Trap signals for automatic cleanup
trap cleanup EXIT

# --- Validation Logic ---

validate_env() {
    log::section "ENVIRONMENT CHECK"
    local deps=("docker" "node" "npm" "curl" "perl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log::error "Dependency '$dep' is missing. Please install it."
        fi
    done
    log::success "All build dependencies are present."
}

sanitize_project() {
    log::section "PROJECT SANITIZATION"
    if [[ ! -d "$SERVICE_DIR" ]]; then
        log::error "Service directory not found at: $SERVICE_DIR"
    fi
    
    cd "$SERVICE_DIR"
    log::info "Normalizing package.json and line endings..."
    
    # Fix potential Windows CRLF issues using Perl
    perl -i -pe 's/\r//g' package.json
    
    # Standardize JSON format
    utils::execute "JSON Normalization" node -e "
        const fs = require('fs');
        const p = JSON.parse(fs.readFileSync('package.json', 'utf8'));
        fs.writeFileSync('package.json', JSON.stringify(p, null, 2));
    "
}

build_app() {
    log::section "BUILD PIPELINE"
    
    if [[ ! -d "node_modules" ]]; then
        utils::execute "NPM Install" npm ci --quiet
    fi

    utils::execute "Static Type Analysis" npm run type-check
    utils::execute "NPM Build Script" npm run build
    
    if [[ ! -f "dist/main.js" ]]; then
        log::error "Build succeeded but artifact 'dist/main.js' was not found."
    fi
    log::success "Compilation successful."
}

verify_runtime() {
    log::section "RUNTIME VERIFICATION"
    
    utils::execute "Docker Image Bake" docker build -f Dockerfile.dev -t "$DOCKER_IMAGE" .
    
    log::info "Launching container health probe..."
    docker run --rm -d -p 3001:3001 --name test-appointment "$DOCKER_IMAGE" > /dev/null
    
    local attempts=0
    local max_attempts=12
    
    # Polling the health endpoint
    while ! curl -s -f "$HEALTH_URL" > /dev/null; do
        attempts=$((attempts + 1))
        if ((attempts >= max_attempts)); then
            echo -e "${RED}Service failed to become healthy. Container logs:${NC}"
            docker logs test-appointment | tail -n 25
            log::error "Health check timeout at $HEALTH_URL"
        fi
        log::warn "Waiting for service... ($attempts/$max_attempts)"
        sleep 5
    done
    
    log::success "Container runtime validated and healthy."
}

test_k8s_orchestration() {
    if ! command -v kubectl &> /dev/null; then
        log::warn "Kubectl not found. Skipping K8s tests."
        return
    fi
    
    log::section "K8S ORCHESTRATION"
    
    # 1. Real creation of the namespace
    utils::execute "Namespace Creation" kubectl create namespace "$TEST_NAMESPACE"
    
    # 2. Brief pause for API propagation
    log::info "Waiting for namespace propagation..."
    sleep 2
    
    cd "$ROOT_DIR"
    for cell in "cell-001" "cell-002"; do
        log::info "Provisioning Cell: ${cell}..."
        
        # 3. Inject variables AND strip hardcoded namespaces
        sed "s|CELL_ID|${cell}|g; s|CELL_ID_VALUE|${cell}|g; s|appointment-service:dev|${DOCKER_IMAGE}|g" \
            infrastructure/k8s/cells/base/cell-dev.yaml | \
            sed '/^[[:space:]]*namespace:/d' | \
            kubectl apply -n "$TEST_NAMESPACE" -f - > "$LOG_FILE" 2>&1 || log::error "Failed to apply manifest for ${cell}"
    done
    
    log::success "Kubernetes manifests are valid and orchestrated."
}

# --- Execution ---

main() {
    echo -e "${BLUE}==================================================================${NC}"
    echo -e "  GOOGLE-GRADE VALIDATOR: ${SERVICE_NAME^^}"
    echo -e "  Working Dir: $(pwd)"
    echo -e "${BLUE}==================================================================${NC}"

    validate_env
    sanitize_project
    build_app
    verify_runtime
    test_k8s_orchestration

    echo -e "\n${GREEN}✔ PRE-FLIGHT VALIDATION SUCCESSFUL. READY TO PUSH.${NC}\n"
}

main "$@"