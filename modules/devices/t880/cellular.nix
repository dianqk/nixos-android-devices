# T880 cellular (EXPERIMENTAL): the vendor CCCI modem driver modules, the
# modem's NV partitions mounted read-only, the MediaTek CCCI modem owner
# (mtk-ccci-userspace, `t880` profile) that serves the modem's file system and
# RPC requests and starts it, and ModemManager with the MediaTek SoC plugin.
# Nothing starts at boot unless `startAtBoot` is set: start
# `t880-modem-owner.service` by hand. No data connection is configured: the
# modem only attaches a bearer when a client asks for one.
{
  config,
  lib,
  pkgs,
  androidPackages,
  ...
}:
let
  cfg = config.hardware.t880.cellular;
  kernel = config.boot.kernelPackages.kernel;
  vendorRoot = "/mnt/vendor";
  # The modem image LK loads on slot A; the owner copies its DRDI entry.
  modemPartition = "modem_a";
  # Mount point under vendorRoot -> partition label (the owner's t880 profile).
  nvMounts = {
    nvdata = "nvdata";
    nvcfg = "nvcfg";
    protect_f = "protect1";
    protect_s = "protect2";
    mdota = "mcf_ota_a";
  };
  modules = [
    "ccci_util_lib"
    "ccmni"
    "ccci_md_all"
    "ccci_ccif"
    "ccci_dpmaif"
  ];
  packaging = androidPackages.packaging;
  # The owner refuses to run on another kernel than the one it was set up
  # for: the release and the SHA-256 of /sys/kernel/notes (the kernel's
  # .notes section, build ID included), taken from this system's vmlinux.
  notesHash = packaging.writeText "elf-notes-sha256.py" ''
    import hashlib, struct, sys
    elf = open(sys.argv[1], "rb").read()
    assert elf[:4] == b"\x7fELF" and elf[4] == 2 and elf[5] == 1
    shoff, = struct.unpack_from("<Q", elf, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", elf, 0x3a)
    def section(i):
        return struct.unpack_from("<IIQQQQIIQQ", elf, shoff + i * shentsize)
    strtab = section(shstrndx)[4]
    for i in range(shnum):
        name, _, _, _, offset, size, *_ = section(i)
        if elf[strtab + name:elf.index(b"\0", strtab + name)] == b".notes":
            print(hashlib.sha256(elf[offset:offset + size]).hexdigest())
            break
    else:
        sys.exit("no .notes section")
  '';
  ownerEnvironment = packaging.runCommand "t880-modem-owner-env" {
    nativeBuildInputs = [ packaging.buildPackages.python3 ];
  } ''
    notes=$(python3 ${notesHash} ${kernel.dev}/vmlinux)
    {
      echo MTK_CCCI_BOARD=t880
      echo MTK_CCCI_EXPECTED_KERNEL=${kernel.modDirVersion}
      echo MTK_CCCI_EXPECTED_NOTES_SHA256=$notes
      echo MTK_CCCI_VENDOR_ROOT=${vendorRoot}
      echo MTK_CCCI_VENDOR_ETC_ROOT=/vendor
      echo MTK_CCCI_PRIVATE_ROOT=/var/lib/mtk-ccci/private
      echo MDINIT_OVERLAY_ROOT=${cfg.nvWorkingCopy}
      echo CCCI_EVIDENCE_DIR=/run/mtk-ccci/evidence
      echo MTK_CCCI_PROPERTY_TABLE=/etc/mtk-ccci/md_sys_props.conf
      echo ${lib.escapeShellArg "MTK_CCCI_DRIVE_ROOTS=${driveRoots}"}
      echo ${lib.escapeShellArg "QQC_MD_RAT_STR=${cfg.ratString}"}
      echo QQC_MD_TIME_TZ=0
      echo MTK_CCCI_ENABLE_MDLOG=0
      echo MTK_CCCI_MODEM_IMAGE=/dev/disk/by-partlabel/${modemPartition}
    } > $out
  '';
  driveRoots = lib.concatStringsSep ";" (
    lib.mapAttrsToList (letter: roots: "${letter}=${lib.concatStringsSep ":" roots}") cfg.driveRoots
  );
  nvUp = packaging.writeShellApplication {
    name = "t880-modem-nv-up";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
    ];
    text = "blockdev --setro \"$(readlink -f /dev/disk/by-partlabel/${modemPartition})\"\n" + lib.concatStrings (
      lib.mapAttrsToList (name: label: ''
        dev=$(readlink -f /dev/disk/by-partlabel/${label})
        blockdev --setro "$dev"
        mkdir -p ${vendorRoot}/${name}
        mountpoint -q ${vendorRoot}/${name} ||
          mount -t ext4 -o ro,noload,nodev,nosuid,noexec "$dev" ${vendorRoot}/${name}
      '') nvMounts
    );
  };
  # The originals are only read: their hashes are recorded when the working
  # copy is first set up and rechecked before every start and after every
  # stop. A change while the owner ran fails the unit; a change between
  # sessions (Android on slot B writes its own NV) is logged.
  # A same-boot modem restart does not work (the modem software does not run
  # again), so a crashed or unresponsive modem is recovered by a clean
  # reboot, rate limited; after too many it stays off until cleared.
  guardState = "/var/lib/t880-modem-guard";
  crashGuard = packaging.writeShellApplication {
    name = "t880-modem-crash-guard";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      systemd
    ];
    text = ''
      state=${guardState}
      mkdir -p "$state"
      log() { echo "t880-modem-crash-guard: $*"; }
      boot_id=$(cat /proc/sys/kernel/random/boot_id)
      handle() {
        reason=$1
        now=$(date +%s)
        window=$(( ${toString cfg.crashReboot.windowMinutes} * 60 ))
        recent=0
        : > "$state/reboots.new"
        if [ -f "$state/reboots" ]; then
          while read -r t; do
            if [ $(( now - t )) -lt "$window" ]; then
              echo "$t" >> "$state/reboots.new"
              recent=$(( recent + 1 ))
            fi
          done < "$state/reboots"
        fi
        mv "$state/reboots.new" "$state/reboots"
        if [ "$recent" -ge ${toString cfg.crashReboot.maxReboots} ]; then
          log "modem failure ($reason); $recent crash reboots within ${toString cfg.crashReboot.windowMinutes} min: not rebooting, modem left off until $state/disabled is removed"
          echo "$(date -Is) $reason" > "$state/disabled"
          systemctl --no-block stop ModemManager.service t880-modem-owner.service || true
          exit 0
        fi
        echo "$now" >> "$state/reboots"
        echo "$(date -Is) boot $boot_id: $reason" >> "$state/history"
        log "modem failure ($reason): rebooting cleanly (crash reboot $(( recent + 1 )) of ${toString cfg.crashReboot.maxReboots} allowed in ${toString cfg.crashReboot.windowMinutes} min)"
        sync
        systemctl reboot
        exit 0
      }
      log "watching the modem (boot $boot_id)"
      since=$(date +%s)
      n=0
      while sleep 5; do
        md=$(cat /sys/kernel/ccci/boot 2>/dev/null || true)
        case "$md" in
          md1:5*) handle "modem exception (md1:5)" ;;
        esac
        result=$(systemctl show -P Result t880-modem-owner.service)
        if [ "$result" != success ]; then
          handle "modem owner failed ($result)"
        fi
        n=$(( n + 1 ))
        if [ $(( n % 6 )) -eq 0 ]; then
          next=$(date +%s)
          if journalctl -q -b -u ModemManager.service --since "@$since" \
              -g "marking modem as invalid" -n 1 2>/dev/null | grep -q .; then
            handle "modem AT channel stalled (ModemManager marked the modem invalid)"
          fi
          since=$next
        fi
      done
    '';
  };
  nvHashes = packaging.writeShellApplication {
    name = "t880-modem-nv-hashes";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      diffutils
    ];
    text = ''
      state=/var/lib/mtk-ccci
      now=$(mktemp)
      (cd ${vendorRoot} && find ${lib.concatStringsSep " " (lib.attrNames nvMounts)} -type f -print0 \
        | sort -z | xargs -0 -r sha256sum) > "$now"
      case "$1" in
        start)
          if [ ! -s "$state/originals.sha256" ]; then
            cp "$now" "$state/originals.sha256"
            echo "originals recorded: $(wc -l < "$now") files"
          elif ! cmp -s "$now" "$state/originals.sha256"; then
            echo "originals differ from the working copy's record (written outside NixOS):"
            diff "$state/originals.sha256" "$now" | grep '^[<>]' | cut -c1-200 || true
          fi
          cp "$now" "$state/session.sha256"
          ;;
        stop)
          if ! cmp -s "$now" "$state/session.sha256"; then
            echo "NV ORIGINALS CHANGED DURING THE SESSION:" >&2
            diff "$state/session.sha256" "$now" | grep '^[<>]' >&2 || true
            rm -f "$now"
            exit 1
          fi
          echo "originals unchanged during the session"
          ;;
      esac
      rm -f "$now"
    '';
  };
  nvDown = packaging.writeShellApplication {
    name = "t880-modem-nv-down";
    runtimeInputs = [ pkgs.util-linux ];
    text = lib.concatStrings (
      lib.mapAttrsToList (name: _: ''
        umount ${vendorRoot}/${name} 2>/dev/null || true
      '') nvMounts
    );
  };
