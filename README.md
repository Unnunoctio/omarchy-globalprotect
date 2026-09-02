# GlobalProtect VPN para la barra de Omarchy

Indicador para la barra: conectar, desconectar y cambiar de perfil de una VPN
GlobalProtect sin abrir una terminal, con estado en vivo y aviso cuando el túnel
se cae.

## Requiere el backend

Este repo es **solo el widget**. Todo el trabajo real —el login SAML, el túnel,
la unidad systemd, la regla polkit— lo hace el CLI `gpvpn`, que vive aparte:

**[Unnunoctio/gpvpn](https://github.com/Unnunoctio/gpvpn)**, versión mínima `1.2.0`.

El widget no implementa nada de VPN, ni toca systemd, ni lee archivos del
backend. Habla con el CLI **por proceso**: `gpvpn status --json` para el estado,
y los subcomandos para actuar. El esquema de ese JSON está documentado en el
README del backend, y es el contrato entre los dos.

Si `gpvpn` falta o es anterior a la versión mínima, el panel lo dice en vez de
fallar de formas raras.

## Instalación

```bash
./install.sh
omarchy plugin enable unnunoctio.globalprotect right
```

`install.sh` copia el QML y avisa si el backend falta o está desactualizado.
También se puede instalar solo por git, que copia únicamente el QML:

```bash
omarchy plugin add https://github.com/Unnunoctio/omarchy-globalprotect
```

> El shell recarga el QML al guardar, pero **no reinstancia** los widgets ya
> montados en la barra: para ver cambios de estructura hace falta
> `omarchy restart shell`.

## Qué hace

- Click izquierdo abre el panel, click derecho conecta/desconecta, click del
  medio refresca. El tooltip del escudo muestra perfil, IP y hace cuánto está
  arriba, sin abrir nada.
- Cada perfil tiene su propio switch: encenderlo sobre el perfil activo baja el
  túnel, encenderlo sobre otro cambia de perfil. El punto lleno marca el activo.
  El switch se enciende apenas se pide la conexión, no recién cuando el túnel
  está arriba.
- El `+` del encabezado da de alta un perfil, y el lápiz de cada fila lo abre en
  modo edición con los campos cargados. El formulario cubre nombre, servidor,
  modo, gateway (solo en modo portal) y sistema.
- Cada fila permite además marcarla por defecto y borrarla, con confirmación. El
  perfil conectado no ofrece borrado: hay que bajarlo primero.
- Conectada, el panel muestra servidor —o portal y gateway—, interfaz, IP y hace
  cuánto está arriba.
- El escudo de la barra va relleno con la VPN arriba, en contorno tenue abajo, y
  late mientras negocia.
- Atajos: `j`/`k` o flechas para moverte, `enter` para activar, `n` nuevo
  perfil, `e` editar, `d` marcar por defecto, `x` borrar, `t`
  conectar/desconectar, `r` refrescar, `g` logs, `esc` cerrar.
  (`h`/`j`/`k`/`l` los consume el navegador de teclado del panel como flechas,
  por eso los logs están en `g`.)
- Avisa al conectar, al fallar, y cuando el túnel se cae solo. Una desconexión
  pedida por vos, o un cambio de perfil, no generan aviso. Una negociación lenta
  tampoco: el backend la reporta como "en curso", no como fallo.
- Opciones en `shell.json`: `refreshIntervalSec` (default 15) y
  `notifyOnDisconnect`.

## Qué NO hace el widget

Estas cosas viven en el backend, a propósito:

| | Dónde |
|---|---|
| `interface` y `extraArgs` de un perfil | `~/.config/gpvpn/profiles.json` o `gpvpn profile edit` |
| Instalar la unidad systemd y la regla polkit | `gpvpn setup`, o el paquete |
| Cualquier cosa que necesite root | La unidad `gpvpn@<uid>`, vía polkit |

El formulario del panel cubre lo que se cambia seguido; el resto es un campo de
escape que no merece ocupar una fila.

## Componentes

| Archivo | Qué hace |
|---|---|
| `plugin/Panel.qml` | El widget de barra y el panel: filas, formulario, diálogos, teclado |
| `plugin/Service.qml` | Estado y acciones: poletea el CLI, decide cuándo notificar |
| `plugin/ShieldIcon.qml` | El escudo, dibujado como `Shape` (los SVG chicos rinden mal en la barra) |
| `plugin/manifest.json` | Metadata del plugin y la dependencia declarada del backend |

## Requisitos

Omarchy con su shell Quickshell, y [`gpvpn`](https://github.com/Unnunoctio/gpvpn)
`>= 1.2.0`.

Opcionales: `libnotify` para los avisos de escritorio, `foot` para el atajo de
logs. Los usa el widget, no el backend.
