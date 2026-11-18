{ runCommand, unicorn-firmware }:
runCommand "unicorn-initrd-firmware" { } ''
  mkdir -p "$out/lib/firmware"
  # GPU and PAS are built in and can request firmware before stage 2 starts.
  cp -r --no-preserve=mode ${unicorn-firmware}/lib/firmware/qcom "$out/lib/firmware/"
''
