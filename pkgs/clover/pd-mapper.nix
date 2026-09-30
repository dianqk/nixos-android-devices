{ pd-mapper }:
pd-mapper.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    substituteInPlace pd-mapper.c \
      --replace-fail \
        '/run/current-system/sw/share/uncompressed-firmware/' \
        '/lib/firmware/'
  '';
})
