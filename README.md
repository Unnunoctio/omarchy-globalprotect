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

Desconectar es `systemctl stop` de la misma unidad, y el cookie se borra ahí
mismo — y también desde un `ExecStopPost` de la unidad, para que no dependa de
que el CLI llegue a hacerlo. La regla polkit acota el permiso sin password a los
verbos start/stop/restart sobre la unidad `gpvpn@<uid>.service` **del uid que la
invoca**, para usuarios locales y activos del grupo `wheel`.

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

### Qué queda en disco

| Ruta | Qué es | Cuánto vive |
|---|---|---|
| `$XDG_STATE_HOME/gpvpn/cookies` | Sesión del proveedor de identidad (el SSO corporativo), en texto plano. Directorio `700`, archivo `600` | Hasta que expire, o la borres |
| `$XDG_RUNTIME_DIR/gpvpn/params` | Cookie del túnel —de un solo uso— y parámetros. `600`, en tmpfs | Se borra al desconectar, y también desde el `ExecStopPost` de la unidad |
| `$XDG_RUNTIME_DIR/gpvpn/last-error` | Diagnóstico del último intento, filtrado de secretos. `600`, en tmpfs | Se borra al desconectar |
| `~/.config/gpvpn/profiles.json` | Los perfiles. No guarda secretos | Permanente |

La sesión del IdP se persiste a propósito: es lo que evita reautenticar de cero en cada
conexión. `gp-saml-gui` la deja por defecto en `~/.gp-saml-gui-cookies` con el umask del
usuario, típicamente `644`; `gpvpn` la mueve **una vez** al directorio de estado y le repone
el modo `600` después de cada login, porque WebKit reescribe el archivo al cerrar la ventana.

Para no persistir nada y autenticar entero cada vez, basta borrar ese archivo.

> Sobre `shred`: el `params` vive en tmpfs, que es memoria y no expone un mapeo estable de
> bloques, así que sobrescribirlo no da la garantía que el nombre sugiere. Lo que protege es
> el `unlink` inmediato, el modo `600` y el directorio `700`.

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
| `clientos` | Qué sistema **se le reporta** al portal y al gateway. `linux-64` (default), `linux`, `win`, `mac-intel`, `android`, `apple-ios` — ver abajo |
| `interface` | Nombre de la interfaz del túnel (default `gpvpn0`). **Solo por JSON**, ver abajo |
| `extraArgs` | Argumentos extra para `openconnect`, editando el JSON a mano. Solo en forma larga (`--opcion=valor`), y sin las opciones que ejecutan comandos, leen más opciones de un archivo o exponen el cookie — ver abajo |

### `clientos` no describe tu máquina

Es el sistema que el cliente **declara**, no el que corre. Existe porque muchos
portales corporativos rechazan clientes Linux, y la salida es reportarse como
otra cosa. La propia `gp-saml-gui`, cuando el portal no devuelve las etiquetas
SAML, sugiere exactamente eso: *"Spoof an officially supported OS"*.

Por eso **no se autodetecta**: el valor de tenerlo es poder no decir la verdad.

El valor viaja en dos momentos, con vocabularios distintos, y `gpvpn` los
mantiene en sincronía a partir de un solo campo:

| Momento | Quién lo manda | Vocabulario |
|---|---|---|
| Prelogin al portal, antes del SAML | `gp-saml-gui --clientos` | `Linux`, `Mac`, `Windows` |
| Handshake del túnel, ya autenticado | `openconnect --os` | `linux-64`, `win`, `mac-intel`… |

**El que decide si te dejan entrar es el primero.** `android` y `apple-ios` no
tienen equivalente ahí —`gp-saml-gui` solo admite esos tres—, así que con ellos
el prelogin va con su valor por defecto y solo cambia lo que reporta el túnel.

### `interface` se edita a mano, a propósito

No está en el formulario del panel. Hay **un solo túnel a la vez**, igual que en
el cliente oficial, así que dos interfaces nunca compiten y renombrarla no
resuelve ningún conflicto. El único uso real es fijar reglas de firewall o
routing al nombre (`nft … oif gpvpn0`), que es algo que se hace una vez y no
desde un panel.

