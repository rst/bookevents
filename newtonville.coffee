# Yet another store where full descriptions are only on the detail pages
# (though the index page will sometimes have a few paragraphs).

class NewtonvilleDetailScraper extends ScheduleScraper
  prep: -> page.injectJs jquery_url
  extract_events: ->
    $("img").remove()           # let's *not* scrape images
    evt = $("div.category-events.entry")
    hdr = evt.find(".entry-title").text()
    [times, title] = hdr.split(/[ ]*– */)
    [day, semidate, time] = times.split(/, */)
    [{
      headline:          title,
      description:       evt.find("div.entry-content").html(),
      date_without_year: semidate,
      time:              time,
      location:          "",
      organizer:         "Newtonville Books"
    }]

class NewtonvilleIndexScraper extends IndexScraper
  prep: -> page.injectJs jquery_url
  collect_subscrapes: ->
    $("h2.entry-title > a").map(-> {url: this.href}).get()
  build_subscrape: -> new NewtonvilleDetailScraper

add_scrape 'http://www.newtonvillebooks.com/cms/category/events/',
  new NewtonvilleIndexScraper
