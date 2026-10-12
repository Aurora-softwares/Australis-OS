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

Use the portable console and file APIs for ordinary application code:

```hylang
System.Console.Write("user> ");
string input = System.Console.ReadLine();
string contents = System.IO.File.ReadAllText("/hello.txt");
if (System.IO.File.Exists("/hello.txt")) {
    System.Console.Write(contents);
}
System.IO.File.WriteAllText("/data/last-input.txt", input);
int value = System.Convert.ToInt32("42");
```

`ReadLine` and `ReadAllText` return independent string values, so they can
be assigned to locals and remain valid after another read. AUEX v1 strings are
currently ASCII and limited to 255 bytes. Failed reads fault the application,
matching the existing native `ReadAllText` failure behavior.

These `System.*` names are the application portability layer. The compiler
selects Linux runtime calls or AUEX operations for the build target.
`System.Australis.*` is reserved for services with Australis-specific
semantics, including VFS metadata, directory enumeration, process yield, and
low-level checked memory operations.

The following Australis-specific calls provide lower-level terminal and file
access:

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
System.Australis.Files.ApiVersion()
System.Australis.Files.ResultByte(index)
System.Australis.Files.ResultU32(index)
System.Australis.Files.WriteResult()
System.Australis.Files.Status()
System.Australis.Process.Yield()
System.Australis.Memory.StoreByte(address, value)
```

`ApiVersion()` returns `1` for this AUEX file API. `WriteResult` writes the
bytes returned by the most recent terminal read, checked file read, or
directory-name call. `ResultByte(index)` and `ResultU32(index)` read one byte
or four little-endian bytes from the last checked file read or directory name;
an out-of-range index returns `-1` and sets status `1`. `DirectoryName` returns
the name length; at the end it returns `-1` with status `5`. `DirectoryCount` and the metadata
queries return `-1` on error; `Status()` gives the corresponding VFS status.
Mutations and checked open/close calls return a VFS status directly (`0` for
success). Read capacities must be literals. `Stat*`, `DirectoryCount`,
`DirectoryName`, `OpenRead`, and `OpenWrite` accept argument paths; create,
delete, and rename still require literal paths. Written contents remain ASCII
literals. Directory indices and truncate lengths may be scalar expressions.
`StoreByte` is exposed for low
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

The compiler allocates initialized strings, a shared low-level read buffer, and
portable returned strings inside the program's checked 64 KiB data region.
Portable reads advance through that bounded region so an earlier string remains
valid after a later read. Scalar locals and expression values live in fixed,
checked VM storage. The compiler emits the AUEX header and both CRCs. Division
or remainder by zero faults only the application. The instruction limit still
terminates an infinite loop and releases its descriptors.

The AUEX backend populates `args` for shell-launched programs. Applications
can read `args.Length` and `args[index]`, compare argument strings with ASCII
literals, inspect their length, and print them. For example:

```hylang
public class Program {
    public static int Main(string[] args) {
        for (int i = 0; i < args.Length; i = i + 1) {
            System.Console.WriteLine(args[i]);
        }
        return 0;
    }
}
```

The shell passes `-an`, `--argument`, and paths as separate unchanged tokens;
each app interprets its own options. Quotes or backslash-escaped spaces group
one argument. The current limit is 16 arguments and a 256-byte shell line.
An app can pass an argument string to the checked read and metadata calls.
For example, `inspector /Bin/inspector.exec` reports its filesystem metadata
and AUEX header, while `inspector /System` lists that directory. With no path,
Inspector uses `/hello.txt`.
Application method calls, general strings and arrays, and process creation
remain future work tracked in `src/userland/README.md`.

## Including separate repositories in the OS image

`Applications.hyproj` is an aggregate project. Add each checked out app
project to its `project_references` list. Every referenced app selects its
root filesystem name through `output`. Plain `.exec` filenames go in the
root and `/Bin` of the HyFS 2 image. An output under `system/` is installed in
`/System` of the HyFS 2 image; for example, `system/hexviewer.exec` becomes
`/System/hexviewer.exec`.
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
On a HyFS 2 boot, the shell's default `PATH` is `/System:/Bin:/`, so typing
`hexviewer` runs `/System/hexviewer.exec`. `PATH=/System:/Bin` changes the
search list for the current shell session, and `path` displays it. Both bare
commands and explicit `run /path/program.exec` pass trailing arguments to
`Main(string[] args)`.
