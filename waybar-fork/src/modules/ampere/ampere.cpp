#include "modules/ampere/ampere.hpp"

#include <cairo.h>
#include <cmath>
#include <chrono>

#include "modules/ampere/renderer.h"

namespace waybar::modules {

Ampere::Ampere(const std::string& id, const Json::Value& config)
    : AModule(config, "ampere", id, false, false),
      sampler_(std::make_unique<ampere::Sampler>()) {
  box_.set_name("ampere");
  box_.get_style_context()->add_class("ampere");
  // Pill chrome is opt-out: "ampere": { "show-pill": false } in the waybar
  // config drops the class and the #ampere.ampere-pill CSS rule stops applying
  // (background, border, padding all come from that one rule).
  if (!config_["show-pill"].isBool() || config_["show-pill"].asBool()) {
    box_.get_style_context()->add_class("ampere-pill");
  }

  // gtkmm-3 Gtk::DrawingArea has no size-taking ctor — the tree's pattern
  // (AGraph) is default-construct + set_size_request. Sized so the whole pill
  // (area height + 3px*2 padding + 1px*2 border = 30px) fits the 32px bar and
  // the dials read as small as the neighboring tray/power icons.
  cpuArea_.set_size_request(38, 22);
  memArea_.set_size_request(38, 22);
  thermoArea_.set_size_request(33, 22);
  for (auto* area : {&cpuArea_, &memArea_, &thermoArea_}) {
    area->set_halign(Gtk::ALIGN_CENTER);
    area->set_valign(Gtk::ALIGN_CENTER);
  }
  box_.pack_start(cpuArea_, false, false, 2);
  box_.pack_start(memArea_, false, false, 2);
  box_.pack_start(thermoArea_, false, false, 2);
  event_box_.add(box_);

  cpuArea_.signal_draw().connect([this](const Cairo::RefPtr<Cairo::Context>& cr) -> bool {
    return onDrawGauge(cr, cpuArea_, cpuLevel_);
  });
  memArea_.signal_draw().connect([this](const Cairo::RefPtr<Cairo::Context>& cr) -> bool {
    return onDrawGauge(cr, memArea_, memLevel_);
  });
  thermoArea_.signal_draw().connect([this](const Cairo::RefPtr<Cairo::Context>& cr) -> bool {
    return onDrawThermo(cr);
  });

  thread_ = [this] {
    sampler_->cpuPct();  // prime baseline on first cycle
    for (;;) {
      const double cpu = sampler_->cpuPct();
      const double mem = sampler_->memPct();
      const ampere::TempReading t = sampler_->temp();
      {
        std::lock_guard<std::mutex> lock(targetMutex_);
        cpuTarget_ = cpu / 100.0;
        memTarget_ = mem / 100.0;
        if (t.ok) {
          const double lo = 30.0;
          double lvl = (t.celsius - lo) / (t.maxC - lo);
          if (lvl < 0) lvl = 0;
          if (lvl > 1) lvl = 1;
          thermoTarget_ = lvl;
          thermoTemp_ = t.celsius;
          thermoMax_ = t.maxC;
        } else {
          thermoTemp_ = -1.0;
        }
      }
      dp.emit();
      thread_.sleep_for(std::chrono::milliseconds(500));
    }
  };

  animConn_ =
      Glib::signal_timeout().connect([this] { ease(); return true; }, 33);
}

bool Ampere::onDrawGauge(const Cairo::RefPtr<Cairo::Context>& context, Gtk::DrawingArea& area,
                         double level) {
  // gtkmm hands us an already-scaled, owned cairo context — never cairo_destroy it.
  ampere_draw_gauge(context->cobj(), area.get_allocated_width(), area.get_allocated_height(),
                    level, &area == &cpuArea_ ? "CPU" : "MEM");
  return true;
}

bool Ampere::onDrawThermo(const Cairo::RefPtr<Cairo::Context>& context) {
  double temp = -1.0, maxC = 100.0;
  {
    std::lock_guard<std::mutex> lock(targetMutex_);
    temp = thermoTemp_;
    maxC = thermoMax_;
  }
  ampere_draw_thermo(context->cobj(), thermoArea_.get_allocated_width(),
                     thermoArea_.get_allocated_height(), thermoLevel_, temp, maxC);
  return true;
}

void Ampere::ease() {
  double tCpu, tMem;
  std::optional<double> tThermo;
  double temp = -1.0;
  {
    std::lock_guard<std::mutex> lock(targetMutex_);
    tCpu = cpuTarget_;
    tMem = memTarget_;
    tThermo = thermoTarget_;
    temp = thermoTemp_;
  }
  auto step = [](double& cur, double target) -> bool {
    if (cur == target) return false;
    double next = cur + (target - cur) * 0.18;
    if (std::fabs(target - next) < 0.002) next = target;
    if (next == cur) return false;
    cur = next;
    return true;
  };
  if (step(cpuLevel_, tCpu)) cpuArea_.queue_draw();
  if (step(memLevel_, tMem)) memArea_.queue_draw();
  if (tThermo.has_value() && step(thermoLevel_, tThermo.value())) thermoArea_.queue_draw();
  // Readout can change while the level is flat (e.g. same fraction, new integer °C)
  if (temp != lastRenderedTemp_) {
    lastRenderedTemp_ = temp;
    thermoArea_.queue_draw();
  }
}

}  // namespace waybar::modules
