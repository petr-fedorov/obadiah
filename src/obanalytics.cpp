#include <Rcpp.h>
#include <cmath>
#include <cstring>
#include <limits>
#include <map>

#ifndef NDEBUG
#include <boost/log/core.hpp>
#include <boost/log/expressions.hpp>
#include <boost/log/sinks/text_file_backend.hpp>
#include <boost/log/sources/record_ostream.hpp>
#include <boost/log/sources/severity_logger.hpp>
#include <boost/log/support/date_time.hpp>
#include <boost/log/utility/setup/common_attributes.hpp>
#include <boost/log/utility/setup/file.hpp>
#endif

#include "epsilon_drawupdowns.h"
#include "order_book_investigation.h"
#include "position_discovery.h"

using namespace Rcpp;
using namespace std;

#ifndef NDEBUG
namespace logging = boost::log;
namespace src = boost::log::sources;
namespace sinks = boost::log::sinks;
namespace keywords = boost::log::keywords;
namespace expr = boost::log::expressions;

#define START_LOGGING(f, s)                                                    \
 using sink_t = sinks::synchronous_sink<sinks::text_file_backend>;             \
 boost::shared_ptr<sink_t> g_file_sink = nullptr;                              \
 try {                                                                         \
  logging::core::get()->set_filter(severity >= obadiah::GetSeverityLevel(s));  \
  g_file_sink =                                                                \
      logging::add_file_log(                                                   \
          keywords::file_name = #f,                                            \
          keywords::format =                                                   \
              (expr::stream                                                    \
               << expr::format_date_time<boost::posix_time::ptime>(            \
                      "TimeStamp", "%Y-%m-%d %H:%M:%S.%f")                     \
               << " "                                                          \
               << expr::if_(expr::has_attr<boost::posix_time::time_duration>(  \
                      "RunTime"))[expr::stream                                 \
                                  << expr::format_date_time<                   \
                                         boost::posix_time::time_duration>(    \
                                         "RunTime", "%S.%f")]                  \
                      .else_[expr::stream << "--"]                             \
               << " " << expr::message));                                      \
 } catch (const std::out_of_range&) {                                          \
  logging::core::get()->set_filter(severity > obadiah::SeverityLevel::kError); \
 }                                                                             \
 src::severity_logger<obadiah::SeverityLevel> lg

#define FINISH_LOGGING                            \
 if (g_file_sink) {                               \
  logging::core::get()->remove_sink(g_file_sink); \
  g_file_sink.reset();                            \
 }
#else
#define START_LOGGING(f, s)
#define FINISH_LOGGING
#endif

#ifndef NDEBUG
__attribute__((constructor)) void
init() {
 logging::add_common_attributes();
 logging::core::get()->add_global_attribute("Scope", attrs::named_scope());
}

BOOST_LOG_ATTRIBUTE_KEYWORD(severity, "Severity", obadiah::SeverityLevel)
#endif

class DepthChangesStream : public obadiah::ObjectStream<obadiah::Level2> {
public:
 DepthChangesStream(DataFrame depth_changes)
     : timestamp_{as<NumericVector>(
           depth_changes["timestamp"])},  // as<> is rather expensive!
       price_{as<NumericVector>(depth_changes["price"])},
       volume_{as<NumericVector>(depth_changes["volume"])},
       side_{as<CharacterVector>(depth_changes["side"])},
       j_(0){};
 operator bool() { return j_ <= timestamp_.length(); }
 DepthChangesStream& operator>>(obadiah::Level2& dc) {
  ++j_;
  if (j_ <= timestamp_.length()) {
   dc.t = timestamp_[j_ - 1];
   dc.p = price_[j_ - 1];
   dc.v = volume_[j_ - 1];
   dc.s = !std::strcmp(side_[j_ - 1], "ask") ? obadiah::Side::kAsk
                                             : obadiah::Side::kBid;
#ifndef NDEBUG
   BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug5)
       << "j_-1=" << j_ - 1 << " " << static_cast<char*>(dc);
#endif
  }
  return *this;
 }

private:
 NumericVector timestamp_;
 NumericVector price_;
 NumericVector volume_;
 CharacterVector side_;
 R_xlen_t j_;
#ifndef NDEBUG
 src::severity_logger<obadiah::SeverityLevel> lg;
#endif
};

