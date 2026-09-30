{
  config,
  lib,
  androidPackages,
  pkgs,
  ...
}:
let
  cfg = config.androidDevices;
  recovery = cfg.recovery.enable;
  ramOnly = recovery;
  device = cfg.deviceName;
  firmware = androidPackages.packaging.runCommand "${device}-initrd-firmware" { } ''
    mkdir -p $out/lib/firmware
    ${lib.concatMapStringsSep "\n" (package: ''
      if test -d ${package}/lib/firmware; then
        chmod -R u+w $out/lib/firmware
        cp -r --no-preserve=mode ${package}/lib/firmware/. $out/lib/firmware/
      fi
    '') cfg.initrdFirmware}
  '';

in
{
  config = lib.mkIf cfg.enable {
    # Assemble with host tools; the contents remain target binaries.
    nixpkgs.overlays = [
      (_final: _prev: {
        makeInitrdNG =
          args:
          androidPackages.buildPackages.callPackage
            (pkgs.path + "/pkgs/build-support/kernel/make-initrd-ng.nix")
            (
              args
              // {
                makeInitrdNGTool = androidPackages.makeInitrdNGTool;
              }
            );
      })
    ];
    boot.initrd = {
      enable = true;
      includeDefaultModules = false;
      availableKernelModules = lib.mkForce [ ];
      kernelModules = lib.mkForce [ ];
      supportedFilesystems = [
        "ext4"
      ];
      compressor = "zstd";
      compressorArgs = [
        "-T0"
        "-6"
      ];
      systemd = {
        enable = true;
        emergencyAccess = true;
        managerEnvironment.SYSTEMD_SYSROOT_FSTAB = lib.mkIf ramOnly (
          lib.mkForce (androidPackages.packaging.writeText "mobile-recovery-fstab" "")
        );
        storePaths = [
          config.boot.initrd.systemd.managerEnvironment.SYSTEMD_SYSROOT_FSTAB
          "${config.boot.initrd.systemd.package}/lib/systemd/systemd-growfs"
        ];
        additionalUpstreamUnits = [ "systemd-growfs@.service" ];
        initrdBin = [
          pkgs.busybox
          pkgs.dtc
          pkgs.kmod
          pkgs.libgpiod
        ];
        # Prefer native systemd/coreutils over overlapping BusyBox applets.
        extraBin = {
          sh = "${pkgs.bash}/bin/sh";
          udevadm = "${config.boot.initrd.systemd.package}/bin/udevadm";
          systemctl = "${config.boot.initrd.systemd.package}/bin/systemctl";
          journalctl = "${config.boot.initrd.systemd.package}/bin/journalctl";
        };
        contents."/lib/firmware".source = "${firmware}/lib/firmware";
        # The boot contract requires built-in storage and USB. Keep stage-2
        # modules out of the initrd before device firmware is available.
        contents."/lib".enable = lib.mkForce false;
        targets.initrd.aliases = lib.mkIf ramOnly (lib.mkForce [ ]);
        targets.mobile-recovery = lib.mkIf ramOnly {
          description = "RAM-only mobile recovery";
          aliases = [ "default.target" ];
          wants = [
            "sysinit.target"
          ];
          after = [ "sysinit.target" ];
          unitConfig.AllowIsolate = true;
        };
        suppressedUnits = lib.optionals ramOnly [
          "initrd-switch-root.target"
          "initrd-switch-root.service"
          "initrd-root-fs.target"
          "initrd-root-device.target"
          "initrd-parse-etc.service"
          "initrd-cleanup.service"
          "initrd-find-nixos-closure.service"
          "initrd-nixos-activation.service"
        ];
        mounts = [
          {
            what = "tmpfs";
            where = "/tmp";
            type = "tmpfs";
            options = "mode=1777";
            wantedBy = [ "sysinit.target" ];
            before = [ "sysinit.target" ];
            unitConfig.DefaultDependencies = false;
          }
        ];
        services.mobile-deployment-complete = lib.mkIf (!ramOnly) {
          description = "Check mobile deployment completed before selecting a generation";
          requiredBy = [ "initrd-find-nixos-closure.service" ];
          before = [ "initrd-find-nixos-closure.service" ];
          after = [ "initrd-fs.target" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          script = ''
            if test -e /sysroot/var/lib/mobile-offline-rebuild/pending ||
               test -e /sysroot/var/lib/mobile-offline-deploy/pending ||
               test -e /sysroot/var/lib/mobile-efi-preparation/pending; then
              echo 'Complete the pending installation or deployment in RAM recovery first.' >&2
              exit 1
            fi
          '';
        };
      };
    };
    boot.kernelParams = [
      "rd.systemd.gpt_auto=no"
    ]
    ++ lib.optional ramOnly "rd.systemd.unit=mobile-recovery.target";
    boot.initrd.systemd.contents."/etc/fstab" = lib.mkIf ramOnly {
      text = lib.mkForce "";
    };
  };
}
