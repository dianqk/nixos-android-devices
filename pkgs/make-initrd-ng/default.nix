{ makeInitrdNGTool }:
makeInitrdNGTool.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./resolve-library-alternatives.patch ];
})
