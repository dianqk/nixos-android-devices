# Clover's firmware loader supplies the runtime /lib/firmware tree.
{ mobile-tqftpserv }:
mobile-tqftpserv.overrideAttrs (_: {
  patches = [ ];
  postPatch = "";
})
