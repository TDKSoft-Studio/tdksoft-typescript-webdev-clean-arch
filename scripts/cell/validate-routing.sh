#!/bin/bash
# Validation script for cell-based routing

NAMESPACE="appointment-system"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Cell Routing Validation${NC}"
echo "============================="

# 1. Vérifier que tous les pods sont Running
echo ""
echo "1. Pod status:"
RUNNING=$(kubectl get pods -n $NAMESPACE -l app=appointment-service \
  --field-selector=status.phase=Running -o name | wc -l)
echo "   $RUNNING/3 pods running"

# 2. Tester chaque cellule
echo ""
echo "2. Health endpoints:"
for cell in cell-001 cell-002 cell-003; do
    RESPONSE=$(kubectl run test-${cell} --image=curlimages/curl -it --rm --restart=Never \
      -n $NAMESPACE -- curl -s http://appointment-${cell}:3001/health 2>/dev/null | grep -o '"status":"[^"]*"' | head -1)
    echo "   $cell: ${RESPONSE:-'error'}"
done

# 3. Test de création de rendez-vous
echo ""
echo "3. Appointment creation test:"
RESPONSE=$(kubectl run create-test --image=curlimages/curl -it --rm --restart=Never \
  -n $NAMESPACE -- curl -s -X POST http://appointment-cell-001:3001/appointments \
  -H 'Content-Type: application/json' \
  -d '{"patientId":"test-001","doctorId":"dr-smith","dateTime":"2024-01-15T10:00:00Z"}' 2>/dev/null)
  
if echo "$RESPONSE" | grep -q "id"; then
    echo -e "${GREEN}   ✅ Appointment created successfully${NC}"
else
    echo "   ❌ Failed to create appointment"
fi

echo ""
echo -e "${GREEN}✅ Validation complete${NC}"
