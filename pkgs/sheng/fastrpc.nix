# ---
# Module: FastRPC Sensor
# Description: FastRPC configuration
# Scope: Host
# ---

{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  libbsd,
  pkg-config,
  libyaml,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "fastrpc";
  version = "1.0.7";

  src = fetchFromGitHub {
    owner = "qualcomm";
    repo = "fastrpc";
    rev = "v${version}";
    hash = "sha256-23aq4o2lRhQdBbdrWBdJKVSjl4JHAqpm/sONeiLBP0c=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    makeWrapper
  ];
  buildInputs = [
    libbsd
    libyaml
  ];

  # The upstream Automake files use absolute paths for these data files.
  # Point them into the store explicitly so the build cannot try to write
  # /usr during install; Sheng provides its own service graph and rules.
  configureFlags = [
    "--with-systemdsystemunitdir=${placeholder "out"}/lib/systemd/system"
    "--with-udevrulesdir=${placeholder "out"}/lib/udev/rules.d"
    "--with-sysusersdir=${placeholder "out"}/lib/sysusers.d"
  ];

  patches = [
    ./fastrpc-rflags.patch
  ];

  # Note: The original APKBUILD skips tests
  preAutoreconf = ''
    mkdir -p m4
  '';

  preConfigure = ''
    rm -rf src/fastrpc_test.c
    rm -rf src/fastrpc_test
  '';

  postInstall = ''
    # Sheng declares its own systemd units and udev integration below. Do not
    # expose the generic upstream units/rules through systemPackages, where
    # they could collide with the device-specific service graph.
    rm -rf "$out/lib/systemd" "$out/lib/udev" "$out/lib/sysusers.d" "$out/usr/lib/sysusers.d"

    # Clean up test binaries that might cause strip errors
    rm -rf $out/share/fastrpc_test
    rm -f $out/bin/fastrpc_test

    # Compile a simple client to keep a PD alive without registering a listener
    gcc -O2 -o $out/bin/fastrpc_keepalive -Iinc -Isrc -L$out/lib -ladsprpc \
      -Wl,-rpath,$out/lib \
      -xc - <<'EOF'
    #include <stdio.h>
    #include <unistd.h>
    #include "remote.h"
    #define ITRANSPORT_PREFIX "'\":;./\\"
    #define CREATE_STATICPD "createstaticpd:"
    int main(int argc, char **argv) {
        if (argc < 2) {
            printf("Usage: %s <uri_suffix>\n", argv[0]);
            return 1;
        }
        char name[256];
        snprintf(name, sizeof(name), "%s%s%s", ITRANSPORT_PREFIX, CREATE_STATICPD, argv[1]);
        remote_handle64 fd;
        if (remote_handle64_open(name, &fd) == 0) {
            printf("Handle opened for %s. Sleeping forever.\n", name);
            while (1) pause();
        } else {
            printf("Failed to open handle for %s.\n", name);
            return 1;
        }
        return 0;
    }
    EOF

    # Wrap binaries so dlopen can confidently find the listener libraries
    for p in adsprpcd cdsprpcd sdsprpcd gdsprpcd; do
      if [ -f $out/bin/$p ]; then
        wrapProgram $out/bin/$p \
          --prefix LD_LIBRARY_PATH : "$out/lib"
      fi
    done
  '';

  meta = with lib; {
    description = "FastRPC Daemon for Qualcomm ADSP";
    homepage = "https://github.com/qualcomm/fastrpc";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
