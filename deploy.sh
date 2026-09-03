#!/bin/bash
set -e

echo "Pointing at live project..."
firebase use review-system-prod-49b7a

echo "Injecting Firebase config into review page & landing page..."
node scripts/inject-firebase-config.js

echo "Building Flutter panels (base-href /app/)..."
cd admin_panel && flutter build web --release --base-href /app/ && cd ..

echo "Assembling public/ ..."
rm -rf public && mkdir -p public/r public/app
cp -R landing_page/* public/
cp -R admin_panel/build/web/* public/app/
cp -R review_page/* public/r/

echo "Deploying to Firebase..."
firebase deploy

echo "Done. Check https://appnexa.co.in"

