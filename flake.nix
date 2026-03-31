{
  description = "nide - A productive development tool for Nim";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      buildFlatpak = pkgs.writeShellApplication {
        name = "build-flatpak";
        runtimeInputs = with pkgs; [ flatpak-builder flatpak librsvg patchelf ];
        text = ''
          set -euo pipefail

          MANIFEST="flatpak/io.github.dneumann42.Nide.yml"
          BUILD_DIR=".flatpak-build"
          REPO_DIR=".flatpak-repo"

          echo "Building nide binary..."
          _pkgbin=$(mktemp -d)
          printf '#!/bin/sh\nPKG_CONFIG_PATH=/usr/lib/pkgconfig exec /usr/bin/pkg-config "$@"\n' \
            > "$_pkgbin/pkg-config"
          chmod +x "$_pkgbin/pkg-config"
          export PATH="$_pkgbin:$PATH"
          rm -rf ~/.cache/nim/nide_r
          nim cpp -d:release --passL:"-L/usr/lib -Wl,-rpath-link,/usr/lib" --out:nide src/nide.nim
          patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 nide
          patchelf --set-rpath "" nide

          echo "Adding Flathub remote (if missing)..."
          flatpak remote-add --user --if-not-exists flathub \
            https://flathub.org/repo/flathub.flatpakrepo || true

          echo "Installing KDE 6.10 runtime (if missing)..."
          flatpak install --user --noninteractive flathub \
            org.kde.Platform//6.10 org.kde.Sdk//6.10 || true

          echo "Converting icon to PNG..."
          rsvg-convert -w 128 -h 128 data/icons/io.github.dneumann42.Nide.svg \
            -o data/icons/io.github.dneumann42.Nide.png

          echo "Building flatpak..."
          flatpak-builder \
            --force-clean \
            --disable-rofiles-fuse \
            --user \
            --install-deps-from=flathub \
            --repo="$REPO_DIR" \
            "$BUILD_DIR" \
            "$MANIFEST"

          echo "Bundling nide.flatpak..."
          flatpak build-bundle \
            --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
            "$REPO_DIR" \
            nide.flatpak \
            io.github.dneumann42.Nide

          echo "Done: nide.flatpak"
        '';
      };
    in {
      packages.${system}.build-flatpak = buildFlatpak;

      apps.${system}.build-flatpak = {
        type = "app";
        program = "${buildFlatpak}/bin/build-flatpak";
      };

      devShells.${system}.default =
        let
          libs = with pkgs; [
            qt6.qtbase
            qt6.qtsvg
            sqlite
            pcre
          ];
        in
        pkgs.mkShell {
          buildInputs = libs ++ (with pkgs; [ pkg-config flatpak-builder flatpak ]);
          shellHook = ''
            export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath libs}:$LD_LIBRARY_PATH

            # Auto-install nimble deps if nimble.paths references missing packages.
            # nimble's lock/install has a bug with git URLs containing '#branch' —
            # the '#' ends up in a temp directory name that breaks. This workaround
            # installs deps individually and regenerates nimble.paths from whatever
            # is actually present in ~/.nimble/pkgs2.
            _nide_check_deps() {
              local missing=0
              if [ -f nimble.paths ]; then
                while IFS= read -r line; do
                  case "$line" in --path:*)
                    local p
                    p="''${line#--path:}"
                    p="''${p%\"}"
                    p="''${p#\"}"
                    [ -d "$p" ] || missing=1
                  ;; esac
                done < nimble.paths
              else
                missing=1
              fi
              echo $missing
            }

            if [ "$(_nide_check_deps)" = "1" ]; then
              echo "[nide] Installing nimble dependencies..."
              nimble install "https://github.com/seaqt/nim-seaqt.git@#qt-6.4" -y 2>/dev/null || true
              nimble install "db_connector >= 0.1.0" -y 2>/dev/null || true
              nimble install "toml_serialization >= 0.2.18" -y 2>/dev/null || true

              echo "[nide] Regenerating nimble.paths..."
              {
                echo "--noNimblePath"
                for pkg in seaqt unittest2 db_connector toml_serialization stew results serialization faststreams; do
                  local p
                  p="$(nimble path "$pkg" 2>/dev/null | tail -1)" || true
                  if [ -n "$p" ] && [ -d "$p" ]; then
                    echo "--path:\"$p\""
                  fi
                done
                echo "--path:\"$(pwd)/src\""
              } > nimble.paths
              echo "[nide] Dependencies ready."
            fi
          '';
        };
    };
}
