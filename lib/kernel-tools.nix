pkgs: with pkgs; [
  bc
  bison
  ccache
  cpio
  dtc
  elfutils
  flex
  gnumake
  gzip
  llvmPackages_23.clang
  llvmPackages_23.lld
  llvmPackages_23.llvm
  android-tools
  openssl
  pahole
  # Kernel host helpers query build-host OpenSSL metadata.
  pkgs.pkgsBuildBuild.pkg-config
  pkgs.pkgsBuildBuild.ubootTools
  python3
  rsync
  xz
  zlib
  zstd
]
