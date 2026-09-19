#include <cassert>
#include <cmath>
#include <cstdio>
#include <string>

#include "modules/ampere/sampler.hpp"

using namespace waybar::modules::ampere;

static bool close(double a, double b) { return std::fabs(a - b) < 1e-9; }

int main() {
  // /proc/stat first line: cpu user nice system idle iowait irq softirq steal guest guest_nice
  auto ct = parseCpuStat("cpu  100 20 50 1000 30 5 7 2 0 0");
  assert(ct.busy == 184.0);            // 100+20+50+5+7+2
  assert(ct.all == 1214.0);            // busy + idle(1000) + iowait(30)

  // 50%: busy +100 over all +200
  assert(close(cpuPctFromDelta(284, 1414, 184, 1214), 50.0));
  // no time elapsed -> 0, not NaN/inf
  assert(close(cpuPctFromDelta(100, 100, 100, 100), 0.0));
  // clamp
  assert(close(cpuPctFromDelta(200, 200, 0, 100), 100.0));
  assert(close(cpuPctFromDelta(0, 200, 100, 100), 0.0));

  const std::string mi =
      "MemTotal:       16000000 kB\n"
      "MemFree:         1000000 kB\n"
      "MemAvailable:    8000000 kB\n";
  assert(close(memPctFromInfo(mi), 50.0));
  assert(memPctFromInfo("MemTotal: 1 kB\n") < 0.0);  // missing MemAvailable
  assert(memPctFromInfo("") < 0.0);

  printf("sampler_test: all assertions passed\n");
  return 0;
}
