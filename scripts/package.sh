#!/usr/bin/env bash
# Builds release packages for every platform into ./artifacts.
# Used by .github/workflows/release.yml; also runs locally (needs the .NET 10 SDK and Node.js).
#
#   scripts/package.sh 1.2.3
#
# Produces:
#   dayone-mcp-win-x64.zip          DayOneMcp.exe + install.ps1 + README.md   (used by install.ps1)
#   dayone-mcp-win-x64.mcpb         Claude Desktop extension (double-click to install)
#   dayone-mcp-<rid>.tar.gz         osx-arm64, osx-x64, linux-x64, linux-arm64 (used by install.sh)
#   SHA256SUMS.txt

set -euo pipefail
VERSION="${1:?usage: scripts/package.sh <version, e.g. 1.2.3>}"
VERSION="${VERSION#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/artifacts"
BUILD="$(mktemp -d)"; trap 'rm -rf "$BUILD"' EXIT
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

rm -rf "$OUT"; mkdir -p "$OUT"

for RID in win-x64 osx-arm64 osx-x64 linux-x64 linux-arm64; do
  echo "==> Publishing $RID"
  dotnet publish "$ROOT/src/DayOneMcp" -c Release -r "$RID" -p:Version="$VERSION" -o "$BUILD/$RID" --nologo -v quiet
  if [ "$RID" = "win-x64" ]; then
    cp "$ROOT/install.ps1" "$ROOT/README.md" "$BUILD/$RID/"
    (cd "$BUILD/$RID" && zip -q -9 "$OUT/dayone-mcp-$RID.zip" DayOneMcp.exe install.ps1 README.md)
  else
    tar -czf "$OUT/dayone-mcp-$RID.tar.gz" -C "$BUILD/$RID" DayOneMcp
  fi
done

echo "==> Building Claude Desktop extension (.mcpb)"
MCPB="$BUILD/mcpb"
mkdir -p "$MCPB/server"
cp "$BUILD/win-x64/DayOneMcp.exe" "$MCPB/server/"
sed "s/\"version\": \"0.0.0\"/\"version\": \"$VERSION\"/" "$ROOT/packaging/mcpb/manifest.json" > "$MCPB/manifest.json"
[ -f "$ROOT/packaging/mcpb/icon.png" ] && cp "$ROOT/packaging/mcpb/icon.png" "$MCPB/"
npx --yes @anthropic-ai/mcpb@2.1.2 validate "$MCPB/manifest.json"
npx --yes @anthropic-ai/mcpb@2.1.2 pack "$MCPB" "$OUT/dayone-mcp-win-x64.mcpb"

echo "==> Checksums"
(cd "$OUT" && sha256sum dayone-mcp-* > SHA256SUMS.txt && cat SHA256SUMS.txt)
ls -la "$OUT"
