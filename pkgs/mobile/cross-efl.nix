{ efl, buildPackages }:
efl.overrideAttrs (old: {
  # Meson's cross branch runs these generators on the build host.
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ buildPackages.enlightenment.efl ];
})
