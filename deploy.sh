#!/bin/bash
set -e

echo "Pointing at live project..."
firebase use review-system-prod-49b7a

echo "Injecting Firebase config into review page..."
node scripts/inject-firebase-config.js

echo "Building Flutter panels..."
cd admin_panel && flutter build web --release && cd ..

echo "Assembling public/ ..."
rm -rf public && mkdir -p public/r
cp -R admin_panel/build/web/* public/
cp -R review_page/* public/r/

echo "Deploying to Firebase..."
firebase deploy

echo "Done. Check https://appnexa.co.in"
