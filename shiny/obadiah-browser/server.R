

## Copyright (C) 2015 Phil Stubbings <phil@parasec.net>
## Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>
## Licensed under the GPL v2 license. See LICENSE.md for full terms.

library(obAnalytics)
library(obadiah)
library(RPostgres)
library(config)
library(dplyr)
library(lubridate)
library(data.table)




# display milliseconds
options(digits.secs=3)

# auxiliary function.. flip a matrix.
reverseMatrix <- function(m) m[rev(1:nrow(m)), ]


get_time_format <- function(from.time, to.time ) {
  if(difftime(  to.time, from.time ) >= as.difftime(1, units="days") ) {
    fmt <- "%Y-%m-%d %H:%M"
  }
  else if (difftime(  to.time, from.time ) >= as.difftime(1, units="hours") )  {
    fmt <- "%H:%M:%S"
  }
  else if (difftime(  to.time, from.time ) >= as.difftime(1, units="mins") )  {
    fmt <- "%M:%S"
  } else  {
    fmt <- "%M:%OS"
  }
  fmt
}

# shiny server ep.
server <- function(input, output, session) {


  con <- obadiah::connect(user=config$user,
                          dbname=config$dbname,
                          host=config$host,
                          port=config$port,
                          sslcert=config$sslcert,
                          sslkey=config$sslkey)



  onSessionEnded(function() { obadiah::disconnect(con)})

  DBI::dbExecute(con$con(), paste0("set application_name to ",shQuote(isolate(input$remote_addr)) ))

  #futile.logger::flog.threshold(futile.logger::DEBUG, 'obadiah')
  #futile.logger::flog.appender(futile.logger::appender.console(), name='obadiah')
  #futile.logger::flog.appender(futile.logger::appender.file('obadiah.log'), name='obadiah')

  pairs <- reactive({

    exchange <- req(input$exchange)
    query <- paste0("select available_pairs as pair from get.available_pairs(",
                    "get.exchange_id(", shQuote(exchange), ")", ") order by 1" )

    pairs <- RPostgres::dbGetQuery(con$con(), query)$pair
    pair <- isolate(input$pair)

    if(!pair %in% pairs ) {
      updateSelectInput(session, "pair",choices=pairs)
    }
    else {
      updateSelectInput(session, "pair",choices=pairs, selected=pair)
    }

    pairs

  })

  pair <- reactive({
    pairs <- pairs()
    pair <- input$pair
    tp <- timePoint()

    req(pair %in% pairs, tp )

    query <- paste0("select s,e from get.available_period(",
                    "get.exchange_id(", shQuote(isolate(input$exchange)), ") , ",
                    "get.pair_id(", shQuote(pair), ")",
                    ") order by 1" )
    period <- RPostgres::dbGetQuery(con$con(), query)

    if(tp < period[1,"s"] | tp > period[1,"e"]) {

      if (tp > period[1,"e"])
        tp <- with_tz(period[1,"e"] - isolate(zoomWidth())/2, isolate(input$tz))
      else
        tp <- with_tz(period[1,"s"] + isolate(zoomWidth())/2, isolate(input$tz))

      updateDateInput(session, "date", value=date(tp), min=as_date(period[1,"s"]), max=as_date(period[1,"e"]))
      updateSliderInput(session, "time.point.h", value=hour(tp))
      updateSliderInput(session, "time.point.m", value=minute(tp))
      updateSliderInput(session, "time.point.s", value=second(tp))
      req(FALSE)
    }
    updateDateInput(session, "date", min=as_date(period[1,"s"]), max=as_date(period[1,"e"]))
    pair
  })


  query <- paste0("select available_exchanges as exchange from get.available_exchanges() order by 1" )
  exchanges <- RPostgres::dbGetQuery(con$con(), query)$exchange
  updateSelectInput(session, "exchange",choices=exchanges)

  process_dblclick <- function(raw_input) {
    tp <- as.POSIXct(raw_input$x, origin='1970-01-01 00:00.00 UTC')
    tp <- with_tz(tp, tz=values$tz)
    updateDateInput(session, "date", value=date(tp))
    updateSliderInput(session, "time.point.h", value=hour(tp))
    updateSliderInput(session, "time.point.m", value=minute(tp))
    updateSliderInput(session, "time.point.s", value=second(tp))

  }

  observeEvent(input$price_level_volume_dblclick, {
    process_dblclick(input$price_level_volume_dblclick)
  })


  observeEvent(input$overview_dblclick, {
    process_dblclick(input$overview_dblclick)
  })


  observeEvent(input$quote.map.dblclick, {
    process_dblclick(input$quote.map.dblclick)
  })


  observeEvent(input$cancellation.volume.map.dblclick, {
    process_dblclick(input$cancellation.volume.map.dblclick)
  })





  values <- reactiveValues(res=NULL)

  observeEvent(input$tz, {
    tz.before <- isolate(values$tz)

    if(!is.null(tz.before)) {
      tp <- isolate(timePoint())
      values$tz <- input$tz
      tp <- with_tz(tp, input$tz)

      updateDateInput(session, "date", value=date(tp))
      updateSliderInput(session, "time.point.h", value=hour(tp))
      updateSliderInput(session, "time.point.m", value=minute(tp))
      updateSliderInput(session, "time.point.s", value=second(tp))
    }
    else {
      values$tz <- input$tz
    }
  })

  observeEvent(input$res, {
    desired.sampling.freq <- as.integer(input$res)%/%1800

    if(desired.sampling.freq > max(as.integer(frequencies))) {
      updateSelectInput(session, "freq", selected=max(as.integer(frequencies)))
    }
    else {
      desired.sampling.freq <- frequencies[which.max(frequencies >= desired.sampling.freq)]
      if(as.integer(desired.sampling.freq) > as.integer(input$freq) || as.integer(input$res) < as.integer(input$freq)) {
        updateSelectInput(session, "freq", selected= desired.sampling.freq)
      }

    }
    values$res <- input$res
  })



  # time reference
  timePoint <- reactive(
    {
      req(input$date, input$time.point.h, input$time.point.m, input$time.point.s, input$time.point.ms)
      d <- ymd(input$date)
      make_datetime(year(d), month(d), day(d),input$time.point.h, input$time.point.m, input$time.point.s, isolate(values$tz))
      }
    )  %>% debounce(2000)


  commission <- reactive({
    req(input$trading.period.commission)
  }) %>% debounce(2000)

  interest.rate <- reactive({
    req(input$trading.period.interest.rate)
  }) %>% debounce(2000)

  volume <- reactive({
    req(input$trading.period.volume)
    as.numeric(input$trading.period.volume)
  }) %>% debounce(2000)



  period <- reactive({
    req(values$res, input$freq)
    list(res=as.integer(values$res), freq=as.integer(input$freq))
  }) %>% debounce(2000)



  depth <- reactive( {

    tp <- timePoint()
    frequency <- period()$freq

    from.time <- tp-zoomWidth()/2
    to.time <- tp+zoomWidth()/2

    exchange <- isolate(input$exchange)
    pair <- pair()

    if (frequency == 0) frequency <- NULL

    withProgress(message="loading depth ...", {
        obadiah::depth(con, from.time, to.time, exchange, pair, frequency, tz=tz(tp))
        })
  })



  depth_filtered <- reactive( {

    if(autoPvRange())
      depth <- depth()
    else{
      depth <- depth() %>% filter(price >= priceVolumeRange()$price.from & price <= priceVolumeRange()$price.to &
                                  ( (volume >= priceVolumeRange()$volume.from & volume <= priceVolumeRange()$volume.to) | volume == 0) )
    }
    depth
  })

  trading_period <- reactive( {
    tp <- timePoint()
    obadiah::trading.period(depth_filtered(), volume(),tz=tz(tp))
  })


  trading_strategy <- reactive( {

    exchange <- isolate(input$exchange)
    pair <- pair()

    tp <- timePoint()
    frequency <- period()$freq
    from.time <- tp-zoomWidth()/2
    to.time <- tp+zoomWidth()/2
    if (frequency == 0) frequency <- NULL

    if(input$show.trading.period == 'M') mode='m'
    else mode='b'

    withProgress(message="calculating trading strategy ...", {
      obadiah::trading.strategy(trading_period(),commission(), interest.rate() , mode=mode, tz=tz(tp))
    })
  })



  depth_cache <- reactive( {

    exchange <- isolate(input$exchange)
    pair <- pair()
    depth <- depth()

    obadiah::getCachedPeriods(cache, exchange, pair, 'depth') %>%
      arrange(cached.period.start,cached.period.end) %>%
      mutate(cached.period.start=format(with_tz(cached.period.start, tz=values$tz), usetz=TRUE),
             cached.period.end=format(with_tz(cached.period.end, tz=values$tz), usetz=TRUE)
             )
  })

  trades <- reactive( {

    exchange <- isolate(input$exchange)
    pair <- pair()

    tp <- timePoint()
    from.time <- tp-12*60*60
    to.time <- tp+12*60*60


    withProgress(message="loading trades ...", {
      obadiah::trades(con, from.time, to.time, exchange, pair, tz=tz(tp))
    })
  })


  events <- reactive( {

    exchange <- isolate(input$exchange)
    pair <- pair()
    tp <- timePoint()
    from.time <- tp-zoomWidth()/2
    to.time <- tp+zoomWidth()/2


    withProgress(message="loading events ...", {
      obadiah::events(con, from.time, to.time, exchange, pair, tz=tz(tp))
    })

  })


  depth.summary <- reactive( {

    tp <- timePoint()
    frequency <- period()$freq

    from.time <- tp-zoomWidth()/2
    to.time <- tp+zoomWidth()/2


    exchange <- isolate(input$exchange)
    pair <- pair()
    if (frequency == 0) frequency <- NULL

    withProgress(message="loading liquidity percentiles ...", {
      obadiah::depth_summary(con, from.time, to.time, exchange, pair,frequency, tz=tz(tp))
    })
  })




  # time window
  zoomWidth <- reactive({
    req(period()$res)
    resolution <- period()$res
    if(resolution == 0) return(input$zoom.width) # custom
    else return(resolution)
  })

  # set time point in ui
  output$time.point.out <- renderText(format(timePoint(),format="%Y-%m-%d %H:%M:%OS3",usetz=TRUE))
  output$zoom.width.out <- renderText(paste(zoomWidth(), "seconds"))

  # get order book given time point
  ob <- reactive({

    exchange <- isolate(input$exchange)
    pair <- pair()

    tp <- timePoint()
    from.time <- tp-zoomWidth()/2
    to.time <- tp+zoomWidth()/2



    order.book.data <- withProgress(message="loading order book ...", {
      obadiah::order_book(con, tp, exchange, pair, bps.range=1000, tz=tz(tp) )
    })
    if(!autoPvRange()) {
      bids <- order.book.data$bids
      bids <- bids[bids$price >= priceVolumeRange()$price.from
                 & bids$price <= priceVolumeRange()$price.to
                 & bids$volume >= priceVolumeRange()$volume.from
                 & bids$volume <= priceVolumeRange()$volume.to, ]
      asks <- order.book.data$asks
      asks <- asks[asks$price >= priceVolumeRange()$price.from
                 & asks$price <= priceVolumeRange()$price.to
                 & asks$volume >= priceVolumeRange()$volume.from
                 & asks$volume <= priceVolumeRange()$volume.to, ]
      order.book.data$bids <- bids
      order.book.data$asks <- asks
    }
    order.book.data
  })

  # auto price+volume range?
  autoPvRange <- reactive(input$pvrange != 0)

  # specified price+volume range
  priceVolumeRange <- reactive({
    list(price.from=as.numeric(input$price.from),
         price.to=as.numeric(input$price.to),
         volume.from=as.numeric(input$volume.from),
         volume.to=as.numeric(input$volume.to))
  }) %>% debounce(4000)

  # reset specified price+volume range to limits
  observe({
    if(input$reset.range) {
      updateNumericInput(session, "price.from", value=0.01)
      updateNumericInput(session, "price.to", value=10000.00)
      updateNumericInput(session, "volume.from", value=0.00000001)
      updateNumericInput(session, "volume.to", value=100000)
    }
  })

  # overview timeseries plot
  output$overview.plot <- renderPlot({
    tp <- timePoint()
    tz <- attr(tp, "tzone")

    from.time <- tp-zoomWidth()/2
    to.time <- tp+zoomWidth()/2

    start.time <- tp - 12*60*60
    end.time <- tp+12*60*60


    p <- plotTrades(trades(), start.time = start.time, end.time = end.time )
    p <- p + ggplot2::geom_vline(xintercept=as.numeric(from.time), col="blue")
    p <- p + ggplot2::geom_vline(xintercept=as.numeric(tp), col="red")
    p + ggplot2::geom_vline(xintercept=as.numeric(to.time), col="blue") + ggplot2::scale_x_datetime(date_breaks="4 hours", labels=scales::date_format(format="%H:%M:%S", tz=tz), limits=c(start.time, end.time))
  })

  # optional price histogram plot
  output$price.histogram.plot <- renderPlot({
    width.seconds <- zoomWidth()
    tp <- timePoint()
    from.time <- tp-width.seconds/2
    to.time <- tp+width.seconds/2
    fmt <- get_time_format(from.time, to.time)

    events.filtered <- events()
    #events.filtered$volume <- events.filtered$volume*10^-8
    if(!autoPvRange()) {
      events.filtered <-
          events.filtered[events.filtered$price >= priceVolumeRange()$price.from
                        & events.filtered$price <= priceVolumeRange()$price.to
                        & events.filtered$volume >= priceVolumeRange()$volume.from
                        & events.filtered$volume <= priceVolumeRange()$volume.to, ]
    }
    plotEventsHistogram(events.filtered, from.time, to.time, val="price", bw=0.25)+ ggplot2::scale_x_datetime(labels=scales::date_format(format=fmt, tz=tz(tp)))
  })

  # optional histogram plot
  output$volume.histogram..plot <- renderPlot({
    width.seconds <- zoomWidth()
    tp <- timePoint()
    from.time <- tp-width.seconds/2
    to.time <- tp+width.seconds/2
    fmt <- get_time_format(from.time, to.time)

    events.filtered <- events()
    #events.filtered$volume <- events.filtered$volume*10^-8
    if(!autoPvRange()) {
      events.filtered <-
          events.filtered[events.filtered$price >= priceVolumeRange()$price.from
                        & events.filtered$price <= priceVolumeRange()$price.to
                        & events.filtered$volume >= priceVolumeRange()$volume.from
                        & events.filtered$volume <= priceVolumeRange()$volume.to, ]
    }
    plotEventsHistogram(events.filtered, from.time, to.time, val="volume", bw=5)+ ggplot2::scale_x_datetime(labels=scales::date_format(format=fmt, tz=input$tz))
  })

  # order book tab

  # order book depth plot
  output$ob.depth.plot <- renderPlot({
    order.book <- ob()
    if(nrow(order.book$bids) > 0 && nrow(order.book$asks) > 0)
      plotCurrentDepth(order.book)
    else {
      par(bg="#000000")
      plot(0)
    }
  })

  output$depth.cache <- renderTable({
    dc <- depth_cache()
    colnames(dc) <- c("start", "end", "# of rows")
    dc
  }, rownames=F, colnames=T, align=c("lll"))

  # order book bids
  output$ob_bids_out <- renderTable({
    bids <- ob()$bids
    if(nrow(bids) > 0 && !any(is.na(bids))) {
      bids$volume <- sprintf("%.8f", bids$volume)
      bids$id <- as.character(bids$id)
      bids$liquidity <- sprintf("%.8f", bids$liquidity)
      bids <- bids[, c("id", "timestamp", "bps", "liquidity", "volume", "price")]
      bids$timestamp <- format(bids$timestamp, "%H:%M:%OS", tz=input$tz, usetz=T)
      bids
    }
  }, rownames=F, colnames=T, align=paste0(rep("l", 6), collapse=""))

  # order book asks
  output$ob.asks.out <- renderTable({
    asks <- ob()$asks
    if(nrow(asks) > 0 && !any(is.na(asks))) {
      asks <- reverseMatrix(asks)
      asks$volume <- sprintf("%.8f", asks$volume)
      asks$liquidity <- sprintf("%.8f", asks$liquidity)
      asks$id <- as.character(asks$id)
      asks <- asks[, c("price", "volume", "liquidity", "bps", "timestamp", "id")]
      asks$timestamp <- format(asks$timestamp, "%H:%M:%OS", tz=input$tz, usetz=T)
      asks
    }
  }, rownames=F, colnames=T, align=paste0(rep("l", 6), collapse=""))

  depthbiasvalue <- reactive( {input$depthbias.value}) %>% debounce(2000)



  # liquidity/depth map plot
  output$depth.map.plot <- renderPlot({
    withProgress(message="generating Price level volume ...", {
      depth <- depth_filtered()
      trades <- trades() %>% filter(direction %in% input$showtrades)

      if("with.ids.only" %in% input$showtrades) trades <- trades %>% filter(!is.na(exchange.trade.id))


      spread <- trading_period()
      if(nrow(spread) > 0) {
        price.from <- 0.995*min(na.omit(spread$bid.price))
        price.to <- 1.005*max(na.omit(spread$ask.price))
      }
      else {
        price.from <- min(depth$price)
        price.to <- max(depth$price)
      }

      if (input$show.trading.period != 'N') positions <- trading_strategy()

      show.all.depth <- "ro" %in% input$showdepth

      width.seconds <- zoomWidth()
      tp <- timePoint()
      tz <- attr(tp, "tzone")
      from.time <- tp-width.seconds/2
      to.time <- tp+width.seconds/2


      if("lr" %in% input$showdepth) {

        first.depth.timestamp <- (depth %>% filter(timestamp >= from.time) %>% summarize(timestamp=min(timestamp)))$timestamp
        first.spread <- na.omit(trading_period())[shift(timestamp, -1) >= first.depth.timestamp, ][1, ]

        anchor.price <- (first.spread$bid.price + first.spread$ask.price)/2
        depth <- depth %>% mutate(price = price/anchor.price - 1)
        trades <- trades %>% mutate(price = price/anchor.price-1)
        price.from <- price.from/anchor.price -1
        price.to <- price.to/anchor.price -1

        if(input$show.trading.period %in% c('M', 'B')) {
          spread <- copy(spread)
          positions <- copy(positions)
          spread[, c("bid.price", "ask.price") := .(bid.price/anchor.price-1, ask.price = ask.price/anchor.price-1)]
          positions[, c("open.price", "close.price") := .(open.price/anchor.price-1,close.price/anchor.price-1)]
        }
      }

      col.bias <- if(input$depthbias == 0) depthbiasvalue() else 0

      fmt <- get_time_format(from.time, to.time)

      if(nrow(trades) == 0) trades <- NULL  # plotPriceLevels() does not detect an empty dataframe itself

      p <- if(!autoPvRange())
        plotPriceLevels(depth,
                        trades=trades,
                        show.all.depth=show.all.depth,
                        col.bias=col.bias,
                        start.time=from.time,
                        end.time=to.time,
                        price.from=priceVolumeRange()$price.from,
                        price.to=priceVolumeRange()$price.to,
                        volume.from=priceVolumeRange()$volume.from,
                        volume.to=priceVolumeRange()$volume.to
                        ) + ggplot2::scale_x_datetime(labels=scales::date_format(format=fmt, tz=tz))
      else
        plotPriceLevels(depth,
                        trades=trades,
                        show.all.depth=show.all.depth,
                        col.bias=col.bias,
                        start.time=from.time,
                        end.time=to.time,
                        price.from=price.from,
                        price.to=price.to
                        ) + ggplot2::scale_x_datetime(labels=scales::date_format(format=fmt, tz=tz))
        #p + ggplot2::geom_vline(xintercept=as.numeric(tp), col="red")
      if (input$show.trading.period != 'N') {
        p <- p +
          ggplot2::geom_segment(ggplot2::aes(x=opened.at, y=open.price, xend=closed.at, yend=close.price),positions, colour="white", arrow=ggplot2::arrow(angle=20, length=ggplot2::unit(0.01, "npc"))) +
          ggplot2::geom_point(ggplot2::aes(x=opened.at, y=open.price), positions, colour="white")
        if (input$show.trading.period == 'M') {
          spread[, "mid.price" := (ask.price + bid.price)/2 ]
          for(data in split(spread, spread[, cumsum(!is.na(mid.price) & is.na(shift(mid.price))) ])) {
            data <- head(data, nrow(data) - sum(is.na(data$mid.price))+1)
            data <- na.omit(data)
            p <- p +
              ggplot2::geom_step(ggplot2::aes(x=timestamp, y=mid.price),data=na.omit(data), colour="white")
          }
        }
        else {
          for(data in split(spread, spread[, cumsum(!is.na(bid.price) & is.na(shift(bid.price))) ])) {
            data <- head(data, nrow(data) - sum(is.na(data$bid.price))+1)
            setnafill(data, "locf", cols="bid.price")
            if(nrow(data > 1))
              p <- p +
                ggplot2::geom_step(ggplot2::aes(x=timestamp, y=bid.price),data=data, colour="red")
          }
          for( data in split(spread, spread[, cumsum(!is.na(ask.price) & is.na(shift(ask.price))) ])) {
            data <- head(data, nrow(data) - sum(is.na(data$ask.price))+1)
            setnafill(data, "locf", cols="ask.price")
            if(nrow(data) > 1)
              p <- p +
                ggplot2::geom_step(ggplot2::aes(x=timestamp, y=ask.price),data=data, colour="green")
          }
        }
      }
      p
    })
  })



  output$price_level_volume_hoverinfo <- renderPrint({
    if(!is.null(input$price_level_volume_hover)) {
      y <- input$price_level_volume_hover$domain$bottom + (input$price_level_volume_hover$domain$top - input$price_level_volume_hover$domain$bottom)*(input$price_level_volume_hover$range$bottom - input$price_level_volume_hover$coords_css$y)/(input$price_level_volume_hover$range$bottom - input$price_level_volume_hover$range$top)
      x <- as.POSIXct(input$price_level_volume_hover$domain$left + (input$price_level_volume_hover$domain$right - input$price_level_volume_hover$domain$left)*(input$price_level_volume_hover$coords_css$x - input$price_level_volume_hover$range$left)/(input$price_level_volume_hover$range$right - input$price_level_volume_hover$range$left),origin="1970-01-01 00:00:00")
      price_tolerance <- (input$price_level_volume_hover$domain$top - input$price_level_volume_hover$domain$bottom)*0.01
      d <- tail(depth_filtered() %>% filter(timestamp >=timePoint() - zoomWidth()/2, timestamp <= x & abs(price -y) <= price_tolerance ),1) %>% filter(volume > 0)
      if(nrow(d) == 1)
        cat("side:", as.character(d$side),  " price:", d$price,  " volume:", d$volume, " since:", format(d$timestamp ,format="%Y-%m-%d %H:%M:%OS3",usetz=TRUE),"\n")
    }
    #str(input$price_level_volume_hover)
  })

  # liquidity percentile plot
  output$depth.percentile.plot <- renderPlot({
    withProgress(message="generating liquidity percentiles ...", {
      width.seconds <- zoomWidth()
      freq <- period()$freq
      tp <- timePoint()
      from.time <- tp-width.seconds/2
      to.time <- tp+width.seconds/2
      fmt <- get_time_format(from.time, to.time)

      plotVolumePercentiles(depth.summary()) + ggplot2::scale_x_datetime(labels=scales::date_format(format=fmt, tz=tz(tp))) + ggplot2::coord_cartesian(xlim=c(from.time,to.time))
    })
  })

  # limit order event tab

  # order events plot
  output$quote.map.plot <- renderPlot({
    withProgress(message="generating Order events ...", {
      width.seconds <- zoomWidth()
      tp <- timePoint()
      from.time <- tp-width.seconds/2
      to.time <- tp+width.seconds/2
      fmt <- get_time_format(from.time, to.time)

      p <- if(!autoPvRange())
        plotEventMap(events(),
                     start.time=from.time,
                     end.time=to.time,
                     price.from=priceVolumeRange()$price.from,
                     price.to=priceVolumeRange()$price.to,
                     volume.from=priceVolumeRange()$volume.from,
                     volume.to=priceVolumeRange()$volume.to)+ ggplot2::scale_x_datetime(labels=scales::date_format(format=fmt, tz=tz(tp)))
      else
        plotEventMap(events(),
                     start.time=from.time,
                     end.time=to.time)+ ggplot2::scale_x_datetime(labels=scales::date_format(format=fmt, tz=tz(tp)))
      p
    })
  })

  # cancellation map
  output$cancellation.volume.map.plot <- renderPlot({
    withProgress(message="generating Cancellation ...", {
      width.seconds <- zoomWidth()
      tp <- timePoint()
      from.time <- tp-width.seconds/2
      to.time <- tp+width.seconds/2
      fmt <- get_time_format(from.time, to.time)

      p <- if(!autoPvRange())
        plotVolumeMap(events(),
                      action="deleted",
                      start.time=from.time,
                      end.time=to.time,
                      log.scale=input$logvol,
                      price.from=priceVolumeRange()$price.from,
                      price.to=priceVolumeRange()$price.to,
                      volume.from=priceVolumeRange()$volume.from,
                      volume.to=priceVolumeRange()$volume.to)+ ggplot2::scale_x_datetime(labels=scales::date_format(format=fmt, tz=tz(tp)))
      else
        plotVolumeMap(events(),
                      action="deleted",
                      start.time=from.time,
                      end.time=to.time,
                      log.scale=input$logvol)+ ggplot2::scale_x_datetime(labels=scales::date_format(format=fmt, tz=tz(tp)))
      p
    })
  })

}
