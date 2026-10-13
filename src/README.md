# Australis system architecture

Australis uses four boundaries: the bootloader, the kernel, system userland,
and application userland. The GUI is part of userland. It receives graphics
and input through kernel interfaces and does not run inside the kernel.

## Responsibility map

| Layer | Owns |
| --- | --- |
| Bootloader | Loads and validates the kernel, captures firmware state, leaves boot services, and enters the kernel. |
| Kernel | CPU state, memory protection, processes, scheduling, system calls, VFS, interrupts, and hardware drivers. |
| System userland | System startup, service supervision, device and mount policy, login, sessions, settings, and application launch policy. |
| GUI userland | Display server, compositor, window protocol, input routing, desktop shell, and graphical session programs. |
| Applications | Command-line tools and graphical programs using public userland APIs. |

Drivers initially remain in the kernel because the current AHCI, NVMe, xHCI,
terminal, and framebuffer paths already work there. A later capability and IPC
model may allow selected drivers to move into isolated user processes.

## Runtime layout

```text
BOOTX64.EFI
    |
    v
KERNEL.BIN
    | mounts the root filesystem and starts PID 1
    v
System.exec                     system manager / PID 1
    |-- ServiceManager
    |   |-- Device.service      inventory and hotplug policy
    |   |-- Storage.service     volume and mount policy
    |   `-- Network.service     network configuration and policy
    |
    |-- Launch.service          manifest resolution and launch policy
    |
    `-- Session.service
        |
        |-- Login.exec
        |
        `-- User session
            |
            |-- CommandShell.exec
            |
            `-- graphical session, when enabled
                |
                |-- Display.service
                |   |-- compositor
                |   |-- window protocol
                |   `-- input routing
                |
                |-- DesktopShell.appb
                |   |-- desktop
                |   |-- taskbar
                |   `-- notifications
                |
                `-- applications
                    |-- Explorer.appb
                    |-- Terminal.appb
                    `-- Calculator.appb
```

`System.exec` is the first user process. The kernel starts it after mounting
the root filesystem. The system manager supervises services and creates a
session. A text-only boot can start `CommandShell.exec` without starting any
GUI component.

The former `SYSTEM.EFI` placeholder has been retired. It will be replaced by
the user executable described above once process arguments, process waiting,
and service supervision exist.

## Source layout

The repository has separate bootloader, kernel, userland, shell, and rescue
projects. The OS-owned userland directories below are the intended layout as
the corresponding components are implemented:

```text
src/
|-- bootloader/                    UEFI boot stage
|-- kernel/                        privileged kernel
|-- rescue/                        optional disk-backed rescue program
|-- shell/                         future userland command shell
`-- userland/
    |-- system/                    PID 1 and service supervision
    |-- services/                  core system services
    |-- libraries/                 shared user APIs and protocols
    |-- commands/                  cat, ls, version, echo, pwd, ...
    `-- gui/
        |-- display/               display server and compositor
        |-- session/               login and graphical session startup
        `-- desktop/               desktop shell components

