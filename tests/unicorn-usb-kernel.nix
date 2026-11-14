{ flake }:
let
  # Kernel checks always use workstation LLVM, including the ARM64 check namespace.
  kernel = flake.legacyPackages.x86_64-linux.devices.unicorn.kernel;
  host = (flake.lib.mkBuildEnvironment { buildSystem = "x86_64-linux"; }).buildPackages;
  # nixpkgs supplies libfdt through dtc without pylibfdt distribution metadata.
  # Keep that runtime dependency and the import/tests; remove only its pip name.
  dtschema = host.python3Packages.dtschema.overridePythonAttrs {
    pythonRemoveDeps = [ "pylibfdt" ];
  };
  schemas = "phy/nxp,ptn3222.yaml:phy/qcom,snps-eusb2-phy.yaml:soc/qcom/qcom,pmic-glink.yaml:connector/usb-connector.yaml:usb/qcom,snps-dwc3.yaml:usb/snps,dwc3.yaml";
in
kernel.overrideAttrs (old: {
  pname = "unicorn-usb-kernel-check";
  # Nixpkgs keeps the prepared source under the kernel dev output.
  outputs = [
    "out"
    "dev"
  ];
  nativeBuildInputs = old.nativeBuildInputs ++ [
    dtschema
    host.dtc
    host.which
  ];
  buildPhase = ''
    runHook preBuild
    cd "$buildRoot"
    grep -qx 'CONFIG_POSIX_MQUEUE=y' .config
    grep -qx 'CONFIG_POSIX_MQUEUE_SYSCTL=y' .config
    grep -qx 'CONFIG_UHID=m' .config
    grep -qx 'CONFIG_HIDRAW=y' .config
    for symbol in USB_CONFIGFS_F_HID USB_CONFIGFS_MASS_STORAGE USB_CONFIGFS_F_UVC; do
      grep -qx "CONFIG_$symbol=y" .config
    done
    make "''${makeFlags[@]}" -j"$NIX_BUILD_CORES" \
      ipc/mqueue.o \
      drivers/phy/phy-nxp-ptn3222.o drivers/phy/phy-snps-eusb2.o \
      drivers/usb/dwc3/ drivers/usb/typec/ucsi/ \
      drivers/usb/host/ \
      drivers/hid/usbhid/ drivers/hid/hid-generic.o drivers/hid/uhid.o \
      drivers/hid/hidraw.o \
      drivers/usb/storage/ drivers/net/usb/ sound/usb/ \
      drivers/usb/gadget/function/
    for object in f_hid f_mass_storage uvc_video uvc_configfs; do
      test -s "drivers/usb/gadget/function/$object.o"
    done
    ${host.llvmPackages_23.llvm}/bin/llvm-readelf -h drivers/phy/phy-nxp-ptn3222.o > architecture
    grep -q 'Machine:.*AArch64' architecture
    make "''${makeFlags[@]}" dt_binding_check DT_SCHEMA_FILES='${schemas}'
    make "''${makeFlags[@]}" CHECK_DTBS=y DT_SCHEMA_FILES='${schemas}' qcom/sm8475-xiaomi-unicorn.dtb
    # Kbuild deliberately ignores dt-validate failures. Run it directly too,
    # and fail this check if the selected USB schemas produce diagnostics.
    dt-validate -p Documentation/devicetree/bindings/processed-schema.json \
      -l '${schemas}' arch/arm64/boot/dts/qcom/sm8475-xiaomi-unicorn.dtb > dt-validation.log 2>&1
    if test -s dt-validation.log; then cat dt-validation.log; exit 1; fi
    cp ${./unicorn-usb-kernel.py} "$TMPDIR/unicorn-usb-kernel.py"
    cp ${./unicorn-usb-kernel.c} "$TMPDIR/unicorn-usb-kernel.c"
    python3 "$TMPDIR/unicorn-usb-kernel.py" --source "$dev/lib/modules/${kernel.modDirVersion}/source"
    runHook postBuild
  '';
  installPhase = ''
    mkdir -p "$out"
    cp .config "$out/config"
    cp architecture "$out/architecture"
    cp dt-validation.log "$out/dt-validation.log"
    cp Documentation/devicetree/bindings/processed-schema.json "$out/processed-schema.json"
    cp arch/arm64/boot/dts/qcom/sm8475-xiaomi-unicorn.dtb "$out/"
    find drivers/phy drivers/usb drivers/hid drivers/net/usb sound/usb -name '*.o' -print > "$out/objects"
    test -s "$out/objects"
  '';
  postInstall = "";
  dontFixup = true;
  doCheck = false;
})
