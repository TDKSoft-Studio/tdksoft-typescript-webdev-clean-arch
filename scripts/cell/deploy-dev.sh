#!/bin/bash

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🏗️  Déploiement des Cells - Environnement DEV${NC}"
echo "========================================="
echo ""

NAMESPACE="appointment-system"
CELL_COUNT=${1:-3}  # 3 cells en dev

# Créer le namespace
echo -e "${YELLOW}📦 Création du namespace: ${NAMESPACE}${NC}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Appliquer le CRD
echo -e "${YELLOW}📜 Application du CRD${NC}"
kubectl apply -f infrastructure/k8s/cells/crd/cell-crd.yaml

# Attendre que le CRD soit prêt
sleep 3

# Déployer les cells
echo -e "${YELLOW}🚀 Déploiement de ${CELL_COUNT} cells...${NC}"
for i in $(seq -f "%03g" 1 ${CELL_COUNT}); do
    echo "  - Création cell-${i}"
    sed "s/CELL_ID/cell-${i}/g" infrastructure/k8s/cells/base/cell-dev.yaml | kubectl apply -f -
done

# Attendre que les pods soient prêts
echo ""
echo -e "${YELLOW}⏳ Attente des pods...${NC}"
sleep 5

# Vérification
echo ""
echo -e "${GREEN}✅ Déploiement terminé!${NC}"
echo ""
echo "📊 État des cells:"
kubectl get cells -n ${NAMESPACE}
echo ""
echo "📊 État des pods:"
kubectl get pods -n ${NAMESPACE}
echo ""
echo "📊 Services:"
kubectl get svc -n ${NAMESPACE}

# Tester le routing
echo ""
echo -e "${BLUE}🔍 Test du routing cellulaire${NC}"
echo "Exécuter: kubectl run test --image=curlimages/curl -it --rm -n ${NAMESPACE} -- curl -H 'x-patient-id: test-123' http://appointment-cell-001:3001/health"
