
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

