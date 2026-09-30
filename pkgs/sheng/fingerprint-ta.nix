{ runCommand, firmware-source }:
runCommand "sheng-fingerprint-ta" { } ''
  install -Dm0644 ${firmware-source}/fpcsheng.elf $out/lib/firmware/fpcsheng.elf
''
