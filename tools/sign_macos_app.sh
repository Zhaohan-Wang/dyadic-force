#!/bin/zsh
set -euo pipefail

# Godot 的 ad-hoc 导出会带上 hardened runtime。在本机 macOS 上，
# LaunchServices / 双击打开会因此被直接杀掉。导出后去掉 runtime 再签一次。

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
	echo "Usage: $0 /path/to/DyadicForce.app" >&2
	exit 2
fi

ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
cat > "$ENTITLEMENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
	<key>com.apple.security.cs.allow-dyld-environment-variables</key>
	<true/>
</dict>
</plist>
EOF

xattr -cr "$APP"
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed for local launch: $APP"
