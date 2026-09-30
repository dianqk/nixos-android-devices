{ rustPlatform, device, features ? [ ] }:
rustPlatform.buildRustPackage {
  pname = "mobile-recovery-screen";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  buildFeatures = [ "device-${device}" ] ++ features;
}
