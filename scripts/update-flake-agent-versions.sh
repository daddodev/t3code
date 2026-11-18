#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flake_file="${FLAKE_FILE:-$repo_root/flake.nix}"
codex_version="${1:-}"
claude_version="${2:-}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $0 [codex-version] [claude-version]"
  echo "Omit either version to use the latest release."
  exit 0
fi

for command in curl jq nix perl; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

if [[ -z "$codex_version" ]]; then
  codex_version="$(curl -fsSL https://api.github.com/repos/openai/codex/releases/latest | jq -r '.tag_name | ltrimstr("rust-v")')"
fi

if [[ -z "$claude_version" ]]; then
  claude_version="$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)"
fi

claude_manifest="$(mktemp)"
trap 'rm -f "$claude_manifest"' EXIT
curl -fsSL "https://downloads.claude.ai/claude-code-releases/$claude_version/manifest.json" -o "$claude_manifest"

prefetch_hash() {
  nix store prefetch-file --json "$1" | jq -r '.hash'
}

claude_hash() {
  local platform="$1"
  local checksum
  checksum="$(jq -r --arg platform "$platform" '.platforms[$platform].checksum' "$claude_manifest")"
  nix hash convert --hash-algo sha256 --to sri "$checksum"
}

export CODEX_VERSION="$codex_version"
export CLAUDE_VERSION="$claude_version"
export CODEX_X86_64_LINUX_HASH="$(prefetch_hash "https://github.com/openai/codex/releases/download/rust-v$codex_version/codex-package-x86_64-unknown-linux-musl.tar.gz")"
export CODEX_AARCH64_LINUX_HASH="$(prefetch_hash "https://github.com/openai/codex/releases/download/rust-v$codex_version/codex-package-aarch64-unknown-linux-musl.tar.gz")"
export CODEX_X86_64_DARWIN_HASH="$(prefetch_hash "https://github.com/openai/codex/releases/download/rust-v$codex_version/codex-package-x86_64-apple-darwin.tar.gz")"
export CODEX_AARCH64_DARWIN_HASH="$(prefetch_hash "https://github.com/openai/codex/releases/download/rust-v$codex_version/codex-package-aarch64-apple-darwin.tar.gz")"
export CLAUDE_X86_64_LINUX_HASH="$(claude_hash linux-x64)"
export CLAUDE_AARCH64_LINUX_HASH="$(claude_hash linux-arm64)"
export CLAUDE_X86_64_DARWIN_HASH="$(claude_hash darwin-x64)"
export CLAUDE_AARCH64_DARWIN_HASH="$(claude_hash darwin-arm64)"

perl -0pi -e '
  s/(codexVersion = ")[^"]+(")/$1$ENV{CODEX_VERSION}$2/;
  s/(claudeVersion = ")[^"]+(")/$1$ENV{CLAUDE_VERSION}$2/;
  for my $tool_config (
    ["CODEX", qr{github\.com/openai/codex}],
    ["CLAUDE", qr{downloads\.claude\.ai/claude-code-releases}],
  ) {
    my ($tool, $url_pattern) = @$tool_config;
    for my $system (
      ["x86_64-linux", "X86_64_LINUX"],
      ["aarch64-linux", "AARCH64_LINUX"],
      ["x86_64-darwin", "X86_64_DARWIN"],
      ["aarch64-darwin", "AARCH64_DARWIN"],
    ) {
      my ($nix_system, $environment_system) = @$system;
      my $hash = $ENV{"${tool}_${environment_system}_HASH"};
      $hash or die "Missing ${tool}_${environment_system}_HASH\n";
      my $changed = s{(${nix_system} = \{\n\s+url = "[^"]*${url_pattern}[^"]*";\n\s+hash = ")[^"]+(")}{${1}${hash}${2}};
      $changed == 1 or die "Could not update ${tool} hash for ${nix_system}\n";
    }
  }
' "$flake_file"

echo "Updated Codex to $codex_version and Claude Code to $claude_version in $flake_file"
