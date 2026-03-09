#!/bin/bash

LINK="$1"

echo "Script AlwaysOn iniciado"
echo ""

echo "Instalando dependências..."

sudo apt install -y libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0

echo ""
echo "Dependências instaladas com sucesso"
echo ""

if [ -z "$LINK" ]; then
    echo "Erro: você precisa informar o link do AlwaysOn."
    echo "Exemplo:"
    echo "bash install-alwayson.sh LINK_DO_ALWAYSON"
    exit 1
fi

echo ""
echo "Baixando AlwaysOn..."

wget --show-progress -O ISLAlwaysOn.sh "$LINK"

chmod +x ISLAlwaysOn.sh

echo ""
echo "Executando instalador..."

./ISLAlwaysOn.sh

echo ""
echo "Processo finalizado."
