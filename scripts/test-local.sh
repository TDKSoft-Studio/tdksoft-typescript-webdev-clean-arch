#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# On remonte d'un cran pour être sûr d'être dans le dossier du service
# (Si tu lances le script depuis le dossier /scripts)
cd ../apps/appointment-svc/

echo -e "${GREEN}🔍 Nettoyage et Validation du package.json...${NC}"

# Nettoyage automatique des caractères invisibles
sed -i 's/\r//g' package.json # Enlève les retours Windows
# Recréation propre via Node pour être certain du format
node -e "const fs = require('fs'); const p = JSON.parse(fs.readFileSync('package.json', 'utf8')); fs.writeFileSync('package.json', JSON.stringify(p, null, 2));"

# 1. Validation JSON
node -e "JSON.parse(require('fs').readFileSync('package.json', 'utf8'))" && echo "✅ JSON syntax is OK" || { echo "❌ JSON still invalid"; exit 1; }

# 2. Vérification des scripts visibles par NPM
echo -e "\n📦 Scripts détectés par NPM :"
npm run | grep "type-check" || { echo -e "${RED}❌ NPM ne voit pas le script type-check. Problème d'encodage.${NC}"; exit 1; }

# 3. Execution
echo -e "\n🚀 Running type-check..."
npm run type-check
