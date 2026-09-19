#ifndef WAYBAR_MODULES_AMPERE_RENDERER_H
#define WAYBAR_MODULES_AMPERE_RENDERER_H

#include <cairo.h>

#ifdef __cplusplus
extern "C" {
#endif

void ampere_draw_gauge(cairo_t *cr, int w, int h, double level, const char *label);
void ampere_draw_thermo(cairo_t *cr, int w, int h, double level, double temp_c,
                        double temp_max_c);

#ifdef __cplusplus
}
#endif

#endif
