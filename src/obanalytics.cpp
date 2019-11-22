#include <Rcpp.h>
#include<map>
#include <cmath>
#include <limits>
#include "log.h"

using namespace Rcpp;
using namespace std;


#define DEBUG 0

// [[Rcpp::export]]
DataFrame spread_from_depth(DatetimeVector timestamp,
                      NumericVector price, NumericVector volume, CharacterVector side) {


#if DEBUG
  FILELog::ReportingLevel() = ldebug3;
  FILE* log_fd = fopen( "spread_from_depth.log", "w" );
  Output2FILE::Stream() = log_fd;
#endif


  double episode = timestamp[0];
  double best_bid_price = 0,
         best_bid_qty = 0,
         best_ask_price = 0,
         best_ask_qty = 0;

  map<double,double> bids;
  map<double,double> asks;


  DatetimeVector timestamp_s(0);
  NumericVector best_bid_prices(0);
  NumericVector best_bid_qtys(0);
  NumericVector best_ask_prices(0);
  NumericVector best_ask_qtys(0);

  for(int i=0; i < timestamp.size(); i++) {
    if(timestamp[i] > episode) {

#if DEBUG
      L_(ldebug3) << "Process episode " << Datetime(episode);
#endif

      bool is_changed = false;

      if(!bids.empty()) {

        if(bids.rbegin()->first != best_bid_price) {
          best_bid_price = bids.rbegin()->first;
          is_changed = true;
        }
        if(bids.rbegin()->first == best_bid_price && bids.rbegin()->second != best_bid_qty) {
          best_bid_qty = bids.rbegin()->second;
          is_changed = true;
        }
#if DEBUG
        L_(ldebug3) << "BID Current price: " << bids.rbegin()->first << " Best price: " << best_bid_price << " Current qty: " << bids.rbegin()->second << " Best qty: " << best_bid_qty;
#endif
      }
      else {
        if(best_bid_price > 0){
          best_bid_price = 0;
          is_changed = true;
        }
      }
      if(!asks.empty()) {
        if(asks.begin()->first != best_ask_price) {
          best_ask_price = asks.begin()->first;
          is_changed = true;
        }
        if(asks.begin()->first == best_ask_price && asks.begin()->second != best_ask_qty) {
          best_ask_qty = asks.begin()->second;
          is_changed = true;
        }
#if DEBUG
        L_(ldebug3) << "ASK Current price: " << asks.begin()->first << " Best price: " << best_ask_price << " Current qty: " << asks.begin()->second << " Best qty: " << best_ask_qty;
#endif
      }
      else {
        if(best_ask_price >0) {
          best_ask_price = 0;
          is_changed = true;
        }
      }
      if(is_changed) {
        timestamp_s.push_back(episode);
        if(best_bid_price > 0) {
          best_bid_prices.push_back(best_bid_price);
          best_bid_qtys.push_back(best_bid_qty);
        }
        else {
          best_bid_prices.push_back(R_NaN);
          best_bid_qtys.push_back(R_NaN);
        }
        if(best_ask_price > 0) {
          best_ask_prices.push_back(best_ask_price);
          best_ask_qtys.push_back(best_ask_qty);
        }
        else {
          best_ask_prices.push_back(R_NaN);
          best_ask_qtys.push_back(R_NaN);
        }

#if DEBUG
        L_(ldebug3) << "Spread Timestamp:" << Datetime(episode) << "BID P: " << best_bid_price << " Q: " << best_bid_qty << "ASK P: " << best_ask_price << " Q: " << best_ask_qty;
#endif
      }

      episode = timestamp[i];
    }
    if(side[i] == "bid") {
      if(volume[i] > 0.0)
        bids[price[i]] = volume[i];
      else
        bids.erase(price[i]);
    }
    else {
      if(volume[i] > 0.0)
        asks[price[i]] = volume[i];
      else
        asks.erase(price[i]);
    }
  }
  return DataFrame::create(Named("timestamp")=as<DatetimeVector>(timestamp_s),
                           Named("best.bid.price")=best_bid_prices,
                           Named("best.bid.volume")=best_bid_qtys,
                           Named("best.ask.price")=best_ask_prices,
                           Named("best.ask.volume")=best_ask_qtys);

}


struct point {
  long double timestamp;
  long double price;
  const bool operator != (const point &e) {
    return (std::fabs(timestamp - e.timestamp) > 10*std::numeric_limits<double>::epsilon() ||
            std::fabs(price - e.price) > 10*std::numeric_limits<double>::epsilon());
  }
};
ostream& operator << (ostream& stream, point & p) {
  stream << "timestamp: " << Datetime(p.timestamp) << " price: " << p.price;
  return stream;
}



