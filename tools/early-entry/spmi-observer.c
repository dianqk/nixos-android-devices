/* SPDX-License-Identifier: GPL-2.0-only
 * Derived transport algorithm: Project-SunUEFI 018634f,
 * uefi/handoff/bootselect/EarlyKeys.c (GPL-2.0-only),
 * https://github.com/slwyts/Project-SunUEFI (see provenance.md).
 * APID preference/count/offset semantics: Linux drivers/spmi/spmi-pmic-arb.c.
 * This implementation takes explicit maps and injected I/O, not board policy.
 */
#include "spmi-observer.h"
static int valid(const struct eg_spmi_io *io)
{
    return io && io->read && io->write &&
        !(io->core & 3) && !(io->config & 3) && !(io->observer & 3) &&
        io->core <= UINT64_MAX-0x3000 && io->config <= UINT64_MAX-0x1000 &&
        io->observer <= UINT64_MAX-0x8000;
}
int eg_spmi_find(const struct eg_spmi_io *io, uint16_t ppid, uint16_t *apid)
{
    uint32_t version, count, map, owner; int found=0;
    uint16_t selected=0;
    if (!valid(io) || !apid || ppid>0xfff ||
        !io->read(io->context,io->core,&version) ||
        !io->read(io->context,io->core+4,&count)) return 0;
    count &= 0x7ff;
    if (version<0x70000000 || version>=0x80000000 || !count || count>1024) return 0;
    for (unsigned i=0;i<count;i++) {
        if (!io->read(io->context,io->core+0x2000+4*i,&map)) return 0;
        if (!map || ((map>>8)&0xfff)!=ppid) continue;
        if (!io->read(io->context,io->config+4*i,&owner)) return 0;
        /* Linux: first match, overridden by each mapping owned by this EE. */
        if (!found || !(owner&7)) selected=(uint16_t)i;
        found=1;
    }
    if (found) *apid=selected;
    return found;
}
static int read_byte(const struct eg_spmi_io *io, uint16_t apid,
                      uint16_t address, uint8_t *value, unsigned polls)
{
    uint64_t start, now, channel; uint32_t state, data;
    if (!valid(io) || !value || apid>=1024 || polls>100000) return 0;
    if (!polls && (!io->counter || io->frequency<1000000 ||
        io->frequency>2000000000ULL || !io->counter(io->context,&start))) return 0;
    channel=io->observer+0x20ULL*apid;
    if (!io->write(io->context,channel,(1U<<27)|((address&255U)<<4))) return 0;
    for (unsigned spin=0;spin<(polls?polls:100000);spin++) {
        if (!io->read(io->context,channel+8,&state)) return 0;
        if (state&1) {
            if ((state&0xe) || !io->read(io->context,channel+0x18,&data)) return 0;
            *value=(uint8_t)data; return 1;
        }
        if (!polls && (!io->counter(io->context,&now) || now-start>=io->frequency/1000)) return 0;
    }
    return 0;
}

int eg_spmi_read_byte(const struct eg_spmi_io *io, uint16_t apid,
                      uint16_t address, uint8_t *value)
{ return read_byte(io,apid,address,value,0); }
int eg_spmi_read_byte_bounded(const struct eg_spmi_io *io, uint16_t apid,
                      uint16_t address, uint8_t *value, unsigned polls)
{ return polls ? read_byte(io,apid,address,value,polls) : 0; }
