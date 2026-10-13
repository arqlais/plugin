#!/bin/sh
# Gera o .rbz e atualiza updates/ (arquivo lido pela atualização automática).
# Uso: sh dev/build.sh "nota 1" "nota 2" ...
set -e
cd "$(dirname "$0")/.."
VERSION=$(sed -n "s/.*VERSION *= *'\([^']*\)'.*/\1/p" plane_plugin.rb)
mkdir -p dist updates
OUT="dist/plane_plugin_v$VERSION.rbz"
rm -f "$OUT"
zip -qr -X "$OUT" plane_plugin.rb plane_plugin -x '*.DS_Store'
cp "$OUT" updates/plane_plugin.rbz
SHA=$(sha256sum updates/plane_plugin.rbz | cut -d' ' -f1)
NOTES=""
for n in "$@"; do NOTES="$NOTES$(printf '%s' "$n" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed 's/.*/"&"/'),"; done
NOTES="[${NOTES%,}]"
cat > updates/latest.json <<JSON
{
  "version": "$VERSION",
  "url": "https://raw.githubusercontent.com/arqlais/plugin/HEAD/updates/plane_plugin.rbz",
  "sha256": "$SHA",
  "notes": $NOTES
}
JSON
echo "Pronto: $OUT (sha256 $SHA)"
