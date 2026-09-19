#include "modules/ampere/renderer.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>

/* Fixed appearance — the 'ampere' theme with the user's loaded overrides
 * (green zone #1DACC6). Baked in per spec: no config surface. */
#define GAUGE_GREEN   0.1137, 0.6745, 0.7765 /* #1DACC6 */
#define GAUGE_YELLOW  0.8980, 0.6471, 0.0392 /* #E5A50A */
#define GAUGE_RED     0.6471, 0.1137, 0.1765 /* #A51D2D */
#define NEEDLE_RGBA   1.0, 1.0, 1.0, 1.0
#define TICK_RGBA     0.8118, 0.8118, 0.8118 /* #cfcfcf */
#define LABEL_RGBA    0.9098, 0.9098, 0.9098 /* #e8e8e8 */
#define HALO_RGBA     0.0470, 0.0470, 0.0627, 0.6
#define PIVOT_RGBA    0.8627, 0.8627, 0.8627 /* #dcdcdc */

static void stroke_zone(cairo_t *cr, double cx, double py, double radius,
                        double a0, double a1, double r, double g, double b) {
  cairo_set_source_rgb(cr, r, g, b);
  cairo_arc(cr, cx, py, radius, a0, a1);
  cairo_stroke(cr);
}

static void draw_halo_text(cairo_t *cr, double x, double y, const char *text,
                           double th, double r, double g, double b, double a) {
  cairo_set_source_rgba(cr, r, g, b, a);
  for (int i = 0; i < 8; i++) {
    const double ang = i * M_PI / 4.0;
    cairo_move_to(cr, x + cos(ang) * th, y + sin(ang) * th);
    cairo_show_text(cr, text);
  }
}

void ampere_draw_gauge(cairo_t *cr, int w, int h, double level, const char *label) {
  if (level < 0) level = 0;
  if (level > 1) level = 1;

  const double cx = w / 2.0;
  const double py = h - 2;
  const double arc_width = fmax(4.0, w * 0.12);
  const double radius = fmax(6.0, fmin(w / 2.0 - 2, py - arc_width / 2 - 2));
  const double needle_len = radius - arc_width / 2 - 1;

  /* Zones: green 0..0.70, yellow 0.70..0.87, red 0.87..1 */
  cairo_set_line_width(cr, arc_width);
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT);
  stroke_zone(cr, cx, py, radius, M_PI + 0.0 * M_PI, M_PI + 0.70 * M_PI,
              GAUGE_GREEN);
  stroke_zone(cr, cx, py, radius, M_PI + 0.70 * M_PI, M_PI + 0.87 * M_PI,
              GAUGE_YELLOW);
  stroke_zone(cr, cx, py, radius, M_PI + 0.87 * M_PI, M_PI + 1.0 * M_PI,
              GAUGE_RED);

  /* End marks only: the low/high ticks at the two arc endpoints ("L" and
   * "H"). The 9 minor ticks between them are intentionally omitted. */
  {
    const double r0v = radius - arc_width - 2;
    const double r1v = radius - arc_width - 6;
    for (int e = 0; e < 2; e++) {
      const double f = e == 0 ? 0.0 : 1.0;
      const double a = M_PI + f * M_PI;
      cairo_set_source_rgb(cr, TICK_RGBA);
      cairo_set_line_width(cr, 1.6);
      cairo_move_to(cr, cx + (r0v - 1) * cos(a), py + (r0v - 1) * sin(a));
      cairo_line_to(cr, cx + (r1v + 1) * cos(a), py + (r1v + 1) * sin(a));
      cairo_stroke(cr);
    }
  }

  /* Label centered just above the pivot, with a dark halo so it reads
   * against the pill. Drawn BEFORE the needle so the needle stays crisp
   * on top. (The 0/50/100 dial numerals are OFF per the loaded
   * show-numbers=false — do not add them.) */
  const double pivot_r = fmax(1.5, w * 0.04);
  int fs = (int)lround(w * 0.16);
  if (fs < 6) fs = 6;
  cairo_set_font_size(cr, fs);
  cairo_text_extents_t ext;
  cairo_text_extents(cr, label, &ext);
  const double lx = cx - ext.width / 2.0;
  const double ly = py - pivot_r - 1.0;
  const double th = fmax(1.0, ceil(fs * 0.12));
  draw_halo_text(cr, lx, ly, label, th, HALO_RGBA);
  cairo_set_source_rgb(cr, LABEL_RGBA);
  cairo_move_to(cr, lx, ly);
  cairo_show_text(cr, label);

  /* Needle with halo */
  const double nw = fmax(2.0, w * 0.055);
  const double a = M_PI + level * M_PI;
  const double nx = cx + needle_len * cos(a);
  const double ny = py + needle_len * sin(a);
  const double halo_w = fmax(1.0, nw * 0.5);
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
  cairo_set_source_rgba(cr, HALO_RGBA);
  cairo_set_line_width(cr, nw + halo_w * 2);
  cairo_move_to(cr, cx, py);
  cairo_line_to(cr, nx, ny);
  cairo_stroke(cr);
  cairo_set_source_rgba(cr, NEEDLE_RGBA);
  cairo_set_line_width(cr, nw);
  cairo_move_to(cr, cx, py);
  cairo_line_to(cr, nx, ny);
  cairo_stroke(cr);

  /* Pivot */
  cairo_set_source_rgb(cr, PIVOT_RGBA);
  cairo_arc(cr, cx, py, pivot_r, 0, 2 * M_PI);
  cairo_fill(cr);
}

