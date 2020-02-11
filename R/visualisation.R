# Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation,  version 2 of the License

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.




#' @import ggplot2
#' @importFrom lubridate tz
#' @importFrom dplyr select group_by summarize mutate dense_rank

#' @export
plotDataAvailability <- function(intervals) {

  from.time <- min(intervals$interval_start)
  to.time <- max(intervals$interval_end)

  if(difftime(  to.time, from.time ) >= as.difftime(1, units="days") ) {
    fmt <- "%Y-%m-%d %H:%M"
  }
  else if (difftime(  to.time, from.time ) >= as.difftime(1, units="hours") )  {
    fmt <- "%H:%M"
  }
  else if (difftime(  to.time, from.time ) >= as.difftime(1, units="mins") )  {
    fmt <- "%H:%M:%S"
  } else  {
    fmt <- "%H:%M:%OS"
  }


 intervals <- intervals %>%
   group_by(exchange) %>%
   mutate(y=dplyr::dense_rank(desc(pair)))

  ggplot(intervals,
         aes(xmin=interval_start, xmax=interval_end, ymin=y, ymax=y+0.7))+
    geom_rect(mapping=aes(fill=c), colour="black", size=0.02) +
    scale_fill_manual("Data:" , values=c("G"="green4", "R"="red"), breaks=c("G", "R"), labels=c("Available", "Not available")) +
    scale_x_datetime(NULL,
                     breaks=seq(min(intervals$interval_start), max(intervals$interval_end), length.out=5),
                     labels=scales::date_format(format=fmt, tz=tz(intervals$interval_start))) +
    scale_y_continuous(NULL, labels=NULL,breaks=NULL) +
    geom_text(aes(x=interval_start, y=y+0.9, label=pair),
              intervals %>%
                select(exchange, pair, y, interval_start) %>%
                group_by(exchange, pair, y) %>%
                summarize(interval_start=min(interval_start)) %>%
                mutate(interval_end = interval_start, c="R"),
              hjust="left", size=2, vjust="top") +
    facet_grid(rows=vars(exchange), scales="free_y", switch="y") +
    theme(legend.position="bottom")
}



#' @importFrom lubridate seconds
#' @export
plotPositionTrellis <- function(positions, trading.period, log.relative.price=TRUE, around=60) {

  positions <- copy(positions)
  positions[, rn := .I]

  (if(log.relative.price) {
    trading.period.trellis <- positions[,
                            trading.period[timestamp >= opened.at - seconds(around) & timestamp <=  closed.at + seconds(around),
                                           .(timestamp,price=log((bid.price+ask.price)/2) - log(open.price))],
                            by=.(rn, closed.at)]
    ggplot(trading.period.trellis,
           aes(x=timestamp, y=price)) +
      geom_point(size=0.1) +
      geom_line() +
      geom_segment(aes(x=opened.at, xend=closed.at, y=0.0, yend=log(close.price)-log(open.price)),positions, color="blue",
                   arrow=arrow(angle=20, length=unit(0.05, "npc"))) +
      facet_wrap(vars(paste0(sprintf("%02.0f", rn),":",as.character(closed.at))), scales="free", ncol=as.integer(round(sqrt(nrow(positions))))) +
      labs(y="Log relative price (position start == 0.0)", x="Timestamp")
  }
  else {
    trading.period.trellis <- positions[,
                            trading.period[timestamp >= opened.at - seconds(around) & timestamp <=  closed.at + seconds(around),
                                           .(timestamp,price=(bid.price+ask.price)/2)],
                            by=.(rn, closed.at)]
    ggplot(trading.period.trellis,
           aes(x=timestamp, y=price)) +
      geom_point(size=0.1) +
      geom_line() +
      geom_segment(aes(x=opened.at, xend=closed.at, y=open.price, yend=close.price),positions, color="blue",
                   arrow=arrow(angle=20, length=unit(0.05, "npc"))) +
      facet_wrap(vars(paste0(sprintf("%02.0f", rn), as.character(closed.at))), scales="free", ncol=as.integer(round(sqrt(nrow(positions))))) +
      labs(y="Price", x="Timestamp")

  }) + scale_x_datetime(date_labels="%H:%M")
}
