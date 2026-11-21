// Run: node tests/model.test.js   (from the plugin folder)
const fs = require("fs"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(".pragma library", "")
const M = new Function(src + "; return { parse, status, isOn, icon, lit, hintKey, isProblem, clientCount, uplinkKey, bandLabel, humanBytes, parseQr, ICON_ON, ICON_OFF, ICON_ALERT }")()

const base = { device: "wlp1s0", radio: "enabled", dnsmasq: "yes", firewall: "open", profile: "Hotspot" }
const info = o => Object.assign({}, base, o)

// parse
const p = M.parse("radio\tenabled\nssid\t<img src=x>\nBAD\tx\nnotab\n" + "x".repeat(40) + "\ty\n")
assert.deepStrictEqual(Object.keys(p), ["radio", "ssid"])
assert.strictEqual(p.ssid, "<img src=x>")
assert.strictEqual(M.parse("ssid\t" + "a".repeat(1000)).ssid.length, 256)
assert.deepStrictEqual(M.parse(""), {})

// status
assert.strictEqual(M.status({}), "absent")
assert.strictEqual(M.status(info({})), "off")
assert.strictEqual(M.status(info({ state: "activating" })), "starting")
assert.strictEqual(M.status(info({ state: "activated" })), "on")
assert.strictEqual(M.status(info({ state: "deactivating" })), "stopping")
assert.strictEqual(M.lit("on"), true)
assert.strictEqual(M.lit("off"), false)

// icon
assert.strictEqual(M.icon("on", info({ uplink: "wwan0" })), M.ICON_ON)
assert.strictEqual(M.icon("on", info({})), M.ICON_ALERT)
assert.strictEqual(M.icon("off", info({})), M.ICON_OFF)

// hints, most blocking first
assert.strictEqual(M.hintKey("absent", {}), "hint.absent")
assert.strictEqual(M.hintKey("off", info({ dnsmasq: "no", firewall: "blocked" })), "hint.noDnsmasq")
assert.strictEqual(M.hintKey("off", info({ firewall: "blocked" })), "hint.firewall")
assert.strictEqual(M.hintKey("off", info({ firewall: "off", wifi_network: "Home" })), "hint.willDisconnect")
assert.strictEqual(M.hintKey("on", info({})), "hint.noUplink")
assert.strictEqual(M.hintKey("on", info({ uplink: "wwan0" })), "")
assert.strictEqual(M.isProblem("hint.firewall"), true)
assert.strictEqual(M.isProblem("hint.willDisconnect"), false)

// details
assert.strictEqual(M.clientCount({ clients: "3" }), 3)
assert.strictEqual(M.clientCount({ clients: "-1" }), 0)
assert.strictEqual(M.clientCount({}), 0)
assert.strictEqual(M.uplinkKey("gsm"), "uplink.cellular")
assert.strictEqual(M.uplinkKey("ethernet"), "uplink.ethernet")
assert.strictEqual(M.uplinkKey("tun"), "uplink.vpn")
assert.strictEqual(M.uplinkKey("bond"), "uplink.other")
assert.strictEqual(M.uplinkKey(""), "")
assert.strictEqual(M.bandLabel("bg"), "2.4 GHz")
assert.strictEqual(M.bandLabel(""), "")
assert.strictEqual(M.humanBytes("1536"), "1.5 KB")
assert.strictEqual(M.humanBytes("nope"), "")

// QR matrix
const q = M.parseQr("meta\twlp1s0\tWPA\tmy\thot spot\n101\n010\n101\n")
assert.strictEqual(q.ssid, "my\thot spot")
assert.strictEqual(q.size, 3)
assert.deepStrictEqual(q.rows, ["101", "010", "101"])
assert.strictEqual(M.parseQr("101\n010\n").size, 0)          // not square
assert.strictEqual(M.parseQr("1a1\n010\n101\n").size, 0)    // bad cell
assert.strictEqual(M.parseQr("meta\tw\tWPA\tx\n").size, 0)  // no matrix
assert.strictEqual(M.parseQr("").size, 0)

console.log("ok")
