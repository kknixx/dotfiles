#include <cairo.h>
#include <stdio.h>

#include "modules/ampere/renderer.h"

/* Renders CPU/MEM/thermo at fixed levels to PNGs for visual QA against the
 * GNOME extension. Throwaway harness — not installed. */
static void render_case(const char *name, int w, int h, double cpu, double mem,
                        double thermo, double temp_c, double temp_max) {
  cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w * 3 + 24, h);
  cairo_t *cr = cairo_create(s);
  cairo_set_source_rgba(cr, 0.95, 0.95, 0.95, 1.0);
  cairo_paint(cr);
  cairo_save(cr); cairo_translate(cr, 4, 0);
  ampere_draw_gauge(cr, w, h, cpu, "CPU"); cairo_restore(cr);
  cairo_save(cr); cairo_translate(cr, w + 12, 0);
  ampere_draw_gauge(cr, w, h, mem, "MEM"); cairo_restore(cr);
  cairo_save(cr); cairo_translate(cr, 2 * w + 20, 0);
  ampere_draw_thermo(cr, 43, h, thermo, temp_c, temp_max); cairo_restore(cr);
  cairo_destroy(cr);
  char path[512];
  snprintf(path, sizeof(path), "/tmp/ampere_ref_%s.png", name);
  cairo_surface_write_to_png(s, path);
  cairo_surface_destroy(s);
}

int main(void) {
  render_case("idle", 50, 30, 0.05, 0.30, 0.25, 50, 100);
  render_case("half", 50, 30, 0.50, 0.50, 0.50, 65, 100);
  render_case("max", 50, 30, 1.00, 0.92, 0.95, 95, 100);
  render_case("nocpu", 50, 30, 0.10, 0.20, 0.40, -1, 100);
  return 0;
}
