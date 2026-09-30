# Shared A/B UFS layout contract. GPT indices and root/ESP order are not identity.
.partitiontable as $t |
[$t.partitions[] | select(.name == "userdata")] as $users |
[$t.partitions[] | select(.name == "linux")] as $roots |
[$t.partitions[] | select(.name == "linux-boot")] as $esps |
($ARGS.named.espBytes // 1073741824) as $espBytes |
($t.partitions | sort_by(.start)) as $sorted |
$users[0] as $userdata | $roots[0] as $root | $esps[0] as $esp |
$t.label == "gpt" and $t.device == $disk and $t.sectorsize == 4096 and
($users | length == 1) and ($roots | length == 1) and ($esps | length == 1) and
all($sorted[]; .start == (.start | floor) and .size == (.size | floor) and
  .start >= ($t.firstlba // 1) and .size > 0 and .start + .size - 1 <= $t.lastlba) and
all(range(1; $sorted | length); . as $i |
  $sorted[$i - 1].start + $sorted[$i - 1].size <= $sorted[$i].start) and
$root.node == $node and
(($root.type | ascii_upcase) == "0FC63DAF-8483-4772-8E79-3D69D8477DE4") and
(($userdata.type | ascii_upcase) |
  . == "1B81E7E6-F50D-419B-A739-2AEEF8DA3335" or
  . == "0FC63DAF-8483-4772-8E79-3D69D8477DE4") and
($espBytes == 0 or $esp.size * $t.sectorsize == $espBytes) and
(($esp.type | ascii_upcase) == "C12A7328-F81F-11D2-BA4B-00A0C93EC93B") and
($userdata.start + $userdata.size <= $root.start) and
($userdata.start + $userdata.size <= $esp.start)
