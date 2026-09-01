# Maintainer: unnunoctio <unnunoctio.dev@gmail.com>
pkgname=gpvpn
pkgver=1.0.0
pkgrel=1
pkgdesc="Cliente GlobalProtect para Omarchy: CLI, unidad systemd y widget de barra"
arch=('any')
url="https://github.com/unnunoctio/omarchy-globalprotect"
license=('MIT')
depends=('gp-saml-gui-git' 'openconnect' 'vpnc' 'polkit' 'systemd' 'bash' 'iproute2' 'jq')
optdepends=(
  'libnotify: avisos de escritorio cuando el tunel se cae'
  'foot: atajo de logs desde el widget'
)
install="${pkgname}.install"
# Los fuentes viven en subdirectorios y makepkg solo acepta fuentes locales
# planas, asi que se instalan directo desde el arbol del proyecto.
source=()
sha256sums=()

package() {
  install -Dm755 "${startdir}/bin/gpvpn" "${pkgdir}/usr/bin/gpvpn"
  install -Dm755 "${startdir}/libexec/gpvpn-tunnel" "${pkgdir}/usr/lib/gpvpn/gpvpn-tunnel"
  install -Dm644 "${startdir}/systemd/gpvpn@.service" "${pkgdir}/usr/lib/systemd/system/gpvpn@.service"
  install -Dm644 "${startdir}/polkit/48-gpvpn.rules" "${pkgdir}/usr/share/polkit-1/rules.d/48-gpvpn.rules"
  install -Dm644 "${startdir}/desktop/gpvpn.desktop" "${pkgdir}/usr/share/applications/gpvpn.desktop"
  install -Dm644 "${startdir}/icons/gpvpn.svg" "${pkgdir}/usr/share/icons/hicolor/scalable/apps/gpvpn.svg"
  install -Dm644 "${startdir}/LICENSE" "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
