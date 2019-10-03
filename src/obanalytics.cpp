#include <Rcpp.h>
#include<map>
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
