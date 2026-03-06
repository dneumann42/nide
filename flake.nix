{
  description = "bench - A productive development tool for Nim";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      buildFlatpak = pkgs.writeShellApplication {
        name = "build-flatpak";
        runtimeInputs = with pkgs; [ nimble flatpak-builder flatpak ];
        text = ''
          set -euo pipefail

          MANIFEST="flatpak/io.github.dneumann42.Bench.yml"
          BUILD_DIR=".flatpak-build"
          REPO_DIR=".flatpak-repo"

          echo "Building bench binary..."
          nimble build -y

          echo "Adding Flathub remote (if missing)..."
          flatpak remote-add --user --if-not-exists flathub \
            https://flathub.org/repo/flathub.flatpakrepo || true

          echo "Installing KDE 6.7 runtime (if missing)..."
          flatpak install --user --noninteractive flathub \
            org.kde.Platform//6.7 org.kde.Sdk//6.7 || true

          echo "Building flatpak..."
          flatpak-builder \
            --force-clean \
            --user \
            --install-deps-from=flathub \
            --repo="$REPO_DIR" \
            "$BUILD_DIR" \
            "$MANIFEST"

          echo "Bundling bench.flatpak..."
          flatpak build-bundle \
            --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
            "$REPO_DIR" \
            bench.flatpak \
            io.github.dneumann42.Bench

          echo "Done: bench.flatpak"
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
          qt6.full
          pkg-config
          flatpak-builder
          flatpak
        ];
      };
    };
}
