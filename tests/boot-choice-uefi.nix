# Same-slot integration is opt-in; it never reuses the legacy slot-switch action.
{ flake }:
flake.inputs.nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    env = flake.lib.mkBuildEnvironment {
      inherit buildSystem;
      config.allowUnfree = true;
    };
    base = env.nixosSystem {
      modules = [
        flake.nixosModules.dodge
        {
          androidDevices.persistentImage.enable = true;
          system.stateVersion = "26.11";
        }
      ];
    };
    candidate = base.extendModules { modules = [ { hardware.dodge.bootChoice.enable = true; } ]; };
    c = candidate.config;
    entries = c.boot.loader.systemd-boot.extraEntries;
    files = c.boot.loader.systemd-boot.extraFiles;
  in
  assert !base.config.androidDevices.boot.uefi.bootChoice.enable;
  assert !(c.system.build ? mobileBootImage);
  assert !c.androidDevices.boot.standaloneFirmwareImage;
  assert !(flake.legacyPackages.${buildSystem}.devices.dodge ? u-boot);
  assert
    c.androidDevices.boot.firmwarePackage.drvPath
    == flake.legacyPackages.${buildSystem}.devices.dodge.boot-firmware.drvPath;
  assert !base.config.androidDevices.boot.actions.androidSameSlot;
  assert c.androidDevices.boot.uefi.bootChoice.enable;
  assert flake.inputs.nixpkgs.lib.any (
    p:
    (p.pname or "") == "boot-choice-native"
    && p.stdenv.buildPlatform.system == buildSystem
    && p.stdenv.hostPlatform.config == "aarch64-unknown-linux-musl"
  ) c.environment.systemPackages;
  assert
    !(flake.inputs.nixpkgs.lib.any (
      p: (p.pname or "") == "boot-choice-native"
    ) base.config.environment.systemPackages);
  assert c.androidDevices.boot.actions.androidSameSlot;
  assert !c.androidDevices.boot.actions.android;
  assert !(entries ? "android-system.conf");
  # Neither enable nor disable may add native-owned paths to upstream's
  # .extra-files deletion tracker. Bootstrap is a guarded runtime hook only.
  assert !(entries ? "android-same-slot.conf");
  assert !(files ? "EFI/android-devices/boot-choice.efi");
  assert !(base.config.boot.loader.systemd-boot.extraEntries ? "android-same-slot.conf");
  assert !(base.config.boot.loader.systemd-boot.extraFiles ? "EFI/android-devices/boot-choice.efi");
  assert flake.inputs.nixpkgs.lib.hasInfix "install-boot-choice.py"
    c.boot.loader.systemd-boot.extraInstallCommands;
  assert
    !(flake.inputs.nixpkgs.lib.hasInfix "install-boot-choice.py" base.config.boot.loader.systemd-boot.extraInstallCommands);
  assert flake.inputs.nixpkgs.lib.all (a: a.assertion) c.assertions;
  {
    helper = c.androidDevices.boot.uefi.bootChoice.package.drvPath;
    bootFiles = c.system.build.mobileBootFiles.drvPath;
    bootstrap = c.boot.loader.systemd-boot.extraInstallCommands;
    installer = c.system.build.installBootLoader.drvPath;
  }
)
