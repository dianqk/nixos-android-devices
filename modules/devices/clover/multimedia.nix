{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  ucm = androidPackages.devices.clover.alsa-ucm;
  ucmDirectory = "${ucm}/share/alsa/ucm2";

  cloverPdMapper = androidPackages.devices.clover.pd-mapper;

  remoteprocControl = androidPackages.packaging.writeShellApplication {
    name = "clover-audio-remoteproc";
    runtimeInputs = with pkgs; [
      coreutils
      kmod
    ];
    text = ''
      find_remoteproc() {
        local wanted="$1" path
        for path in /sys/class/remoteproc/remoteproc*; do
          [ -e "$path/name" ] || continue
          if [ "$(cat "$path/name")" = "$wanted" ]; then
            printf '%s\n' "$path"
            return 0
          fi
        done
        return 1
      }

      wait_remoteproc() {
        local wanted="$1" path
        for _ in $(seq 1 100); do
          if path=$(find_remoteproc "$wanted"); then
            printf '%s\n' "$path"
            return 0
          fi
          sleep 0.1
        done
        echo "$wanted remoteproc did not appear within 10 seconds." >&2
        return 1
      }

      wait_state() {
        local wanted="$1" expected="$2" path
        path=$(wait_remoteproc "$wanted")
        for _ in $(seq 1 150); do
          if [ "$(cat "$path/state")" = "$expected" ]; then
            return 0
          fi
          sleep 0.1
        done
        echo "$wanted remoteproc did not become $expected within 15 seconds." >&2
        return 1
      }

      set_state() {
        local wanted="$1" requested="$2" path state
        path=$(wait_remoteproc "$wanted")
        state=$(cat "$path/state")
        case "$requested:$state" in
          start:offline|stop:running) echo "$requested" > "$path/state" ;;
        esac
      }

      case "''${1:-}" in
        probe)
          modprobe qcom_q6v5_pas
          # qcom_q6v5_pas auto-boots both PAS devices. Audio needs only ADSP;
          # wait for those asynchronous boots, then stop only CDSP while
          # retaining ADSP's one reliable boot this session.
          wait_state adsp running
          wait_state cdsp running
          set_state cdsp stop
          ;;
        start) set_state adsp start ;;
        stop) set_state adsp stop ;;
        *) echo "usage: clover-audio-remoteproc probe|start|stop" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  config = lib.mkIf (!config.androidDevices.recovery.enable) {
    environment.systemPackages = [
      pkgs.alsa-utils
      cloverPdMapper
    ];

    environment.variables.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.pipewire-pulse.environment.ALSA_CONFIG_UCM2 = ucmDirectory;
    systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucmDirectory;

    systemd.services.clover-adsp-probe = {
      description = "Prepare Clover audio remote processor";
      after = [ "clover-firmware-loader.service" ];
      requires = [ "clover-firmware-loader.service" ];
      before = [ "clover-pd-mapper.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${remoteprocControl}/bin/clover-audio-remoteproc probe";
      };
    };

    systemd.services.clover-pd-mapper = {
      description = "Serve Clover protection-domain mappings";
      after = [ "clover-adsp-probe.service" ];
      requires = [ "clover-adsp-probe.service" ];
      before = [ "clover-adsp.service" ];
      serviceConfig = {
        ExecStart = "${cloverPdMapper}/bin/pd-mapper";
        Restart = "no";
      };
    };

    systemd.services.clover-adsp = {
      description = "Start Clover audio remote processor";
      wantedBy = [ "multi-user.target" ];
      after = [ "clover-pd-mapper.service" ];
      bindsTo = [ "clover-pd-mapper.service" ];
      requires = [ "clover-pd-mapper.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "no";
        ExecStart = "${remoteprocControl}/bin/clover-audio-remoteproc start";
        ExecStop = "${remoteprocControl}/bin/clover-audio-remoteproc stop";
      };
    };
  };
}
