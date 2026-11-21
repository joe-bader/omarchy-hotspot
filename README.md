# omarchy-hotspot

An [Omarchy](https://omarchy.org/) bar widget for a Wi-Fi hotspot: share the
laptop's cellular or wired connection with your phone, tablet, or another
computer.

- **Bar icon**: lit while the hotspot runs; dimmed when off; a crossed-out
  network glyph when it is on with nothing to share.
- **Left click**: open the panel. **Right click**: hotspot on/off.
- **Panel**: on/off switch, connected devices, a hint for anything in the way
  (missing dnsmasq, firewall, no internet to share), network name, band, what
  it is sharing, data used this session, a **Show password** button for
  devices without a camera, and a **Show QR code** button that shows a code a
  phone can scan to join. Both are cleared when hidden or when the panel
  closes.
  Keyboard: arrows move, Enter activates.

The hotspot uses the laptop's Wi-Fi card, so turning it on disconnects Wi-Fi
from its usual network; NetworkManager reconnects when the hotspot is turned
off. Pair it with [omarchy-cellular](https://github.com/joe-bader/omarchy-cellular)
to share mobile data.

## Install

```bash
omarchy plugin add https://github.com/joe-bader/omarchy-hotspot.git --enable
```

## Requirements

NetworkManager runs the hotspot and needs dnsmasq to hand out addresses:

```bash
omarchy pkg add dnsmasq
```

Omarchy's firewall (ufw) blocks devices on the hotspot. Allow them once:

```bash
sudo ~/.config/omarchy/plugins/joe.hotspot/setup-firewall           # add rules
sudo ~/.config/omarchy/plugins/joe.hotspot/setup-firewall --remove  # undo
```

The rules only cover the Wi-Fi device and the hotspot subnet 10.42.0.0/24:
DHCP and DNS to the laptop, and routing out to the internet.

## Network name and password

The first time it is turned on, the widget creates a NetworkManager profile
named `Hotspot`: network `<hostname>-hotspot`, WPA2, 2.4 GHz, and a random
12-character password, shown by **Show password** in the panel. Change them
with:

```bash
nmcli connection modify Hotspot wifi.ssid "My Hotspot" wifi-sec.psk "new password"
```

Use 5 GHz with `wifi.band a`, if your Wi-Fi card allows an access point there.

The profile is marked metered, so NetworkManager tells Android devices that
join to hold back background data (DHCP option 43, `ANDROID_METERED`). iPhones,
iPads, Macs, and Windows don't read that hint: turn on Low Data Mode or
Metered connection for the hotspot on those devices yourself. To stop
announcing it:

```bash
nmcli connection modify Hotspot connection.metered unknown
```

## Settings

`refreshIntervalSec` (default 15; the panel polls every 3s while open):

```bash
omarchy bar set joe.hotspot refreshIntervalSec 30
```

## Development

- `hotspot-status` — read-only helper that prints hotspot state from `nmcli`,
  `iw`, and ufw's rule files as `key<TAB>value` lines.
- `hotspot-up` — creates the profile on first use and brings it up.
- `setup-firewall` — the ufw rules above.
- `Model.js` — pure status logic; test with `node tests/model.test.js`.
- `Panel.qml` — the bar icon and panel. The QR code is drawn from
  `omarchy-network-qr` output; Omarchy only lets a plugin summon its own
  panels, so the built-in Wi-Fi share card isn't available to it.
- `i18n/en.json` — strings; add `<lang>.json` files for translations.

Tested with an Intel Wi-Fi card (iwlwifi).

## License

MIT
