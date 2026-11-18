{ flake }:
let
  kernel = flake.legacyPackages.x86_64-linux.devices.asphalt.kernel;
  host = (flake.lib.mkBuildEnvironment { buildSystem = "x86_64-linux"; }).buildPackages;
  dtschema = host.python3Packages.dtschema.overridePythonAttrs {
    pythonRemoveDeps = [ "pylibfdt" ];
  };
  schemas = "clock/qcom,gcc-sm8450.yaml:ufs/qcom,sc7180-ufshc.yaml:crypto/qcom,inline-crypto-engine.yaml";
in
kernel.overrideAttrs (old: {
  pname = "asphalt-ufs-kernel-check";
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
    make "''${makeFlags[@]}" -j"$NIX_BUILD_CORES" \
      drivers/ufs/core/ufshcd.o drivers/ufs/host/ufs-qcom.o \
      drivers/clk/qcom/gcc-sm8450.o drivers/clk/qcom/gdsc.o \
      drivers/soc/qcom/ice.o
    ${host.llvmPackages_23.llvm}/bin/llvm-readelf -h drivers/ufs/core/ufshcd.o > architecture
    grep -q 'Machine:.*AArch64' architecture
    make "''${makeFlags[@]}" dt_binding_check DT_SCHEMA_FILES='${schemas}'
    make "''${makeFlags[@]}" CHECK_DTBS=y DT_SCHEMA_FILES='${schemas}' qcom/sm8475-lenovo-asphalt.dtb
    dt-validate -p Documentation/devicetree/bindings/processed-schema.json \
      -l '${schemas}' arch/arm64/boot/dts/qcom/sm8475-lenovo-asphalt.dtb > dt-validation.log 2>&1
    if test -s dt-validation.log; then cat dt-validation.log; exit 1; fi
    python3 ${./asphalt-ufs.py} arch/arm64/boot/dts/qcom/sm8475-lenovo-asphalt.dtb
    runHook postBuild
  '';
  installPhase = ''
    mkdir -p "$out"
    cp .config "$out/config"
    cp architecture dt-validation.log "$out/"
    cp arch/arm64/boot/dts/qcom/sm8475-lenovo-asphalt.dtb "$out/"
  '';
  postInstall = "";
  dontFixup = true;
  doCheck = false;
})
