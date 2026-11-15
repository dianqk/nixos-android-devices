{
  writeShellApplication,
  alsa-utils,
  coreutils,
  gnused,
  jq,
  util-linux,
}:
writeShellApplication {
  name = "android-audio-orientation";
  runtimeInputs = [
    alsa-utils
    coreutils
    gnused
    jq
    util-linux
  ];
  text = builtins.readFile ./audio-orientation.sh;
}
