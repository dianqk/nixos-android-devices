#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Host-only: build a freestanding library and execute its real EFI entry against
# RAM firmware services. Requires a canonical owned flag-3 host-file fixture.
set -euo pipefail
: "${BOOT_CHOICE_IMAGE:?set a regular owned flag-3 image file}"
: "${GNU_EFI:?set the native GNU-EFI package directory}"
: "${TEST_OUTPUT:?set an existing host evidence/cache directory}"
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$TEST_OUTPUT/fixture"
export BOOT_CHOICE_TEST_EXPORT="$TEST_OUTPUT/fixture"
cargo test --release --offline --manifest-path "$root/pkgs/boot-choice-efi/Cargo.toml" export_efi_fixture -- --ignored
cargo build --release --offline --manifest-path "$root/pkgs/boot-choice-efi/Cargo.toml"
objcopy --remove-section=.data.DW.ref.rust_eh_personality --remove-section=.eh_frame \
  --remove-section='.gcc_except_table*' --strip-symbol=rust_eh_personality \
  "$root/pkgs/boot-choice-efi/target/release/libboot_choice_efi.a" "$TEST_OUTPUT/host-firmware.a"
extra=()
if [[ -n "${UBOOT_SOURCE:-}" ]]; then
  python3 "$root/tests/boot-choice-file-open.py"
  extra=(-DUSE_PRODUCTION_OPEN "$TEST_OUTPUT/production-open.o")
fi
cc "${extra[@]}" -I"$GNU_EFI/include/efi" -I"$GNU_EFI/include/efi/$(uname -m)" \
  -fshort-wchar -fno-builtin -Wall -Wextra -Werror \
  "$root/tests/boot-choice-efi-execution.c" "$TEST_OUTPUT/host-firmware.a" -o "$TEST_OUTPUT/efi-execution"
time "$TEST_OUTPUT/efi-execution" "$TEST_OUTPUT/fixture"
