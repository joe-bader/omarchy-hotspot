import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Hotspot bar widget: access-point icon in the bar, and a panel with the
// hotspot switch, connected devices, what is being shared, and a QR code to
// join it. The QR code is drawn here from `omarchy-network-qr`: plugins can
// only summon their own panels, so Omarchy's Wi-Fi share card is out of reach.
//
// State comes from the bundled `hotspot-status` helper (read-only nmcli + iw).
// Turning on goes through `hotspot-up`, which creates the NetworkManager
// profile on first use. Commands are argv arrays, never a shell string.
Panel {
  id: root
  moduleName: "joe.hotspot"
  ipcTarget: "joe.hotspot"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property int refreshIntervalSec: Math.max(5, Number(setting("refreshIntervalSec", 15)) || 15)

  property var info: ({})
  property bool loaded: false
  property bool busy: false
  // Optimistic on/off while a change is in flight; null otherwise.
  property var desiredOn: null
  property string lastError: ""

  // QR code to join the hotspot; it holds the password, so it is only kept
  // while shown.
  property bool qrShown: false
  property var qrRows: []
  property string qrError: ""

  // Password for devices without a camera; same lifetime rules as the QR.
  property bool passwordShown: false
  property string password: ""
  property string passwordError: ""

  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property string st: Model.status(info)
  readonly property bool hotspotOn: desiredOn !== null ? desiredOn : Model.isOn(st)
  readonly property bool hasDevice: st !== "absent"
  readonly property bool canShare: st === "on" && String(info.ssid || "") !== ""
  readonly property bool hasProfile: hasDevice && String(info.profile || "") !== ""
  // Cursor slots: 0 switch, then password (when a profile exists), then QR.
  readonly property int passwordIndex: hasProfile ? 1 : -1
  readonly property int qrIndex: canShare ? (hasProfile ? 2 : 1) : -1
  readonly property int cursorCount: 1 + (hasProfile ? 1 : 0) + (canShare ? 1 : 0)

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string statusText: {
    if (busy && desiredOn !== null) return strings.t(desiredOn ? "status.starting" : "status.stopping")
    if (st === "on") return strings.tn("clients", Model.clientCount(info)).arg(Commons.I18n.formatNumber(Model.clientCount(info)))
    return strings.t("status." + st)
  }
  readonly property string hintKey: Model.hintKey(st, info)
  readonly property string hintText: {
    if (hintKey === "") return ""
    var text = strings.t(hintKey)
    if (hintKey === "hint.firewall") return text.arg(pluginDir.replace(/^\/home\/[^\/]+/, "~"))
    if (hintKey === "hint.willDisconnect") return text.arg(String(info.wifi_network))
    return text
  }
  readonly property string sharingText: {
    var key = Model.uplinkKey(info.uplink_type)
    return key === "" ? "" : strings.t(key) + " (" + String(info.uplink) + ")"
  }
  readonly property string dataText: {
    if (info.down_bytes === undefined) return ""
    return "↓ " + Model.humanBytes(info.down_bytes, Commons.I18n.formatNumber)
      + "   ↑ " + Model.humanBytes(info.up_bytes, Commons.I18n.formatNumber)
  }

  readonly property string tooltipText: {
    var parts = [strings.t("title"), statusText]
    if (st === "on" && info.ssid) parts.push(String(info.ssid))
    return parts.join(" — ")
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function applyStatus(raw) {
    var next = Model.parse(raw)
    if (Object.keys(next).length === 0) return
    info = next
    loaded = true
    if (desiredOn !== null && !busy && Model.isOn(Model.status(next)) === desiredOn) desiredOn = null
  }

  function run(argv) {
    if (actionProc.running) return
    busy = true
    lastError = ""
    actionProc.command = argv
    actionProc.running = true
  }

  function toggleHotspot() {
    if (busy || !hasDevice) return
    var on = !hotspotOn
    desiredOn = on
    if (on) run([pluginDir + "/hotspot-up", String(info.device)])
    else run(["nmcli", "connection", "down", "id", String(info.profile)])
  }

  function toggleQr() {
    if (qrShown) { hideQr(); return }
    if (!canShare || qrProc.running) return
    qrShown = true
    qrRows = []
    qrError = ""
    qrProc.command = ["omarchy-network-qr", "--meta", String(info.device)]
    qrProc.running = true
  }

  function hideQr() {
    if (qrProc.running) qrProc.running = false
    qrShown = false
    qrRows = []
    qrError = ""
  }

  function togglePassword() {
    if (passwordShown) { hidePassword(); return }
    if (!hasProfile || passwordProc.running) return
    passwordShown = true
    password = ""
    passwordError = ""
    passwordProc.command = ["nmcli", "--show-secrets", "--escape", "no", "--get-values",
      "802-11-wireless-security.psk", "connection", "show", "id", String(info.profile)]
    passwordProc.running = true
  }

  function hidePassword() {
    if (passwordProc.running) passwordProc.running = false
    passwordShown = false
    password = ""
    passwordError = ""
  }

  function applyQr(raw) {
    if (!qrShown) return
    var parsed = Model.parseQr(raw)
    // The device could have fallen back to ordinary Wi-Fi in the meantime;
    // never show a code for a different network.
    if (parsed.size === 0 || parsed.ssid !== String(info.ssid || "")) {
      qrError = strings.t("qrFailed")
      return
    }
    qrRows = parsed.rows
  }

  function activateCursor() {
    if (!cursorActive) return
    if (cursorIndex === 0) toggleHotspot()
    else if (cursorIndex === passwordIndex) togglePassword()
    else if (cursorIndex === qrIndex) toggleQr()
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      refresh()
    } else {
      hideQr()
      hidePassword()
    }
  }
  onHasProfileChanged: if (!hasProfile) hidePassword()
  onCanShareChanged: if (!canShare) hideQr()
  onCursorCountChanged: cursorIndex = Math.min(cursorIndex, cursorCount - 1)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: [root.pluginDir + "/hotspot-status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
  }

  Process {
    id: actionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var msg = lines[lines.length - 1] || ""
        if (msg !== "") root.lastError = msg.slice(0, 200)
      }
    }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) root.lastError = ""
      else root.desiredOn = null
      root.refresh()
      settleTimer.restart()
    }
  }

  Process {
    id: qrProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyQr(text) }
    onExited: function(exitCode) {
      if (root.qrShown && exitCode !== 0 && root.qrRows.length === 0) root.qrError = strings.t("qrFailed")
    }
  }

  Process {
    id: passwordProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.passwordShown) return
        var pw = String(text || "").replace(/\r?\n$/, "")
        if (pw === "" || pw.length > 64) root.passwordError = strings.t("passwordFailed")
        else root.password = pw
      }
    }
    onExited: function(exitCode) {
      if (root.passwordShown && exitCode !== 0 && root.password === "") root.passwordError = strings.t("passwordFailed")
    }
  }

  // Wi-Fi reconnects to its usual network a few seconds after the hotspot
  // stops, and clients join shortly after it starts; look again then.
  Timer { id: settleTimer; interval: 4000; repeat: false; onTriggered: root.refresh() }

  Timer {
    interval: root.opened ? 3000 : root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.icon(root.st, root.info)
    dimmed: root.loaded && !Model.lit(root.st)
    tooltipText: root.opened ? "" : root.tooltipText
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleHotspot()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        var delta = dy !== 0 ? dy : dx
        root.cursorIndex = Math.max(0, Math.min(root.cursorCount - 1, root.cursorIndex + delta))
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelHero {
          id: hero
          width: parent.width
          title: strings.t("title")
          meta: root.statusText
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: Model.lit(root.st) ? 1.0 : 0.5
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: Model.icon(root.st, root.info)
              color: root.st === "on" && Model.isProblem(root.hintKey) ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: hotspotSwitch
              visible: root.hasDevice
              checked: root.hotspotOn
              busy: root.busy
              hasCursor: root.cursorActive && root.cursorIndex === 0
              foreground: root.foreground
              onHovered: function(on) { if (on) { root.cursorActive = true; root.cursorIndex = 0 } }
              onToggled: root.toggleHotspot()

              PanelToolTip {
                visible: hotspotSwitch.containsMouse
                text: root.hotspotOn ? strings.t("turnOff") : strings.t("turnOn")
                fontFamily: root.fontFamily
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: root.lastError !== "" ? root.lastError : root.hintText
          color: root.lastError !== "" || Model.isProblem(root.hintKey) ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        PanelSeparator {
          visible: details.visible
          foreground: root.foreground
        }

        Column {
          id: details
          visible: root.hasDevice && String(root.info.ssid || "") !== ""
          width: parent.width
          spacing: Style.spacing.labelGap

          InfoPair { label: strings.t("networkName"); value: String(root.info.ssid || "") }
          InfoPair { label: strings.t("band"); value: Model.bandLabel(root.info.band) }
          InfoPair { label: strings.t("sharing"); value: root.st === "on" ? root.sharingText : "" }
          InfoPair { label: strings.t("dataUsed"); value: root.st === "on" ? root.dataText : "" }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.passwordShown && text !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.passwordError !== "" ? root.passwordError : root.password
          color: root.passwordError !== "" ? root.urgent : root.foreground
          // Large in the bar's monospace font, so it can be read off and typed in.
          font.family: root.fontFamily
          font.pixelSize: root.passwordError !== "" ? Style.font.bodySmall : Style.font.display
          wrapMode: Text.WrapAnywhere
        }

        Button {
          visible: root.hasProfile
          width: parent.width
          text: root.passwordShown ? strings.t("hidePassword") : strings.t("showPassword")
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          hasCursor: root.cursorActive && root.cursorIndex === root.passwordIndex
          onClicked: root.togglePassword()
          onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = root.passwordIndex } }
        }

        Rectangle {
          id: qrBox
          visible: root.qrShown && root.qrRows.length > 0
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(200)
          height: width
          // Scanners want dark modules on a light ground whatever the theme.
          color: "white"
          radius: Style.space(6)

          Canvas {
            id: qrCanvas
            anchors.fill: parent
            anchors.margins: Style.space(4)
            property var rows: root.qrRows
            onRowsChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var n = rows.length
              if (n === 0) return
              var cell = Math.floor(Math.min(width, height) / n)
              var off = Math.floor((Math.min(width, height) - cell * n) / 2)
              ctx.fillStyle = "black"
              for (var y = 0; y < n; y++)
                for (var x = 0; x < n; x++)
                  if (rows[y].charAt(x) === "1") ctx.fillRect(off + x * cell, off + y * cell, cell, cell)
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.qrShown && text !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.qrError !== "" ? root.qrError : (root.qrRows.length === 0 ? strings.t("qrLoading") : strings.t("qrHint"))
          color: root.qrError !== "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Button {
          visible: root.canShare
          width: parent.width
          text: root.qrShown ? strings.t("hideQr") : strings.t("showQr")
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          hasCursor: root.cursorActive && root.cursorIndex === root.qrIndex
          onClicked: root.toggleQr()
          onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = root.qrIndex } }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    visible: value !== ""
    width: parent.width
    spacing: Style.space(8)

    InfoText { id: labelText; text: parent.label; opacity: 0.6 }
    Item { width: Math.max(0, parent.width - labelText.implicitWidth - valueText.width - parent.spacing * 2); height: 1 }
    InfoText {
      id: valueText
      text: parent.value
      width: Math.min(implicitWidth, parent.width * 0.62)
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignRight
    }
  }

  component InfoText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