Si lo necesitás, va directo al JSON:

```json
{ "id": "trabajo", "server": "vpn.empresa.com", "interface": "vpn-trabajo" }
```

o por CLI: `gpvpn profile edit --id trabajo --interface vpn-trabajo`.
Una edición desde el panel **no lo toca**.

### Qué no se admite en `extraArgs`

Esos argumentos terminan en el argv de un proceso que corre como root, así que
`gpvpn-tunnel` los filtra antes de pasárselos a `openconnect`:

- **Forma corta rechazada entera.** `getopt` acepta el valor pegado (`-s/tmp/x`)
  y el agrupamiento (`-qs /tmp/x`), así que no hay forma confiable de filtrarla.
- **Opciones prohibidas**, comparadas por prefijo porque `getopt_long` resuelve
  abreviaturas no ambiguas —`--csd-wrap` llega a `--csd-wrapper` igual—:
  `--script`, `--script-tun`, `--csd-wrapper`, `--csd-user` (ejecutan comandos);
  `--config`, `--xmlconfig` (leen más opciones de un archivo, por donde se
  colaría cualquier otra); `--pid-file` (escritura arbitraria); `--cookie`,
  `--cookieonly`, `--printcookie`, `--dump-http-traffic` (exponen el cookie);
  `--interface`, `--os` (eluden la validación que el script ya hizo);
  `--background` (rompe `Type=exec`).

**No hay autodescubrimiento de gateways.** Seleccionar uno es trivial
(`--authgroup`), pero enumerarlos implica autenticar contra el portal y parsear
la lista que openconnect saca por su prompt interactivo. Eso no se escribe a
ciegas: hace falta un portal real contra el cual probarlo.

## Instalación

```bash
./install.sh                 # instala el árbol de trabajo y copia el widget
omarchy plugin enable unnunoctio.globalprotect right
gpvpn profile add --id trabajo --server vpn.empresa.com
```

| Modo | Qué hace |
|---|---|
| `./install.sh` | Instala los archivos del árbol actual vía `pkexec`. Es el modo de iteración |
| `./install.sh --plugin` | Solo re-copia el widget |
| `./install.sh --package` | `makepkg` + `pacman -U`: construye el paquete del **tag publicado** |

El `PKGBUILD` toma la fuente de un tag de git, que es lo que hace falta para que
el paquete sea reproducible. Por eso `--package` construye la versión publicada
y no lo que tengas editado — y por eso el modo por defecto instala directo.

> Instalar directo deja los archivos divergiendo del paquete de pacman, cosa que
> `pacman -Qkk gpvpn` reporta. Se normaliza con `./install.sh --package` una vez
> que el tag existe.

Instalando el widget solo por git (`omarchy plugin add`), el backend hay que
ponerlo aparte, porque ese comando copia únicamente el QML:

```bash
gpvpn setup      # instala unidad systemd y regla polkit vía pkexec
```

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
- El `+` del encabezado da de alta un perfil, y el lápiz de cada fila lo abre en
  modo edición con los campos cargados. El formulario cubre nombre, servidor,
  modo, gateway (solo en modo portal) y sistema; `interface` y `extraArgs` van
  por JSON. Enter salta al campo siguiente y guarda en el último; `esc` cierra.
- Cada fila permite además marcarla por defecto y borrarla, con confirmación. El
  perfil conectado no ofrece borrado: hay que bajarlo primero.
- Conectada, el panel muestra gateway, interfaz, IP y hace cuánto está arriba.
  Desconectada no muestra nada entre el encabezado y la lista.
- El escudo de la barra va relleno con la VPN arriba, en contorno tenue abajo, y
  late mientras negocia.
- Atajos: `j`/`k` o flechas para moverte, `enter` para activar, `n` nuevo
  perfil, `e` editar, `d` marcar por defecto, `x` borrar, `t`
  conectar/desconectar, `r` refrescar, `g` logs, `esc` cerrar.
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
