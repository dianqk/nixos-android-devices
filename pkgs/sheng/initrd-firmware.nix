{
  runCommand,
  wireless-regdb,
  sheng-firmware,
}:
runCommand "sheng-initrd-firmware" { } ''
  mkdir -p $out/lib/firmware
  cp -r --no-preserve=mode ${sheng-firmware}/lib/firmware/qcom $out/lib/firmware/
  # PAS is built into Sheng's kernel and auto-starts ADSP/CDSP while udev is
  # still running in the initrd, so their main images must accompany the DTB
  # metadata already present here. The video blob is stage-2-only and remains
  # excluded to keep the initrd small.
  find $out/lib/firmware/qcom -type f \
    -name vpu30_4v.mbn -delete
  cp -r --no-preserve=mode ${sheng-firmware}/lib/firmware/novatek $out/lib/firmware/
  cp -r --no-preserve=mode ${wireless-regdb}/lib/firmware/. $out/lib/firmware/
''
