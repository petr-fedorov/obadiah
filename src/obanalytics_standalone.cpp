#ifdef OBADIAH_STANDALONE

#include <boost/log/core.hpp>
#include <boost/log/expressions.hpp>
#include <boost/log/sinks/text_file_backend.hpp>
#include <boost/log/sources/record_ostream.hpp>
#include <boost/log/sources/severity_logger.hpp>
#include <boost/log/support/date_time.hpp>
#include <boost/log/utility/setup/common_attributes.hpp>
#include <boost/log/utility/setup/file.hpp>
#include <boost/tokenizer.hpp>
#include <fstream>
#include <iostream>
#include <string>
#include "base.h"
// Compile with:
// g++ -std=gnu++14 -DOBADIAH_STANDALONE -lpthread -lboost_log
// -lboost_log_setup -lboost_thread obanalytics_standalone.cpp base.cpp severity_level.cpp
// Add  -g -pg for gprof

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

BOOST_LOG_ATTRIBUTE_KEYWORD(severity, "Severity", obadiah::SeverityLevel)
class DepthChangesFromFile : public obadiah::ObjectStream<obadiah::Level2> {
public:
 DepthChangesFromFile(const char* const filename) : csv_(filename) {
  is_all_processed_ = false;
 };
 DepthChangesFromFile& operator>>(obadiah::Level2& dc) {
  std::string line;
  if (std::getline(csv_, line)) {
   boost::tokenizer<boost::escaped_list_separator<char> > tok(line);
   auto field = tok.begin();
   dc.t = std::strtod((*field).c_str(), nullptr);
   dc.p = std::strtod((*++field).c_str(), nullptr);
   dc.v = std::strtod((*++field).c_str(), nullptr);
   dc.s = !std::strcmp((*++field).c_str(), "ask") ? obadiah::Side::kAsk
                                                  : obadiah::Side::kBid;

   BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug5) << static_cast<char*>(dc);
  } else {
   BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug5) << "Done!";
   is_all_processed_ = true;
  }
  return *this;
 }

private:
 std::ifstream csv_;
 src::severity_logger<obadiah::SeverityLevel> lg;
};

int
main() {
 logging::add_common_attributes();
 START_LOGGING(standalone.log, "DEBUG1");
 DepthChangesFromFile dc("depth1.csv");
 obadiah::TradingPeriod<std::allocator> trading_period{&dc, 0};
 obadiah::BidAskSpread output;
 std::vector<double> timestamp, bid_price, ask_price;
 while (true) {
  BOOST_LOG_SCOPED_LOGGER_ATTR(lg, "RunTime", attrs::timer());
  if (!(trading_period >> output)) break;
  timestamp.push_back(output.t.t);
  bid_price.push_back(output.p_bid);
  ask_price.push_back(output.p_ask);
  BOOST_LOG_SEV(lg, obadiah::SeverityLevel::kDebug1)
      << static_cast<char*>(output);
 }
 FINISH_LOGGING;
}

#endif