// [[Rcpp::export]]
DataFrame
CalculateTradingPeriod(DataFrame depth_changes, NumericVector volume,
                       CharacterVector debug_level) {
 START_LOGGING(CalculateTradingPeriod.log, as<string>(debug_level));

 DepthChangesStream dc{depth_changes};
 obadiah::TradingPeriod<std::allocator> trading_period{&dc, as<double>(volume)};
 std::vector<double> timestamp, bid_price, ask_price;
 obadiah::BidAskSpread output;
 while (true) {
#ifndef NDEBUG
  BOOST_LOG_SCOPED_LOGGER_ATTR(lg, "RunTime", attrs::timer());
#endif
  if (!(trading_period >> output)) break;
  timestamp.push_back(output.t.t);
  bid_price.push_back(output.p_bid);
  ask_price.push_back(output.p_ask);
#ifndef NDEBUG
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug1)
      << static_cast<char*>(output);
#endif
 }
 FINISH_LOGGING;
 Rcpp::List tmp(3);
 tmp[0] = timestamp;
 tmp[1] = bid_price;
 tmp[2] = ask_price;
 Rcpp::DataFrame result(tmp);
 Rcpp::CharacterVector names(3);
 names[0] = "timestamp";
 names[1] = "bid.price";
 names[2] = "ask.price";
 result.attr("names") = names;

 return result;
 /*return Rcpp::DataFrame::create(Rcpp::Named("timestamp") = timestamp,
                                Rcpp::Named("bid.price") = bid_price,
                                Rcpp::Named("ask.price") = ask_price);
                                */
};

// [[Rcpp::export]]
DataFrame
CalculateOrderBookSnapshots(DataFrame depth_changes, NumericVector tick_size, IntegerVector max_levels,
                       CharacterVector debug_level) {
 START_LOGGING(CalculateOrderBookSnapshots.log, as<string>(debug_level));

 std::size_t max_lvl = max_levels[0];

 DepthChangesStream dc{depth_changes};
 obadiah::DepthToSnapshots<> depth_to_snapshots{&dc,tick_size[0], max_lvl};
 std::vector<double> timestamp, bid_price, ask_price;
 std::vector<std::vector<obadiah::Volume>> ask_levels{max_lvl};
 std::vector<std::vector<obadiah::Volume>> bid_levels{max_lvl};
 obadiah::OrderBookSnapshot<> output;
 while (true) {
#ifndef NDEBUG
  BOOST_LOG_SCOPED_LOGGER_ATTR(lg, "RunTime", attrs::timer());
#endif
  if (!(depth_to_snapshots >> output)) break;
  timestamp.push_back(output.t.t);
  bid_price.push_back(output.bid_price);
  ask_price.push_back(output.ask_price);
  for(std::size_t i=0; i < max_lvl; ++i) {
   ask_levels[i].push_back(output.asks[i]);
   bid_levels[i].push_back(output.bids[i]);
  }
#ifndef NDEBUG
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug1)
      << static_cast<char *>(output.t);
#endif
 }
 FINISH_LOGGING;
 Rcpp::List tmp(3+ 2*max_lvl);
 tmp[0] = timestamp;
 tmp[1] = bid_price;
 tmp[2] = ask_price;
 for(std::size_t i=0; i< max_lvl; ++i) {
  tmp[3+2*i] = bid_levels[i];
  tmp[3+2*i+1] = ask_levels[i];
 }
 Rcpp::DataFrame result(tmp);
 Rcpp::CharacterVector names(3+ 2*max_lvl);
 names[0] = "timestamp";
 names[1] = "bid.price";
 names[2] = "ask.price";
 char buffer[100];
 for(std::size_t i=0; i< max_lvl; ++i) {
  sprintf(buffer, "b%lu", i);
  names[3+2*i] = buffer; 
  sprintf(buffer, "a%lu", i);
  names[3+2*i+1] = buffer;
 }
 result.attr("names") = names;

 return result;
};
// [[Rcpp::export]]
DataFrame
CalculateOrderBookChanges(DataFrame depth_changes,
                          CharacterVector debug_level) {
 START_LOGGING(CalculateOrderBookChanges.log, as<string>(debug_level));

 DepthChangesStream dc{depth_changes};
 obadiah::OrderBookChanges<> order_book_changes(&dc);
 std::vector<double> timestamp, price, volume;
 std::vector<string> side;
 std::vector<obadiah::ChainId> chain_id;

 obadiah::OrderBookChange output;
 while (order_book_changes >> output) {
#ifndef NDEBUG
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug4)
      << static_cast<char*>(output);
#endif
  timestamp.push_back(output.t.t);
  price.push_back(output.p);
  volume.push_back(output.v);
  chain_id.push_back(output.id);
  if (output.s == obadiah::Side::kBid)
   side.push_back("bid");
  else
   side.push_back("ask");
 }
 FINISH_LOGGING;

 return Rcpp::DataFrame::create(
     Rcpp::Named("timestamp") = timestamp, Rcpp::Named("price") = price,
     Rcpp::Named("volume") = volume, Rcpp::Named("side") = side,
     Rcpp::Named("chain.id") = chain_id);
};

