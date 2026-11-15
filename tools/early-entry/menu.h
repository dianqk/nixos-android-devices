/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef EG_MENU_H
#define EG_MENU_H
#include "draw.h"
/* Selection policy takes explicit clock/key/paint callbacks, not a board name.
 * bits0/1/2 are Up/Down/Power. No storage backend is called by the menu. */
struct eg_menu_io {
 void *ctx;
 int (*clock)(void *,uint64_t *,uint64_t *);
 int (*keys)(void *,unsigned *);
 void (*paint)(void *,unsigned,unsigned);
};
unsigned eg_menu(const struct eg_menu_io *,unsigned preference);
#endif
