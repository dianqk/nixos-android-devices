{
  fetchzip,
  runCommand,
  m4,
  alsa-utils,
}:
let
  source = fetchzip {
    name = "audioreach-topology-d6bb205a";
    url = "https://codeload.github.com/linux-msm/audioreach-topology/tar.gz/d6bb205aca5f4b8fa6b2f44cf8b5f6a081cbf037";
    extension = "tar.gz";
    hash = "sha256-J/xqKMa428ScOa/WOvoRopZpo2L70w78XRp8v7JHKRY=";
  };
in
runCommand "unicorn-audio-topology"
  {
    # alsatplg does not need a host PipeWire daemon or its multimedia closure.
    nativeBuildInputs = [
      m4
      (alsa-utils.override { withPipewireLib = false; })
    ];
    passthru.upstream = source;
  }
  ''
    # Keep the fixed upstream source immutable. Local files add the verified
    # legacy TDM endpoint and retain WR_SH output port1 required by the kernel.
    cp ${./module_tdm.m4} module_tdm.m4
    cp ${./subgraph-device-tdm-playback.m4} subgraph-device-tdm-playback.m4
    cp ${./subgraph-stream-playback.m4} subgraph-stream-playback.m4
    cp ${./tdm-parameters.m4} tdm-parameters.m4
    m4 -I. -I${source} ${./Xiaomi-12S-Pro.m4} > topology.conf
    mkdir -p $out/lib/firmware/qcom/sm8475 $out/share/unicorn-audio
    alsatplg -c topology.conf -o $out/lib/firmware/qcom/sm8475/Xiaomi-12S-Pro-tplg.bin \
      2>compile.log
    # External kernel DAI streams are not widgets in the topology. No other
    # undefined routes are accepted even if alsatplg returns success.
    sed "/^ALSA lib dapm.c:.*undefined sink widget\/stream 'RX_CODEC_DMA_RX_0 Playback'$/d; /^ALSA lib dapm.c:.*undefined source widget\/stream 'TX_CODEC_DMA_TX_3 Capture'$/d; /^ALSA lib dapm.c:.*undefined sink widget\/stream 'Tertiary TDM0 Playback'$/d" \
      compile.log > unexpected.log
    test ! -s unexpected.log || { cat unexpected.log >&2; exit 1; }
    cp topology.conf compile.log $out/share/unicorn-audio/
    cp ${source}/LICENSE.BSD-3-Clause $out/share/unicorn-audio/LICENSE
    alsatplg -d $out/lib/firmware/qcom/sm8475/Xiaomi-12S-Pro-tplg.bin \
      -o $out/share/unicorn-audio/decoded.conf
  ''
