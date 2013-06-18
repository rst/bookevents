Handlebars = require('handlebars')
_ = require('lodash')
page = require('webpage').create()

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
  <style type="text/css">
    dt.event_date {
      font-size: 125%;
      font-weight: bold;
    }
    li.event {
      display: block;
      padding: 5px;
      border: 2px solid #800;
      margin-bottom: 7px;
      background-color: #fdd;
    }
  </style>
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
        <div class="where">{{time}}, {{{location}}}</div>
        <div class="event_headline">{{{headline}}}</div>
        <div class="event_description">{{{description}}}</div>
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
        add_event(event) for event in page.evaluate(scraper.scrape)
        do_scrape()

class ScheduleScraper
  await: -> true
  prep: -> true
  scrape: -> alert("scrape not overridden!")
  constructor: (overrides) ->
    @await  = overrides.await  if overrides.await?
    @prep   = overrides.prep   if overrides.prep?
    @scrape = overrides.scrape if overrides.scrape?

# Individual scrapes

add_scrape "http://harvard.com/events",
  new ScheduleScraper(
    await: -> ($(".event_right").size()) > 0
    scrape: ->
      $(".event_right").map( ->
        time_info = $(".event_listing_bubble_date", this).html()
        [day, date, time] = time_info.split('<br>')
        {
          headline:    $("h2", this).html(),
          description: $(".event_intro", this).html(),
          date:        date.trim(),
          time:        time.trim(),
          location:    $(".event_listing_bubble_location", this).html().trim()
        }).get())

coop_url = 'http://harvardcoopbooks.bncollege.com/webapp/wcs/stores/servlet/BNCBcalendarEventListView?langId=-1&storeId=52084&catalogId=10001'
#jquery_url = "http://code.jquery.com/jquery-1.10.1.min.js"
jquery_url = "jquery-1.10.1.min.js"

add_scrape coop_url,
  new ScheduleScraper(
    await: -> document.getElementById('dynamicCOE').firstChild != null
    prep: -> page.injectJs jquery_url
    scrape: ->
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
          location:
            "Harvard COOP "+$(divs[4]).text().replace(/Location:/,'').trim()
        }
      ).get())

add_scrape "http://www.brooklinebooksmith.com/events/mainevent.html",
  new ScheduleScraper
    prep: ->
      page.injectJs jquery_url
      console.log("can't inject lodash") unless page.injectJs 'lodash.js'
    scrape: ->
      $("tr[valign=middle] td").has("p").map( ->

        # Apologies if this hurts your eyes... it looks like the
        # HTML here is hand-hacked, to judge by the wildly inconsistent
        # markup.  So, we do our best.  Note that sometimes the date
        # and time aren't in a <p> at all, in which case, we still lose;
        # the "Breakwater Reading Series" on June 21 is the live example
        # of this as I write.

        grafs = $("p",this)   # XXX can miss date, time preceding first <p>!
        description = $(grafs[1]).html()

        lines = $(grafs[0]).html().split(/<br\/?>/)
        lines = _.map( lines, (x) -> x.replace(/\/?<strong\/?>/, '').trim())

        times = lines.shift()
        [date, time] = times.split /\ +at\ +/

        # XXX year not present; kludge it for now.
        # And deal with other vagaries of hand-hacked markup...
        date = date.replace(/th$/, '') # ... 14th
        date = date.replace(/st$/, '') # ... 21st
        date = date.replace(/nd$/, '') # ... 22nd
        date = date.replace(/^[A-Za-z]+, */, '') + ", 2013"

        if ((lines[0] || '').match(/Coolidge *Corner *Theat/))
          lines.shift()
          location = 'Coolidge Corner Theatre (tickets required)'
        else
          location = 'Brookline Booksmith'

        headline = lines.join(', ')

        return {
          headline:    headline,
          description: description,
          date:        date,
          time:        time,
          location:    location
        }
      ).get()

# Kick it all off:

do_scrape()