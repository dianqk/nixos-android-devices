# ---
# Module: Hardware Profile (Sheng)
# Description: Board-specific hardware details and firmware loading
# Scope: Host
# ---

{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  shengUcm = androidPackages.devices.sheng.alsa-ucm;
in
{
  config = lib.mkIf (!config.androidDevices.recovery.enable) {
    # Managing the P2P interface can leave WCN7850 scans stuck after a toggle.
    networking.networkmanager.unmanaged = [ "interface-name:p2p-dev-wlp1s0" ];
    services.udev.extraRules = ''
      ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1", ENV{ID_INPUT_TOUCHSCREEN_INTEGRATION}="internal"
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="NVTCapacitiveTouchScreen", TAG+="uaccess"
      SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_PATH}=="platform-1d84000.ufshc-scsi-*", ENV{UDISKS_IGNORE}="1"
    '';

    networking.networkmanager.wifi = lib.mkIf (config.hardware.sheng.wifiMacAddress != null) {
      macAddress = config.hardware.sheng.wifiMacAddress;
      scanRandMacAddress = false;
    };
    networking.hostName = lib.mkDefault config.hardware.sheng.systemHostName;
    environment.systemPackages = [ shengUcm ];
    environment.variables.ALSA_CONFIG_UCM2 = "${shengUcm}/share/alsa/ucm2";
    systemd.user.settings.Manager.DefaultEnvironment = "ALSA_CONFIG_UCM2=${shengUcm}/share/alsa/ucm2";
    fileSystems."/mnt/vendor/persist" = {
      device = "/dev/disk/by-partlabel/persist";
      fsType = "ext4";
      options = [
        "ro"
        "noatime"
      ];
    };

    hardware.enableRedistributableFirmware = false;
    hardware.firmware = lib.mkBefore [ (androidPackages.devices.sheng.firmware) ];
    hardware.firmwareCompression = "zstd";
    hardware.wirelessRegulatoryDatabase = true;

    boot.initrd.availableKernelModules = [
      "pwrseq_qcom_wcn"
    ];

    # Keep board drivers explicit until their modalias autoload paths have been
    # validated across cold boots. systemd-modules-load handles dependencies and
    # reports module load failures.
    boot.kernelModules = [
      # Wi-Fi / MHI
      "mhi"
      "mhi_pci_generic"
      "qrtr_mhi"
      "mhi_wwan_ctrl"
      "mhi_wwan_mbim"
      "mhi_net"
      "ath12k"

      # Bluetooth
      "bluetooth"
      "btqca"
      "hci_uart"
      "rfkill_gpio"

      # Touchscreen
      "spi_geni_qcom"
      "nt36532e_ts"

      # Audio
      "soundwire_qcom"
      "snd_soc_qcom_common"
      "snd_q6apm"
      "q6apm_dai"
      "q6prm"
      "q6apm_lpass_dais"
      "snd_soc_wcd938x"
      "snd_soc_wcd938x_sdw"
      "snd_soc_cs35l43_i2c"

      # Cameras
      "i2c_qcom_cci"
      "qcom_camss"
      "s5kjn1_sheng"
      "ov32d40"

      # Fingerprint sensor
      "fpc1553"

      # LEDs
      "leds_qcom_flash"
      "leds_qcom_lpg"
    ];

    # Some Sheng drivers do not probe reliably in parallel during a cold boot.
    systemd.services.systemd-modules-load.environment.SYSTEMD_MODULES_LOAD_NUM_THREADS = "1";

    hardware.bluetooth = {
      enable = lib.mkDefault true;
      powerOnBoot = lib.mkDefault true;
    };

    systemd.services.sheng-bluetooth-address =
      lib.mkIf (config.hardware.sheng.bluetoothAddress != null)
        {
          description = "Configure Sheng Bluetooth public address";
          wantedBy = [ "multi-user.target" ];
          before = [ "bluetooth.service" ];
          after = [ "systemd-modules-load.service" ];
          path = with pkgs; [
            bluez
            coreutils
            gnugrep
          ];
          script = ''
            for attempt in $(seq 1 600); do
              state=$(btmgmt extinfo 2>/dev/null || true)
              if grep -q 'Unconfigured controller' <<<"$state"; then
                exec btmgmt --index 0 public-addr ${lib.escapeShellArg config.hardware.sheng.bluetoothAddress}
              fi
              if grep -q 'Primary controller' <<<"$state"; then
                exit 0
              fi
              sleep 0.1
            done
            echo 'Bluetooth controller did not appear within 60 seconds.' >&2
            exit 1
          '';
        };

  };
}
