# Australis `.exec` applications

Each application is a normal format 2 Hylang project. Keep the source and its
`.hyproj` file together so the directory can live in its own repository.

```toml
format = 2
name = "Example"
version = "0.1.0"
type = "exec"
output = "example.exec"
sources = ["Program.hy"]
project_references = []
```

Create a new project with:

```bash
hy new exec Example
```

Build one application directly with:

```bash
hy build Example/Example.hyproj -o example.exec
```

## Available AUEX calls

An AUEX v1 entry point is `static void Main(string[] args)` or
`static int Main(string[] args)`. Application code can use scoped integer and
Boolean locals, assignment, `+`, `-`, `*`, `/`, `%`, unary `-` and `!`, all six
comparisons, `&&`, `||`, `if`/`else`, `while`, `for`, `break`, and `continue`.
Integer and Boolean values can be written with `System.Console.Write` and
`System.Console.WriteLine`, and `Main` can return a computed exit code.

```hylang
public class Program {
    public static int Main(string[] args) {
        int total = 0;
        for (int i = 1; i <= 5; i = i + 1) {
            total = total + i;
        }
        System.Console.WriteLine(total);
        return total;
    }
}
```

The following Australis calls provide terminal and file access:

```text
System.Console.WriteLine("text")
System.Australis.Terminal.Write("text")
System.Australis.Terminal.WriteLine("text")
System.Australis.Terminal.ReadLine(capacity)
System.Australis.Terminal.WriteResult()
System.Australis.Files.Open("/path")
System.Australis.Files.Read(capacity)
System.Australis.Files.Close()
System.Australis.Files.OpenRead("/path")
System.Australis.Files.OpenWrite("/data/path")
System.Australis.Files.ReadChecked(capacity)
System.Australis.Files.Replace("ASCII contents")
System.Australis.Files.Append("ASCII contents")
System.Australis.Files.Truncate(length)
System.Australis.Files.CloseChecked()
System.Australis.Files.Create("/data/path", "ASCII contents")
System.Australis.Files.Delete("/data/path")
System.Australis.Files.Mkdir("/data/folder")
System.Australis.Files.Rmdir("/data/folder")
System.Australis.Files.Rename("/data/old", "/data/new")
System.Australis.Files.StatKind("/path")
System.Australis.Files.StatSize("/path")
System.Australis.Files.StatId("/path")
System.Australis.Files.StatCreated("/path")
System.Australis.Files.StatModified("/path")
System.Australis.Files.StatTimeFlags("/path")
System.Australis.Files.StatAttributes("/path")
System.Australis.Files.DirectoryCount("/folder")
System.Australis.Files.DirectoryName("/folder", index)
System.Australis.Files.WriteResult()
System.Australis.Files.Status()
System.Australis.Process.Yield()
System.Australis.Memory.StoreByte(address, value)
```

`WriteResult` writes the bytes returned by the most recent terminal read,
checked file read, or directory-name call. `DirectoryName` returns the name
length; a negative result means an error. `DirectoryCount` and the metadata
queries return `-1` on error; `Status()` gives the corresponding VFS status.
Mutations and checked open/close calls return a VFS status directly (`0` for
success). Read capacities must be literals. The current AUEX compiler requires
file paths and written contents to be ASCII literals; directory indices and
truncate lengths may be scalar expressions. `StoreByte` is exposed for low
level tests; normal programs should use terminal and file operations.
`StatKind` returns `1` for a file and `2` for a directory. In
`StatTimeFlags`, bit 0 marks a known creation time and bit 1 marks a known
modification time; a missing timestamp must be treated as unavailable.

Filesystem status values are: `0` success, `1` invalid argument, `2` mount
failure, `3` not mounted, `4` not found, `5` end of file, `6` I/O failure,
`7` corrupt, `8` read-only, `9` already exists, `10` nonempty directory,
`11` no space, `12` stale handle, and `13` cross-volume rename. A raw HyFS 2
data partition mounts writable at `/data` by default. The boot and USB mounts
remain read-only; ordinary applications write through checked VFS calls.

The compiler allocates initialized strings and a shared read buffer inside the
program's checked 64 KiB data region. Scalar locals and expression values live
in fixed, checked VM storage. The compiler emits the AUEX header and both CRCs.
Division or remainder by zero faults only the application. The instruction
limit still terminates an infinite loop and releases its descriptors.

The current structured backend does not yet populate `args`, call application
methods, or provide general strings, arrays, and process creation. Those
features are tracked in `src/userland/README.md`.

## Including separate repositories in the OS image

`Applications.hyproj` is an aggregate project. Add each checked out app
project to its `project_references` list. Every referenced app selects its
root filesystem name through `output`, which must be a plain `.exec` filename.
The repositories may be outside this repository because project references
are resolved relative to the aggregate manifest.

You can keep a separate aggregate beside your app repositories and build an
image with it:

```bash
make iso APPLICATIONS_PROJECT=/path/to/MyApplications.hyproj
```

An application repository may also publish a prebuilt `.exec`. Include one or
more such artifacts without adding project references:

```bash
make iso APPLICATION_ARTIFACTS="/path/Calculator.exec /path/Editor.exec"
```

The standard build compiles the default aggregate into `build/applications`,
stages those executables with the static files under `rootfs`, and then creates
the HyFS image. No Python program generator is involved.

Use `make applications` when you only want to rebuild the `.exec` files.
