#!/usr/bin/env bash
# scripts/build-web.sh
# One-command web build & assembly script for production & emulator web hosting.

set -e

# Monorepo root directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==========================================================="
echo "🔨 BUILDING & ASSEMBLING WEB DISTRIBUTION (build-web.sh)"
echo "==========================================================="

# Parse emulator flag
EMULATOR_DEFINE=""
if [[ "$*" == *"--use-emulator"* ]] || [[ "$USE_EMULATOR" == "true" ]]; then
  EMULATOR_DEFINE="--dart-define=USE_EMULATOR=true"
  echo "⚡ Build Target: EMULATOR CONNECTED ($EMULATOR_DEFINE)"
else
  echo "🌐 Build Target: PRODUCTION LIVE FIREBASE"
fi

# 1. Inject Firebase Config for Customer Review Page
echo "\n1️⃣ Injecting Firebase Config for Customer Review Page..."
node scripts/inject-firebase-config.js

# 2. Build Flutter Web Release in admin_panel/
echo "\n2️⃣ Compiling Flutter Web Application (admin_panel)..."
cd "$REPO_ROOT/admin_panel"
flutter build web --release $EMULATOR_DEFINE
cd "$REPO_ROOT"

# 3. Cleanly assemble public/ directory
echo "\n3️⃣ Assembling public/ directory structure..."
rm -rf public
mkdir -p public/r

# Copy Flutter Web release build output to public/ root
cp -R admin_panel/build/web/* public/

# Copy customer review page files to public/r/
cp -R review_page/* public/r/

# 4. Strict Validation Checks
echo "\n4️⃣ Verifying public/ assembly integrity..."

# Verification A: public/index.html must be the real Flutter app
if [ ! -f "public/index.html" ]; then
  echo "❌ Assembly Error: public/index.html does not exist!"
  exit 1
fi

if ! grep -q "flutter_bootstrap.js" public/index.html && ! grep -q "flutter.js" public/index.html && ! grep -q "main.dart.js" public/index.html; then
  echo "❌ Assembly Error: public/index.html is NOT the Flutter application!"
  exit 1
fi

# Verification B: public/r/index.html must exist
if [ ! -f "public/r/index.html" ]; then
  echo "❌ Assembly Error: public/r/index.html missing!"
  exit 1
fi

# Verification C: No double-nesting (public/r/r/ must NOT exist)
if [ -d "public/r/r" ]; then
  echo "❌ Assembly Error: Double-nested directory public/r/r detected!"
  exit 1
fi

echo "\n==========================================================="
echo "✅ WEB BUILD ASSEMBLY COMPLETE & VERIFIED!"
echo "   - Flutter App Root: public/index.html"
echo "   - Customer Review Page: public/r/index.html"
echo "===========================================================\n"
