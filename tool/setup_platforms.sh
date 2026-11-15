#!/usr/bin/env bash
# Gera as pastas android/ e ios/ e aplica permissões. Rode uma vez após clonar.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --platforms=android,ios --org app.loomisflow --project-name loomisflow_studio .
rm -f test/widget_test.dart   # teste de exemplo gerado pelo flutter create
python3 tool/patch_platforms.py
flutter pub get

echo
echo "Pronto. Rode em um aparelho REAL (o ML Kit não roda em simulador iOS arm64):"
echo "  flutter run --release"
