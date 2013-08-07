# Porter Square books is Indiebound-ish.

add_scrape "http://www.portersquarebooks.com/event/#{ib_date_frag}/list",
  new IbIndexScraper({
    organizer: "Porter Square Books",
    description_selector: "#content .content > p"})

