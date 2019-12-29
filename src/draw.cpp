// Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation,  version 1 of the License

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 01110-1301 USA.

#include "draw.h"
#include <Rcpp.h>
#include <map>
#include "log.h"

namespace obadiah {

template <typename T>
int
sgn(T val) {
 return (T(0) < val) - (val < T(0));
}

void
Draw::process_spreads(Rcpp::NumericVector timestamp,
                      Rcpp::NumericVector price) {
 for (R_xlen_t i = 1; i < timestamp.length(); ++i) {
#ifndef NDEBUG
  L_(ldebug3) << "NEXT SPREAD " << Rcpp::Datetime(timestamp[i]) << " "
              << price[i];
#endif
  extend(timestamp[i], price[i]);
  if (IsCompleted()) SaveAndStartNew();
 }
 SaveAndStartNew();
};

void
Draw::extend(double next_timestamp, double next_price) {
 e_.timestamp = next_timestamp;
 e_.orig_price = next_price;
 e_.log_price = std::log(next_price);
#ifndef NDEBUG
 L_(ldebug3) << "EXTENDED END" << e_;
#endif

 if (std::fabs(e_.log_price - tp_.log_price) >
         std::numeric_limits<double>::epsilon() &&
     ((std::signbit(tp_.log_price - s_.log_price) ==
       std::signbit(e_.log_price - tp_.log_price)) ||
      (std::signbit(tp_.log_price - s_.log_price) !=
       std::signbit(e_.log_price - s_.log_price)))) {
  tp_.timestamp = next_timestamp;
  tp_.orig_price = next_price;
  tp_.log_price = std::log(next_price);
#ifndef NDEBUG
  L_(ldebug3) << "EXTENDED TuP" << tp_;
#endif
 };
}

std::ostream&
operator<<(std::ostream& stream, Draw::DrawPoint& p) {
 stream << " timestamp: " << Rcpp::Datetime(p.timestamp)
        << " price: " << p.orig_price;
 return stream;
}

std::ostream&
operator<<(std::ostream& stream, Type2Draw& p) {
 stream << " timestamp: " << Rcpp::Datetime(p.s_.timestamp)
        << " end: " << Rcpp::Datetime(p.e_.timestamp)
        << " start price: " << p.s_.orig_price
        << " end price: " << p.e_.orig_price
        << " duration: " << p.e_.timestamp - p.s_.timestamp
        << " IsDrawDuration(): " << p.IsDrawDurationExceeded()
        << " IsMinDrawSize(): " << p.IsMinDrawSizeAchieved()
        << " IsDrawSizeTolerance(): " << p.IsDrawSizeToleranceExceeded()
        << " IsPriceChangeThreshold(): " << p.IsPriceChangeThresholdExceeded();
 return stream;
};

bool
Type2Draw::IsCompleted() const {
 return (IsDrawDurationExceeded() && !IsMinDrawSizeAchieved()) ||
        (IsMinDrawSizeAchieved() &&
         (IsDrawSizeToleranceExceeded() || IsPriceChangeThresholdExceeded()));
}

void
Type2Draw::SaveAndStartNew() {
#ifndef NDEBUG
 L_(ldebug3) << "SAVED DRAW " << *this;
#endif
 previous_draw_size_ = std::fabs(e_.log_price - s_.log_price);

 output_table_.timestamp.push_back(s_.timestamp);
 output_table_.end.push_back(tp_.timestamp);
 output_table_.start_price.push_back(s_.orig_price);
 output_table_.end_price.push_back(tp_.orig_price);
 long double d_sz = std::round(1000000 * (tp_.orig_price - s_.orig_price) /
                               s_.orig_price) /
                    100,
             d_sp =
                 std::round(100 * d_sz / (tp_.timestamp - s_.timestamp)) / 100;

 output_table_.size.push_back(d_sz);
 output_table_.speed.push_back(d_sp);
 s_ = tp_;
 tp_ = e_;
#ifndef NDEBUG
 L_(ldebug3) << "STARTED NEW DRAW" << *this;
#endif
}

Rcpp::DataFrame
Draw::get_table() {
 return Rcpp::DataFrame::create(
     Rcpp::Named("draw.start") = output_table_.timestamp,
     Rcpp::Named("draw.end") = output_table_.end,
     Rcpp::Named("start.price") = output_table_.start_price,
     Rcpp::Named("end.price") = output_table_.end_price,
     Rcpp::Named("draw.size") = output_table_.size,
     Rcpp::Named("draw.speed") = output_table_.speed);
}

struct Decision {
 Decision()
     : draw_revenue(0),
       direction(0),
       entry(0),
       exit(0),
       max_price_ahead(0),
       min_price_ahead(0){};
 double draw_revenue;
 double direction;  // -1, 0, 1;
 R_xlen_t entry;
 R_xlen_t exit;
 double max_price_ahead;
 double min_price_ahead;
};

void
Type3Draw::process_spreads(Rcpp::NumericVector timestamp,
                           Rcpp::NumericVector price) {
 std::vector<Decision> decisions(timestamp.length());
 std::vector<double> log_price(timestamp.length());

 for (R_xlen_t i = 0; i < timestamp.length(); i++)
  log_price[i] = std::log(price[i]);

 decisions[timestamp.length() - 1].max_price_ahead =
     -std::numeric_limits<double>::infinity();
 decisions[timestamp.length() - 1].min_price_ahead =
     std::numeric_limits<double>::infinity();

 for (R_xlen_t i = timestamp.length() - 2; i >= 0; --i) {
#ifndef NDEBUG
  L_(ldebug3) << "SPREAD: i: " << i
              << " timestamp[i]: " << Rcpp::Datetime(timestamp[i])
              << " price[i]: " << price[i] << " log_price[i]: " << log_price[i];
#endif
  if (log_price[i + 1] > decisions[i + 1].max_price_ahead) {
   decisions[i].max_price_ahead = log_price[i + 1];
  } else {
   decisions[i].max_price_ahead = decisions[i + 1].max_price_ahead;
  }

  if (log_price[i + 1] < decisions[i + 1].min_price_ahead) {
   decisions[i].min_price_ahead = log_price[i + 1];
  } else {
   decisions[i].min_price_ahead = decisions[i + 1].min_price_ahead;
  }

  decisions[i].max_price_ahead -= discount_ * (timestamp[i + 1] - timestamp[i]);
  decisions[i].min_price_ahead += discount_ * (timestamp[i + 1] - timestamp[i]);

  bool stop{false};

  for (R_xlen_t j = i + 1; !stop && j < timestamp.length(); ++j) {
   double price_change = log_price[j] - log_price[i];
   double time_costs = discount_ * (timestamp[j] - timestamp[i]);

   if (decisions[j].direction) {
    stop = true;
    if ((sgn(price_change) == sgn(decisions[j].direction) ||
         !sgn(price_change)) &&
        (std::fabs(price_change) >= time_costs)) {
     decisions[i].direction = decisions[j].direction;
     decisions[i].exit = decisions[j].exit;

     if (decisions[i].direction == 1) {
      decisions[i].max_price_ahead = log_price[i] + transaction_costs_;
      decisions[i].min_price_ahead = log_price[i];
     } else {
      decisions[i].max_price_ahead = log_price[i];
      decisions[i].min_price_ahead = log_price[i] - transaction_costs_;
     }

#ifndef NDEBUG
     L_(ldebug3) << "EXTENDED DRAW: [" << j << "," << decisions[j].exit
                 << "] to [" << i << "," << decisions[i].exit << "]"
                 << "[ " << Rcpp::Datetime(timestamp[i]) << ", "
                 << Rcpp::Datetime(timestamp[decisions[j].exit]) << "] "
                 << " max_price_ahead: " << decisions[i].max_price_ahead
                 << " min_price_ahead: " << decisions[i].min_price_ahead;
#endif
     decisions[j].direction = 0;
     decisions[j].draw_revenue = 0;
     decisions[j].exit = 0;
     break;
    }
   }
   if ((std::fabs(price_change) > time_costs + transaction_costs_) &&
       (std::fabs(price_change) - time_costs > decisions[i].draw_revenue)) {
#ifndef NDEBUG
    if (!decisions[i].direction)
     L_(ldebug3) << "CREATED DRAW: [" << i << "," << j << "]";
    else
     L_(ldebug3) << "REPLACED DRAW: [" << i << "," << j << "]";
#endif
    decisions[i].direction = sgn(price_change);

    // note that we are saving/comparing a time-cost adjusted draw revenue
    // time_costs will be different for different values of j
    decisions[i].draw_revenue = std::fabs(price_change) - time_costs;
    decisions[i].exit = j;
   }

   if ((log_price[i] + transaction_costs_ > decisions[j].max_price_ahead) &&
       (log_price[i] - transaction_costs_ < decisions[j].min_price_ahead)) {
    stop = true;
   }
#ifndef NDEBUG
   if (stop) {
    L_(ldebug3) << "STOPPED j: " << j
                << " timestamp[j]: " << Rcpp::Datetime(timestamp[j])
                << " price[j]: " << price[j]
                << " log_price[j]: " << log_price[j]
                << " time_costs: " << time_costs
                << " min_ahead: " << decisions[j].min_price_ahead
                << " max_ahead: " << decisions[j].max_price_ahead;
   };
#endif
  }
 }
#ifndef NDEBUG
 L_(ldebug3) << "OUTPUT";
#endif
 for (R_xlen_t i = 0; i < timestamp.length();) {
  if (decisions[i].direction) {
   R_xlen_t entry = i;
   R_xlen_t exit = decisions[i].exit;
   i = exit;

   output_table_.timestamp.push_back(timestamp[entry]);
   output_table_.end.push_back(timestamp[exit]);
   output_table_.start_price.push_back(price[entry]);
   output_table_.end_price.push_back(price[exit]);
   long double d_sz = std::round(1000000 * (price[exit] - price[entry]) /
                                 price[entry]) /
                      100,
               d_sp = std::round(100 * d_sz /
                                 (timestamp[exit] - timestamp[entry])) /
                      100;

   output_table_.size.push_back(d_sz);
   output_table_.speed.push_back(d_sp);
  } else {
   ++i;
  }
 }
};

}  // namespace obadiah

using namespace Rcpp;
using namespace std;
// [[Rcpp::export]]
DataFrame
DrawsFromSpread(NumericVector timestamp, NumericVector price,
                IntegerVector draw_type, List params) {
#ifndef NDEBUG
 FILELog::ReportingLevel() = ldebug3;
 FILE* log_fd = fopen("DrawsFromSpread.log", "w");
 Output2FILE::Stream() = log_fd;
#endif

 obadiah::Draw* draw;
 switch (draw_type[0]) {
  case 2:
   draw = new obadiah::Type2Draw{timestamp[0],
                                 price[0],
                                 as<double>(params["min.draw"]),
                                 as<double>(params["duration"]),
                                 as<double>(params["tolerance"]),
                                 as<double>(params["max.draw"])};
   break;
  case 3:
   draw = new obadiah::Type3Draw{as<double>(params["transaction.costs"]),
                                 as<double>(params["discount.rate"])};
   break;
  default:
   Rf_error("Unknown draw.type");
   break;
 };
 draw->process_spreads(timestamp, price);
 return draw->get_table();
}
