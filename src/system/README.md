# Australis OS System

## Core layout

```text
BOOTX64.EFI
│
KERNEL.BIN
│
AUSTRALIS.OS
│
├── System Services
│   ├── device.serv
│   ├── network.serv
│   ├── storage.serv
│   └── ...
│
├── LAUNCHER.OS
│   └── Application Launch Management
│
└── Session Manager
    │
    ├── DISPLAY.OS
    │   ├── Window Management
    │   ├── Display Compositing
    │   └── Input Routing
    │
    └── Login Manager
        │
        User Session
        │
        SHELL.OS
        │
        ├── DESKTOP.appl
        ├── TASKBAR.appl
        ├── NOTIFICATIONS.appl
        │
        └── Applications
            ├── EXPLORER.appl
            ├── TERMINAL.appl
            └── Other Applications
```

## Applications layout

```text
Calculator.appl/
├── manifest.json
├── Calculator.exec
└── Resources/
    └── icon.png
```

```json
{
    "name": "Calculator",
    "identifier": "os.australis.calculator",
    "version": "1.0.0",
    "executable": "Calculator.exec",
    "icon": "Resources/icon.png",
    "type": "application"
}
```

## File extensions

### Australis OS specific

| Extension | Meaning | Example | Notes |
| --- | --- | --- | --- |
| `.appb` | Application | `Calculator.appb` | |
| `.exec` | Executable program | `Terminal.exec` | |
| `.service` | System service | `Network.service` | |
| `.driver` | Device driver | `Graphics.driver` | |
| `.library` | Program library | `Graphics.library` | |
| `.package` | Installation package | `installer.package` | |
| `.addon` | Application plugin | `Extension.addon` | |
| `.theme` | Visual theme | `Dark.theme` | |
| `.link` | File or application shortcut | `Browser.link` | |
| `.layout` | Desktop configuration | `Default.layout` | |
| `.icons` | Icon collection | `MODERN.icons` | |
| `.widget` | Desktop widget | `CLOCK.widget` | |
| `.settings` | Australis-specific configuration | `SYSTEM.settings` | |

### Standard formats

| Category | Extensions |
| --- | --- |
| Documents | `.txt`, `.pdf`, `.md` |
| Images | `.png`, `.jpg`, `.webp`, `.svg` |
| Video | `.mp4`, `.mkv`, `.webm` |
| Audio | `.mp3`, `.flac`, `.wav` |
| Archives | `.zip`, `.tar`, `.7z` |
| Configuration | `.json`, `.toml`, `.yaml` |
| Programming | `.hy`, `.c`, `.cpp`, `.py` |

##

Australlis should have a .OS file extension for executables managing the OS, and a seperate extension for thoes being managed by a .OS file... for example to system itself, self-manages so it should be a .OS file and the calculator app will be open within the SHELL.OS file, so it should be an .appl extension.
