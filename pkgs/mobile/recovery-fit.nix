{
  runCommand,
  buildPackages,
  lib,
}:

# A FIT carrying a RAM recovery (kernel, initrd and DTB), supplied by the host
# or carried in an Android boot image's ramdisk. The command line is
# stored in the DTB's /chosen/bootargs; U-Boot leaves it in place when its
# own bootargs variable is unset. Data stays embedded so that the FIT's FDT
# total size covers the whole payload; U-Boot realigns the DTB itself.
{
  name,
  kernel,
  kernelCompression ? "gzip",
  initrd,
  dtb,
  cmdline,
  # Optional size limit, such as the board's U-Boot fastboot download buffer.
  maximumBytes ? null,
}:
runCommand name
  {
    passthru = {
      inherit
        kernel
        kernelCompression
        initrd
        dtb
        cmdline
        maximumBytes
        ;
    };
    nativeBuildInputs = [
      buildPackages.ubootTools
      buildPackages.dtc
    ];
  }
  ''
    cp ${dtb} recovery.dtb
    chmod u+w recovery.dtb
    fdtput -p -t s recovery.dtb /chosen bootargs ${lib.escapeShellArg cmdline}
    cat > recovery.its <<EOF
    /dts-v1/;
    / {
      description = "NixOS RAM recovery";
      android-devices,payload = "ram-recovery";
      #address-cells = <1>;
      images {
        kernel {
          description = "Linux kernel";
          data = /incbin/("${kernel}");
          type = "kernel_noload";
          arch = "arm64";
          os = "linux";
          compression = "${kernelCompression}";
          load = <0>;
          entry = <0>;
          hash { algo = "sha256"; };
        };
        ramdisk {
          description = "Recovery initrd";
          data = /incbin/("${initrd}");
          type = "ramdisk";
          arch = "arm64";
          os = "linux";
          compression = "none";
          hash { algo = "sha256"; };
        };
        fdt {
          description = "Device tree";
          data = /incbin/("recovery.dtb");
          type = "flat_dt";
          arch = "arm64";
          compression = "none";
          hash { algo = "sha256"; };
        };
      };
      configurations {
        default = "recovery";
        recovery {
          description = "NixOS RAM recovery";
          kernel = "kernel";
          ramdisk = "ramdisk";
          fdt = "fdt";
        };
      };
    };
    EOF
    mkimage -f recovery.its "$out"
    mkimage -l "$out"
    test "$(fdtget "$out" / android-devices,payload)" = ram-recovery
    test "$(fdtget "$out" /configurations default)" = recovery
    ${lib.optionalString (maximumBytes != null) ''
      size=$(stat -c %s "$out")
      test "$size" -le ${toString maximumBytes} || {
        echo "Recovery FIT is $size bytes; limit is ${toString maximumBytes}" >&2
        exit 1
      }
    ''}
  ''
