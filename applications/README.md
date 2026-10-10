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
hydrogen-stage1 new exec Example
```

Build one application directly with:

```bash
hydrogen-stage1 build Example/Example.hyproj -o example.exec
```

## Available AUEX calls

An AUEX v1 entry point is `static void Main(string[] args)` or
`static int Main(string[] args)`. The compiler currently accepts a linear
sequence of these calls and a final literal return code:

```text
System.Console.WriteLine("text")
System.Australis.Terminal.Write("text")
System.Australis.Terminal.WriteLine("text")
System.Australis.Terminal.ReadLine(capacity)
System.Australis.Terminal.WriteResult()
System.Australis.Files.Open("/path")
System.Australis.Files.Read(capacity)
System.Australis.Files.Close()
System.Australis.Process.Yield()
System.Australis.Memory.StoreByte(address, value)
```

`WriteResult` writes the bytes returned by the most recent terminal or file
read. Read capacities and return codes must be literals. Paths and output must
be ASCII literals. `StoreByte` is exposed for low level tests; normal programs
should use terminal and file operations.

The compiler allocates initialized strings and a shared read buffer inside the
program's checked 64 KiB data region. It emits the AUEX header and both CRCs.

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
