/* SPDX-License-Identifier: MIT */
#pragma once
#include "core.h"
#define UI_MAX_COLUMNS 128
#define UI_MAX_ROWS 128
/* '#' represents a solid white cell; ordinary ASCII is white on black. */
struct canvas { unsigned width, height; char cells[UI_MAX_COLUMNS * UI_MAX_ROWS]; };
int render(struct canvas *, const struct sample *, const char *message);
int write_preview(const char *path, const struct sample *, unsigned columns, unsigned rows);
