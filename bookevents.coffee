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

page = require('webpage').create()

# page.onConsoleMessage = (msg, line, source) -> console.log(msg)

events = []

add_event = (event) -> events.push(event)

dump_events = () ->
  for event in events
    console.log "----"
    console.log "    date: "     + event.date
    console.log "    location: " + event.location
    console.log "    headline: " + event.headline
    console.log "DESCRIPTION:"
    console.log event.description

handle_page = (kont, url, testFx, onReady) ->
  page.open url, (status) ->
    if status isnt 'success'
      console.log 'Failed on ' + url
      kont()
    else
      waitFor testFx, ->
        onReady()
        kont()

harvard_bkstore = (kont) ->
  handle_page kont, 'http://harvard.com/events',
    ->
      # Check in the page if a specific element is now visible
      page.evaluate ->
        ($(".event_right").size()) > 0
    , ->
      events_arr = page.evaluate ->
        events_arr_inner = []
        $(".event_right").each( ->
          events_arr_inner.push({
            headline:    $("h2", this).html(),
            description: $(".event_intro", this).html(),
            date:        $(".event_listing_bubble_date", this).html(),
            location:    $(".event_listing_bubble_location", this).html()
          }))
        events_arr_inner

      add_event(event) for event in events_arr

coop_url = 'http://harvardcoopbooks.bncollege.com/webapp/wcs/stores/servlet/BNCBcalendarEventListView?langId=-1&storeId=52084&catalogId=10001'
jquery_url = "http://code.jquery.com/jquery-1.10.1.min.js"

harvard_coop = (kont) ->
  handle_page kont, coop_url,
    ->
      page.evaluate ->
        document.getElementById('dynamicCOE').firstChild != null
    , ->
      page.injectJs jquery_url
      events_arr = page.evaluate ->
        events_arr_inner = []
        $("#dynamicCOE td").has("div.pLeft10").each( ->
          divs = $("div.pLeft10", this)
          html = $(divs[1]).html()
          # Note that what comes out here is messy, with "LOCATION" in the
          # location, and ugly and superfluous comments just about everywhere.
          events_arr_inner.push({
            headline:    $(divs[1]).html(),
            description: $(divs[2]).html(),
            date:        $(divs[0]).html(),
            location:    "Harvard COOP " + $(divs[4]).html()
          }))
        events_arr_inner

      add_event(event) for event in events_arr

harvard_coop( -> harvard_bkstore( -> dump_events(); phantom.exit() ))
