{
  lib,
  stdenv,
  gnu-efi,
}:
assert stdenv.hostPlatform.isAarch64;
stdenv.mkDerivation {
  pname = "mobile-boot-action";
  version = "1";
  src = lib.cleanSource ./.;
  buildInputs = [ gnu-efi ];
  hardeningDisable = [ "all" ];
  dontConfigure = true;
  dontFixup = true;
  buildPhase = ''
    runHook preBuild
    $CC -I${gnu-efi}/include/efi -I${gnu-efi}/include/efi/aarch64 \
      -fpic -ffreestanding -fno-stack-protector -fshort-wchar -fno-strict-aliasing \
      -Wall -Wextra -Werror -c main.c -o main.o
    $LD -nostdlib --no-undefined -znocombreloc -shared -Bsymbolic \
      --defsym=EFI_SUBSYSTEM=10 -T ${gnu-efi}/lib/elf_aarch64_efi_local.lds \
      ${gnu-efi}/lib/crt0-efi-aarch64-local.o main.o \
      -L${gnu-efi}/lib -lefi -lgnuefi -o mobile-boot-action.so
    # GNU EFI's AArch64 crt0 already supplies the PE/COFF header.
    $OBJCOPY -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
      -j .rodata -j .rel -j .rela -j '.rel.*' -j '.rela.*' -j .reloc -O binary \
      mobile-boot-action.so mobile-boot-action.efi
    runHook postBuild
  '';
  installPhase = ''
    install -Dm644 mobile-boot-action.efi $out/mobile-boot-action.efi
  '';
  meta = {
    description = "Confirmed OEM reboot targets for compatible mobile U-Boot firmware";
    license = lib.licenses.gpl2Plus;
    platforms = [ "aarch64-linux" ];
  };
}
