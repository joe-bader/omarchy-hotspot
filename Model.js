.pragma library

// Pure helpers for the hotspot widget: parse hotspot-status output and derive
// one status. No QML here, so it can be exercised from node
// (see tests/model.test.js).

// Material Design glyphs from the Nerd Font.
var ICON_ON = "󰀃"        // access_point
var ICON_OFF = "󱔑"       // access_point_off
var ICON_ALERT = "󰯡"     // access_point_network_off

var MAX_FIELD = 256

function parse(raw) {
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length && i < 100; i++) {
    var line = lines[i]
    var tab = line.indexOf("\t")
    if (tab <= 0) continue
    var key = line.slice(0, tab)
    if (!/^[a-z_]{1,32}$/.test(key)) continue
    out[key] = line.slice(tab + 1).slice(0, MAX_FIELD)
  }
  return out
}

// One of: absent, off, starting, on, stopping
function status(info) {
  if (!info || !info.device) return "absent"
  if (info.state === "activated") return "on"
  if (info.state === "activating") return "starting"
  if (info.state === "deactivating") return "stopping"
  return "off"
}

function isOn(st) {
  return st === "on" || st === "starting"
}

function icon(st, info) {
  if (st === "absent") return ICON_OFF
  if (st === "on" && !info.uplink) return ICON_ALERT
  return isOn(st) ? ICON_ON : ICON_OFF
}

// The bar icon is only full strength while the hotspot runs.
function lit(st) {
  return isOn(st)
}

// Translation key for the problem or warning to show under the hero, or "".
// Ordered by what blocks the user first.
function hintKey(st, info) {
  if (st === "absent") return "hint.absent"
  if (info.dnsmasq === "no") return "hint.noDnsmasq"
  if (info.firewall === "blocked") return "hint.firewall"
  if (st === "on" && !info.uplink) return "hint.noUplink"
  if (st === "off" && info.wifi_network) return "hint.willDisconnect"
  return ""
}

function isProblem(key) {
  return key === "hint.absent" || key === "hint.noDnsmasq" || key === "hint.firewall" || key === "hint.noUplink"
}

function clientCount(info) {
  var n = parseInt(info.clients, 10)
  return isFinite(n) && n >= 0 ? n : 0
}

// NetworkManager device type of the uplink -> translation key.
function uplinkKey(type) {
  switch (String(type || "")) {
    case "gsm":
    case "cdma":
    case "modem": return "uplink.cellular"
    case "ethernet": return "uplink.ethernet"
    case "wifi": return "uplink.wifi"
    case "tun":
    case "wireguard":
    case "vpn": return "uplink.vpn"
    case "": return ""
    default: return "uplink.other"
  }
}

function bandLabel(band) {
  if (band === "bg") return "2.4 GHz"
  if (band === "a") return "5 GHz"
  return ""
}

function humanBytes(raw, formatNumber) {
  var n = parseFloat(raw)
  if (!isFinite(n) || n < 0) return ""
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  var decimals = i === 0 || n >= 100 ? 0 : 1
  return (formatNumber ? formatNumber(n, decimals) : n.toFixed(decimals)) + " " + units[i]
}

// Output of `omarchy-network-qr --meta <iface>`: a "meta<TAB>iface<TAB>
// security<TAB>ssid" line, then a square matrix of 0/1 rows (quiet zone
// included). Returns { ssid, rows, size }; size 0 when the matrix is invalid.
var MAX_QR = 185  // version 40 (177) plus a 4-module quiet zone each side

function parseQr(raw) {
  var lines = String(raw || "").trim().split(/\r?\n/).filter(function(l) { return l !== "" })
  var ssid = ""
  if (lines.length > 0 && lines[0].indexOf("meta\t") === 0)
    ssid = lines.shift().split("\t").slice(3).join("\t")
  var empty = { ssid: ssid, rows: [], size: 0 }
  var size = lines.length
  if (size === 0 || size > MAX_QR) return empty
  for (var i = 0; i < size; i++)
    if (lines[i].length !== size || !/^[01]+$/.test(lines[i])) return empty
  return { ssid: ssid, rows: lines, size: size }
}
