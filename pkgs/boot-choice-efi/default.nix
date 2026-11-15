{ lib, stdenv, rustPlatform, gnu-efi }:
assert stdenv.hostPlatform.isAarch64;
rustPlatform.buildRustPackage {
  pname = "boot-choice-efi";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.intersection (lib.fileset.gitTracked ../..)
      (lib.fileset.unions [ ./. ../../tools/boot-choice ]);
  };
  cargoRoot = "pkgs/boot-choice-efi";
  buildAndTestSubdir = "pkgs/boot-choice-efi";
  cargoHash = "sha256-/i/qMhFBa7H/UHOWJKjEVhmEiwh4DmygouYR2TwClb4=";
  buildInputs = [ gnu-efi ];
  hardeningDisable = [ "all" ];
  dontFixup = true;
  NIX_DONT_SET_RPATH = "1";
  doCheck = false; # host tests are run separately; this build is freestanding
  RUSTFLAGS = "-C panic=abort -C relocation-model=pic";
  postBuild = ''
    cd pkgs/boot-choice-efi
    $CC -I${gnu-efi}/include/efi -I${gnu-efi}/include/efi/aarch64 \
      -fpic -ffreestanding -fno-builtin -fno-stack-protector -fshort-wchar -fno-strict-aliasing \
      -Wall -Wextra -Werror -c transport.c -o transport.o
    # No unwind runtime in firmware; discard only unused unwind metadata.
    sed -e '/  .eh_frame /d; /  .eh_frame_hdr /d; /  .gcc_except_table /d' \
      -e '/^SECTIONS/{n;a\  /DISCARD/ : { *(.eh_frame*) *(.gcc_except_table*) *(.data.DW.ref.*) }
      }' \
      ${gnu-efi}/lib/elf_aarch64_efi_local.lds > firmware.lds
    $OBJCOPY --remove-section=.data.DW.ref.rust_eh_personality --remove-section=.eh_frame --remove-section=".gcc_except_table*" \
      --strip-symbol=rust_eh_personality \
      ../../target/${stdenv.hostPlatform.rust.rustcTarget}/release/libboot_choice_efi.a firmware.a
    NIX_LDFLAGS="" $LD -nostdlib --no-undefined --gc-sections --exclude-libs=ALL -znocombreloc -shared -Bsymbolic \
      --defsym=EFI_SUBSYSTEM=10 -T firmware.lds \
      ${gnu-efi}/lib/crt0-efi-aarch64-local.o transport.o \
      firmware.a \
      -L${gnu-efi}/lib -lefi -lgnuefi -o boot-choice.so
    $OBJCOPY -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
      -j .rodata -j .rel -j .rela -j '.rel.*' -j '.rela.*' -j .reloc -O binary \
      boot-choice.so boot-choice.efi
    cd ../..
  '';
  installPhase = ''
    install -Dm644 pkgs/boot-choice-efi/boot-choice.efi $out/boot-choice.efi
    install -Dm644 pkgs/boot-choice-efi/boot-choice.so $out/lib/boot-choice.so
  '';
  meta = {
    description = "Transactional, independently verified same-slot owned-image UEFI boot-choice helper";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
