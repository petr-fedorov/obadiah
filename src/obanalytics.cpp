#include <Rcpp.h>
#include <cmath>
#include <cstring>
#include <limits>
#include <map>

#define BOOST_LOG_DYN_LINK 1
#include <boost/log/core.hpp>
#include <boost/log/expressions.hpp>
#include <boost/log/sinks/text_file_backend.hpp>
#include <boost/log/sources/record_ostream.hpp>
#include <boost/log/sources/severity_logger.hpp>
#include <boost/log/utility/setup/common_attributes.hpp>
#include <boost/log/utility/setup/file.hpp>
#include "position_discovery.h"

namespace logging = boost::log;
namespace src = boost::log::sources;
namespace sinks = boost::log::sinks;
namespace keywords = boost::log::keywords;

using namespace Rcpp;
using namespace std;

#define START_LOGGING(f, s)                                                    \
 using sink_t = sinks::synchronous_sink<sinks::text_file_backend>;             \
 boost::shared_ptr<sink_t> g_file_sink = logging::add_file_log(                \
     keywords::file_name = #f, keywords::format = "[%TimeStamp%]: %Message%"); \
 logging::core::get()->set_filter(severity >= obadiah::SeverityLevel::s);      \
 src::severity_logger<obadiah::SeverityLevel> lg

#define FINISH_LOGGING                           \
 logging::core::get()->remove_sink(g_file_sink); \
 g_file_sink.reset()

__attribute__((constructor)) void
init() {
 logging::add_common_attributes();
}

BOOST_LOG_ATTRIBUTE_KEYWORD(severity, "Severity", obadiah::SeverityLevel)

class DepthChangesStream : public obadiah::ObjectStream<obadiah::Level2> {
public:
 DepthChangesStream(DataFrame depth_changes)
     : depth_changes_(depth_changes), j_(0){};
 operator bool() { return j_ <= depth_changes_.nrow(); }
 DepthChangesStream& operator>>(obadiah::Level2& dc) {
  ++j_;
  if (j_ <= depth_changes_.nrow()) {
   dc.t = as<NumericVector>(depth_changes_["timestamp"])[j_ - 1];
   dc.p = as<NumericVector>(depth_changes_["price"])[j_ - 1];
   dc.v = as<NumericVector>(depth_changes_["volume"])[j_ - 1];
   dc.s =
       !std::strcmp(as<CharacterVector>(depth_changes_["side"])[j_ - 1], "ask")
           ? obadiah::Side::kAsk
           : obadiah::Side::kBid;
   BOOST_LOG_SEV(lg, obadiah::SeverityLevel::DEBUG5)
       << "j_-1=" << j_ - 1 << " " << static_cast<char*>(dc);
  }
  return *this;
 }

private:
 DataFrame depth_changes_;
 R_xlen_t j_;
 src::severity_logger<obadiah::SeverityLevel> lg;
};

// [[Rcpp::export]]
DataFrame
CalculateTradingPeriod(DataFrame depth_changes, NumericVector volume) {
 START_LOGGING(CalculateTradingPeriod.log, INFO);

 DepthChangesStream dc{depth_changes};
 obadiah::TradingPeriod<std::allocator> trading_period{&dc, as<double>(volume)};
 std::vector<double> timestamp, bid_price, bid_volume, ask_price, ask_volume;
 obadiah::BidAskSpread output;
 while (trading_period >> output) {
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::DEBUG4)
      << static_cast<char*>(output);
  timestamp.push_back(output.t.t);
  bid_price.push_back(output.p_bid);
  ask_price.push_back(output.p_ask);
 }
 FINISH_LOGGING;

 return Rcpp::DataFrame::create(Rcpp::Named("timestamp") = timestamp,
                                Rcpp::Named("bid.price") = bid_price,
                                Rcpp::Named("ask.price") = ask_price);
};

class TradingPeriod : public obadiah::ObjectStream<obadiah::BidAskSpread> {
public:
 TradingPeriod(DataFrame trading_period)
     : timestamp_(as<NumericVector>(trading_period["timestamp"])),
       bid_(as<NumericVector>(trading_period["bid.price"])),
       ask_(as<NumericVector>(trading_period["ask.price"])),
       j_(0){};
 operator bool() { return j_ <= timestamp_.length(); }
 TradingPeriod& operator>>(obadiah::BidAskSpread& s) {
  j_++;
  if (j_ <= timestamp_.length()) {
   s.t = timestamp_[j_ - 1];
   s.p_bid = bid_[j_ - 1];
   s.p_ask = ask_[j_ - 1];
   BOOST_LOG_SEV(lg, obadiah::SeverityLevel::DEBUG5) << static_cast<char*>(s);
  }
  return *this;
 }

private:
 NumericVector timestamp_;
 NumericVector bid_;
 NumericVector ask_;
 R_xlen_t j_;
 src::severity_logger<obadiah::SeverityLevel> lg;
};

