import sys
from pathlib import Path


path = Path(sys.argv[1])
source = path.read_text()

scan_anchor = "# Scan through mounted partitions and symlink all of the blobs.\n"
writable_directories = r'''# NixOS provides some top-level firmware directories as links into its
# immutable merged tree. Expand directories that need stock additions into
# writable runtime directories without changing anything in the Nix store.
for directory in qcom qca
do
	if [ -L "$BASEDIR/target/$directory" ]
	then
		EXTRA_DIRECTORY="$(readlink "$BASEDIR/target/$directory")"
		rm "$BASEDIR/target/$directory"
		mkdir "$BASEDIR/target/$directory"
		for blob in "$EXTRA_DIRECTORY"/*
		do
			if ! [ -e "$blob" ]; then break; fi
			ln -s "$blob" "$BASEDIR/target/$directory/$(basename "$blob")"
		done
	fi
done

'''
assert source.count(scan_anchor) == 1
source = source.replace(scan_anchor, writable_directories + scan_anchor)

old_bluetooth = r'''	for btblob in "$BASEDIR/mnt/bluetooth$(ab_get_slot)/image"/*
	do
		ln -s "$btblob" "$BASEDIR"/target/qca/
	done'''
new_bluetooth = r'''	for btblob in "$BASEDIR/mnt/bluetooth$(ab_get_slot)/image"/*
	do
		target="$BASEDIR/target/qca/$(basename "$btblob")"
		if ! [ -e "$target" ]; then ln -s "$btblob" "$target"; fi
	done'''
assert source.count(old_bluetooth) == 1
source = source.replace(old_bluetooth, new_bluetooth)

old_prefix = (
    'FIRMWARE_PREFIX=$(find /sys/firmware/devicetree -name "firmware-name" '
    '| head -n1 | xargs cat | xargs dirname)'
)
new_prefix = r'''FIRMWARE_PROPERTY=$(find /sys/firmware/devicetree -name "firmware-name" -print -quit)
if [ -n "$FIRMWARE_PROPERTY" ]
then
	FIRMWARE_NAME=$(tr -d '\000' < "$FIRMWARE_PROPERTY")
	FIRMWARE_PREFIX=$(dirname "$FIRMWARE_NAME")
else
	FIRMWARE_PREFIX=""
fi'''
assert source.count(old_prefix) == 1
path.write_text(source.replace(old_prefix, new_prefix))