struct draws {
  std::vector<long double> draw_timestamp,
                           draw_end,
                            draw_start_price,
  draw_end_price,
  draw_size,
  draw_speed;

  inline void add(point &s, point &e) {
    if(std::fabs(s.timestamp - e.timestamp) > std::numeric_limits<double>::epsilon()) {
#if DEBUG
      L_(ldebug3) << "Added draw s: " << s << " e: " << e;
#endif
      draw_timestamp.push_back(s.timestamp);
      draw_end.push_back(e.timestamp);
      draw_start_price.push_back(s.price);
      draw_end_price.push_back(e.price);
      long double d_sz = std::round(1000000*(e.price - s.price)/s.price)/100,
        d_sp = std::round(100*d_sz/(e.timestamp - s.timestamp))/100;

      draw_size.push_back(d_sz);
      draw_speed.push_back(d_sp);

    }
    else {
#if DEBUG
      L_(ldebug3) << "Skipped zero-length draw s: " << s << " e: " << e;
#endif

    }
  }

};


// [[Rcpp::export]]
DataFrame draws_from_spread(NumericVector timestamp, NumericVector price, NumericVector gamma_0, NumericVector theta) {

#if DEBUG
  FILELog::ReportingLevel() = ldebug3;
  FILE* log_fd = fopen( "draws_from_spread.log", "w" );
  Output2FILE::Stream() = log_fd;
#endif


  point s {timestamp[0],price[0]},  // draw (s)tart
        tp {timestamp[0],price[0]}, // (t)urning (p)oint
        e {timestamp[0],price[0]};  // draw (e)nd

  draws d;

#if DEBUG
  L_(ldebug3) << "The first draw started " << s;
#endif


  for(R_xlen_t i = 1; i < timestamp.length(); ++i) {
#if DEBUG
    L_(ldebug3) << "Timestamp " << Datetime(timestamp[i]) << " price " << price[i];
#endif
    if(std::fabs(price[i] - tp.price) > 10*std::numeric_limits<double>::epsilon()) {
      if( (tp.price > s.price && price[i] > tp.price) ||
          (tp.price < s.price && price[i] < tp.price) ) { // extend the draw and set the new turning point
        tp.price = price[i];
        tp.timestamp = timestamp[i];
        e.price = price[i];
        e.timestamp = timestamp[i];
#if DEBUG
        L_(ldebug3) << "The current draw extended in the same direction " << e;
#endif

      }
      else {  // check whether the current draw has ended and the new draw is to be started
        long double gamma = 0.01*gamma_0[0]/(1 + theta[0]*(tp.timestamp - s.timestamp));
#if DEBUG
        L_(ldebug3) << "gamma " << gamma << " epsilon " <<  std::fabs(tp.price - s.price)*gamma << " delta " << std::fabs(price[i] - tp.price) << " diff " << std::fabs(price[i] - tp.price) - std::fabs(tp.price - s.price)*gamma;
#endif
        if( std::fabs(price[i] - tp.price) - std::fabs(tp.price - s.price)*gamma > -0.000001 ){ // -0.000001 is from empirical observation that prices may have no more than 5 decimal digits
          // the turn after the latest turning point has exceeded threshould, so the new draw will start FROM THE TURNING POINT (i.e. in the past)
          // and the current draw will be returned

          d.add(s, tp);
          s = tp;
#if DEBUG
          L_(ldebug3) << "The new draw started " << s;
#endif

          e.timestamp = timestamp[i];
          e.price = price[i];
          tp = e;
        }
        else {  // the current draw has not ended yet, just extend it ...
#if DEBUG
          L_(ldebug3) << "The current draw has not ended yet " << e;
#endif
          e.price = price[i];
          e.timestamp = timestamp[i];
        }
      }
    }
    else {  // price hasn't changed, so just extend the current draw

      e.price = price[i];
      e.timestamp = timestamp[i];

#if DEBUG
      L_(ldebug3) << "Price hasn't changed " << e;
#endif

    }

  }
  if (s != e)
    d.add(s,tp);

  return Rcpp::DataFrame::create(Rcpp::Named("timestamp")=d.draw_timestamp,
                                 Rcpp::Named("draw.end")=d.draw_end,
                                 Rcpp::Named("start.price")=d.draw_start_price,
                                 Rcpp::Named("end.price")=d.draw_end_price,
                                 Rcpp::Named("draw.size")=d.draw_size,
                                 Rcpp::Named("draw.speed")=d.draw_speed);
}
