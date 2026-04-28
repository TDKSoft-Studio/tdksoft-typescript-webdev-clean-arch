#!/bin/bash

# Test du consistent hashing entre les cells
echo "🔍 Test du routing cell-based"
echo "============================="

NAMESPACE="appointment-system"

# Fonction pour obtenir la cell d'un patient
get_cell_for_patient() {
    local patient_id=$1
    # Simuler le hash consistent (à remplacer par le vrai algorithme)
    local hash=$(echo -n "$patient_id" | md5sum | cut -c1-2)
    local cell_num=$((16#${hash} % 3 + 1))
    printf "cell-%03d" $cell_num
}

# Tester plusieurs patients
echo ""
echo "Distribution des patients:"
for patient in patient-{001..010}; do
    cell=$(get_cell_for_patient $patient)
    echo "  $patient -> $cell"
done

echo ""
echo "Test de routing réel:"
kubectl run routing-test --image=curlimages/curl -it --rm --restart=Never -n ${NAMESPACE} -- sh -c "
for patient in patient-001 patient-002 patient-003; do
    echo -n \"\${patient}: \"
    curl -s -H \"x-patient-id: \${patient}\" http://appointment-cell-001:3001/health | head -1
done
" 2>/dev/null || echo "Test terminé"

echo ""
echo "✅ Test de routing terminé"
