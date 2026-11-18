# Sourced by the two direct-compiler scripts. Respect an explicitly selected SDK.
if [[ -z "${SDKROOT:-}" ]]; then
    developer_dir="$(xcode-select -p)"
    for candidate in "$developer_dir/SDKs/MacOSX.sdk" "$developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"; do
        if [[ -d "$candidate" ]]; then export SDKROOT="$candidate"; break; fi
    done
fi