in
{
  options.hardware.t880.cellular = {
    enable = lib.mkEnableOption ''
      cellular through the vendor CCCI modem driver (EXPERIMENTAL): the modem
      modules, read-only NV mounts, the CCCI modem owner and ModemManager with
      the MediaTek SoC plugin. Installed system only
    '';
    startAtBoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start the modem owner (which loads the modules, mounts the NV
        partitions and starts the modem) during boot. When false, start
        `t880-modem-owner.service` by hand.
      '';
    };
    crashReboot = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.startAtBoot;
        defaultText = lib.literalExpression "config.hardware.t880.cellular.startAtBoot";
        description = ''
          Reboot cleanly when the modem crashes (exception state), its owner
          fails, or ModemManager loses the AT channel. The modem cannot be
          restarted within one boot. After `maxReboots` crash reboots within
          `windowMinutes` the modem is left off until
          /var/lib/t880-modem-guard/disabled is removed.
        '';
      };
      maxReboots = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = "Crash reboots allowed within the window.";
      };
      windowMinutes = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "Window for counting crash reboots.";
      };
    };
    modemManager = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable ModemManager with the MediaTek SoC plugin and start it with the
        modem owner. It never connects data by itself; a data connection needs
        an explicit client request or a NetworkManager profile.
      '';
    };
    ratString = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z/]+";
      # as Android on this tablet (modem type 22)
      default = "N/Lf/Lt/W/G";
      description = "Radio access technologies passed to the modem in its boot data.";
    };
    nvWorkingCopy = lib.mkOption {
      type = lib.types.strMatching "/[A-Za-z0-9/._-]+";
      default = "/var/lib/mtk-ccci/overlay";
      example = "/run/mtk-ccci/overlay";
      description = ''
        Working copy of the modem NV: every modem write and NV restore goes
        here, initialised from the read-only originals on first use. The
        originals (nvdata, nvcfg, protect1/2, mcf_ota) are never written.
        A directory under /run makes it a per-boot tmpfs copy (tests).
      '';
    };
    driveRoots = lib.mkOption {
      type = lib.types.attrsOf (lib.types.nonEmptyListOf lib.types.path);
      default = {
        # Android mounts the modem OTA store (mcf_ota) at /mnt/vendor/mdota.
        T = [
          "/vendor/etc/mdota"
          "${vendorRoot}/mdota"
        ];
      };
      description = ''
        Per-drive candidate roots of the modem file system that replace the
        owner's defaults (`MTK_CCCI_DRIVE_ROOTS`), tried in order.
      '';
    };
    package = lib.mkPackageOption androidPackages "mtk-ccci-userspace" {
      pkgsText = "androidPackages";
    };
    modemManagerPackage = lib.mkPackageOption androidPackages "modemmanager-mtk-soc" {
      pkgsText = "androidPackages";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.androidDevices.recovery.enable;
        message = "hardware.t880.cellular is for the installed system, not RAM recovery.";
      }
    ];

    networking.modemmanager = lib.mkIf cfg.modemManager {
      enable = lib.mkDefault true;
      package = lib.mkDefault cfg.modemManagerPackage;
    };
    # The USB gadget serial ports belong to the host link, not to a modem.
    services.udev.extraRules = lib.mkIf cfg.modemManager ''
      SUBSYSTEM=="tty", KERNEL=="ttyGS[0-9]*", ENV{ID_MM_DEVICE_IGNORE}="1"
    '';

    systemd.services = {
      # ModemManager runs with the modem owner, not on its own at boot.
      ModemManager.wantedBy = lib.mkIf (cfg.modemManager && !cfg.startAtBoot) (lib.mkForce [ ]);
      ModemManager.partOf = lib.optional cfg.modemManager "t880-modem-owner.service";
      # ModemManager Requires=polkit.service: restart a changed polkit during a
      # configuration switch instead of stopping it, which stopped ModemManager
      # and left it stopped.
      polkit.stopIfChanged = lib.mkIf cfg.modemManager false;

      # The modem's NV partitions (shared with Android) are only ever read:
      # block devices set read-only, ext4 mounted without journal replay.
      t880-modem-nv = {
        description = "T880 modem NV partitions (read-only)";
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe nvUp;
          ExecStop = lib.getExe nvDown;
        };
      };

      # The CCCI modules cannot be unloaded: they stay until the next boot.
      t880-modem-modules = {
        description = "T880 CCCI modem driver modules";
        after = [ "systemd-modules-load.service" ];
        path = [ pkgs.kmod ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.kmod}/bin/modprobe -a ${lib.escapeShellArgs modules}";
        };
      };

      # Closing the owner stops the modem, so a configuration switch must not
      # restart it; it stops (and stops the modem) at shutdown.
      t880-modem-crash-guard = lib.mkIf cfg.crashReboot.enable {
        description = "T880 modem crash guard (clean reboot on modem failure)";
        wantedBy = [ "t880-modem-owner.service" ];
        after = [ "t880-modem-owner.service" ];
        partOf = [ "t880-modem-owner.service" ];
        restartIfChanged = false;
        serviceConfig = {
          ExecStart = lib.getExe crashGuard;
          Restart = "no";
        };
      };

      t880-modem-owner = {
        description = "T880 CCCI modem owner (starts the modem)";
        unitConfig.ConditionPathExists = "!${guardState}/disabled";
        wantedBy = lib.optional cfg.startAtBoot "multi-user.target";
        requires = [
          "t880-modem-nv.service"
          "t880-modem-modules.service"
        ];
        after = [
          "t880-modem-nv.service"
          "t880-modem-modules.service"
          "time-sync.target"
        ];
        wants = lib.optional cfg.modemManager "ModemManager.service";
        before = lib.optional cfg.modemManager "ModemManager.service";
        restartIfChanged = false;
        stopIfChanged = false;
        # Type=simple alone completes before SCP/MD startup. Keep dependants
        # ordered after real READY, including ModemManager's initial port probe.
        path = [ pkgs.coreutils ];
        postStart = ''
          deadline=$(( SECONDS + 45 ))
          while [ "$SECONDS" -lt "$deadline" ]; do
            if [ -z "''${MAINPID:-}" ] || ! kill -0 "$MAINPID" 2>/dev/null; then
              echo "modem owner exited before READY" >&2
              exit 1
            fi
            state=$(cat /sys/kernel/ccci/boot 2>/dev/null || true)
            case "$state" in
              md1:4*) exit 0 ;;
              md1:5*) echo "modem entered exception before READY" >&2; exit 1 ;;
            esac
            sleep 0.1
          done
          echo "modem did not reach READY within 45 seconds" >&2
          exit 1
        '';
        serviceConfig = {
          Type = "simple";
          EnvironmentFile = ownerEnvironment;
          ExecStartPre = "${lib.getExe nvHashes} start";
          ExecStart = lib.getExe cfg.package;
          ExecStopPost = "${lib.getExe nvHashes} stop";
          Restart = "no";
          UMask = "0077";
          RuntimeDirectory = "mtk-ccci";
          RuntimeDirectoryMode = "0700";
          StateDirectory = "mtk-ccci";
          StateDirectoryMode = "0700";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [
            "/run/mtk-ccci"
            "/var/lib/mtk-ccci"
          ]
          ++ lib.optional (!lib.hasPrefix "/var/lib/mtk-ccci/" cfg.nvWorkingCopy) cfg.nvWorkingCopy;
          # Defence in depth on top of the read-only block devices and mounts.
          ReadOnlyPaths = [ vendorRoot ];
          TimeoutStopSec = 60;
        };
      };
    };
  };
}
