# WiFi

!!! info "Regenerate"
    Run `gendocs` in the devShell to populate this page with live option data.

Declarative NetworkManager profile generation via clan vars.

Source: `modules/wifi.nix`

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.wifi.networks` | `list of (submodule)` | List of WiFi networks to configure via NetworkManager and clan vars. |
| `clanarchy.wifi.networks.*.ssid` | `string` | WiFi SSID. |
| `clanarchy.wifi.networks.*.varName` | `string` | Clan vars generator name for this network's PSK. |
