# MacTemp

A tiny macOS menu bar app that shows your Mac's CPU temperature (e.g. `48°C`), refreshing every 2 seconds.

- **Apple Silicon:** reads the CPU die sensors through IOKit's HID temperature sensors (no admin password needed).
- **Intel:** reads the SMC keys `TC0P` / `TC0D`.
- Click the temperature to see °C and °F, a Cool / Warm / Hot label, and macOS's thermal state (Nominal / Fair / Serious / Critical). Includes a °C/°F toggle and a Quit button.

Requires macOS 13 or later.

## Build and run

You need the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh
open MacTemp.app
```

The app lives only in the menu bar (no Dock icon). Quit it from its menu.