applications/                     separately versioned application repos
```

The `src/userland` tree contains components shipped as part of the operating
system. Independently versioned programs remain under `applications` while
checked out for an image build and may live in their own repositories.

## Filesystem layout

The default HyFS 2 image already creates `/System`, `/System/Core`, `/Bin`,
`/Applications`, `/Users`, `/Volumes`, and `/Temporary`. The entries under
`/System` below are the intended packaged system layout; `System.exec` and
services are not yet installed. The retained HyFS 1 compatibility image
contains only flat root files:

```text
/System/
|-- Core/System.exec
|-- Services/*.service
|-- Libraries/*.library
|-- Drivers/*.driver
|-- Settings/*.settings
`-- Resources/
/Bin/*.exec
/Applications/*.appb
/Users/<name>/
/Volumes/<name>/
/Temporary/
```

`/Bin` is the default location for command-line programs. The current kernel
recovery shell searches `PATH=/System:/Bin:/`. The first userland shell should
use `PATH=/Bin:/System` until a `/System/Bin` directory is actually packaged.
A command containing `/` is resolved directly; other commands are searched in
`PATH`, with `.exec` appended when the name has no extension.

## Shell and process boundary

The shell owns command parsing, environment expansion, `PATH` lookup, and
foreground job control. The kernel owns process creation, argument transfer,
waiting, termination, and resource cleanup.

Most commands become external programs:

| External program | Kernel interface required |
| --- | --- |
| `cat.exec` | Arguments, dynamic paths, open/read/close, and EOF/error results. |
| `ls.exec` | Directory enumeration and file metadata. |
| `version.exec` | Read-only system information. |
| `echo.exec` | Arguments and terminal output. |
| `pwd.exec` | Process working-directory query. |
| `devices.exec` | Read-only device inventory. |
| `mounts.exec` | Read-only mount inventory. |
| `ps.exec` | Read-only process inventory. |

Commands that change the shell process remain built-ins: `cd`, `set`,
`export`, `unset`, `exit`, and later `jobs`, `fg`, and `bg`.

## Executables and bundles

An extension identifies packaging and intent. Privilege comes from the loader,
manifest, signature, and granted capabilities rather than the filename.

| Extension | Meaning | Example |
| --- | --- | --- |
| `.exec` | Executable payload | `cat.exec` |
| `.os` | System component bundle | `System.os` |
| `.appb` | Graphical or packaged application bundle | `Calculator.appb` |
| `.service` | Supervised service bundle | `Storage.service` |
| `.driver` | Driver package | `Graphics.driver` |
| `.library` | Userland library | `Graphics.library` |
| `.package` | Installable package | `calculator.package` |
| `.addon` | Application plugin | `Markdown.addon` |
| `.theme` | Theme bundle | `Dark.theme` |
| `.link` | File or application shortcut | `Browser.link` |
| `.layout` | Desktop or window layout | `Default.layout` |
| `.icons` | Icon collection | `Modern.icons` |
| `.widget` | Desktop widget | `Clock.widget` |
| `.settings` | Australis settings data | `System.settings` |

The canonical suffixes are lowercase so paths behave consistently on
case-sensitive filesystems. Product names may retain normal capitalization,
as in `System.os` and `Calculator.appb`.

### Application bundle

```text
Calculator.appb/
|-- manifest.json
|-- Calculator.exec
`-- Resources/
    `-- icon.png
```

```json
{
    "name": "Calculator",
    "identifier": "os.australis.calculator",
    "version": "1.0.0",
    "executable": "Calculator.exec",
    "icon": "Resources/icon.png",
    "type": "application",
    "capabilities": []
}
```

### System component bundle

```text
System.os/
|-- manifest.json
|-- System.exec
`-- Resources/
```

A `.os` bundle is reserved for an operating-system component managed by the
system manager. It is still a user process. It does not gain kernel privilege
from its extension.
The first PID 1 milestone installs a direct executable at
`/System/Core/System.exec`; the `System.os` bundle layout is a later packaging
format for that component. See `userland/system/README.md` for the startup
contract and `rescue/README.md` for the fallback boundary.

## Standard data formats

| Category | Extensions |
| --- | --- |
| Documents | `.txt`, `.pdf`, `.md` |
| Images | `.png`, `.jpg`, `.webp`, `.svg` |
| Video | `.mp4`, `.mkv`, `.webm` |
| Audio | `.mp3`, `.flac`, `.wav` |
| Archives | `.zip`, `.tar`, `.7z` |
| Configuration | `.json`, `.toml`, `.yaml` |
| Programming | `.hy`, `.c`, `.cpp`, `.py` |

## Design rules

1. The bootloader loads the kernel; it does not start desktop applications.
2. The kernel exposes mechanisms and enforces isolation; userland chooses
   service, session, launch, and desktop policy.
3. The GUI remains optional. Text-only boot must remain usable over COM1 and
   the framebuffer terminal.
4. System services use the same process and executable model as applications,
   with explicit capabilities and supervision.
5. Application bundles contain resources and metadata; `.exec` remains the
   executable payload format.
6. Public system calls and IPC protocols are versioned before services depend
   on them.
