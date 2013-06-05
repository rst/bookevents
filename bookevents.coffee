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
        ($(".event_right_details").size()) > 0
    , ->
      console.log "====================="
      console.log "Harvard Bookshop"
      events_arr = page.evaluate ->
        events_arr_inner = []
        $(".event_right_details").each( (node) ->
           events_arr_inner.push( $(this).text() ))
        events_arr_inner

      for event_html in events_arr
        console.log "-----"
        console.log event_html

coop_url = 'http://harvardcoopbooks.bncollege.com/webapp/wcs/stores/servlet/BNCBcalendarEventListView?langId=-1&storeId=52084&catalogId=10001'
jquery_url = "http://code.jquery.com/jquery-1.10.1.min.js"

harvard_coop = (kont) ->
  handle_page kont, coop_url,
    ->
      page.evaluate ->
        document.getElementById('dynamicCOE').firstChild != null
    , ->
      console.log "====================="
      console.log "COOP"
      page.injectJs jquery_url
      descs = page.evaluate ->
        elts = $("#dynamicCOE td").has("div")
        descs = []
        elts.each ->
          str = ""
          $(this, "div").each( -> str += ($(this).text() + "\n"))
          descs.push(str)
        descs
      for desc in descs
        console.log desc
        console.log "--------------"

harvard_bkstore( -> harvard_coop( -> phantom.exit() ))