// [[Rcpp::export]]
DataFrame
DiscoverPositions(DataFrame computed_trading_period, NumericVector phi,
                  NumericVector rho) {
 START_LOGGING(DiscoverPositions.log, DEBUG3);

 TradingPeriod trading_period(computed_trading_period);
 obadiah::TradingStrategy trading_strategy(&trading_period, phi[0], rho[0]);
 std::vector<double> opened_at, open_price, closed_at, close_price, log_return,
     rate;
 obadiah::Position p;
 while (trading_strategy >> p) {
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::DEBUG3) << p;
  opened_at.push_back(p.s.t);
  open_price.push_back(p.s.p);
  closed_at.push_back(p.e.t);
  close_price.push_back(p.e.p);
  log_return.push_back(p.s.p > p.e.p ? std::log(p.s.p) - std::log(p.e.p)
                                     : std::log(p.e.p) - std::log(p.s.p));
  rate.push_back(std::exp(log_return.back() / (p.e.t - p.s.t)) - 1);
 }
 FINISH_LOGGING;
 return Rcpp::DataFrame::create(Rcpp::Named("opened.at") = opened_at,
                                Rcpp::Named("open.price") = open_price,
                                Rcpp::Named("closed.at") = closed_at,
                                Rcpp::Named("close.price") = close_price,
                                Rcpp::Named("log.return") = log_return,
                                Rcpp::Named("rate") = rate);
}

// [[Rcpp::export]]
DataFrame
spread_from_depth(DatetimeVector timestamp, NumericVector price,
                  NumericVector volume, CharacterVector side) {
 START_LOGGING(spread_from_depth.log, INFO);

 double episode = timestamp[0];
 double best_bid_price = 0, best_bid_qty = 0, best_ask_price = 0,
        best_ask_qty = 0;

 map<double, double> bids;
 map<double, double> asks;

 DatetimeVector timestamp_s(0);
 NumericVector best_bid_prices(0);
 NumericVector best_bid_qtys(0);
 NumericVector best_ask_prices(0);
 NumericVector best_ask_qtys(0);

 for (int i = 0; i <= timestamp.size(); i++) {
  if (i == timestamp.size() || timestamp[i] > episode) {
   BOOST_LOG_SEV(lg, obadiah::SeverityLevel::DEBUG3) << "Updating spread after episode " << Datetime(episode);

   bool is_changed = false;

   if (!bids.empty()) {
    if (bids.rbegin()->first != best_bid_price) {
     best_bid_price = bids.rbegin()->first;
     is_changed = true;
    }
    if (bids.rbegin()->first == best_bid_price &&
        bids.rbegin()->second != best_bid_qty) {
     best_bid_qty = bids.rbegin()->second;
     is_changed = true;
    }
    BOOST_LOG_SEV(lg, obadiah::SeverityLevel::DEBUG3) << " BID Current price: " << bids.rbegin()->first
                << " Best price: " << best_bid_price
                << " Current qty: " << bids.rbegin()->second
                << " Best qty: " << best_bid_qty;
   } else {
    if (best_bid_price > 0) {
     best_bid_price = 0;
     is_changed = true;
    }
   }
   if (!asks.empty()) {
    if (asks.begin()->first != best_ask_price) {
     best_ask_price = asks.begin()->first;
     is_changed = true;
    }
    if (asks.begin()->first == best_ask_price &&
        asks.begin()->second != best_ask_qty) {
     best_ask_qty = asks.begin()->second;
     is_changed = true;
    }
    BOOST_LOG_SEV(lg, obadiah::SeverityLevel::DEBUG3) << "ASK Current price: " << asks.begin()->first
                << " Best price: " << best_ask_price
                << " Current qty: " << asks.begin()->second
                << " Best qty: " << best_ask_qty;
   } else {
    if (best_ask_price > 0) {
     best_ask_price = 0;
     is_changed = true;
    }
   }
   if (is_changed) {
    timestamp_s.push_back(episode);
    if (best_bid_price > 0) {
     best_bid_prices.push_back(best_bid_price);
     best_bid_qtys.push_back(best_bid_qty);
    } else {
     best_bid_prices.push_back(R_NaN);
     best_bid_qtys.push_back(R_NaN);
    }
    if (best_ask_price > 0) {
     best_ask_prices.push_back(best_ask_price);
     best_ask_qtys.push_back(best_ask_qty);
    } else {
     best_ask_prices.push_back(R_NaN);
     best_ask_qtys.push_back(R_NaN);
    }

    BOOST_LOG_SEV(lg, obadiah::SeverityLevel::DEBUG3) << "Produced spread change record - timestamp:"
                << Datetime(episode) << "BID P: " << best_bid_price
                << " Q: " << best_bid_qty << "ASK P: " << best_ask_price
                << " Q: " << best_ask_qty;
   }

   if (i < timestamp.size())
    episode = timestamp[i];
   else
    break;  // We are done!
  }
  if (side[i] == "bid") {
   if (volume[i] > 0.0)
    bids[price[i]] = volume[i];
   else
    bids.erase(price[i]);
  } else {
   if (volume[i] > 0.0)
    asks[price[i]] = volume[i];
   else
    asks.erase(price[i]);
  }
 }
 FINISH_LOGGING;
 return DataFrame::create(Named("timestamp") = as<DatetimeVector>(timestamp_s),
                          Named("best.bid.price") = best_bid_prices,
                          Named("best.bid.volume") = best_bid_qtys,
                          Named("best.ask.price") = best_ask_prices,
                          Named("best.ask.volume") = best_ask_qtys);
}

struct point {
 double timestamp;
 double log_price;
 double orig_price;

 const bool operator!=(const point& e) {
  return (std::fabs(timestamp - e.timestamp) >
              std::numeric_limits<double>::epsilon() ||
          std::fabs(log_price - e.log_price) >
              std::numeric_limits<double>::epsilon());
 }
};
ostream&
operator<<(ostream& stream, point& p) {
 stream << "timestamp: " << Datetime(p.timestamp) << " price: " << p.orig_price;
 return stream;
}

