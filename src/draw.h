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

#ifndef OBADIAH_DRAW_H
#define OBADIAH_DRAW_H

#include <Rcpp.h>
#include <cmath>
#include <limits>
#include <ostream>

#ifndef NDEBUG
#include "log.h"
#endif

namespace obadiah {
class Draw {
public:
 Draw(double timestamp, double price)
     : s_{timestamp, price}, tp_{timestamp, price}, e_{timestamp, price} {};
 virtual ~Draw(){};
 virtual void process_spreads(Rcpp::NumericVector timestamp, Rcpp::NumericVector price);
 virtual void extend(double next_timestamp, double next_price);
 virtual void SaveAndStartNew() = 0;
 virtual bool IsCompleted() const = 0;
 virtual Rcpp::DataFrame get_table() = 0;

protected:
 struct Table {
  std::vector<double> timestamp;
  std::vector<double> end;
  std::vector<double> start_price;
  std::vector<double> end_price;
  std::vector<double> size;
  std::vector<double> speed;
 };

 struct DrawPoint {
  DrawPoint(double t, double p)
      : timestamp(t), log_price(std::log(p)), orig_price(p){};
  double timestamp;
  double log_price;
  double orig_price;

  inline const bool operator!=(const DrawPoint& other) {
   return (std::fabs(timestamp - other.timestamp) >
               std::numeric_limits<double>::epsilon() ||
           std::fabs(log_price - other.log_price) >
               std::numeric_limits<double>::epsilon());
  }
 };
 friend std::ostream& operator<<(std::ostream& stream, DrawPoint& p);
 DrawPoint s_;
 DrawPoint tp_;
 DrawPoint e_;
 Table output_table_;
};

class Type2Draw : public Draw {
public:
 Type2Draw(double starting_timestamp, double starting_price,
           double min_draw, double duration,
           double tolerance, double max_draw)
     : Draw(starting_timestamp, starting_price),
       min_draw_(min_draw),
       duration_(duration),
       tolerance_(tolerance),
       max_draw_(max_draw),
       previous_draw_size_(0.0) {
#ifndef NDEBUG
  L_(ldebug3) << "New Type2Draw: " << *this;
#endif
 };

 ~Type2Draw() {
#ifndef NDEBUG
  L_(ldebug3) << "Deleted Type2Draw: " << *this;
#endif
 };

 void SaveAndStartNew();
 bool IsCompleted() const;
 Rcpp::DataFrame get_table();
 friend std::ostream& operator<<(std::ostream& stream, Type2Draw& p);

 inline bool IsDrawDurationExceeded() const {
  return e_.timestamp - s_.timestamp > duration_;
 };

 inline double current_tolerance() const {
  double x = std::fabs(tp_.log_price - s_.log_price);
  return tolerance_ /
         (1 + std::exp((x - max_draw_ / 2) * 10 /
                       max_draw_));
 };

 inline bool IsDrawSizeToleranceExceeded() const {
  return std::fabs(e_.log_price - tp_.log_price) >
         std::fabs(tp_.log_price - s_.log_price) *
             current_tolerance();
 };

 inline bool IsPriceChangeThresholdExceeded() const {
  return false;
  // return std::fabs(e_.log_price - tp_.log_price) > max_draw_;
 };

 inline bool IsMinDrawSizeAchieved() const {
  return std::fabs(e_.log_price - s_.log_price) >= min_draw_;
 };

private:
 const double min_draw_;
 const double duration_;
 const double tolerance_;
 const double max_draw_;

 double previous_draw_size_;
};
}  // namespace obadiah
#endif
