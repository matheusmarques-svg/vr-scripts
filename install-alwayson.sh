#!/bin/bash

LINK="$1"

echo "Script AlwaysOn iniciado"
echo ""

echo "Instalando dependências..."

sudo apt install -y libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0

echo ""
echo "Baixando instalador AlwaysOn..."

wget -O alwayson.tar.gz https://www.islonline.net/download/ISLAlwaysOn_linux.tar.gz

tar -xzf alwayson.tar.gz

DIR=$(find . -type d -name "ISLAlwaysOn*" | head -n1)

cd "$DIR"

echo ""
echo "Executando instalação..."

sudo ./ISLAlwaysOn install "$LINK"

echo ""
echo "Instalação finalizada"
