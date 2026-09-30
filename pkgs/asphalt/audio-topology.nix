{
  runCommand,
  fetchFromGitHub,
  buildPackages,
}:
let
  audioreachSource = fetchFromGitHub {
    owner = "linux-msm";
    repo = "audioreach-topology";
    rev = "993a17dcb672357998a463a73f120064d6c74f4f";
    hash = "sha256-L2qem2uUvV/AgQRZCl/LOmAdaWyc13pDTlNjEXDtgVc=";
  };
in
runCommand "asphalt-audioreach-topology"
  {
    nativeBuildInputs = [
      buildPackages.alsa-utils
      buildPackages.m4
    ];
  }
  ''
    m4 -I ${audioreachSource} ${./audio/Lenovo-Y700.m4} > Lenovo-Y700.conf
    alsatplg -c Lenovo-Y700.conf -o Lenovo-Y700-tplg.bin
    install -Dm0644 Lenovo-Y700-tplg.bin \
      "$out/lib/firmware/qcom/sm8475/Lenovo-Y700-tplg.bin"
  ''
