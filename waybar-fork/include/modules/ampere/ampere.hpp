#pragma once

#include <gtkmm/box.h>
#include <gtkmm/drawingarea.h>
#include <memory>
#include <mutex>
#include <optional>

#include "AModule.hpp"
#include "modules/ampere/sampler.hpp"
#include "util/sleeper_thread.hpp"

namespace waybar::modules {

class Ampere : public AModule {
 public:
  Ampere(const std::string& id, const Json::Value& config);

 private:
  bool onDrawGauge(const Cairo::RefPtr<Cairo::Context>& cr, Gtk::DrawingArea& area, double level);
  bool onDrawThermo(const Cairo::RefPtr<Cairo::Context>& cr);
  void ease();

  Gtk::Box box_;
  Gtk::DrawingArea cpuArea_;
  Gtk::DrawingArea memArea_;
  Gtk::DrawingArea thermoArea_;

  std::unique_ptr<ampere::Sampler> sampler_;
  util::SleeperThread thread_;

  std::mutex targetMutex_;
  double cpuTarget_ = 0.0;
  double memTarget_ = 0.0;
  std::optional<double> thermoTarget_;
  double thermoTemp_ = -1.0;
  double thermoMax_ = 100.0;

  // main-thread only (easing + draw both run on the GTK main loop)
  double cpuLevel_ = 0.0;
  double memLevel_ = 0.0;
  double thermoLevel_ = 0.0;
  double lastRenderedTemp_ = -1.0;

  sigc::connection animConn_;
};

}  // namespace waybar::modules
