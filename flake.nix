# The `rushi-tui-mermaid-ext` extension flake (Mode B, per
# docs/reference/nix/ext-flake-authoring.md).
#
# A single UI-extension package: a small Rust binary that renders
# `fence:mermaid` code blocks as Unicode box-drawing art. A consumer
# wires it into a `rushi` package via `rushi.external_ui_extensions`:
#
#   rushi.external_ui_extensions = [
#     mermaidExtFlake.packages.${system}.mermaid-ext
#   ]
#
# The package $out is the UI-extension $out contract (P1):
#   $out/mermaid/ext.toml
#   $out/mermaid/target/debug/mermaid-ext (matches ext.toml `command`)

{
  description = "rushi-tui-mermaid-ext — mermaid TUI transform extension for rushi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, fenix }:
    let
      # Mirror the kernel flake list + genAttrs (not flake-utils
      # eachDefaultSystem, which transposes the result and breaks
      # nix develop / per-system devShells).
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      pkgLib = nixpkgs.lib;

      buildFor = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          rustToolchain = fenix.packages.${system}.stable.withComponents [
            "cargo" "clippy" "rust-src" "rustc" "rustfmt" "rust-analyzer"
          ];

          # `self` is the git tree of this repo, so untracked build
          # artifacts (target/, sessions/) are already excluded. A
          # consumer fetching this flake from GitHub gets the same
          # tree. The crate root is the repo root, so the whole tree
          # is the source (no intra-repo path deps to worry about).
          src = "${self}";

          # This crate lives at the repo root: a standalone package with
          # an empty `[workspace]` table, detached from any parent
          # workspace. There are no intra-repo path deps, so the source
          # root *is* the crate. The `[[bin]]` name in Cargo.toml is the
          # binary name (mermaid-ext).
          built = pkgs.rustPlatform.buildRustPackage {
            pname = "mermaid-ext";
            version = "0.1.0";
            inherit src;
            nativeBuildInputs = [ rustToolchain ];
            cargoLock = { lockFile = "${self}/Cargo.lock"; };
            doCheck = false;
          };

          # UI-ext wrapper: $out/<ext>/ext.toml + <ext>/<binDir>/<bin>.
          # `binDir` must equal the relative `command` path in ext.toml,
          # because the TUI resolves `command` against the ext entry dir.
          # This ext.toml points at `target/debug/mermaid-ext` (a dev-build
          # artifact of the monorepo ext-env.sh), so pass binDir =
          # "target/debug". buildRustPackage's release binary is copied
          # there. Same `version` + placeholder-`src` requirement as the
          # doc skeleton.
          wrapped = pkgs.stdenv.mkDerivation {
            pname = "mermaid-ui-ext";
            version = "0.1.0";
            src = pkgs.writeTextFile {
              name = "mermaid-ext-src";
              destination = "/placeholder";
              text = "";
            };
            nativeBuildInputs = [ built ];
            installPhase = ''
              mkdir -p $out/mermaid/target/debug
              cp ${self}/ext.toml $out/mermaid/ext.toml
              cp -rL ${built}/bin/. $out/mermaid/target/debug/
            '';
            # Issue #13: declare the UI-ext entry dir. lib.mkRushi reads
            # meta.rushi.ext at eval time and fills the consumer
            # [ui_extensions] enabled list with "mermaid".
            meta = {
              description = "mermaid UI extension for rushi";
              rushi = { ext = "mermaid"; };
            };
          };
        in
        rec {
          mermaid-ext = wrapped;
          default = mermaid-ext;
        };
    in
    {
      # Top-level `packages` (system as the inner key) is the standard
      # flake shape: `nix build .` resolves packages.<host>.default,
      # and the consumer reads extFlake.packages.<system>.<name>.
      packages = pkgLib.genAttrs supportedSystems (system: buildFor system);
    };
}
