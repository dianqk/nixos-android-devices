{ rmtfs }:
rmtfs.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./rmtfs-debug-format.patch ];
})
