{
  runCommand,
  buildPackages,
  lib,
}:

{
  name,
  kernel,
  initrd,
  cmdline,
  dtbs ? [ ],
  base,
  kernelOffset,
  ramdiskOffset,
  secondOffset,
  tagsOffset,
  pageSize,
  maximumBytes ? null,
  avbFooter ? null,
  headerVersion ? 0,
  dtbPlacement ? "append-to-kernel",
  dtbOffset ? "0x00000000",
}:
assert lib.assertMsg (
  dtbPlacement != "boot-image" || headerVersion == 2
) "Android boot-image DTBs require boot header version 2";
assert lib.assertMsg (
  dtbPlacement != "boot-image" || dtbs != [ ]
) "Android boot-image DTB placement requires at least one DTB";
runCommand name
  {
    nativeBuildInputs = [ buildPackages.android-tools ];
  }
  ''
    kernel_image="$TMPDIR/kernel-with-dtbs"
    dtb_args=()
    ${
      if dtbPlacement == "boot-image" then
        ''
          cp ${kernel} "$kernel_image"
          dtb_image="$TMPDIR/dtbs"
          cat ${lib.escapeShellArgs dtbs} > "$dtb_image"
          dtb_args=(--dtb "$dtb_image" --dtb_offset ${dtbOffset})
        ''
      else
        ''
          cat ${kernel} ${lib.escapeShellArgs dtbs} > "$kernel_image"
        ''
    }
    header_args=(
      ${lib.optionalString (headerVersion < 3) ''
        --base ${base}
        --kernel_offset ${kernelOffset}
        --ramdisk_offset ${ramdiskOffset}
        --second_offset ${secondOffset}
        --tags_offset ${tagsOffset}
        --pagesize ${pageSize}
      ''}
    )
    mkbootimg "''${header_args[@]}" \
      "''${dtb_args[@]}" \
      --header_version ${toString headerVersion} \
      --kernel "$kernel_image" \
      --ramdisk ${initrd} \
      --cmdline ${lib.escapeShellArg cmdline} \
      -o "$out"
    test "$(head -c 8 "$out")" = 'ANDROID!'
    ${lib.optionalString (avbFooter != null) ''
      # Replace the entire partition, including any old footer. A short raw
      # flash can otherwise leave a footer pointing inside the new payload.
      avbtool add_hash_footer --image "$out" \
        --partition_name ${lib.escapeShellArg avbFooter.partitionName} \
        --partition_size ${toString avbFooter.partitionSize} \
        --algorithm NONE --hash_algorithm sha256 --salt ""
      test "$(stat -c %s "$out")" -eq ${toString avbFooter.partitionSize}
      # avbtool resolves hash descriptors relative to the input filename.
      ln -s "$out" "$TMPDIR/${avbFooter.partitionName}.img"
      avbtool verify_image --image "$TMPDIR/${avbFooter.partitionName}.img"
    ''}
    ${lib.optionalString (maximumBytes != null) ''
      size=$(stat -c %s "$out")
      test "$size" -le ${toString maximumBytes} || {
        echo "Android boot image is $size bytes; limit is ${toString maximumBytes}" >&2
        exit 1
      }
    ''}
  ''
