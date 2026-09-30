# Build the same pinned FAT/GPT implementation for host-side disk-file tests.
# nix build --impure --expr 'import ./tests/uboot-fat-sandbox.nix { flake = builtins.getFlake (toString ./.); }' --no-link
{ flake }:
let
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
in
(pkgs.buildUBoot {
  pname = "uboot-fat-sandbox";
  version = "2026.10-rc5";
  src = flake.legacyPackages.x86_64-linux.devices.asphalt.u-boot.firmware.src;
  defconfig = "sandbox_defconfig";
  extraConfig = ''
    # CONFIG_SANDBOX_SDL is not set
    # CONFIG_EFI_RUNTIME_UPDATE_CAPSULE is not set
    # CONFIG_EFI_CAPSULE_ON_DISK is not set
    # CONFIG_EFI_CAPSULE_FIRMWARE_RAW is not set
    CONFIG_FS_FAT_HANDLE_SECTOR_SIZE_MISMATCH=y
  '';
  filesToInstall = [
    "u-boot"
    "u-boot.dtb"
    ".config"
  ];
}).overrideAttrs
  (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [
      pkgs.xxd
      pkgs.pkg-config
    ];
  })
