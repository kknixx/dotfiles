#!/bin/sh
# Regression check: on this AMD box the ampere sampler must resolve the CPU
# package temp (k10temp Tctl), not the first-listed sensor (NVMe).
# Usage: sh tests/ampere/sensor_fix_check.sh   (from the waybar source dir)
set -e
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.cpp" <<'EOF'
#include <cstdio>
#include "modules/ampere/sampler.hpp"
int main() {
  const auto r = waybar::modules::ampere::Sampler().temp();
  printf("%.1f\n", r.celsius);
}
EOF
g++ -I include "$tmp/main.cpp" src/modules/ampere/sampler.cpp -o "$tmp/check"
got=$("$tmp/check")
k10=$(for d in /sys/class/hwmon/hwmon*; do [ "$(cat "$d/name" 2>/dev/null)" = "k10temp" ] && echo "$d" && break; done)
[ -n "$k10" ] || { echo "SKIP: no k10temp hwmon on this box"; exit 0; }
tctl=$(for t in "$k10"/temp*_input; do [ "$(cat "${t%_input}_label" 2>/dev/null)" = "Tctl" ] && echo "$t" && break; done)
[ -n "$tctl" ] || { echo "SKIP: no Tctl input under k10temp"; exit 0; }
want=$(awk '{print $1/1000.0}' "$tctl")
awk -v g="$got" -v w="$want" 'BEGIN { d = g - w; if (d < 0) d = -d; exit d > 1.0 ? 1 : 0 }' \
  && echo "PASS: sampler ${got}C ~= k10temp Tctl ${want}C" \
  || { echo "FAIL: sampler ${got}C != Tctl ${want}C"; exit 1; }
