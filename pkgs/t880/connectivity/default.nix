# MediaTek connsys drivers for the T880 (MT6897 + MT6637), built out of tree
# against the device kernel: conninfra, connfem, wmt_chrdev_wifi_connac2, the
# gen4m Wi-Fi driver and (experimental) bt_drv_6897. Source only; the firmware
# stays outside this package (see hardware.t880.connectivity).
{
  lib,
  stdenv,
  fetchFromGitHub,
  buildPackages,
  kernel,
}:
stdenv.mkDerivation {
  pname = "t880-connectivity-modules";
  version = "0-unstable-2026-09-23-${kernel.version}";

  src = fetchFromGitHub {
    owner = "soralis0912-dev";
    repo = "kernel_xiaomi_mt6897-mediatek_modules";
    rev = "307ae6e261d670f49e294e90d0c2dc10b0433cf1";
    sparseCheckout = [
      "connectivity/common"
      "connectivity/conninfra"
      "connectivity/connfem"
      "connectivity/wlan"
      "connectivity/bt/mt66xx"
    ];
    hash = "sha256-h0jXlx0URy8D8+ZVhQN0kW76YqAK+Hr32xa4MkiUM3c=";
  };

  patches = [
    ./patches/0001-t880-add-a-compatibility-header-layer-for-Linux-7.x.patch
    ./patches/0002-conninfra-build-and-run-on-Linux-7.x-for-the-MT6897-.patch
    ./patches/0003-connfem-build-on-Linux-7.x.patch
    ./patches/0004-wlan-adaptor-build-wmt_chrdev_wifi-against-an-out-of.patch
    ./patches/0005-gen4m-build-and-run-the-MT6897-Wi-Fi-driver-on-Linux.patch
    ./patches/0006-bt-mt66xx-run-bt_drv_6897-on-Linux-7.x-with-in-kerne.patch
    ./patches/0007-conninfra-gen4m-do-not-depend-on-a-modular-modem-dri.patch
    ./patches/0008-bt-mt6897-btcvsd.patch
    ./patches/0009-bt-preserve-management-power-initialization.patch
    ./patches/0010-conninfra-forward-MT6897-ATF-subsystem-status.patch
    ./patches/0011-bt-mt6897-acknowledge-CCIF-before-CPU-release.patch
    ./patches/0012-bt-mt6897-add-bounded-ownership-snapshots.patch
    ./patches/0013-bt-retire-T880-controller-keep-awake-workaround.patch
    ./patches/0014-bt-restore-controller-address-after-power-cycle.patch
  ];

  postPatch = ''
    cp ${./btmtk-btcvsd.c} connectivity/bt/mt66xx/btif/btmtk-btcvsd.c
    cp ${./btmtk-btcvsd.h} connectivity/bt/mt66xx/include/btmtk-btcvsd.h
    cp ${./btcvsd-layout.h} connectivity/bt/mt66xx/include/btcvsd-layout.h
    cp ${./btcvsd-cvsd.h} connectivity/bt/mt66xx/include/btcvsd-cvsd.h
    ${buildPackages.python3}/bin/python3 ${../../../tests/t880-conninfra-status}/test.py \
      --source . --cc ${buildPackages.stdenv.cc}/bin/cc
    ${buildPackages.python3}/bin/python3 ${../../../tests/t880-bt-address}/test.py \
      --source . --cc ${buildPackages.stdenv.cc}/bin/cc
    ${buildPackages.python3}/bin/python3 ${../../../tests/t880-bt-startup}/test.py \
      --source . --cc ${buildPackages.stdenv.cc}/bin/cc
    ${buildPackages.python3}/bin/python3 ${../../../tests/t880-bt-own-snapshot}/test.py \
      --source . --cc ${buildPackages.stdenv.cc}/bin/cc
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  # The kernel's flags carry the exact toolchain (one contains a space); its
  # O= points at the kernel's own build tree and is dropped for -C build.
  __structuredAttrs = true;
  makeFlags = builtins.filter (flag: !lib.hasPrefix "O=" flag) kernel.makeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  # Stock user build without MediaTek platform hooks the mainline kernel does
  # not provide (power throttling, battery-voltage TX power, AEE, MDDP), without
  # NAN and without the CCCI modem hooks (the modem driver modules are loaded
  # by hand, never as a Wi-Fi dependency).
  buildPhase = ''
    runHook preBuild
    S=$PWD/connectivity
    kmake() {
      make "''${makeFlags[@]}" -j"$NIX_BUILD_CORES" "$@" modules
    }
    kmake M=$S/conninfra KO_CODE_PATH=$S/conninfra \
      CONFIG_MTK_COMBO_CHIP_CONSYS_6897=y CONFIG_ARCH_MEDIATEK= \
      TARGET_BUILD_VARIANT=user
    kmake M=$S/connfem KO_CODE_PATH=$S/connfem
    kmake M=$S/wlan/adaptor CONN_SRC=$S CONNAC_VER=2_0 \
      MODULE_NAME=wmt_chrdev_wifi_connac2 \
      KBUILD_EXTRA_SYMBOLS=$S/conninfra/Module.symvers
    kmake M=$S/wlan/core/gen4m KO_CODE_PATH=$S/wlan/core/gen4m CONN_SRC=$S \
      SEGMENT=SP MODULE_NAME=wlan_drv_gen4m_6897 CONFIG_ARCH_MEDIATEK= \
      CONFIG_MTK_WIFI_POWER_THROTTLING=n CONFIG_MTK_WIFI_SUPPORT_VOLT_INFO=n \
      CONFIG_MODIFY_TX_POWER_BY_BAT_VOLT=n CONFIG_MTK_AEE_FEATURE=n \
      CONFIG_MTK_MDDP_SUPPORT= CONFIG_MTK_WIFI_NAN=n CONFIG_MTK_WIFI_CCCI_SUPPORT=n \
      CONFIG_MTK_CONNSYS_DEDICATED_LOG_PATH=y \
      "KBUILD_EXTRA_SYMBOLS=$S/conninfra/Module.symvers $S/connfem/Module.symvers $S/wlan/adaptor/Module.symvers"
    # Bluetooth (experimental): BEIF transport, in-kernel HCI.
    kmake M=$S/bt/mt66xx/6897 KO_PATH=$S/bt/mt66xx/6897 CONN_SRC=$S \
      CONFIG_ARCH_MEDIATEK= TARGET_BUILD_VARIANT=user \
      "KBUILD_EXTRA_SYMBOLS=$S/conninfra/Module.symvers $S/connfem/Module.symvers"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    S=$PWD/connectivity
    for dir in conninfra connfem wlan/adaptor wlan/core/gen4m bt/mt66xx/6897; do
      make "''${makeFlags[@]}" M=$S/$dir INSTALL_MOD_PATH=$out \
        INSTALL_MOD_DIR=extra/t880-connectivity INSTALL_MOD_STRIP=1 \
        DEPMOD=true modules_install
    done
    # The kernel does not sign modules, so there are no module certificates.
    # NixOS module aggregation copies modules.cer and appends each external
    # module's .ko.cer: provide them empty.
    moddir=$out/lib/modules/${kernel.modDirVersion}
    touch $moddir/modules.cer
    for ko in $moddir/extra/t880-connectivity/*.ko*; do
      touch "''${ko%.ko*}.ko.cer"
    done
    runHook postInstall
  '';

  passthru.tests.btcvsd =
    buildPackages.runCommand "t880-btcvsd-layout-test"
      {
        nativeBuildInputs = [ buildPackages.stdenv.cc ];
      }
      ''
        cp ${./btcvsd-layout.h} btcvsd-layout.h
        cc -std=c11 -O2 -Wall -Wextra -Werror -I. ${../../../tests/t880-btcvsd.c} -o test
        ./test
        touch "$out"
      '';

  passthru.tests.cvsd =
    buildPackages.runCommand "t880-cvsd-codec-test"
      {
        nativeBuildInputs = [ buildPackages.stdenv.cc ];
      }
      ''
        cp ${./btcvsd-cvsd.h} btcvsd-cvsd.h
        cc -std=c11 -O2 -Wno-unknown-pragmas -I${./cvsd-reference} \
          -c ${./cvsd-reference/filter.c} -o filter.o
        cc -std=c11 -O2 -Wall -Wextra -Werror -I. \
          ${../../../tests/t880-cvsd.c} filter.o -o test
        ./test ${./cvsd-reference}
        touch "$out"
      '';

  meta = {
    description = "MediaTek connsys (conninfra, connfem, gen4m Wi-Fi, bt_drv Bluetooth) drivers for the T880";
    homepage = "https://github.com/soralis0912-dev/kernel_xiaomi_mt6897-mediatek_modules";
    license = with lib.licenses; [
      gpl2Only
      bsd2
      bsd3
    ];
    platforms = [ "aarch64-linux" ];
  };
}
