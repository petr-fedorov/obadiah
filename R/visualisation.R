#' @import ggplot2
#'
#'

#' @export
plotEventsIntervals <- function(intervals) {

  ggplot(intervals,
         aes(xmin=interval_start, xmax=interval_end, ymin=y, ymax=y+0.7, fill=c))+
    geom_rect(colour="black", size=0.02) +
    scale_fill_manual(values=c("G"="green4", "Y"="yellow2", "R"="red")) +
    scale_x_datetime(NULL, date_breaks='1 month') +
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
