{ flake }:
let
  # The VM and every backend run on x86_64; avoid build-host-for-target
  # splicing that drags AArch64 libraries into this standalone host test.
  host = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  packages = import ../pkgs { pkgs = host; };
  lib = host.lib;
in
host.testers.runNixOSTest {
  name = "usb-gadgets";
  node.specialArgs.androidPackages = packages;
  nodes.machine = { config, ... }: {
    imports = [ ../modules/mobile/usb-signaller.nix ];
    # Exercise the real shared USB module on an emulated UDC, without importing
    # a Qualcomm board or replacing the VM's x86 kernel with a phone kernel.
    options.androidDevices = {
      deviceName = lib.mkOption {
        type = lib.types.str;
        default = "usb-gadget-test";
      };
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      usb.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      recovery.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      usbSerial = lib.mkOption {
        type = lib.types.str;
        default = "usb-gadget-test";
      };
      usbController = lib.mkOption {
        type = lib.types.str;
        default = "dummy_udc.0";
      };
      kernelPackage = lib.mkOption {
        type = lib.types.raw;
        default = {
          config.isYes = _: true;
        };
      };
    };
    config = {
      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;
      networking.useDHCP = false;
      boot.kernelModules = [
        "dummy_hcd"
        "usb_f_hid"
        "hid_multitouch"
        "usb_f_mass_storage"
        "usb_storage"
        "usb_f_uvc"
        "uvcvideo"
        "cdc_ncm"
        "cdc_acm"
        "loop"
      ];
      environment.systemPackages = [
        host.python3
        host.usbutils
        host.v4l-utils
        host.dosfstools
        host.util-linux
      ];
      users.users.test = {
        isNormalUser = true;
        uid = 1000;
      };
      androidDevices.usb.acm.enable = true;
      androidDevices.usb.hidraw.enable = true;
      androidDevices.usb.signaller = {
        roleSwitch = "dummy";
        hidTouch.enable = true;
        massStorage = {
          enable = true;
          image = "/var/lib/usb/disk.img";
          readOnly = false;
        };
        uvc.enable = true;
        tethering.enable = true;
        mtp = {
          enable = true;
          user = "test";
          directories = [ "/home/test/USB-Share" ];
        };
      };
      systemd.tmpfiles.rules = [ "d /var/lib/usb 0700 root root -" ];
      systemd.services.usb-signaller.wantedBy = lib.mkForce [ ];
      systemd.services.usb-signaller.environment.USB_GADGET_CONFIG = "/run/test-gadgets.json";
      systemd.services.usb-signaller-touch-mode.environment.USB_GADGET_CONFIG = "/run/test-gadgets.json";
      systemd.services.usb-signaller-storage-mode.environment.USB_GADGET_CONFIG =
        "/run/test-gadgets.json";
      systemd.services.usb-signaller-uvc-mode.environment.USB_GADGET_CONFIG = "/run/test-gadgets.json";
    };
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("cp /etc/usb-signaller/gadgets.json /run/test-gadgets.json")
    machine.succeed("usb-storage-image create /var/lib/usb/disk.img --size-mib 64")
    machine.succeed("systemctl start usb-signaller")
    try:
        print(machine.succeed("python3 ${./usb-gadgets-integration.py}", timeout=180))
    except Exception:
        print(machine.execute("journalctl -b -u 'usb-signaller*' --no-pager")[1])
        raise
    machine.succeed("systemctl stop usb-signaller")
    machine.succeed("test -z \"$(ls /sys/kernel/config/usb_gadget)\"")
  '';
}
