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

