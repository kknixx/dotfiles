#pragma once

#include <string>

namespace waybar::modules::ampere {

struct CpuTimes {
  double busy{};
  double all{};
};

struct TempReading {
  bool ok = false;
  double celsius = 0.0;
  double maxC = 100.0;
};

CpuTimes parseCpuStat(const std::string& firstLine);
double cpuPctFromDelta(double busy, double all, double prevBusy, double prevAll);
double memPctFromInfo(const std::string& meminfoContents);

class Sampler {
 public:
  Sampler();
  double cpuPct();  // first call primes the baseline and returns 0
  double memPct();
  TempReading temp() const;

 private:
  double prevBusy_ = 0.0;
  double prevAll_ = 0.0;
  bool cpuPrimed_ = false;
  mutable std::string tempInputPath_;
  mutable std::string tempMaxPath_;  // may be empty -> maxC stays 100
  void resolveSensor();
};

}  // namespace waybar::modules::ampere
