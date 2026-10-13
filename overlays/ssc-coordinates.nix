_final: prev: {
  libssc = prev.libssc.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./libssc-device-coordinates.patch ];
    postBuild = (old.postBuild or "") + ''
      $CC ${../tests/libssc-coordinates.c} -I./src -I./data -I../src \
        ../src/libssc-client.c ../src/libssc-common.c data/*.pb-c.c \
        $(pkg-config --cflags --libs gio-unix-2.0 qmi-glib libprotobuf-c) \
        -lm -o test-device-coordinates
    '';
    doCheck = prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform;
    checkPhase = ''
      runHook preCheck
      ./test-device-coordinates
      runHook postCheck
    '';
  });
  iio-sensor-proxy = prev.iio-sensor-proxy.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./iio-ssc-device-coordinates.patch ];
    postBuild = (old.postBuild or "") + ''
      $CC ${../tests/iio-ssc-coordinates.c} -I../src -I. \
        ../src/orientation.c ../src/accel-mount-matrix.c \
        ../src/accel-scale.c ../src/accel-attributes.c ../src/drivers.c \
        $(pkg-config --cflags --libs gio-2.0 gudev-1.0 libssc) \
        -lm -o test-ssc-coordinates
    '';
    doCheck = prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform;
    checkPhase = ''
      runHook preCheck
      ./test-ssc-coordinates
      runHook postCheck
    '';
  });
}
