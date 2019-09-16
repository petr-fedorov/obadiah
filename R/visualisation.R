#' @import ggplot2
#' @importFrom lubridate tz
#' @importFrom dplyr select group_by summarize mutate

#' @export
plotEventsIntervals <- function(intervals) {

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


  ggplot(intervals,
         aes(xmin=interval_start, xmax=interval_end, ymin=y, ymax=y+0.7, fill=c))+
    geom_rect(colour="black", size=0.02) +
    scale_fill_manual(values=c("G"="green4", "Y"="yellow2", "R"="red")) +
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
    theme(legend.position="none")
}
