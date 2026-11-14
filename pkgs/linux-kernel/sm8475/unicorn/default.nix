{
  baseKernel,
  lib,
  llvmPackages_23,
  openssl,
}:
{
  pname = "linux-unicorn";
  inherit (baseKernel) version modDirVersion src;
  configfile = ./kernel.config;
  patches = import ./series.nix;
  dtbs = [ "qcom/sm8475-xiaomi-unicorn.dtb" ];
  nativeBuildInputs = [
    llvmPackages_23.lld
    openssl.out
  ];
  extraMakeFlags = [
    "HOSTLDFLAGS=-fuse-ld=lld -Wl,-rpath,${lib.getLib openssl}/lib"
  ];
  preBuild = ''
    export LD_LIBRARY_PATH="${openssl.out}/lib"
  '';
  configOverrides = import ./config.nix { inherit lib; };
}
