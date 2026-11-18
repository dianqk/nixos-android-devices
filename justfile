# Build repository examples; see docs/development.md and docs/development.zh.md.
set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

# Enable the CLI for these commands, preserving any caller-provided Nix settings.
export NIX_CONFIG := env("NIX_CONFIG", "") + "\nextra-experimental-features = nix-command flakes"

# List commands without evaluating or building the flake.
default:
    @just --list

# List supported device codenames.
devices:
    nix eval --json --file lib/devices.nix --apply builtins.attrNames

# List a device's artifact names (including nested groups such as minimal).
artifacts device:
    nix eval --no-update-lock-file --json ".#devices.$1" --apply 'attrs: builtins.filter (name: name != "recurseForDerivations") (builtins.attrNames attrs)'

# Build one artifact: just build unicorn kernel --max-jobs 1 --cores 8
build device artifact="system" *args:
    device="$1"; artifact="$2"; shift 2; nix build --no-update-lock-file --print-build-logs ".#devices.$device.$artifact" --out-link "result-$device-$artifact" "$@"

# Preview builds and cache downloads without building or creating an output link.
plan device artifact="system" *args:
    device="$1"; artifact="$2"; shift 2; nix build --no-update-lock-file --dry-run --no-link ".#devices.$device.$artifact" "$@"

# Evaluate an artifact's derivation path without building it.
drv device artifact="system" *args:
    device="$1"; artifact="$2"; shift 2; nix eval --no-update-lock-file --raw ".#devices.$device.$artifact.drvPath" "$@"

# Read an artifact's available build log.
log device artifact="kernel" *args:
    device="$1"; artifact="$2"; shift 2; nix log --no-update-lock-file ".#devices.$device.$artifact" "$@"

# Show the store path and closure size of an existing output link.
size path:
    nix path-info --closure-size --human-readable "$1"

# Evaluate checks without builds; add --all-systems to cover both build platforms.
eval *args:
    nix flake check --no-update-lock-file --no-build --option allow-import-from-derivation false "$@"

# Evaluate and build the current platform's flake checks (host-only tests).
check *args:
    nix flake check --no-update-lock-file --print-build-logs --option allow-import-from-derivation false "$@"

# Run one named check on the current Nix platform: just check-one public-api
check-one name *args:
    system="$(nix eval --impure --raw --expr builtins.currentSystem)"; name="$1"; shift; nix build --no-update-lock-file --no-link --print-build-logs --option allow-import-from-derivation false ".#checks.$system.$name" "$@"

# Enter the LLVM/ccache kernel shell, or pass --command COMMAND ARG...
dev *args:
    nix develop --no-update-lock-file .#kernel "$@"

# Enter a shell with host Android, deployment and kernel tools.
tools *args:
    nix shell --no-update-lock-file .#android-tools .#mobile-device .#kernel-tools "$@"

# Run mobile-device; pass its usual explicit target and operation arguments.
mobile *args:
    nix run --no-update-lock-file .#mobile-device -- "$@"

# Import, verify, export or prepare a kernel queue; see: just queue --help
queue +args:
    python3 tools/kernel-queue.py "$@"
