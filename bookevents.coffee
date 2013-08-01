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
    desc_selector = scraper.ov.description_selector
    desc = $(desc_selector).map( -> "<p>#{$(this).html()}</p>").get().join('')

    # The (sole) event on the detail page:
    [{
      headline:    scraper.ov.headline    || $(".title").text()
      description: scraper.ov.description || desc
      date:        scraper.ov.date        || date
      time:        scraper.ov.time        || times.join(' ')
      location:    scraper.ov.location    || location_block.html()
      organizer:   scraper.ov.organizer   || "Somebody"
    }]

# And links to Indiebound-ish event pages frequently have "today's date"
# embedded, so we make that available in the right format.

now = new Date()
ib_date_frag = "#{now.getFullYear()}/#{now.getMonth()+1}/#{now.getDate()}"

################################################################
# Individual scrapes

# Porter Square books is Indiebound-ish.

add_scrape "http://www.portersquarebooks.com/event/#{ib_date_frag}/list",
  new IbIndexScraper({
    organizer: "Porter Square Books",
    description_selector: "#content .content > p"})

# Brookline Booksmith doesn't link to the standard Indiebound-ish event page,
# but it's there...

add_scrape "http://www.brooklinebooksmith-shop.com/event/#{ib_date_frag}/list",
  new IbIndexScraper({
    organizer: "Brookline Booksmith",
    description_selector: "#main .content > p"})

# Harvard Book Store has a *different* system, which seems sui generis
# so far... but also requires going to detail pages to get a full
# description out.

class HarvardDetailScraper extends ScheduleScraper
  extract_events: ->
    time_info = $(".event_details_date .event_details_text").html()
    [day, date, time] = time_info.split('<br>')
    location = $(".event_details_location .event_details_text").html()
    details = $("#tab_content_details")
    details.find(".first_block").remove()
    $("img").remove()           # do *not* want to scrape images!

    # Limit the damage from broken markup (<li> not in a <ul>)
    # in descriptions; wrap each in an enclosing <ul>.  Not quite
    # right, but nothing's quite right.

    details.find(".block > li").each( ->
      floating_li = $(this)
      floating_li.after('<ul class="bogonbogonbogon"></ul>')
      $("ul.bogonbogonbogon").append( floating_li )
      $("ul.bogonbogonbogon").toggleClass("bogonbogonbogon")
    )

    [{
       headline:    $("h1").text() + " " + $(".event_intro").text()
       description: details.find(".block").html(),
       date:        date.trim(),
       time:        time.trim(),
       location:    location,
       organizer:   "Harvard Book Store"
    }]

class HarvardIndexScraper extends IndexScraper
  await: -> ($("a.event_listing_more").size()) > 0
  collect_subscrapes: ->
    $("a.event_listing_more").map(-> {url: this.href}).get()
  build_subscrape: -> new HarvardDetailScraper

add_scrape "http://harvard.com/events", new HarvardIndexScraper

# Here's the Harvard Coop, which has a system that's partly shared
# among Barnes & Noble stores (or at least the college-affiliated
# ones).  Then again, different ones are running different versions;
# as of late June, 2013, the B.U. bookstore is running an earlier
# version than the one scraped below, with completely different
# markup.  (The same version the Coop *was* running as of a couple
# of weeks ago.)
#
# Note that events here are presented on pages paginated by month.
# So, after scraping one month's events (or, what's left of the
# month), we may want to also look ahead a month or two.

coop_url = 'http://harvardcoopbooks.bncollege.com/webapp/wcs/stores/servlet/BNCBcalendarEventListView?langId=-1&storeId=52084&catalogId=10001'

class CoopScraper extends ScheduleScraper

  constructor: (nmonths) -> @nmonths = nmonths

  scrape: ->
    super                       # grab all events on *this* page, as usual
    if @nmonths > 0
      next_url = page.evaluate -> $("p.strEvntHead a:last")[0].href
      add_scrape( next_url, new CoopScraper( @nmonths - 1 ))

  await: -> document.getElementById('dynamicCOE').firstChild != null
  prep: -> page.injectJs jquery_url

  extract_events: ->

    # There's a *lot* of implicit stuff in here, with the structure
    # not well reflected (if at all) in the markup.  If you think this
    # is painful to read, imagine writing it!
    #
    # For starters, they don't bother putting the year into the text,
    # and the month is abbreviated, so we get those out of the URL if
    # present(!), and assume current month if not.

    href = document.location.toString()
    yearmatch = href.match(/eventYear=([0-9]+)/)
    monthmatch = href.match(/eventMonth=([0-9]+)/)

    year = if yearmatch then yearmatch[1] else new Date().getFullYear()
    rawmonth = if monthmatch then monthmatch[1] else new Date().getMonth()
    month = 1+1*rawmonth

    # Days and event descriptions are in a <dl>, in matched <dt><dd> pairs.
    # Someone may have thought this is semantic markup.  It's not.

    dts = $(".contBar > dl > dt")
    dds = $(".contBar > dl > dd")
    events = []

    for i in [0...dts.length]

      # Day and time information.  Markup isn't terribly helpful...

      dt = $(dts[i])
      day = dt.find("h3").text().match(/\d+/)[0]
      time = dt.find(".calEventLst").text().match(/\d\d:\d\d\w+/)[0]
      date = "#{year}/#{month}/#{day}"

      # In the <dd>, we have the closest we'll get to an identifiable
      # headline, in an <h4> element, and the rest is the description.

      dd = $(dds[i])
      head_elt = dd.find("h4")
      head_elt.remove()

      # Have as much as we can get...

      events.push({
        headline:    head_elt.text(),
        description: dd.html(),
        date:        date,
        time:        time,
        organizer:   "Harvard Coop",
        location:    "Harvard Coop"
      })

    events

add_scrape coop_url, new CoopScraper(3)

# Kick it all off:

do_scrape()
