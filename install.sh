#!/usr/bin/env bash
# Instala gpvpn desde el arbol de trabajo y copia el widget al directorio de
# plugins del shell de Omarchy.
#
#   ./install.sh             instala el arbol actual  (iteracion de desarrollo)
#   ./install.sh --plugin    solo re-copia el widget
#   ./install.sh --package   construye el paquete del tag publicado (makepkg)
#
# El PKGBUILD toma la fuente del tag de git, que es lo que hace falta para que
# el paquete sea reproducible y publicable. Por eso `makepkg` construye la
# version PUBLICADA y no lo que tengas editado: para probar tus cambios va el
# modo por defecto, que instala los archivos directamente.
#
# Ojo: instalar directo deja los archivos divergiendo del paquete de pacman
# (`pacman -Qkk gpvpn` lo va a reportar). Se normaliza reinstalando el paquete
# una vez publicado el tag.

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

install_tree() {
  pkexec bash -c '
    set -e
    install -Dm755 "$1" /usr/bin/gpvpn
    install -Dm755 "$2" /usr/lib/gpvpn/gpvpn-tunnel
    install -Dm644 "$3" /usr/lib/systemd/system/gpvpn@.service
    install -Dm644 "$4" /usr/share/polkit-1/rules.d/48-gpvpn.rules
    install -Dm644 "$5" /usr/share/applications/gpvpn.desktop
    install -Dm644 "$6" /usr/share/icons/hicolor/scalable/apps/gpvpn.svg
    systemctl daemon-reload
  ' _ "$PWD/bin/gpvpn" "$PWD/libexec/gpvpn-tunnel" "$PWD/systemd/gpvpn@.service" \
      "$PWD/polkit/48-gpvpn.rules" "$PWD/desktop/gpvpn.desktop" "$PWD/icons/gpvpn.svg"
  echo "Backend instalado desde el arbol de trabajo"
}

case "${1-}" in
  --plugin)  install_plugin; exit 0 ;;
  --package)
    makepkg -f
    pkg=(gpvpn-*.pkg.tar.zst)
    sudo pacman -U --noconfirm "${pkg[-1]}"
    install_plugin
    exit 0 ;;
  "") ;;
  *) echo "uso: $0 [--plugin|--package]" >&2; exit 2 ;;
esac

install_tree
install_plugin
echo
echo "Listo. Agrega el widget con: omarchy plugin enable $PLUGIN_ID right"
