{
  runCommand,
  boot-selector-builder,
  boot-choice-efi,
  firmware,
  diagnosticStages ? false,
}:
runCommand "dodge-boot-choice-template-${if diagnosticStages then "diagnostic" else "1"}" { } ''
  ${boot-selector-builder}/bin/boot-selector-builder \
    --adapter dodge --export-template --intent-prototype ${
      if diagnosticStages then "--diagnostic-stages" else ""
    } \
    --payload ${firmware}/u-boot.bin --elf ${firmware}/u-boot \
    --config ${firmware}/.config \
    --efi-helper ${boot-choice-efi}/boot-choice.efi --output-dir $out
''
