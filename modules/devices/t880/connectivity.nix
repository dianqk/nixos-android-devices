# T880 Wi-Fi: the MediaTek connsys drivers (conninfra, connfem,
# wmt_chrdev_wifi, gen4m) built out of tree, plus the boot-time bring-up the
# stock Android HAL does: feed the per-device NVRAM from nvdata, then power
# Wi-Fi on. The proprietary connsys files are not shipped: the user provides
# them either as `firmwarePackage` (installed with hardware.firmware) or in
# `firmwareDirectory` on the device (see docs/t880.md).
{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.t880.connectivity;
  # The files these drivers request (stock /vendor/firmware names). The
  # Wi-Fi and Bluetooth firmware itself is loaded by LK from
  # connsys_{wifi,bt}_<slot>; the Bluetooth driver also reads BT_FW.cfg
  # (antenna and TSSI settings).
  firmwareFiles = [
    "conninfra.cfg"
    "connfem.cfg"
  ]
  ++ lib.optional cfg.bluetooth.enable "BT_FW.cfg";
  # Where the bring-up checks for the files before powering anything on.
  firmwareRoot =
    if cfg.firmwarePackage != null then "${cfg.firmwarePackage}/lib/firmware" else cfg.firmwareDirectory;
  bringUp = androidPackages.packaging.writeShellApplication {
    name = "t880-wifi-up";
    runtimeInputs = with pkgs; [
      coreutils
      kmod
      util-linux
    ];
    text = ''
      run=/run/t880-wifi
      for f in ${lib.escapeShellArgs firmwareFiles}; do
        [ -e "${firmwareRoot}/$f" ] || { echo "missing ${firmwareRoot}/$f" >&2; exit 1; }
      done

      modprobe wlan_drv_gen4m_6897
      for _ in $(seq 50); do [ -c /dev/wmtWifi ] && break; sleep 0.1; done
      [ -c /dev/wmtWifi ] || { echo "no /dev/wmtWifi" >&2; exit 1; }

      # Per-device calibration: read-only from nvdata, kept in tmpfs only.
      nvdata=$(readlink -f ${lib.escapeShellArg cfg.nvramPartition})
      blockdev --setro "$nvdata"
      mkdir -p "$run/nvdata"
      mount -o ro,noload,nodev,nosuid,noexec "$nvdata" "$run/nvdata"
      trap 'umount "$run/nvdata" 2>/dev/null || true; rm -f "$run/wrbuf"' EXIT
      size=$(stat -c %s "$run/nvdata/APCFG/APRDEB/WIFI")
      { printf 'WR-BUF:NVRAM'; cat "$run/nvdata/APCFG/APRDEB/WIFI"; } > "$run/wrbuf"
      ${lib.optionalString cfg.bluetooth.enable ''
        # The Bluetooth address (first 6 bytes of BT_Addr, display order).
        bdaddr=$(od -A n -t x1 -N 6 "$run/nvdata/APCFG/APRDEB/BT_Addr" | tr -s ' ' | sed 's/^ //;s/ $//;s/ /:/g')
      ''}
      umount "$run/nvdata"
      # The NVRAM must arrive in a single write.
      dd if="$run/wrbuf" of=/dev/wmtWifi bs=$((size + 12)) count=1 status=none
      rm -f "$run/wrbuf"
      ${lib.optionalString cfg.bluetooth.enable ''
        # Bluetooth registers next, so conninfra runs the stock BT + Wi-Fi
        # pre-calibration before either radio is powered on.
        modprobe bt_drv_6897 bdaddr="$bdaddr"
        unset bdaddr
      ''}

      # Power Wi-Fi on; this waits for the first pre-calibration.
      if ! printf 1 > /dev/wmtWifi; then
        echo "Wi-Fi power-on failed during the connsys pre-calibration" >&2
        ${if cfg.bluetooth.enable then ''
          # After a power-on started by the charger, the bootloader may skip
          # loading the connsys firmware; the Bluetooth pre-calibration then
          # fails and takes Wi-Fi with it. Retry once without Bluetooth.
          echo "retrying without Bluetooth" >&2
          modprobe -r bt_drv_6897 || true
          sleep 1
          if ! printf 1 > /dev/wmtWifi; then
            echo "Wi-Fi still fails: the bootloader probably did not load the connsys firmware in this boot (charger-started power-on); a normal reboot restores Wi-Fi and Bluetooth" >&2
            exit 1
          fi
        '' else ''
          exit 1
        ''}
      fi
      for _ in $(seq 100); do [ -e /sys/class/net/wlan0 ] && exit 0; sleep 0.1; done
      echo "wlan0 did not appear" >&2
      exit 1
    '';
  };
in
{
  options.hardware.t880.connectivity = {
    enable = lib.mkEnableOption "Wi-Fi through the MediaTek connsys drivers" // {
      default = !config.androidDevices.recovery.enable;
      defaultText = lib.literalExpression "!config.androidDevices.recovery.enable";
    };
    firmwarePackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression ''
        androidPackages.devices.t880.firmware.override {
          firmware-source = androidPackages.mkFirmwareArchive {
            name = "t880-firmware-source";
            url = "…";
            hash = "…";
          };
        }
      '';
      description = ''
        Package with the stock connsys files in `lib/firmware`
        (${lib.concatStringsSep ", " firmwareFiles}), installed through
        hardware.firmware. When null, the files are taken from
        `firmwareDirectory` on the device instead.
      '';
    };
    firmwareDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/android-devices/t880-firmware";
      description = ''
        Directory on the device with the stock connsys files, used when
        `firmwarePackage` is null. The files are linked into /lib/firmware.
        They are proprietary and not provided here; the bring-up is skipped
        while the directory is missing.
      '';
    };
    bluetooth.enable = lib.mkEnableOption ''
      Bluetooth through the MediaTek bt_drv (EXPERIMENTAL). The controller
      registers with the kernel Bluetooth stack (BlueZ) with the device's
      address from nvdata, restored after each controller power cycle. Normal
      controller sleep and management power transitions are supported
    '';
    nvramPartition = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-partlabel/nvdata";
      description = ''
        Android nvdata partition holding the per-device Wi-Fi calibration
        and MAC address (`APCFG/APRDEB/WIFI`). It is only ever mounted
        read-only, with the block device set read-only first.
      '';
    };
    modules = lib.mkOption {
      type = lib.types.package;
      default = androidPackages.devices.t880.connectivity-modules.override {
        kernel = config.boot.kernelPackages.kernel;
      };
      defaultText = lib.literalExpression "androidPackages.devices.t880.connectivity-modules";
      description = "Out-of-tree connsys kernel modules built for the system kernel.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.extraModulePackages = [ cfg.modules ];
    boot.extraModprobeConfig = lib.mkIf cfg.bluetooth.enable ''
      # Stock pre-calibration ordering: wait for Bluetooth to register.
      options conninfra t880_precal_wait_bt=1
    '';
    hardware.firmware = lib.optional (cfg.firmwarePackage != null) cfg.firmwarePackage;
    # NixOS owns firmware_class.path; the kernel still searches /lib/firmware.
    systemd.tmpfiles.rules = lib.optionals (cfg.firmwarePackage == null) (
      [ "d /lib/firmware 0755 root root -" ]
      ++ map (f: "L+ /lib/firmware/${f} - - - - ${cfg.firmwareDirectory}/${f}") firmwareFiles
    );

    systemd.services.t880-wifi = {
      description = "T880 Wi-Fi bring-up (connsys NVRAM feed and power-on)";
      wantedBy = [ "multi-user.target" ];
      # iwd and NetworkManager must find wlan0 already there.
      before = [
        "network-pre.target"
        "iwd.service"
        "NetworkManager.service"
        "wpa_supplicant.service"
      ];
      wants = [ "network-pre.target" ];
      after = [
        "systemd-tmpfiles-setup.service"
        "systemd-modules-load.service"
      ];
      unitConfig.ConditionDirectoryNotEmpty = firmwareRoot;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "t880-wifi";
        RuntimeDirectoryMode = "0700";
        ExecStart = lib.getExe bringUp;
        # Power Wi-Fi off cleanly after the network stack has stopped.
        ExecStop = "${pkgs.runtimeShell} -c 'printf 0 > /dev/wmtWifi || true'";
        TimeoutStartSec = 60;
      };
    };
  };
}
