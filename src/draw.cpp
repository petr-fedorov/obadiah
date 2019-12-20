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
     : max_revenue(0),
       direction(0),
       entry(0),
       exit(0),
       max_price_ahead(0),
       min_price_ahead(0){};
 double max_revenue;
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

#ifndef NDEBUG
 L_(ldebug3) << "decisions size()" << decisions.size();
#endif

 for (R_xlen_t i = 0; i < timestamp.length(); i++)
  log_price[i] = std::log(price[i]);

 decisions[timestamp.length() - 1].max_price_ahead =
     -std::numeric_limits<double>::infinity();
 decisions[timestamp.length() - 1].min_price_ahead =
     std::numeric_limits<double>::infinity();

 for (R_xlen_t i = timestamp.length() - 2; i >= 0; --i) {
#ifndef NDEBUG
  L_(ldebug3) << "SPREAD: timestamp " << Rcpp::Datetime(timestamp[i])
              << " price " << price[i];
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

#ifndef NDEBUG
  L_(ldebug3) << "AHEAD Max:  " << std::fixed << std::setprecision(2)
              << std::exp(decisions[i].max_price_ahead)
              << " Min: " << std::exp(decisions[i].min_price_ahead);
#endif

  decisions[i].max_revenue =
      decisions[i + 1].max_revenue;  // i.e. if we do not open any position

  for (R_xlen_t j = i + 1; j < timestamp.length(); ++j) {
   double costs =
       transaction_costs_ + discount_ * (timestamp[j] - timestamp[i]);

   if (log_price[j] >
       log_price[i] + costs) {  // long could be a feasible option at time i
    if (decisions[j].max_revenue + log_price[j] - log_price[i] - costs >
        decisions[i].max_revenue) {
     decisions[i].max_revenue =
         decisions[j].max_revenue + log_price[j] - log_price[i] - costs;
     decisions[i].direction = 1;
     decisions[i].entry = i;
     decisions[i].exit = j;
    }
   } else if (log_price[i] >
              log_price[j] +
                  costs) {  // short could be a feasible option at time i
    if (decisions[j].max_revenue + log_price[i] - log_price[j] - costs >
        decisions[i].max_revenue) {
     decisions[i].max_revenue =
         decisions[j].max_revenue + log_price[i] - log_price[j] - costs;
     decisions[i].direction = -1;
     decisions[i].entry = i;
     decisions[i].exit = j;
    }
   }

   if (decisions[j].max_price_ahead - log_price[i] < transaction_costs_ &&
       log_price[i] - decisions[j].min_price_ahead < transaction_costs_) {
#ifndef NDEBUG
    L_(ldebug3) << "BREAK at timestamp " << Rcpp::Datetime(timestamp[j]) <<
     std::fixed << std::setprecision(2) << " price: " << std::exp(log_price[i]) <<
     " max ahead: " << std::exp(decisions[j].max_price_ahead) <<
     " min ahead: " << std::exp(decisions[j].min_price_ahead);
#endif
    break;
   }
  }
 }
#ifndef NDEBUG
 L_(ldebug3) << "OUTPUT";
#endif
 for (R_xlen_t i = 0; i < timestamp.length();) {
  if (decisions[i].direction != 0) {
   R_xlen_t entry = decisions[i].entry;
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
