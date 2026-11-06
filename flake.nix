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
          codexVersion = "0.166.0";
          codexRelease =
            {
              x86_64-linux = {
                url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-x86_64-unknown-linux-musl.tar.gz";
                hash = "sha256-HUSyi8SsmTfX01MiZLqmilB842SVag1Ou4VvMxze4lQ=";
              };
              aarch64-linux = {
                url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-aarch64-unknown-linux-musl.tar.gz";
                hash = "sha256-eCG3fdouYoP7H2PzFlF3onHaiDPoV89nPGyhyds7/MY=";
              };
              x86_64-darwin = {
                url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-x86_64-apple-darwin.tar.gz";
                hash = "sha256-HLZWkCML5ZgsZUuiZV46O1lNzpxVt4Dni/3+/4Kdetk=";
              };
              aarch64-darwin = {
                url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-aarch64-apple-darwin.tar.gz";
                hash = "sha256-VaRAy1eflwq+fHmrGB5UsOpMQZvpnzM7vYaO66ycIfA=";
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
          claudeVersion = "2.1.318";
          claudeRelease =
            {
              x86_64-linux = {
                url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/linux-x64/claude";
                hash = "sha256-cIx3sgTbMAhv9vHtNFd72gPhvnTO2AVXy/e1Qknr8L0=";
              };
              aarch64-linux = {
                url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/linux-arm64/claude";
                hash = "sha256-U6DX4hnXsIBOy6XbwAJ0Xon3hsyUbS3oWmRw1bLR+wY=";
              };
              x86_64-darwin = {
                url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/darwin-x64/claude";
                hash = "sha256-7pyFd6Uoqo76R4v1UrF++kC7WKpJgdKRPBPTg6TUCaQ=";
              };
              aarch64-darwin = {
                url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/darwin-arm64/claude";
                hash = "sha256-Z3oup79XbO3SDhkdlzkU7YpBeW9TpjsZIzgd3E1bXn0=";
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
      linuxBrowserDeps =
        pkgs:
        with pkgs;
        lib.optionals stdenv.isLinux [
          alsa-lib
          at-spi2-atk
          at-spi2-core
          cairo
          cups
          dbus
          expat
          glib
          gtk3
          libdrm
          libgbm
          libnotify
          libsecret
          mesa
          nspr
          nss
          pango
          systemd
          libxcb
          libxkbcommon
          libX11
          libXcomposite
          libXcursor
          libXdamage
          libXext
          libXfixes
          libXi
          libXrandr
          libXrender
          libXScrnSaver
          libXtst
        ];
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
                ${lib.optionalString pkgs.stdenv.isLinux ''
                  export LD_LIBRARY_PATH="${lib.makeLibraryPath (linuxBrowserDeps pkgs)}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                ''}

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
        in
        {
          default = pkgs.mkShell {
            packages = [
              (pkgs.writeShellScriptBin "t3" ''
                exec ${pkgs.nodejs_24}/bin/node "$T3CODE_DEV_CLI" "$@"
              '')
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
            ++ linuxBrowserDeps pkgs;

            env = lib.optionalAttrs pkgs.stdenv.isLinux {
              LD_LIBRARY_PATH = lib.makeLibraryPath (linuxBrowserDeps pkgs);
            };

            shellHook = ''
              export T3CODE_DEV_CLI="$PWD/apps/server/dist/bin.mjs"
              echo "T3 Code dev shell"
            '';
          };
        }
      );
    };
}
