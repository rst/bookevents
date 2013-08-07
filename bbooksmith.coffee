# Brookline Booksmith doesn't link to the standard Indiebound-ish event page,
# but it's there...

add_scrape "http://www.brooklinebooksmith-shop.com/event/#{ib_date_frag}/list",
  new IbIndexScraper({
    organizer: "Brookline Booksmith",
    description_selector: "#main .content > p"})

