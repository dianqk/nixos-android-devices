{ runCommand }:
runCommand "asphalt-disabled-dtbo.img" { } ''
  dd if=/dev/zero of=$out bs=1048576 count=24 status=none
''
