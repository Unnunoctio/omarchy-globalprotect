import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "unnunoctio.globalprotect"
  ipcTarget: "unnunoctio.globalprotect"
  manageIpc: false

  property bool cursorActive: false
  property string focusSection: "header"
  property int profileIndex: 0
  property bool addingProfile: false
  property bool errorExpanded: false
  // Fuente de verdad del dialogo de borrado: vacio = cerrado.
  property string pendingRemovalId: ""
  property string pendingRemovalName: ""
  // Vacio = el formulario da de alta; con un id = edita ese perfil.
  property string editingId: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: vpn.state === "failed" ? urgent : (vpn.active ? foreground : dim)
  readonly property color barIconColor: vpn.state === "failed" ? (bar ? bar.urgent : Color.urgent)
                                                               : (vpn.active ? barForeground : Qt.darker(barForeground, 1.55))
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && vpn.installed

  function toggleVpn() {
    if (vpn.installed && vpn.hasProfiles) vpn.toggle()
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
  }

  function setProfileCursor(index) {
    cursorActive = true
    focusSection = "profiles"
    profileIndex = index
  }

  function selectedProfile() {
    if (vpn.profiles.length === 0) return null
    return vpn.profiles[Math.max(0, Math.min(profileIndex, vpn.profiles.length - 1))]
  }

  // Cada fila enciende o apaga su propio perfil: sobre el que ya esta arriba
  // desconecta, sobre otro cambia (el CLI baja y vuelve a subir el tunel).
  function toggleProfile(p) {
    if (!p) return
    if (p.id === vpn.activeProfileId) vpn.disconnect()
    else vpn.connect(p.id)
  }

  // `gpvpn profile rm` no desconecta, asi que borrar el perfil activo dejaria el
  // tunel arriba apuntando a una config que ya no existe. Hay que bajarlo antes.
  function canRemove(p) {
    return !!p && p.id !== vpn.activeProfileId && !vpn.removing
  }

  function askRemoveProfile(p) {
    if (!canRemove(p)) return
    pendingRemovalName = String(p.name || p.id)
    pendingRemovalId = String(p.id)
    // Arranca sobre Cancelar: la accion es destructiva y no tiene deshacer.
    removeConfirm.selectedIndex = 0
  }

  function cancelRemoval() {
    pendingRemovalId = ""
    pendingRemovalName = ""
  }

  function confirmRemoval() {
    var id = pendingRemovalId
    cancelRemoval()
    vpn.removeProfile(id)
  }

  function fillForm(p) {
    nameField.text = p ? String(p.name || p.id || "") : ""
    serverField.text = p ? String(p.server || "") : ""
    modeGroup.value = p ? String(p.mode || "gateway") : "gateway"
    gatewayField.text = p ? String(p.gateway || "") : ""
    ifaceField.text = p ? String(p.interface || "") : ""
    clientosDropdown.value = p ? String(p.clientos || "linux-64") : "linux-64"
  }

  function openAddForm() {
    editingId = ""
    addingProfile = true
    vpn.saveError = ""
    fillForm(null)
    setHeaderCursor()
    Qt.callLater(function () { nameField.forceActiveFocus() })
  }

  function openEditForm(p) {
    if (!p) return
    editingId = String(p.id)
    addingProfile = true
    vpn.saveError = ""
    fillForm(p)
    Qt.callLater(function () { nameField.forceActiveFocus() })
  }

  function closeAddForm() {
    addingProfile = false
    editingId = ""
    vpn.saveError = ""
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function toggleAddForm() {
    if (addingProfile) closeAddForm()
    else openAddForm()
  }

  function submitForm() {
    vpn.saveProfile(editingId, nameField.text, serverField.text, modeGroup.value,
                    gatewayField.text, clientosDropdown.value, ifaceField.text)
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0 && vpn.profiles.length > 0) setProfileCursor(0)
      return
    }
    if (focusSection === "profiles") {
      if (dy < 0 && profileIndex === 0) {
        setHeaderCursor()
        return
      }
      profileIndex = Math.max(0, Math.min(vpn.profiles.length - 1, profileIndex + dy))
    }
  }

  function activateCursor() {
    // El control del header dejo de ser el switch: ahora da de alta un perfil.
    if (focusSection === "header") {
      toggleAddForm()
      return
    }
    toggleProfile(selectedProfile())
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "header"
    profileIndex = 0
    addingProfile = false
    errorExpanded = false
    cancelRemoval()
    vpn.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: vpn
    settings: root.settings
  }

  Connections {
    target: vpn
    function onProfileSaved(id) { root.closeAddForm() }
    // Tras borrar, la lista se acorta: el cursor puede quedar fuera de rango.
    function onProfileRemoved(id) {
      root.profileIndex = Math.max(0, Math.min(root.profileIndex, vpn.profiles.length - 2))
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(profile: string): string { vpn.connect(profile); return "ok" }
    function disconnect(): string { vpn.disconnect(); return "ok" }
    function refresh(): string { vpn.refresh(); return "ok" }
    function status(): string { return vpn.state }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Lo que antes obligaba a abrir el panel para verlo. BarIconButton extiende
    // WidgetButton, que ya resuelve el tooltip contra la barra.
    tooltipText: {
      if (!vpn.installed) return "GlobalProtect · backend no disponible"
      if (vpn.state === "connected") {
        var parts = [vpn.profileName !== "" ? vpn.profileName : "Conectada"]
        if (vpn.ip !== "") parts.push(vpn.ip)
        if (uptime.text !== "") parts.push("hace " + uptime.text)
        return parts.join(" · ")
      }
      if (vpn.state === "connecting") return "GlobalProtect · levantando el túnel…"
      if (vpn.state === "authenticating") return "GlobalProtect · esperando el login SAML…"
      if (vpn.state === "failed") return "GlobalProtect · falló la conexión"
      return vpn.hasProfiles ? "GlobalProtect · desconectada" : "GlobalProtect · sin perfiles"
    }
    iconComponent: Component {
      Item {
        ShieldIcon {
          anchors.centerIn: parent
          iconSize: Style.space(13)
          color: root.barIconColor
          filled: vpn.connected
          holeColor: root.bar ? root.bar.background : Color.background
          opacity: vpn.busyState ? 0.55 : 1.0

          // Latido mientras negocia: el escudo hueco solo no alcanza para
          // distinguir "conectando" de "desconectada".
          SequentialAnimation on opacity {
            running: vpn.busyState
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
          }
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleVpn()
      else if (buttonCode === Qt.MiddleButton) vpn.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Mientras se escribe en el formulario las teclas son texto, no atajos.
      blocked: nameField.activeFocus || serverField.activeFocus
               || gatewayField.activeFocus || ifaceField.activeFocus
               || clientosDropdown.popupOpen
      onMoveRequested: function (dx, dy) {
        if (root.pendingRemovalId !== "") {
          if (dx !== 0) removeConfirm.selectedIndex = removeConfirm.selectedIndex === 0 ? 1 : 0
          return
        }
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: {
        if (root.pendingRemovalId !== "") {
          if (removeConfirm.selectedIndex === 0) root.cancelRemoval()
          else root.confirmRemoval()
          return
        }
        if (root.cursorActive) root.activateCursor()
      }
      onCloseRequested: {
        if (root.pendingRemovalId !== "") root.cancelRemoval()
        else if (root.addingProfile) root.closeAddForm()
        else root.close()
      }
      onDeleteRequested: {
        if (root.pendingRemovalId === "" && root.focusSection === "profiles") {
          root.askRemoveProfile(root.selectedProfile())
        }
      }
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (root.pendingRemovalId !== "") return
        var key = String(t || "").toLowerCase()
        if (key === "t") root.toggleVpn()
        else if (key === "n") root.toggleAddForm()
        else if (key === "e") { if (root.focusSection === "profiles") root.openEditForm(root.selectedProfile()) }
        else if (key === "d") { if (root.focusSection === "profiles" && root.selectedProfile()) vpn.setDefaultProfile(root.selectedProfile().id) }
        else if (key === "r") vpn.refresh()
        // `l` no llega hasta aca: PanelKeyCatcher lo gasta como flecha derecha.
        else if (key === "g") Quickshell.execDetached(["uwsm-app", "--", "foot", "-T", "GlobalProtect", "bash", "-c", "gpvpn logs -f"])
      }

      ConfirmDialog {
        id: removeConfirm
        anchors.fill: parent
        z: 10
        opened: root.pendingRemovalId !== ""
        message: "¿Borrar el perfil «" + root.pendingRemovalName + "»?"
        confirmText: "Borrar"
        cancelText: "Cancelar"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelRemoval()
        onConfirmed: root.confirmRemoval()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // Lo lee el trailingControl del hero, cuyo `root` resuelve a
            // PanelHero y no a este Panel.
            readonly property bool ringVisible: root.headerHasCursor
            readonly property bool formOpen: root.addingProfile
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "GlobalProtect"
              meta: vpn.stateLabel()
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: vpn.active ? 1.0 : 0.5
              iconComponent: Component {
                ShieldIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  filled: vpn.connected
                  holeColor: Color.popups.background
                }
              }

              trailingControl: Component {
                PanelActionButton {
                  visible: vpn.installed
                  bordered: true
                  iconText: header.formOpen ? "󰅖" : "󰐕"
                  tooltipText: header.formOpen ? "Cancelar" : "Agregar perfil"
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  hasCursor: header.ringVisible
                  onHovered: function (on) { if (on) header.focusHero() }
                  onClicked: root.toggleAddForm()
                }
              }
            }
          }

          Column {
            visible: vpn.actionStatus !== "" || vpn.lastError !== ""
            width: parent.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: vpn.actionStatus !== "" ? vpn.actionStatus
                    : (root.errorExpanded ? vpn.lastErrorFull : vpn.lastError)
              color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            // Un error de certificado o de HIP no entra en 160 caracteres, y el
            // detalle quedaba solo en `g` -> logs.
            Text {
              visible: vpn.actionStatus === "" && vpn.errorTruncated
              text: root.errorExpanded ? "ver menos" : "ver más"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.underline: expandArea.containsMouse

              MouseArea {
                id: expandArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.errorExpanded = !root.errorExpanded
              }
            }
          }

          PanelSeparator {
            visible: vpn.connected
            foreground: root.foreground
          }

          Column {
            visible: vpn.connected
            width: parent.width
            spacing: Style.spacing.labelGap

            // Con modo portal se muestran los dos: el portal contra el que se
            // autentica y el gateway que se eligio dentro de el.
            InfoPair {
              visible: vpn.serverHost !== ""
              label: vpn.profileMode === "portal" ? "Portal" : "Servidor"
              value: vpn.serverHost
            }
            InfoPair {
              visible: vpn.profileMode === "portal"
              label: "Gateway"
              value: vpn.gatewayName !== "" ? vpn.gatewayName : "automático"
            }
            InfoPair { label: "Interfaz"; value: vpn.interfaceName }
            InfoPair {
              visible: vpn.ip !== ""
              label: "IP"
              value: vpn.ip
            }
            InfoPair {
              visible: uptime.text !== ""
              label: "Conectada hace"
              value: uptime.text
            }
          }

          PanelSeparator {
            visible: vpn.installed
            foreground: root.foreground
          }

          Column {
            id: addForm
            visible: root.addingProfile
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: root.editingId !== "" ? "EDITAR PERFIL" : "NUEVO PERFIL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            FormRow {
              label: "Nombre"
              TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "Trabajo"
                foreground: root.foreground
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                onAccepted: serverField.forceActiveFocus()
                Keys.onEscapePressed: root.closeAddForm()
              }
            }

            FormRow {
              label: "Servidor"
              TextField {
                id: serverField
                Layout.fillWidth: true
                placeholderText: "vpn.empresa.com"
                foreground: root.foreground
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                onAccepted: modeGroup.value === "portal" ? gatewayField.forceActiveFocus()
                                                          : root.submitForm()
                Keys.onEscapePressed: root.closeAddForm()
              }
            }

            FormRow {
              label: "Modo"
              ButtonGroup {
                id: modeGroup
                Layout.fillWidth: true
                focusable: false
                value: "gateway"
                options: ["gateway", "portal"]
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onChanged: function (v) { modeGroup.value = v }
              }
            }

            // Solo aplica autenticando contra un portal: es el --authgroup de
            // openconnect, el mismo desplegable del cliente oficial.
            FormRow {
              visible: modeGroup.value === "portal"
              label: "Gateway"
              TextField {
                id: gatewayField
                Layout.fillWidth: true
                placeholderText: "el que elija el portal"
                foreground: root.foreground
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.closeAddForm()
              }
            }

            FormRow {
              label: "Interfaz"
              TextField {
                id: ifaceField
                Layout.fillWidth: true
                placeholderText: "gpvpn0"
                foreground: root.foreground
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.closeAddForm()
              }
            }

            FormRow {
              label: "Sistema"
              Dropdown {
                id: clientosDropdown
                Layout.fillWidth: true
                showLabel: false
                value: "linux-64"
                options: ["linux-64", "linux", "win", "mac-intel", "android", "apple-ios"]
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function (v) { clientosDropdown.value = v }
              }
            }

            Text {
              visible: vpn.saveError !== ""
              width: parent.width
              text: vpn.saveError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                text: root.editingId !== "" ? "el id no cambia al editar" : "el id sale del nombre"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Button {
                text: "Cancelar"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.closeAddForm()
              }

              Button {
                id: saveButton
                readonly property bool ready: nameField.text.trim() !== ""
                                              && serverField.text.trim() !== ""
                                              && !vpn.saving
                text: vpn.saving ? "Guardando…" : "Guardar"
                bordered: true
                selected: ready
                opacity: ready ? 1.0 : 0.45
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: if (ready) root.submitForm()
              }
            }
          }

          PanelSeparator {
            visible: root.addingProfile
            foreground: root.foreground
          }

          Column {
            visible: vpn.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "PERFILES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: !vpn.hasProfiles
              width: parent.width
              text: "No hay perfiles configurados.\nAgrega uno con el botón + de arriba."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              id: profileColumn
              visible: vpn.hasProfiles
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: vpn.profiles
                ProfileRow {
                  required property var modelData
                  required property int index
                  width: profileColumn.width
                  profile: modelData
                  rowIndex: index
                }
              }
            }
          }

          Text {
            visible: !vpn.installed
            width: parent.width
            text: "No se encontró el CLI `gpvpn`.\nInstala el backend con: gpvpn setup"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "n nuevo · e editar · x borrar · d default · t conectar · r refrescar · g logs · esc"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // El uptime se calcula desde el timestamp de la unidad, asi que hay que
  // repintarlo aunque el estado no cambie.
  QtObject {
    id: uptime
    property string text: ""
  }

  // Corre siempre que haya tunel, no solo con el panel abierto: el tooltip de
  // la barra tambien muestra el uptime.
  Timer {
    interval: 1000
    running: vpn.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: uptime.text = vpn.uptimeText()
  }

  // Etiqueta a la izquierda, control a la derecha: el hijo que le pasen es el
  // control y se estira solo.
  component FormRow: RowLayout {
    id: formRow
    property string label: ""

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(8)

    Text {
      Layout.preferredWidth: Style.space(62)
      Layout.alignment: Qt.AlignVCenter
      text: formRow.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  component ProfileRow: CursorSurface {
    id: profileRow
    property var profile: null
    property int rowIndex: 0
    readonly property bool isActive: profile && profile.id === vpn.activeProfileId
    readonly property bool isDefault: profile && profile.id === vpn.defaultProfile

    hasCursor: root.cursorActive && root.focusSection === "profiles" && root.profileIndex === rowIndex
    foreground: root.foreground
    implicitHeight: Math.max(rowContent.implicitHeight, profileSwitch.implicitHeight) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setProfileCursor(profileRow.rowIndex)
      onClicked: {
        root.setProfileCursor(profileRow.rowIndex)
        root.toggleProfile(profileRow.profile)
      }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(7)
        height: width
        radius: width / 2
        Layout.alignment: Qt.AlignVCenter
        color: profileRow.isActive ? root.foreground : "transparent"
        border.width: profileRow.isActive ? 0 : 1
        border.color: root.dim
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: profileRow.profile ? String(profileRow.profile.name || profileRow.profile.id) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: profileRow.profile ? String(profileRow.profile.server || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideLeft
        }
      }

      Text {
        // Cede el lugar a los botones cuando el cursor esta sobre la fila.
        visible: profileRow.isDefault && !profileRow.isActive && !profileRow.hasCursor
        text: "default"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      // Los tres aparecen solo con el cursor sobre la fila, para no cargar la
      // lista con acciones que casi nunca se usan.
      PanelActionButton {
        visible: profileRow.hasCursor && !profileRow.isDefault
        iconText: "󰐃"
        tooltipText: "Marcar por defecto"
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: false
        Layout.alignment: Qt.AlignVCenter
        onClicked: vpn.setDefaultProfile(profileRow.profile ? profileRow.profile.id : "")
      }

      PanelActionButton {
        visible: profileRow.hasCursor
        iconText: "󰏫"
        tooltipText: "Editar perfil"
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: false
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.openEditForm(profileRow.profile)
      }

      // El perfil activo no ofrece borrado: primero hay que desconectar.
      PanelActionButton {
        visible: profileRow.hasCursor && !profileRow.isActive
        iconText: "󰩹"
        tooltipText: "Borrar perfil"
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: false
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.askRemoveProfile(profileRow.profile)
      }

      // El switch de la fila manda sobre su propio perfil; la fila entera sigue
      // siendo clickeable, pero el switch se come el click cuando cae encima.
      ToggleSwitch {
        id: profileSwitch
        Layout.alignment: Qt.AlignVCenter
        checked: profileRow.isActive
        busy: vpn.busy && profileRow.isActive
        cursorRing: false
        trackHeight: Style.space(18)
        foreground: root.foreground
        onHovered: function (on) { if (on) root.setProfileCursor(profileRow.rowIndex) }
        onToggled: {
          root.setProfileCursor(profileRow.rowIndex)
          root.toggleProfile(profileRow.profile)
        }
      }
    }
  }

  component InfoPair: Item {
    id: pair
    property string label: ""
    property string value: ""

    width: parent.width
    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: pair.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: valueText
      anchors.left: labelText.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: pair.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
    }
  }
}
