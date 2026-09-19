#include "modules/ampere/sampler.hpp"

#include <cctype>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace waybar::modules::ampere {

namespace {

std::string readFile(const std::string& path) {
  std::ifstream f(path);
  if (!f) return "";
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

bool readIntFile(const std::string& path, long& out) {
  std::string s = readFile(path);
  if (s.empty()) return false;
  const auto end = s.find_first_not_of("0123456789-");
  if (end == 0) return false;  // no leading numeric run (e.g. "N/A") -> would throw
  out = std::stol(s.substr(0, end == std::string::npos ? s.size() : end));
  return true;
}

// "MemTotal:" / "MemAvailable:" key -> kB value, -1 if absent
long meminfoField(const std::string& content, const std::string& key) {
  auto pos = content.find(key);
  if (pos == std::string::npos) return -1;
  pos += key.size();
  while (pos < content.size() && (content[pos] == ' ' || content[pos] == '\t')) pos++;
  if (pos >= content.size()) return -1;
  long v = 0;
  if (std::sscanf(content.c_str() + pos, "%ld", &v) != 1) return -1;
  return v;
}

struct Candidate {
  std::string name;   // hwmon `name` or thermal `type` (fallback: path stem)
  std::string label;  // hwmon `tempN_label` (fallback "tempN") or thermal `type`
  std::string input;  // absolute millidegree file
  std::string maxp;   // absolute tempN_max (hwmon only; empty for thermal)
};

std::string stemOf(const std::string& p) {
  auto i = p.find_last_of('/');
  return i == std::string::npos ? p : p.substr(i + 1);
}

std::string lowerCopy(const std::string& s) {
  std::string o;
  for (char c : s) o += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return o;
}

std::string upperCopy(const std::string& s) {
  std::string o;
  for (char c : s) o += static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
  return o;
}

// sensor.js defaultSensorId priority 1: /^package/i on the label (anchored, case-insensitive).
bool labelIsPackage(const std::string& label) {
  const std::string l = lowerCopy(label);
  return l.size() >= 7 && l.compare(0, 7, "package") == 0;
}

// Anchored case-insensitive prefix match on the label (e.g. "tctl" matches "Tctl").
bool labelIsPrefix(const std::string& label, const std::string& prefix) {
  const std::string l = lowerCopy(label);
  return l.compare(0, prefix.size(), prefix) == 0;
}

// Faithful port of sensor.js listSensors(): hwmon temps (readable, hwmon0..31 x
// temp1..16) in order, then thermal zones (0..63, present) in order.
std::vector<Candidate> listSensors() {
  std::vector<Candidate> out;
  for (int hw = 0; hw < 32; hw++) {
    char base[64];
    std::snprintf(base, sizeof(base), "/sys/class/hwmon/hwmon%d", hw);
    std::string name = readFile(std::string(base) + "/name");
    while (!name.empty() && (name.back() == '\n' || name.back() == '\r')) name.pop_back();
    if (name.empty()) name = stemOf(base);
    for (int n = 1; n <= 16; n++) {
      char slot[96];
      std::snprintf(slot, sizeof(slot), "%s/temp%d", base, n);
      long val;
      if (!readIntFile(std::string(slot) + "_input", val)) continue;
      std::string label = readFile(std::string(slot) + "_label");
      while (!label.empty() && (label.back() == '\n' || label.back() == '\r')) label.pop_back();
      if (label.empty()) label = "temp" + std::to_string(n);
      Candidate c;
      c.name = name;
      c.label = label;
      c.input = std::string(slot) + "_input";
      long mx;
      if (readIntFile(std::string(slot) + "_max", mx) && mx > 0)
        c.maxp = std::string(slot) + "_max";
      out.push_back(std::move(c));
    }
  }
  for (int z = 0; z < 64; z++) {
    char slot[64];
    std::snprintf(slot, sizeof(slot), "/sys/class/thermal/thermal_zone%d", z);
    std::string type = readFile(std::string(slot) + "/type");
    while (!type.empty() && (type.back() == '\n' || type.back() == '\r')) type.pop_back();
    long val;
    const bool present = !type.empty() || readIntFile(std::string(slot) + "/temp", val);
    if (!present) continue;
    Candidate c;
    c.name = type.empty() ? stemOf(std::string(slot)) : type;
    c.label = c.name;
    c.input = std::string(slot) + "/temp";
    out.push_back(std::move(c));
  }
  return out;
}

}  // namespace

CpuTimes parseCpuStat(const std::string& firstLine) {
  CpuTimes t;
  std::istringstream ss(firstLine);
  std::string tag;
  double v[10] = {0};
  ss >> tag;
  for (int i = 0; i < 10 && ss; ++i) ss >> v[i];
  // v: user nice system idle iowait irq softirq steal guest guest_nice
  t.busy = v[0] + v[1] + v[2] + v[5] + v[6] + v[7];
  t.all = t.busy + v[3] + v[4];
  return t;
}

double cpuPctFromDelta(double busy, double all, double prevBusy, double prevAll) {
  const double dBusy = busy - prevBusy;
  const double dAll = all - prevAll;
  if (dAll <= 0) return 0.0;
  double pct = dBusy / dAll * 100.0;
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  return pct;
}

double memPctFromInfo(const std::string& content) {
  const long total = meminfoField(content, "MemTotal:");
  const long avail = meminfoField(content, "MemAvailable:");
  if (total <= 0 || avail < 0) return -1.0;
  double pct = (total - avail) / static_cast<double>(total) * 100.0;
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  return pct;
}

Sampler::Sampler() { resolveSensor(); }

double Sampler::cpuPct() {
  const std::string line = readFile("/proc/stat");
  auto eol = line.find('\n');
  const std::string first = eol == std::string::npos ? line : line.substr(0, eol);
  const CpuTimes now = parseCpuStat(first);
  double pct = 0.0;
  if (cpuPrimed_) {
    pct = cpuPctFromDelta(now.busy, now.all, prevBusy_, prevAll_);
  }
  prevBusy_ = now.busy;
  prevAll_ = now.all;
  cpuPrimed_ = true;
  return pct;
}

double Sampler::memPct() {
  const double pct = memPctFromInfo(readFile("/proc/meminfo"));
  return pct < 0 ? 0.0 : pct;
}

void Sampler::resolveSensor() {
  // Faithful port of sensor.js defaultSensorId: three priority finds over a
  // COMBINED ordered sensor list (hwmon temps, then thermal zones).
  const std::vector<Candidate> sensors = listSensors();

  // 1) coretemp "Package id 0"  (/^package/i on the label)
  for (const auto& c : sensors) {
    if (c.name == "coretemp" && labelIsPackage(c.label)) {
      tempInputPath_ = c.input;
      tempMaxPath_ = c.maxp;
      return;
    }
  }
  // 2) AMD k10temp "Tctl" — package temp, the AMD equivalent of coretemp's
  //    "Package id 0" (without this, AMD boxes fall through to the first
  //    sensor in list order, which is often an NVMe drive, not the CPU).
  for (const auto& c : sensors) {
    if (c.name == "k10temp" && labelIsPrefix(c.label, "tctl")) {
      tempInputPath_ = c.input;
      tempMaxPath_ = c.maxp;
      return;
    }
  }
  // 3) a TCPU sensor (name "TCPU", case-insensitive), anywhere in the list
  for (const auto& c : sensors) {
    if (upperCopy(c.name) == "TCPU") {
      tempInputPath_ = c.input;
      tempMaxPath_ = c.maxp;
      return;
    }
  }
  // 4) first sensor
  if (!sensors.empty()) {
    tempInputPath_ = sensors[0].input;
    tempMaxPath_ = sensors[0].maxp;
  }
}

TempReading Sampler::temp() const {
  TempReading r;
  if (tempInputPath_.empty()) return r;
  long milli;
  if (!readIntFile(tempInputPath_, milli)) return r;
  r.ok = true;
  r.celsius = milli / 1000.0;
  if (!tempMaxPath_.empty()) {
    long maxMilli;
    if (readIntFile(tempMaxPath_, maxMilli) && maxMilli > 0) r.maxC = maxMilli / 1000.0;
  }
  return r;
}

}  // namespace waybar::modules::ampere
