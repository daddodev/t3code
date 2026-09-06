{
  description = "T3 Code development shell";

  nixConfig = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      mkCodex =
        pkgs:
        let
          codexVersion = "0.153.4";
          codexRelease =
            {
              x86_64-linux = {
                url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-x86_64-unknown-linux-musl.tar.gz";
                hash = "sha256-qCIYfhokIMYcWSZyG/vYeHAe2VVHybsNTeRJiha6GCE=";
              };
              aarch64-linux = {
                url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-aarch64-unknown-linux-musl.tar.gz";
                hash = "sha256-/DlcsEOhCTqw2zT0Sroxmb+qnOZAzZvn/ViPRLDaZKQ=";
              };
              x86_64-darwin = {
                url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-x86_64-apple-darwin.tar.gz";
                hash = "sha256-PuY41xVchW7zHz9Khcshld4ZOZYtOSTJNbJPBRRWSj0=";
              };
              aarch64-darwin = {
                url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-aarch64-apple-darwin.tar.gz";
                hash = "sha256-NUONofv3ptt92zvOyERI+mAVuhiEYUcql9nR2n2cQ1M=";
              };
            }
            .${pkgs.stdenv.hostPlatform.system};
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "codex";
          version = codexVersion;
          src = pkgs.fetchurl codexRelease;
          nativeBuildInputs = with pkgs; [
            gnutar
            gzip
          ];
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p "$out"
            tar -xzf "$src" -C "$out"
            chmod -R u+w "$out"
            runHook postInstall
          '';
        };
      mkClaude =
        pkgs:
        let
          claudeVersion = "2.1.263";
          claudeRelease =
            {
              x86_64-linux = {
                url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/linux-x64/claude";
                hash = "sha256-JtAgNR6BEvQAZ5Dzz85DtMnfDBux0OVCNk1kFRuB1bo=";
              };
              aarch64-linux = {
                url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/linux-arm64/claude";
                hash = "sha256-fSXXyK5sbgCcx9rk6Bf2dBef0x+3dhvNVv7kwpArTAM=";
              };
              x86_64-darwin = {
                url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/darwin-x64/claude";
                hash = "sha256-qUqLIp+oXDoxbGtKNeCqIr7BqrvT0UIoJs4dEN3Ih1E=";
              };
              aarch64-darwin = {
                url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/darwin-arm64/claude";
                hash = "sha256-710pCcivSfMattVIfpAxZ3e8L6wXCt/oFgcWyqiq9Pk=";
              };
            }
            .${pkgs.stdenv.hostPlatform.system};
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "claude-code";
          version = claudeVersion;
          src = pkgs.fetchurl claudeRelease;
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          # Claude bundles Bun. Stripping the executable makes it run as Bun instead of Claude.
          dontStrip = true;
          nativeBuildInputs = [ pkgs.makeWrapper ] ++ lib.optional pkgs.stdenv.isLinux pkgs.autoPatchelfHook;
          buildInputs = lib.optional pkgs.stdenv.isLinux pkgs.alsa-lib;
          installPhase = ''
            runHook preInstall
            install -Dm755 "$src" "$out/bin/claude-code"
            makeWrapper "$out/bin/claude-code" "$out/bin/claude" \
              --set DISABLE_AUTOUPDATER 1 \
              --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
              --set DISABLE_INSTALLATION_CHECKS 1 \
              --set USE_BUILTIN_RIPGREP 0 \
              ${lib.optionalString pkgs.stdenv.isLinux ''
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [ pkgs.alsa-lib ]} \
              ''}--prefix PATH : ${
                pkgs.lib.makeBinPath (
                  [
                    pkgs.procps
                    pkgs.ripgrep
                  ]
                  ++ lib.optionals pkgs.stdenv.isLinux [
                    pkgs.bubblewrap
                    pkgs.socat
                  ]
                )
              }
            runHook postInstall
          '';
        };
      forEachSystem = f: lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      formatter = forEachSystem (pkgs: pkgs.nixfmt-rfc-style);

      packages = forEachSystem (
        pkgs:
        let
          codex = mkCodex pkgs;
          claude = mkClaude pkgs;
          mkT3Code =
            name: command:
            pkgs.writeShellApplication {
              inherit name;
              runtimeInputs = [
                pkgs.bun
                claude
                codex
                pkgs.nodejs_24
              ];
              text = ''
                bun install --backend=copyfile --frozen-lockfile
                export PATH="$PWD/node_modules/.bin:$PATH"

                exec ${command} "$@"
              '';
            };
          t3code = mkT3Code "t3code" "bun run start";
          t3code-dev = mkT3Code "t3code-dev" "bun scripts/dev-runner.ts dev";
        in
        {
          inherit claude codex;
          default = t3code;
          start = t3code;
          dev = t3code-dev;
        }
      );

      apps = forEachSystem (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.start}/bin/t3code";
        };
        start = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.start}/bin/t3code";
        };
        dev = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.dev}/bin/t3code-dev";
        };
      });

      devShells = forEachSystem (
        pkgs:
        let
          codex = mkCodex pkgs;
          claude = mkClaude pkgs;
          linuxElectronDeps =
            with pkgs;
            lib.optionals stdenv.isLinux [
              alsa-lib
              at-spi2-atk
              cairo
              cups
              dbus
              expat
              gtk3
              libdrm
              libnotify
              mesa
              nspr
              nss
              pango
              xorg.libX11
              xorg.libXcomposite
              xorg.libXcursor
              xorg.libXdamage
              xorg.libXext
              xorg.libXfixes
              xorg.libXi
              xorg.libXrandr
              xorg.libXrender
              xorg.libXScrnSaver
              xorg.libXtst
            ];
        in
        {
          default = pkgs.mkShell {
            packages = [
              claude
              codex
              pkgs.bun
              pkgs.gh
              pkgs.git
              pkgs.gnumake
              pkgs.nodejs_24
              pkgs.pkg-config
              pkgs.python312
            ]
            ++ linuxElectronDeps;

            shellHook = ''
              echo "T3 Code dev shell"
            '';
          };
        }
      );
    };
}
