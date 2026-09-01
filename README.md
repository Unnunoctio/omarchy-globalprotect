# GlobalProtect VPN para Omarchy

Cliente GlobalProtect que vive en la barra de Omarchy: conectar, desconectar y
cambiar de perfil sin abrir una terminal, con estado en vivo y aviso cuando el
túnel se cae.

Son tres piezas: un CLI (`gpvpn`), una unidad systemd que corre el túnel, y un
widget Quickshell para la barra.

## Por qué no usa gpclient

`globalprotect-openconnect` (el `gpclient` de yuezk, en el repo `extra`) ya es un
cliente GP completo, pero no sirve de base para un widget: no expone el estado
de forma consultable, y arrastra GUI GTK3, tray propio y su propio daemon. Un
indicador de barra necesita exactamente lo que no da, un `status` barato que se
pueda pollear.

## Cómo funciona

El login SAML y el túnel están separados, y esa es toda la idea:

```
gpvpn connect [perfil]
  │
  ├─ gp-saml-gui -g|-p <servidor>                  (como el usuario, ventana GTK)
  │     └─ imprime HOST / USER / COOKIE / OS en stdout
  │
  ├─ escribe $XDG_RUNTIME_DIR/gpvpn/params         (0600, tmpfs)
  │
  └─ systemctl start gpvpn@$(id -u)                (sin password, regla polkit)
        └─ /usr/lib/gpvpn/gpvpn-tunnel             (root)
              └─ exec openconnect --protocol=gp …
```

`gp-saml-gui` sin flag de exec **imprime** el cookie en vez de lanzar
`openconnect` él mismo. Eso es lo que permite que el túnel viva en una unidad
systemd propia en vez de colgar de una terminal, y por lo tanto que conectar y
desconectar sean dos acciones independientes.

Desconectar es `systemctl stop` de la misma unidad, y el cookie se borra con
`shred`. La regla polkit acota el permiso sin password a las unidades
`gpvpn@<uid>.service` y a los verbos start/stop/restart, para usuarios locales
del grupo `wheel`.

Un solo túnel a la vez, igual que el cliente oficial: cambiar de perfil baja el
actual y levanta el nuevo. Antes de conectar, `gpvpn` se niega si detecta otro
`openconnect` ajeno corriendo, que se pelearía con éste por la tabla de rutas.

### Estados

La unidad se pone `active` apenas arranca `openconnect`, que todavía tarda unos
segundos en negociar. Por eso el estado real se deduce de la interfaz:

| Unidad | Interfaz | Estado |
|---|---|---|
| — | — | `authenticating` (mientras existe el marker del login) |
| active | sin IP | `connecting` |
| active | con IP | `connected` |
| failed | — | `failed` |
| inactive | — | `disconnected` |

## Perfiles

Viven en `~/.config/gpvpn/profiles.json`. El alta corriente se hace desde el
panel — el botón `+` del encabezado abre un formulario con Nombre, Servidor y
Modo, y deriva el id del nombre (`Trabajo` → `trabajo`). Para todo lo demás
—borrar, cambiar el default, los campos que el formulario no pide— está el CLI:

```bash
gpvpn profile add --id trabajo --name "Trabajo" --server vpn.empresa.com
gpvpn profile add --id acme --name "ACME" --server portal.acme.com \
                  --mode portal --gateway "Santiago"
gpvpn profile default trabajo
gpvpn profile rm acme
gpvpn list
```

| Campo | Qué es |
|---|---|
| `mode` | `gateway` (default) autentica directo contra el gateway; `portal` contra el portal |
| `gateway` | Con `mode: portal`, qué gateway elegir. Es `--authgroup` de openconnect: el mismo desplegable del cliente oficial |
| `clientos` | `linux-64` (default), `linux`, `win`, `mac-intel`, `android`, `apple-ios` |
| `interface` | Nombre de la interfaz del túnel (default `gpvpn0`) |
| `extraArgs` | Argumentos extra para `openconnect`, editando el JSON a mano |

**No hay autodescubrimiento de gateways.** Seleccionar uno es trivial
(`--authgroup`), pero enumerarlos implica autenticar contra el portal y parsear
la lista que openconnect saca por su prompt interactivo. Eso no se escribe a
ciegas: hace falta un portal real contra el cual probarlo.

## Instalación

```bash
./install.sh                 # construye, instala el paquete y copia el widget
omarchy plugin enable unnunoctio.globalprotect right
gpvpn profile add --id trabajo --server vpn.empresa.com
```

Instalando el widget solo por git (`omarchy plugin add`), el backend hay que
ponerlo aparte, porque ese comando copia únicamente el QML:

```bash
gpvpn setup      # instala unidad systemd y regla polkit vía pkexec
```

Para iterar sobre el widget: `./install.sh --plugin`.

> El shell recarga el QML al guardar, pero **no reinstancia** los widgets ya
> montados en la barra: para ver cambios de estructura hace falta
> `omarchy restart shell`.

## El widget

- Click izquierdo abre el panel, click derecho conecta/desconecta, click del
  medio refresca.
- Cada perfil tiene su propio switch: encenderlo sobre el perfil activo baja el
  túnel, encenderlo sobre otro cambia de perfil. El punto lleno marca el activo.
  El switch se enciende apenas se pide la conexión, no recién cuando el túnel
  está arriba.
- El `+` del encabezado da de alta un perfil sin salir del panel. Enter salta al
  campo siguiente y guarda en el último; `esc` cierra el formulario.
- Conectada, el panel muestra gateway, interfaz, IP y hace cuánto está arriba.
  Desconectada no muestra nada entre el encabezado y la lista.
- El escudo de la barra va relleno con la VPN arriba, en contorno tenue abajo, y
  late mientras negocia.
- Atajos: `j`/`k` o flechas para moverte, `enter` para activar, `n` nuevo
  perfil, `t` conectar/desconectar, `r` refrescar, `g` logs, `esc` cerrar.
  (`h`/`j`/`k`/`l` los consume el navegador de teclado del panel como flechas,
  por eso los logs están en `g`.)
- Avisa al conectar, al fallar, y cuando el túnel se cae solo. Una desconexión
  pedida por vos, o un cambio de perfil, no generan aviso.
- Opciones en `shell.json`: `refreshIntervalSec` (default 15) y
  `notifyOnDisconnect`.

## Componentes

| Archivo | Destino | Qué hace |
|---|---|---|
| `bin/gpvpn` | `/usr/bin/` | CLI: connect, disconnect, toggle, status, list, profile, logs, setup |
| `libexec/gpvpn-tunnel` | `/usr/lib/gpvpn/` | Corre `openconnect` como root; valida dueño y permisos del cookie |
| `systemd/gpvpn@.service` | `/usr/lib/systemd/system/` | Unidad por uid, `Type=exec`, `KillSignal=SIGINT` |
| `polkit/48-gpvpn.rules` | `/usr/share/polkit-1/rules.d/` | start/stop sin password, acotado a esta unidad |
| `plugin/` | `~/.config/omarchy/plugins/unnunoctio.globalprotect/` | Widget de la barra |

## Requisitos

`gp-saml-gui`, `openconnect`, `vpnc` (por `/etc/vpnc/vpnc-script`), `jq`,
`polkit`, `systemd`. Opcionales: `libnotify` para los avisos, `foot` para el
atajo de logs.
