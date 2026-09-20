# rushi-tui-mermaid-ext

A `rushi` TUI extension that renders `fence:mermaid` code blocks as
Unicode box-drawing art. It is the reference `transform` extension
(stage 3 of the kernel's `ui-extension-plan`).

## What it does

When a message contains a ` ```mermaid ` fence, the host extracts the
fence body and sends it to this binary. The binary parses the Mermaid
source with the `mermaid-text` crate and replies with the rendered
Unicode art. The host then replaces the fence with the art in the TUI.

Failure is quiet. If the source does not parse, or the render is wider
than the host's width budget, the binary sends no reply. The host then
shows the raw fence instead (the per-operation G5 fallback). So a broken
or over-wide diagram never erases the block. It just stays a code
fence.

## Protocol

One JSON line per request on `stdin`, one `transformed` reply on
`stdout`. The host sends `transform` requests scoped to
`fence:mermaid`. The reply carries the art as a list of lines under the
same `req` id. See `ext.toml` for the manifest fields (`command`,
`caps = ["transform"]`, `transform = ["fence:mermaid"]`,
`protocol_v = 1`).

## Layout

```
Cargo.toml       standalone cargo package, [[bin]] name = "mermaid-ext"
Cargo.lock
ext.toml         [ext] manifest, command = "target/debug/mermaid-ext"
src/main.rs      the stdin/stdout transform binary
flake.nix        the extension flake (Mode B)
```

The `ext.toml` `command` is a path relative to the entry dir. The host
resolves it against the entry directory, so no `PATH` export is needed
for the global layer.

## The Nix flake

`flake.nix` exposes one UI-extension package, `packages.<system>.mermaid-ext`
(`default` aliases it). The package's `$out` is the UI-extension
contract:

```
$out/mermaid/ext.toml
$out/mermaid/target/debug/mermaid-ext
```

The binary lands under `target/debug/` to match the `ext.toml`
`command` path, even though `buildRustPackage` produces a release
binary. That is the `binDir = "target/debug"` invariant from the
ext-flake-authoring guide. The package also declares
`meta.rushi.ext = "mermaid"` so the kernel's `lib.mkRushi` can fill the
consumer's `[ui_extensions]` enabled list at eval time.

Wire it into a consumer flake with:

```nix
rushi.external_ui_extensions = [
  mermaidExtFlake.packages.${system}.mermaid-ext
];
```

## Build (local, no Nix)

The crate is standalone. Build the debug binary the `ext.toml` points
at:

```sh
cargo build          # binary lands in ./target/debug/mermaid-ext
```

The kernel's `ext-env.sh` already builds this crate and puts its
`target/debug` dir on `PATH` for the local global layer.
