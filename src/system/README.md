# Australis OS System

## Core layout

```text
BOOTX64.EFI
│
KERNEL.BIN
│
ASTRALIS.OS
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
    "identifier": "os.astralis.calculator",
    "version": "1.0.0",
    "executable": "Calculator.exec",
    "icon": "Resources/icon.png",
    "type": "application"
}
```

## File extensions

### Australis OS specific

| Extension | Meaning | Example | Notes |
|---|---|---|---|
| `.appl` | Application | `Calculator.appl` | More distinctive alternative to `.app` |
| `.exec` | Executable program | `Terminal.exec` | Clear, readable name |
| `.serv` | System service | `Network.serv` | Short for service |
| `.driv` | Device driver | `Graphics.driv` | Short for driver |
| `.libr` | Program library | `Graphics.libr` | Alternative to `.lib` |
| `.inst` | Installation package | `Browser.inst` | Intuitive, but already used elsewhere |
| `.plug` | Application plugin | `Extension.plug` | Already has some existing uses |
| `.skin` | Visual theme | `Dark.skin` | Established uses in other software |
| `.link` | File or application shortcut | `Browser.link` | Already used by some software |
| `.desk` | Desktop configuration | `Default.desk` | Candidate worth considering |
| `.icns` | Icon collection | `MODERN.icns` | This is an apple standard for icons... need to think of something more unique |
| `.wdgt` | Desktop widget | `CLOCK.wdgt` | |
| `.cfg` | Astralis-specific configuration | `SYSTEM.cfg` | .cfg is widely used, may be worth using it as its already open and used but also good to have something better for internal use. |

### Standard formats

| Category | Extensions |
|---|---|
| Documents | `.txt`, `.pdf`, `.md` |
| Images | `.png`, `.jpg`, `.webp`, `.svg` |
| Video | `.mp4`, `.mkv`, `.webm` |
| Audio | `.mp3`, `.flac`, `.wav` |
| Archives | `.zip`, `.tar`, `.7z` |
| Configuration | `.json`, `.toml`, `.yaml` |
| Programming | `.hy`, `.c`, `.cpp`, `.py` |

##
Australlis should have a .OS file extension for executables managing the OS, and a seperate extension for thoes being managed by a .OS file... for example to system itself, self-manages so it should be a .OS file and the calculator app will be open within the SHELL.OS file, so it should be an .appl extension.
