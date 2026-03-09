#!/bin/bash

echo "Script AlwaysOn iniciado"
echo ""

echo "Instalando dependências..."

sudo apt install -y libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0

echo ""
echo "Dependências instaladas com sucesso"
echo ""

# pedir link do AlwaysOn
read -p "Cole o link do AlwaysOn: " LINK

echo ""
echo "Baixando AlwaysOn..."

wget -O ISLAlwaysOn.sh "$LINK"

if [ ! -f ISLAlwaysOn.sh ]; then
    echo "Erro ao baixar o instalador."
    exit 1
fi

chmod +x ISLAlwaysOn.sh

echo ""
echo "Executando instalador..."

./ISLAlwaysOn.sh

echo ""
echo "Processo finalizado."
