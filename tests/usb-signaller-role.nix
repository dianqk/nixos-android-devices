{
  flake,
  system ? builtins.currentSystem,
}:
let
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
in
flake.packages.${system}.usb-signaller.overrideAttrs (old: {
  pname = "usb-signaller-role-test";
  nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ pkgs.dbus ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    env -u USB_SIGNALLER_MANAGE_ROLE dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- "$out/bin/usb-signaller"
    USB_SIGNALLER_MANAGE_ROLE=0 dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- "$out/bin/usb-signaller"
    USB_SIGNALLER_MANAGE_ROLE=1 dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- "$out/bin/usb-signaller"
    USB_SIGNALLER_ACM_SERVICE=serial-getty@ttyGS0.service USB_SIGNALLER_MANAGE_ROLE=0 dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- "$out/bin/usb-signaller"
    USB_SIGNALLER_ACM_SERVICE=serial-getty@ttyGS0.service USB_SIGNALLER_MANAGE_ROLE=1 dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- "$out/bin/usb-signaller"
    runHook postInstallCheck
  '';
  postPatch = old.postPatch + ''
    cp ${./usb-signaller-role.rs} src/main.rs
  '';
})
