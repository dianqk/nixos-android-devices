# From the repository root:
# nix build --impure --expr 'import ./tests/usb-signaller-acm.nix { flake = builtins.getFlake (toString ./.); }' --out-link tmp/acm-test
# sudo python3 tests/usb-signaller-acm.py tmp/acm-test/bin/usb-signaller
# The runner owns a new dummy_hcd instance; it never accepts a physical UDC.
{
  flake,
  system ? builtins.currentSystem,
}:
flake.packages.${system}.usb-signaller.overrideAttrs (old: {
  pname = "usb-signaller-acm-test";
  postPatch = old.postPatch + ''
    cp ${./usb-signaller-acm.rs} src/main.rs
  '';
  # No physical controller or D-Bus service is touched by this fixture.
})
