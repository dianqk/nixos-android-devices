final: prev: {
  androidDevicePackages = import ../pkgs {
    pkgs = final;
    # Preserve the builder selected by mkBuildEnvironment when the overlay is
    # also included by a consumer. A standalone overlay defaults to native.
    compilationPkgs = prev.androidDevicePackages.compilationPkgs or final;
  };
}
