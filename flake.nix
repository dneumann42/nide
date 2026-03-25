{
  description = "nide - A productive development tool for Nim";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nim
          nimble
          qt6.qtbase
          qt6.wrapQtAppsHook
          pkg-config
          flatpak-builder
          flatpak
        ];
      };
    };
}
