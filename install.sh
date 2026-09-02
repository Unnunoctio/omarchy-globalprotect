#!/usr/bin/env bash
# Copia el widget al directorio de plugins del shell de Omarchy.
#
#   ./install.sh
#
# El backend es un paquete aparte: https://github.com/Unnunoctio/gpvpn
# Este widget no lo instala ni lo administra; solo lo invoca.

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

PLUGIN_ID="unnunoctio.globalprotect"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
MIN_CLI="1.2.0"

# --plugin queda aceptado por costumbre: antes distinguia el widget del backend,
# y ahora este repo es solo el widget.
case "${1-}" in
  "" | --plugin) ;;
  *) echo "uso: $0 [--plugin]" >&2; exit 2 ;;
esac

# El validador de Omarchy rechaza symlinks dentro de un plugin, asi que se
# copia; esta es la unica direccion valida, plugin/ manda.
mkdir -p "$PLUGIN_DIR"
rsync -a --delete plugin/ "$PLUGIN_DIR/"
omarchy plugin validate "$PLUGIN_DIR"
echo "Widget copiado a $PLUGIN_DIR"
echo

if ! command -v gpvpn >/dev/null; then
  echo "Falta el backend: instalalo desde https://github.com/Unnunoctio/gpvpn"
elif ! version="$(gpvpn --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')" || [[ -z $version ]]; then
  # gpvpn --version existe desde 1.2.0: si no imprime una version, es anterior.
  echo "El backend es anterior a $MIN_CLI; actualizalo o el panel va a fallar en cosas puntuales"
else
  echo "Backend: gpvpn $version (se necesita >= $MIN_CLI)"
fi
echo "Agrega el widget con: omarchy plugin enable $PLUGIN_ID right"
