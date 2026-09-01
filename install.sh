#!/usr/bin/env bash
# Instala el paquete (CLI + unidad systemd + regla polkit) y copia el widget al
# directorio de plugins del shell de Omarchy.
#
#   ./install.sh            construye e instala todo
#   ./install.sh --plugin   solo re-copia el widget (iteracion rapida)

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

PLUGIN_ID="unnunoctio.globalprotect"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"

install_plugin() {
  # El validador de Omarchy rechaza symlinks dentro de un plugin, asi que se
  # copia; esta es la unica direccion valida, plugin/ manda.
  mkdir -p "$PLUGIN_DIR"
  rsync -a --delete plugin/ "$PLUGIN_DIR/"
  omarchy plugin validate "$PLUGIN_DIR"
  echo "Widget copiado a $PLUGIN_DIR"
}

if [[ ${1-} == --plugin ]]; then
  install_plugin
  exit 0
fi

makepkg -f
pkg=(gpvpn-*.pkg.tar.zst)
sudo pacman -U --noconfirm "${pkg[-1]}"
install_plugin
echo
echo "Listo. Agrega el widget con: omarchy plugin enable $PLUGIN_ID right"
