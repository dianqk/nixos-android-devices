/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef EG_INTENT_SELECTION_H
#define EG_INTENT_SELECTION_H
#include "commit-intent.h"
#include "menu.h"
/* Offline next-protocol composition, NOT the existing bootstrap's 0/1 ABI.
 * Must run only after the exact profile/normal-mode/ownership guards. On a
 * refused result caller must use original Android with original x0, not reset.
 * Output token is meaningful for the U-Boot routes, including NOPREFWRITE. */
enum eg_choice_route eg_intent_selection(const struct eg_menu_io *,
    const unsigned char *pages,const unsigned char *generation,unsigned char *token);
#endif
