{ runCommand }:
let
  names = [
    "cs35l41-dsp1-spk-prot-xiaomi-unicorn-t.wmfw"
    "cs35l41-dsp1-spk-prot-xiaomi-unicorn-t.bin"
    "cs35l41-dsp1-spk-prot-xiaomi-unicorn-b.wmfw"
    "cs35l41-dsp1-spk-prot-xiaomi-unicorn-b.bin"
    "cs35l41-xiaomi-unicorn-calibration.bin"
    "cs35l41-xiaomi-unicorn-t-music.be32"
    "cs35l41-xiaomi-unicorn-b-music.be32"
  ];
in runCommand "unicorn-speaker-runtime-links" {
  # The targets intentionally do not exist during a Nix build. Never compress
  # or dereference them; only these public names/links enter the store.
  passthru.compressFirmware = false;
} ''
  mkdir -p $out/lib/firmware/cirrus
  for name in ${builtins.concatStringsSep " " names}; do
    ln -s /run/unicorn-audio/firmware/cirrus/$name $out/lib/firmware/cirrus/$name
  done
''
