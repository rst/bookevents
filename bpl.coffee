class BplScraper extends ScheduleScraper
  prep: -> page.injectJs jquery_url
  extract_events: ->
    $("img").remove()
    $("div.storyrow").map( ->
      evt_div = $(this)
      margin_items = evt_div.find("h4 > span.fltlft")
      margin_html = margin_items.html()
      [spacer, spacer2, day, semidate, time, spacer3, loc] =
        margin_html.split(/<br *\/?>/)
      margin_items.remove()     # so we don't see it in the headline!

      headline_node = evt_div.find("h4")
      headline = headline_node.text()
      headline_node.remove()

      {
        headline:          headline,
        description:       evt_div.html(), # what's left of it!
        date_without_year: semidate,
        time:              time,
        location:          loc,
        organizer:         "Boston Public Library"
      }
    ).get()

add_scrape "http://www.bpl.org/programs/author_series.htm", new BplScraper

