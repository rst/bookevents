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
    }
    dt.event_date {
      margin-top: 35px;
      font-size: 125%;
      font-weight: bold;
    }
    li.event {
      display: block;
      padding: 5px;
      border: 2px solid #88d;
      margin-bottom: 7px;
      background-color: #eef;
    }
    li.event div.event_description{ display: none; }
    li.event div.event_location{ display: none; }
    li.event.expanded div.event_description{ display: block; }
    li.event.expanded div.event_location{ display: block; }
  </style>
  <script src="jquery-1.10.1.min.js"></script>
  <script>
    $(function() {
      $("li.event").click( function() { $(this).toggleClass("expanded") })
    });
  </script>
</head>
<body>
  <h1>Scheduled bookstore readings</h1>
  <dl>
"""

epilog = """
  </dl></body></html>
"""

date_events_template = Handlebars.compile """
  <dt class="event_date">{{date}}</dt>
  <dd><ul>
    {{#each events}}
      <li class="event">
        <div class="intro">{{time}}, {{{organizer}}} presents:</div>
        <div class="event_headline">{{{headline}}}</div>
        <div class="event_description">{{{description}}}</div>
        <div class="event_location">{{{location}}}</div>
      </li>
    {{/each}}
  </ul></dd>
"""

dump_events = () ->
  groups = _.groupBy( events, "date_int" )
  date_ints = _.keys( groups ).sort()
  date_htmls =
    for date_int in date_ints
      date = groups[date_int][0].date_obj
      date_events_template({ date: date, events: groups[date_int] })
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

# A lot of bookstores seem to use a common Drupal framework which may
# be sourced from (or hosted by) indiebound.org.  (A lot of them are
# in the same /24 CIDR block.)  Unfortunately, on these, a lot of
# useful information is available only on the event detail pages, so
# we pull down the list of events, and then scrape the detail pages
# individually.
#
# FWIW, we have jQuery preloaded in these.  That is, jQuery 1.2.
# But trying to inject something newer on top...

# Event-list pages here don't contain enough info for a full listing,
# so we need to scrape individual detail pages.

class IbIndexScraper extends IndexScraper

  collect_subscrapes: ->
    $("div.event div.title a").map(-> {url: this.href}).get()

  build_subscrape: (params) -> new IbDetailScraper(params)

# Scraping an individual detail page.  Constructor takes overrides,
# in case some of the index pages have more reliable info on
# certain fields.

class IbDetailScraper extends ScheduleScraper

  constructor: (event_overrides = {}) ->
    this.ov = event_overrides

  prep: -> page.injectJs jquery_url

  extract_events: (scraper) ->

    # Bad manners to scrape out their <img> tags; nuke 'em.
    $("img").remove()

    # Do a little parsing...
    start_elt = $("div.event-start")
    start_elt.find("label").remove()
    times = start_elt.html().trim().split(' ')
    date = times.shift()

    location_block = $("div.field-field-location > div.field-items")

    # The (sole) event on the detail page:
    [{
      headline:    scraper.ov.headline    || $(".title").html()
      description: scraper.ov.description || $("#content .content p[dir=ltr]").html()
      date:        scraper.ov.date        || date
      time:        scraper.ov.time        || times.join(' ')
      location:    scraper.ov.location    || location_block.html()
      organizer:   scraper.ov.organizer   || "Somebody"
    }]

################################################################
# Individual scrapes

now = new Date()
ib_date_frag = "#{now.getFullYear()}/#{now.getMonth()+1}/#{now.getDate()}"

add_scrape "http://www.portersquarebooks.com/event/#{ib_date_frag}/list",
  new IbIndexScraper( organizer: "Porter Square Books" )

# Brookline Booksmith doesn't link to the standard Indiebound-ish event page,
# but it's there...

add_scrape "http://www.brooklinebooksmith-shop.com/event/#{ib_date_frag}/list",
  new IbIndexScraper( organizer: "Brookline Booksmith" )

add_scrape "http://harvard.com/events",
  new SimpleScraper
    await: -> ($(".event_right").size()) > 0
    extract_events: ->
      $(".event_right").map( ->
        time_info = $(".event_listing_bubble_date", this).html()
        [day, date, time] = time_info.split('<br>')
        {
          headline:    $("h2", this).html(),
          description: $(".event_intro", this).html(),
          date:        date.trim(),
          time:        time.trim(),
          location:    $(".event_listing_bubble_location", this).html().trim(),
          organizer:   "Harvard Book Shop"
        }).get()

coop_url = 'http://harvardcoopbooks.bncollege.com/webapp/wcs/stores/servlet/BNCBcalendarEventListView?langId=-1&storeId=52084&catalogId=10001'
#jquery_url = "http://code.jquery.com/jquery-1.10.1.min.js"

add_scrape coop_url,
  new SimpleScraper
    await: -> document.getElementById('dynamicCOE').firstChild != null
    prep: -> page.injectJs jquery_url
    extract_events: ->
      $("#dynamicCOE td").has("div.pLeft10").map( ->

        # We don't try to capture markup from bncollege.com ---
        # it's appalling.  But we do want to turn <br> tags into
        # whitespace, so...

        $("br",this).after(" ")

        # Extract stuff

        divs = $("div.pLeft10", this)
        time_info = $(divs[3]).text().replace(/Time:/,'').trim()
        [start_time, end_time] = time_info.split('-')
        {
          headline:    $(divs[1]).text().trim(),
          description: $(divs[2]).text().trim(),
          date:        $(divs[0]).text().trim(),
          time:        start_time,
          end_time:    end_time,
          organizer:   "Harvard Coop",
          location:
            "Harvard Coop "+$(divs[4]).text().replace(/Location:/,'').trim()
        }
      ).get()

# Kick it all off:

do_scrape()
