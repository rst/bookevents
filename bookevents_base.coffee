Handlebars = require('handlebars')
_ = require('lodash')
page = require('webpage').create()

jquery_url = "jquery-1.10.1.min.js"

# Utility routine (a cut-down version of a phantomJS sample that I began with):

waitFor = (testFx, onReady, timeOutMillis=8000) ->
  start = new Date().getTime()
  condition = false
  f = ->
    if (new Date().getTime() - start < timeOutMillis) and not condition
      # If not time-out yet and condition not yet fulfilled
      condition = testFx()
    else
      if not condition
        # If condition still not fulfilled (timeout but condition is 'false')
        console.log "'waitFor()' timeout"
        phantom.exit 1
      else
        onReady()
        clearInterval interval #< Stop this interval
  interval = setInterval f, 250 #< repeat check every 250ms

# To see output from "console.log" inside "page.evaluate":
# page.onConsoleMessage = (msg, line, source) -> console.log(msg)

# Suppress stray complaints about junk JS on the pages
page.onError = -> true

# The list of events we're building up.

events = []

add_event = (event) ->

  # Kludgery to fill in years in dates for the (surprisingly common)
  # case that the store event pages leave them off.

  if event.date_without_year
    now = Date.now()
    this_year = new Date(now).getFullYear()
    try_date = "#{event.date_without_year}, #{this_year}"
    if now <= Date.parse(try_date)
      event.date = try_date
    else
      event.date = "#{event.date_without_year}, #{this_year+1}"

  event.date_int = Date.parse(event.date)
  event.date_obj = new Date(event.date_int)
  events.push(event)

# Printing it

prolog = """
<html>
<head>
  <meta charset="UTF-8"/>
  <style type="text/css">
    body {
      background-color: #fff;
      max-width: 800px;
      margin-left: auto;
      margin-right: auto;
    }
    div.event_day > h2 {
      margin-top: 35px;
      margin-bottom: 5px;
      font-size: 125%;
      font-weight: bold;
    }
    div.event_day > ul {
      margin: 0px;
    }
    li.event {
      display: block;
      padding: 5px;
      border: 2px solid #88d;
      margin-bottom: 7px;
      background-color: #eef;
    }
    li.event div.intro { font-size: 80%; margin-bottom: 1ex; }
    li.event div.event_description { display: none; }
    li.event div.event_location { display: none; }
    li.event.expanded div.event_description { display: block; }
    li.event.expanded div.event_location { display: block; }

    /* The "expand/contract" button */

    li.event div.sillybutton {
      float: right;
      font-size: 70%;
      border: 1px solid black;
      background-color: #e8e8ff;
      cursor: pointer;
    }
    li.event div.sillybutton span:before { content: "Expand"; }
    li.event.expanded div.sillybutton span:before { content: "Contract"; }

    /* Suppress vcard headings in some of what we're copying from the stores */

    dl.adr dt { display: none; }
  </style>
  <script src="jquery-1.10.1.min.js"></script>
  <script>
    $(function() {
      $("div.sillybutton").click( function() {
         $(this).parents(".event").toggleClass("expanded") })
       });
  </script>
</head>
<body>
  <h1>Scheduled bookstore readings</h1>
"""

epilog = "</body></html>"

date_events_template = Handlebars.compile """
<div class="event_day">
  <h2>{{date}}</h2>
  <ul>
    {{#each events}}
      <li class="event">
        <div class="sillybutton"><span/></div>
        <div class="intro">{{time}}, {{{organizer}}} presents:</div>
        <div class="event_headline">{{{headline}}}</div>
        <div class="event_description">{{{description}}}</div>
        <div class="event_location">{{{location}}}</div>
      </li>
    {{/each}}
  </ul>
</div>
"""

dump_events = () ->
  groups = _.groupBy( events, "date_int" )
  date_ints = _.keys( groups ).sort()
  date_htmls =
    for date_int in date_ints
      date = groups[date_int][0].date_obj
      date_events_template({
        date: date.toDateString(),
        events: groups[date_int] })
  console.log prolog + date_htmls.join('') + epilog

# Mechanics of the scrape

scraper_stack = []

add_scrape = (url, scraper) -> scraper_stack.push( [url, scraper] )

do_scrape = ->
  if scraper_stack.length == 0
    dump_events()
    phantom.exit()
  else
    do_single_scrape( scraper_stack.pop()... )

do_single_scrape = (url, scraper) ->
  page.open url, (status) ->
    if status isnt 'success'
      do_scrape()
    else
      waitFor (-> page.evaluate(scraper.await)), ->
        scraper.prep()
        scraper.scrape()
        do_scrape()

class ScheduleScraper
  await: -> true
  prep: -> true
  scrape: -> add_event(event) for event in page.evaluate(@extract_events, this)
  extract_events: -> alert("extract_events not overridden!")

class SimpleScraper extends ScheduleScraper
  constructor: (overrides) ->
    @await          = overrides.await          if overrides.await?
    @prep           = overrides.prep           if overrides.prep?
    @scrape         = overrides.scrape         if overrides.scrape?
    @extract_events = overrides.extract_events if overrides.extract_events?

# Abstract scraper for an "index page" that points to *other* pages that have
# events...

class IndexScraper extends ScheduleScraper

  constructor: (event_overrides) ->
    @overrides = event_overrides

  scrape: ->
    for subscrape in page.evaluate( @collect_subscrapes, this )
      add_scrape( subscrape.url,
                  @build_subscrape( _.defaults( subscrape, @overrides )))

  collect_subscrapes: -> console.log("didn't override collect_subscrapes")
  build_subscrape: -> console.log("didn't override build_subscrape")

