# Maintainer: unnunoctio <unnunoctio.dev@gmail.com>
pkgname=gpvpn
pkgver=1.1.0
pkgrel=1
pkgdesc="Cliente GlobalProtect para Omarchy: CLI, unidad systemd y widget de barra"
arch=('any')
url="https://github.com/Unnunoctio/omarchy-globalprotect"
license=('MIT')
depends=('gp-saml-gui-git' 'openconnect' 'vpnc' 'polkit' 'systemd' 'bash' 'iproute2' 'jq')
makedepends=('git')
optdepends=(
  'libnotify: avisos de escritorio cuando el tunel se cae'
  'foot: atajo de logs desde el widget'
)
install="${pkgname}.install"

# Fuente por tag de git. La version anterior usaba ${startdir} con source=()
# vacio, que solo construye desde adentro del arbol del proyecto: makepkg no
# descargaba nada y el paquete no era reproducible ni publicable en AUR.
#
# La contra es que `makepkg` construye la version PUBLICADA, no lo que tengas
# editado. Para instalar el arbol de trabajo, usa ./install.sh
_repo=omarchy-globalprotect
source=("${_repo}::git+${url}.git#tag=v${pkgver}")
sha256sums=('SKIP')

package() {
  cd "${srcdir}/${_repo}"
  install -Dm755 bin/gpvpn                "${pkgdir}/usr/bin/gpvpn"
  install -Dm755 libexec/gpvpn-tunnel     "${pkgdir}/usr/lib/gpvpn/gpvpn-tunnel"
  install -Dm644 systemd/gpvpn@.service   "${pkgdir}/usr/lib/systemd/system/gpvpn@.service"
  install -Dm644 polkit/48-gpvpn.rules    "${pkgdir}/usr/share/polkit-1/rules.d/48-gpvpn.rules"
  install -Dm644 desktop/gpvpn.desktop    "${pkgdir}/usr/share/applications/gpvpn.desktop"
  install -Dm644 icons/gpvpn.svg          "${pkgdir}/usr/share/icons/hicolor/scalable/apps/gpvpn.svg"
  install -Dm644 LICENSE                  "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
