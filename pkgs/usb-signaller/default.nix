{
  lib,
  rustPlatform,
  fetchFromCodeberg,
  pkg-config,
  systemd,
  util-linux,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "usb-signaller";
  version = "0.4.2";
  src = fetchFromCodeberg {
    owner = "DylanVanAssche";
    repo = "usb-signaller";
    rev = "v${finalAttrs.version}";
    hash = "sha256-c4wI6sHHiCad18t62dD9SEgdmoo0S+BO22wUGytIJ0Q=";
  };
  cargoHash = "sha256-cmsxh7ZjU4z2LvwsnqZNlS5P9aeL05eZrg+mPDR9ShQ=";
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ systemd ];
  patches = [
    ./nixos-integration.patch
    ./optional-acm.patch
  ];
  postPatch = ''
    substituteInPlace src/service.rs \
      --replace-fail /usr/bin/systemctl ${systemd}/bin/systemctl \
      --replace-fail 'Command::new("systemctl")' 'Command::new("${systemd}/bin/systemctl")'
    substituteInPlace src/sysfs.rs \
      --replace-fail 'Command::new("mount")' 'Command::new("${util-linux}/bin/mount")' \
      --replace-fail 'Command::new("umount")' 'Command::new("${util-linux}/bin/umount")' \
      --replace-fail 'sysfs_symlink("/sys", "/home")' 'sysfs_symlink("/", ".")' \
      --replace-fail 'sysfs_mkdir("/sys")' 'sysfs_mkdir("/")'
  '';
  meta = {
    description = "USB gadget and role manager for mainline Linux mobile devices";
    homepage = "https://codeberg.org/DylanVanAssche/usb-signaller";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "usb-signaller";
  };
})
