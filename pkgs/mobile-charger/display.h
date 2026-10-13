/* SPDX-License-Identifier: MIT */
#pragma once
#include "ui.h"
struct display;
struct display_geometry { unsigned width_mm, height_mm, font_width; };
struct display *display_open(const char *connector, const char *backlight,
                             const struct display_geometry *);
int display_power(struct display *, bool on);
int display_show(struct display *, const struct canvas *);
unsigned display_width(const struct display *);
unsigned display_height(const struct display *);
void display_close(struct display *);
