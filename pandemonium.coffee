# Pandemonium is Indiebound-ish.

add_scrape "http://www.pandemoniumbooks.com/event/#{ib_date_frag}/list/all/329",
  new IbIndexScraper({
    organizer: "Pandemonium Books",
    description_selector: "#content .content > p"})

