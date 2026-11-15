# Mali-G615 (arch 11.8) CSF firmware for panthor, from linux-firmware.
{
  runCommand,
  linux-firmware,
}:
runCommand "t880-gpu-firmware" { } ''
  mkdir -p $out/lib/firmware/arm/mali/arch11.8
  cp ${linux-firmware}/lib/firmware/arm/mali/arch11.8/mali_csffw.bin* \
    $out/lib/firmware/arm/mali/arch11.8/
  test -n "$(ls $out/lib/firmware/arm/mali/arch11.8/mali_csffw.bin*)"
''
