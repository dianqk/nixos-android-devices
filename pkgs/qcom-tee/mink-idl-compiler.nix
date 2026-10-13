# Build-time tool: generates the C headers for Mink IDL interfaces.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "mink-idl-compiler";
  version = "0.2.3";

  src = fetchFromGitHub {
    owner = "quic";
    repo = "mink-idl-compiler";
    tag = "v${finalAttrs.version}";
    hash = "sha256-z/+IruyJR5cLVKYGszInKlt7RezEiVY9SUsQDXYEkxc=";
  };

  cargoHash = "sha256-iC87D83VWDjK4h1J/yfAmliCksxhF5oSrdNC8ouchJc=";
  # build.rs runs `git describe` for --version; the tarball has no .git.
  postPatch = ''
    cat > idlc/build.rs <<'RS'
    pub fn main() {
        println!("cargo:rustc-env=GIT_HASH=v${finalAttrs.version}");
    }
    RS
  '';

  cargoBuildFlags = [ "--package=idlc" ];
  doCheck = false;

  meta = {
    description = "Mink IDL compiler";
    homepage = "https://github.com/quic/mink-idl-compiler";
    license = lib.licenses.bsd3;
    mainProgram = "idlc";
  };
})
