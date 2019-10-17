## Copyright (C) 2015 Phil Stubbings <phil@parasec.net>
## Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>
## Licensed under the GPL v2 license. See LICENSE.md for full terms.


ui <- function(req) {

tz <- 'Europe/Moscow'

fluidPage(
  includeCSS("www/bootstrap-slate.css"),
  includeCSS("www/my.css"),
  div(style = "display: none;",
      textInput("remote_addr", "remote_addr",
                if (!is.null(req[["HTTP_X_FORWARDED_FOR"]]))
                  req[["HTTP_X_FORWARDED_FOR"]]
                else
                  req[["REMOTE_ADDR"]]
      )
  ),
  titlePanel("OBADiah | Order Book Analytics Database for microstructure visualisation"),
  sidebarLayout(
    sidebarPanel(width=3,
      wellPanel(
        h4("Instrument"),
        fluidRow(
                column(6, selectInput("exchange", "Exchange", choices="")),
                column(6, selectInput("pair", "Pair", choices=""))
                 )
      ),
      hr(),
      plotOutput("overview.plot",
                 height="250px", dblclick="overview_dblclick"),
      hr(),
      wellPanel(
        h4("Period"),
        fluidRow(column(6,         selectInput("res",
                                               "Duration",
                                               list("3 seconds"=3,
                                                    "15 seconds"=15,
                                                    "30 seconds"=30,
                                                    "1 minute"=60,
                                                    "3 minute"=180,
                                                    "5 minutes"=300,
                                                    "15 minutes"=900,
                                                    "30 minutes"=1800,
                                                    "1 hour"=3600,
                                                    "3 hours"=10800,
                                                    "6 hours"=21600,
                                                    "12 hours"=43200
                                                    # "1 day"=86399,
                                                    # "custom"=0
                                               ),
                                               selected=180)),
                  column(6,        selectInput("freq",
                                               "Sampling frequency",
                                               list("All"=0,
                                                    "5 seconds"=5,
                                                    "10 seconds"=10,
                                                    "15 seconds"=15,
                                                    "30 seconds"=30
                                               ),
                                               selected=0)
                  )
                 ),
        h5("Center"),
        verbatimTextOutput("time.point.out"),
        fluidRow(column(6, dateInput("date",
                                     label="Date",
                                     value=Sys.Date(),
                                     min="2019-01-27",
                                     max=Sys.Date())),
                 column(6,selectInput("tz", "Time zone", choices=tzlist, selected=tz))),

        sliderInput("time.point.h",
                    "Hour",
                    min=0,
                    max=23,
                    value=lubridate::hour(lubridate::with_tz(Sys.time(), tz=tz)) - 1,
                    step=1,
                    width="100%"),
        sliderInput("time.point.m",
                    "Minute",
                    min=0,
                    max=59,
                    value=as.POSIXlt(Sys.time() - 3600)$min,
                    step=1,
                    width="100%"),
        sliderInput("time.point.s",
                    "Second",
                    min=0,
                    max=59,
                    value=0,
                    step=1,
                    width="100%"),
        sliderInput("time.point.ms",
                    "Millisecond",
                    min=0,
                    max=999,
                    value=0,
                    step=1,
                    width="100%")),
      conditionalPanel(
        condition="input.res == 0",
        wellPanel(
          sliderInput("zoom.width",
                      "Zoom width",
                      min=1,
                      max=86399,
                      value=60,
                      step=1,
                      width="100%"),
        verbatimTextOutput("zoom.width.out"))),
      hr(),
      # conditionalPanel(
      #   condition="input.histcheck",
      #   wellPanel(
      #     plotOutput("price.histogram.plot",
      #                height="250px"),
      #     plotOutput("volume.histogram..plot",
      #                height="250px"))
      # ),
      wellPanel(
        h4("Price & Volume Filter"),
        fluidRow(
          column(6, selectInput("pvrange",
                                "",
                                list("Auto"=1,
                                     "Custom"=0))))),
          #,
          # column(5, checkboxInput("histcheck",
          #                         label="Show histograms",
          #                         value=F)))),
      conditionalPanel(
        condition="input.pvrange == 0",
        wellPanel(
          fluidRow(
            column(6, numericInput("price.from",
                                   label="Price from",
                                   value=0.01,
                                   min=0.01,
                                   max=999.99)),
            column(6, numericInput("price.to",
                                   label="Price to",
                                   value=10000.00,
                                   min=0.02,
                                   max=1000.00))),
          hr(),
          fluidRow(
            column(6, numericInput("volume.from",
                                   label="Volume from",
                                   value=0.00000001,
                                   min=0.00000001,
                                   max=99999.99999999)),
            column(6, numericInput("volume.to",
                                   label="Volume to",
                                   value=100000,
                                   min=0.00000002,
                                   max=100000))),
          actionButton("reset.range", label="Reset range")))),
    mainPanel(width=9,
      tabsetPanel(type="tabs", selected="Price level volume",
        tabPanel("Price level volume",
                 plotOutput("depth.map.plot", height="800px", dblclick="price_level_volume_dblclick",
                            hover = hoverOpts(id = "price_level_volume_hover", delayType = "throttle"))
                 ,
                 conditionalPanel(
                   condition="$.inArray('lp', input.showdepth) > -1",
                     plotOutput("depth.percentile.plot", height="400px"))
                 ,
                 wellPanel(
                   verbatimTextOutput("price_level_volume_hoverinfo"),
                   fluidRow( column(2, wellPanel(radioButtons("showspread", label="Show spread", choices=c("Mid price"='M', "Best prices"='B', "None"='N'),
                                                    selected='M', inline=F),
                                                 checkboxInput("skip.crossed","Skip crossed", TRUE))),
                             column(2, wellPanel(radioButtons("showdraws", label="Show draws", choices=c("None"='N', "Mid price"='mid-price', "Asks"='ask', "Bids"='bid'),
                                                              selected='N', inline=F),
                                                 numericInput("minimal.draw", label="Min. draw (pct)", value=30))
                                    ),
                             column(3, wellPanel(checkboxGroupInput("showtrades",label="Show trades", choices=list("Buys"="buy", "Sells"="sell", "With exchange.trade.id only"="with.ids.only"), inline=F))),
                             column(2, wellPanel(checkboxGroupInput("showdepth",label="Show depth", choices=list("Resting orders"="ro", "Relative price"="lr", "Liquidity percentiles (slow)" ="lp" )))),
                             column(3, wellPanel(fluidRow(
                               column(6, selectInput("depthbias","Colour bias",list("Log10"=2,"Custom"=0), selected=0)),
                               column(6, conditionalPanel(condition="input.depthbias == 0",numericInput("depthbias.value", label="bias", value=0.1)))
                             )))
                             )

                 )
#                 ,
#                 wellPanel(
#                   tableOutput('depth.cache')
#                 )
#          wellPanel(
#            fluidRow(column(4,  checkboxInput("showpercentiles",label="Show liquidity percentiles", value=F))
#              ))
        ),
        tabPanel("Order events",
                 wellPanel(
                   plotOutput("quote.map.plot", height="800px", dblclick="quote.map.dblclick"))
        ),
        tabPanel("Cancellations",
                 wellPanel(
                     plotOutput("cancellation.volume.map.plot",
                                height="800px", dblclick="cancellation.volume.map.dblclick"),
                     checkboxInput("logvol",
                                   label="Logarithmic scale",
                                   value=T))),
        tabPanel("Order book",
                 wellPanel(
                   plotOutput("ob.depth.plot")),
                 hr(),
                 fluidRow(
                   column(6, align="right",
                          wellPanel(
                            tags$h3("Bids"),
                            hr(),
                            tableOutput("ob_bids_out"))),
                   column(6, align="left",
                          wellPanel(
                            tags$h3("Asks"),
                            hr(),
                            tableOutput("ob.asks.out"))))),
        tabPanel("Trades",
                 wellPanel(
                   dataTableOutput(outputId="trades.out"))),
        tabPanel("Events",
                 wellPanel(
                   dataTableOutput(outputId="events.out"))),
        tabPanel("About",
                 wellPanel(
                   h1("About"),
                   p("This tool has been developed using the",
                     a("Shiny", href="http://shiny.rstudio.com/"),
                     "web application framework for R."),
                   p("It is based on", tags$b(a("obAnalytics",
                       href="https://github.com/phil8192/ob-analytics")),
                     "- an R package created to explore and visualise
                      microstructure data and ", tags$b(a("OBADiah",
                      href="https://github.com/petr-fedorov/obadiah")),
                     " - database & utilities developed using PostgreSQL, Python and R ",
                     " to store, cleanse and render large volumes of microstructure data for exploration"),
                   br(),
                   p("Copyright", HTML("&copy;"), "2015, Phil Stubbings."),
                   p(a("phil@parasec.net", href="mailto:phil@parasec.net")),
                   p(a("http://parasec.net", href="http://parasec.net")),
                   p("Copyright", HTML("&copy;"), "2019, Petr Fedorov."),
                   p(a("petr.fedorov@phystech.edu", href="mailto:petr.fedorov@phystech.edu"))
                   ))))))
}

