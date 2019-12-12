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

class CasualDraw : public Draw {
public:
 CasualDraw(double starting_timestamp, double starting_price,
            double min_draw_size_threshold, double max_draw_duration_threshold,
            double draw_size_tolerance, double price_change_threshold)
     : Draw(starting_timestamp, starting_price),
       min_draw_size_threshold_(min_draw_size_threshold),
       max_draw_duration_threshold_(max_draw_duration_threshold),
       draw_size_tolerance_(draw_size_tolerance),
       price_change_threshold_(price_change_threshold),
       previous_draw_size_(0.0) {
#ifndef NDEBUG
  L_(ldebug3) << "New CasualDraw: " << *this;
#endif
 };

 ~CasualDraw() {
#ifndef NDEBUG
  L_(ldebug3) << "Deleted CasualDraw: " << *this;
#endif
 };

 void SaveAndStartNew();
 bool IsCompleted() const;
 Rcpp::DataFrame get_table();
 friend std::ostream& operator<<(std::ostream& stream, CasualDraw& p);

 inline bool IsDrawDurationExceeded() const {
  return e_.timestamp - s_.timestamp > max_draw_duration_threshold_;
 };

 inline bool IsDrawSizeToleranceExceeded() const {
  return std::fabs(e_.log_price - tp_.log_price) >
         previous_draw_size_ * draw_size_tolerance_;
 };

 inline bool IsPriceChangeThresholdExceeded() const {
  return std::fabs(e_.log_price - tp_.log_price) > price_change_threshold_;
 };

 inline bool IsMinDrawSizeAchieved() const {
  return std::fabs(e_.log_price - s_.log_price) >= min_draw_size_threshold_;
 };

private:
 const double min_draw_size_threshold_;
 const double max_draw_duration_threshold_;
 const double draw_size_tolerance_;
 const double price_change_threshold_;

 double previous_draw_size_;
};
}  // namespace obadiah
#endif
