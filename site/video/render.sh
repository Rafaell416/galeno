#!/bin/bash
# Renderiza los cuatro videos y sus pósters. Uso: ./render.sh   (desde site/video; Node 22)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
for id in Hero-es Hero-en WhatsApp-es WhatsApp-en; do
  lower=$(echo "$id" | tr 'A-Z' 'a-z')
  npx remotion render src/index.ts "$id" "out/$lower.mp4"
done
# Pósters: un cuadro de cada video (el 200 del hero ya tiene las herramientas marcadas; el 200 de WhatsApp, las tres tarjetas).
for lang in es en; do
  npx remotion still src/index.ts "Hero-$lang" "out/poster-$lang.jpg" --frame=200 --image-format=jpeg --jpeg-quality=88
  npx remotion still src/index.ts "WhatsApp-$lang" "out/poster-flow-$lang.jpg" --frame=200 --image-format=jpeg --jpeg-quality=88
done
echo "Listo: site/video/out/"
