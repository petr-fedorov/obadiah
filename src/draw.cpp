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
Draw::process_spreads(Rcpp::NumericVector timestamp, Rcpp::NumericVector price) {
 for (R_xlen_t i = 1; i < timestamp.length(); ++i) {
#ifndef NDEBUG
  L_(ldebug3) << "NEXT SPREAD " << Datetime(timestamp[i]) << " " << price[i];
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
Type2Draw::get_table() {
 return Rcpp::DataFrame::create(
     Rcpp::Named("timestamp") = output_table_.timestamp,
     Rcpp::Named("draw.end") = output_table_.end,
     Rcpp::Named("start.price") = output_table_.start_price,
     Rcpp::Named("end.price") = output_table_.end_price,
     Rcpp::Named("draw.size") = output_table_.size,
     Rcpp::Named("draw.speed") = output_table_.speed);
}

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
  default:
   Rf_error("Unknown draw.type");
   break;
 };
 draw->process_spreads(timestamp, price);
 return draw->get_table();
}
