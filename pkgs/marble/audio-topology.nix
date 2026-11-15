{
  runCommand,
  fetchFromGitHub,
  pkgsBuildBuild,
}:
let
  # Same pinned source as the Y700 2023 topology.
  audioreachSource = fetchFromGitHub {
    owner = "linux-msm";
    repo = "audioreach-topology";
    rev = "993a17dcb672357998a463a73f120064d6c74f4f";
    hash = "sha256-L2qem2uUvV/AgQRZCl/LOmAdaWyc13pDTlNjEXDtgVc=";
  };
in
# The sound card is "SM8475-Xiaomi-Marble" with the sm8450 driver name, so
# q6apm requests qcom/sm8450/SM8475-Xiaomi-Marble-tplg.bin.
runCommand "marble-audioreach-topology"
  {
    nativeBuildInputs = [
      pkgsBuildBuild.alsa-utils
      pkgsBuildBuild.m4
    ];
  }
  ''
    m4 -I ${audioreachSource} -I ${./audio} ${./audio/SM8475-Xiaomi-Marble.m4} \
      > SM8475-Xiaomi-Marble.conf
    alsatplg -c SM8475-Xiaomi-Marble.conf -o SM8475-Xiaomi-Marble-tplg.bin
    install -Dm0644 SM8475-Xiaomi-Marble-tplg.bin \
      "$out/lib/firmware/qcom/sm8450/SM8475-Xiaomi-Marble-tplg.bin"
  ''
