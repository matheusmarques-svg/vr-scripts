#!/bin/bash

echo "Script AlwaysOn iniciado"

echo "Instalando dependências..."

sudo apt install -y \
libxcb-icccm4 \
libxcb-image0 \
libxcb-keysyms1 \
libxcb-render-util0 \
libxcb-xinerama0 \
libxcb-xkb1 \
libxkbcommon-x11-0

echo "Dependências instaladas com sucesso"