// [[Rcpp::export]]
DataFrame
ChangeTickSize(DataFrame depth_changes, NumericVector tick_size,
               CharacterVector debug_level) {
 START_LOGGING(ChangeTickSize.log, as<string>(debug_level));

 DepthChangesStream dc{depth_changes};
 obadiah::TickSizeChanger<> tick_size_changer(&dc, tick_size[0]);
 std::vector<double> timestamp, price, volume;
 std::vector<string> side;

 obadiah::Level2 output;
 while (tick_size_changer >> output) {
#ifndef NDEBUG
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug4)
      << static_cast<char*>(output);
#endif
  timestamp.push_back(output.t.t);
  price.push_back(output.p);
  volume.push_back(output.v);
  if (output.s == obadiah::Side::kBid)
   side.push_back("bid");
  else
   side.push_back("ask");
 }
 FINISH_LOGGING;

 return Rcpp::DataFrame::create(
     Rcpp::Named("timestamp") = timestamp, Rcpp::Named("price") = price,
     Rcpp::Named("volume") = volume, Rcpp::Named("side") = side);
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
#ifndef NDEBUG
   BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug5) << static_cast<char*>(s);
#endif
  }
  return *this;
 }

private:
 NumericVector timestamp_;
 NumericVector bid_;
 NumericVector ask_;
 R_xlen_t j_;
#ifndef NDEBUG
 src::severity_logger<obadiah::SeverityLevel> lg;
#endif
};

// [[Rcpp::export]]
DataFrame
DiscoverPositions(DataFrame computed_trading_period, NumericVector phi,
                  NumericVector rho, CharacterVector debug_level) {
 START_LOGGING(DiscoverPositions.log, as<string>(debug_level));

 TradingPeriod trading_period(computed_trading_period);
 obadiah::TradingStrategy trading_strategy(&trading_period, phi[0], rho[0]);
 std::vector<double> opened_at, open_price, closed_at, close_price, log_return,
     rate;
 obadiah::Position p;
 while (trading_strategy >> p) {
#ifndef NDEBUG
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug3) << p;
#endif
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

class Prices : public obadiah::ObjectStream<obadiah::InstantPrice> {
public:
 Prices(DataFrame trading_period)
     : timestamp_(as<NumericVector>(trading_period["timestamp"])),
       prices_(as<NumericVector>(trading_period["price"])),
       j_(0){};
 operator bool() { return j_ <= timestamp_.length(); }
 Prices& operator>>(obadiah::InstantPrice& s) {
  j_++;
  if (j_ <= timestamp_.length()) {
   s.t = timestamp_[j_ - 1];
   s.p = prices_[j_ - 1];
#ifndef NDEBUG
   BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug5) << s;
#endif
  }
  return *this;
 }

private:
 NumericVector timestamp_;
 NumericVector prices_;
 R_xlen_t j_;
#ifndef NDEBUG
 src::severity_logger<obadiah::SeverityLevel> lg;
#endif
};

// [[Rcpp::export]]
DataFrame
DiscoverDrawUpDowns(DataFrame precomputed_prices, NumericVector epsilon,
                    CharacterVector debug_level) {
 START_LOGGING(DiscoverDrawUpDowns.log, as<string>(debug_level));

 Prices prices(precomputed_prices);
 obadiah::EpsilonDrawUpDowns trading_strategy(&prices, epsilon[0]);
 std::vector<double> opened_at, open_price, closed_at, close_price, log_return,
     rate;
 obadiah::Position p;
 while (trading_strategy >> p) {
#ifndef NDEBUG
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug3) << p;
#endif
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
 START_LOGGING(spread_from_depth.log, "kInfo");

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
#ifndef NDEBUG
   BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug3)
       << "Updating spread after episode " << Datetime(episode);
#endif

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
#ifndef NDEBUG
    BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug3)
        << " BID Current price: " << bids.rbegin()->first
        << " Best price: " << best_bid_price
        << " Current qty: " << bids.rbegin()->second
        << " Best qty: " << best_bid_qty;
#endif
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
#ifndef NDEBUG
    BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug3)
        << "ASK Current price: " << asks.begin()->first
        << " Best price: " << best_ask_price
        << " Current qty: " << asks.begin()->second
        << " Best qty: " << best_ask_qty;
#endif
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

#ifndef NDEBUG
    BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug3)
        << "Produced spread change record - timestamp:" << Datetime(episode)
        << "BID P: " << best_bid_price << " Q: " << best_bid_qty
        << "ASK P: " << best_ask_price << " Q: " << best_ask_qty;
#endif
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