void ampere_draw_thermo(cairo_t *cr, int w, int h, double level, double temp_c,
                        double temp_max_c) {
  if (level < 0) level = 0;
  if (level > 1) level = 1;

  const double cy = h / 2.0;
  const double r = fmax(6.0, fmin(w - 12, floor(h / 2.0) - 3));
  const double arc_width = fmax(3.0, lround(r * 0.45));
  const double cx = r + arc_width / 2.0 + 1;
  const double needle_len = r + 1;
  const double a0 = M_PI / 2.0;
  const double span = M_PI;
  const double green_end = a0 + span * 0.35;
  const double yellow_end = a0 + span * 0.70;

  /* Zones: cold->hot from bottom-left (cold) clockwise to top (hot) */
  cairo_set_line_width(cr, arc_width);
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT);
  stroke_zone(cr, cx, cy, r, a0, green_end, GAUGE_GREEN);
  stroke_zone(cr, cx, cy, r, green_end, yellow_end, GAUGE_YELLOW);
  stroke_zone(cr, cx, cy, r, yellow_end, a0 + span, GAUGE_RED);

  /* End marks only: the cold/hot ticks at the two arc endpoints, matching
   * the gauges' low/high marks. The 3 interior ticks are omitted. */
  {
    const double r0 = r - arc_width - 1;
    const double r1 = fmax(1.5, r - arc_width - 4.5);
    for (int e = 0; e < 2; e++) {
      const double f = e == 0 ? 0.0 : 1.0;
      const double a = a0 + f * span;
      cairo_set_source_rgba(cr, TICK_RGBA, 0.8);
      cairo_set_line_width(cr, 1.6);
      cairo_move_to(cr, cx + r0 * cos(a), cy + r0 * sin(a));
      cairo_line_to(cr, cx + r1 * cos(a), cy + r1 * sin(a));
      cairo_stroke(cr);
    }
  }

  /* Needle — width factor 0.055, the ampere theme's needleWidth (same as the gauge) */
  const double nw = fmax(2.0, w * 0.055);
  const double a = a0 + span * level;
  const double nx = cx + needle_len * cos(a);
  const double ny = cy + needle_len * sin(a);
  const double halo_w = fmax(1.0, nw * 0.5);
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
  cairo_set_source_rgba(cr, HALO_RGBA);
  cairo_set_line_width(cr, nw + halo_w * 2);
  cairo_move_to(cr, cx, cy);
  cairo_line_to(cr, nx, ny);
  cairo_stroke(cr);
  cairo_set_source_rgba(cr, NEEDLE_RGBA);
  cairo_set_line_width(cr, nw);
  cairo_move_to(cr, cx, cy);
  cairo_line_to(cr, nx, ny);
  cairo_stroke(cr);

  /* Pivot */
  cairo_set_source_rgb(cr, PIVOT_RGBA);
  cairo_arc(cr, cx, cy, fmax(1.5, r * 0.18), 0, 2 * M_PI);
  cairo_fill(cr);

  /* °C readout in the open right half; hidden when sensor unreadable */
  if (temp_c >= 0) {
    double shown = temp_c;
    if (shown > temp_max_c) shown = temp_max_c;
    char text[16];
    snprintf(text, sizeof(text), "%lld°", (long long)llround(shown));
    const double right_space = (w - 1) - cx;
    int fs = (int)lround(h * 0.40);
    if (fs < 9) fs = 9;
    cairo_set_font_size(cr, fs);
    cairo_text_extents_t ext;
    cairo_text_extents(cr, text, &ext);
    while (ext.width > right_space && fs > 8) {
      fs -= 1;
      cairo_set_font_size(cr, fs);
      cairo_text_extents(cr, text, &ext);
    }
    const double lx = cx + right_space / 2.0 - ext.width / 2.0;
    const double ly = cy + ext.height / 3.0;
    const double th = fmax(1.0, ceil(fs * 0.12));
    draw_halo_text(cr, lx, ly, text, th, HALO_RGBA);
    cairo_set_source_rgb(cr, LABEL_RGBA);
    cairo_move_to(cr, lx, ly);
    cairo_show_text(cr, text);
  }
}
