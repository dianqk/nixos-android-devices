{ flake }:
flake.inputs.nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
  buildSystem:
  let
    lib = flake.inputs.nixpkgs.lib;
    env = flake.lib.mkBuildEnvironment { inherit buildSystem; };
    config =
      (env.nixosSystem {
        modules = [
          flake.nixosModules.polaris
          (flake.outPath + "/examples/polaris/minimal.nix")
        ];
      }).config;
  in
  assert lib.all (a: a.assertion) config.assertions;
  assert lib.filterAttrs (_: user: user.isNormalUser) config.users.users == { };
  assert config.services.getty.autologinUser == "root";
  assert config.systemd.defaultUnit == "multi-user.target";
  assert !config.services.xserver.enable && !config.programs.sway.enable;
  assert !config.hardware.bluetooth.enable && !config.services.pipewire.enable;
  assert !config.networking.networkmanager.enable && !config.networking.wireless.enable;
  assert !(config.systemd.services ? modem-rmtfs);
  assert !(config.systemd.services ? polaris-pd-mapper);
  assert config.boot.loader.systemd-boot.enable;
  assert config.fileSystems."/".autoResize && !config.boot.growPartition;
  assert config.systemd.services ? usb-signaller;
  assert config.systemd.services.usb-signaller.wantedBy == [ "multi-user.target" ];
  assert config.systemd.network.networks."10-mobile-usb".networkConfig.DHCPServer;
  assert config.services.openssh.enable;
  assert config.services.openssh.settings.PermitRootLogin == "yes";
  assert config.services.openssh.settings.PermitEmptyPasswords;
  assert config.security.pam.services.sshd.allowNullPassword;
  assert config.services.openssh.startWhenNeeded;
  assert config.systemd.sockets.sshd.socketConfig.FreeBind;
  assert config.services.openssh.settings.PasswordAuthentication;
  assert config.users.users.root.hashedPassword == "";
  assert config.users.users.root.openssh.authorizedKeys.keys == [ ];
  assert !config.services.openssh.openFirewall;
  assert map (a: a.addr) config.services.openssh.listenAddresses == [ "172.16.42.1" ];
  assert !(builtins.elem 22 config.networking.firewall.allowedTCPPorts);
  assert builtins.elem 22 config.networking.firewall.interfaces.usb0.allowedTCPPorts;
  assert config.nix.enable;
  assert !config.nixpkgs.flake.setFlakeRegistry && !config.nixpkgs.flake.setNixPath;
  {
    system = config.system.build.toplevel.drvPath;
    rootfs = config.system.build.mobileSystemImage.drvPath;
    bootFiles = config.system.build.mobileBootFiles.drvPath;
  }
)
