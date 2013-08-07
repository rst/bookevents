
# Here's the Harvard Coop, which has a system that's partly shared
# among Barnes & Noble stores (or at least the college-affiliated
# ones).  Then again, different ones are running different versions;
# as of late June, 2013, the B.U. bookstore is running an earlier
# version than the one scraped below, with completely different
# markup.  (The same version the Coop *was* running as of a couple
# of weeks ago.)
#
# Note that events here are presented on pages paginated by month.
# So, after scraping one month's events (or, what's left of the
# month), we may want to also look ahead a month or two.

coop_url = 'http://harvardcoopbooks.bncollege.com/webapp/wcs/stores/servlet/BNCBcalendarEventListView?langId=-1&storeId=52084&catalogId=10001'

class CoopScraper extends ScheduleScraper

  constructor: (nmonths) -> @nmonths = nmonths

  scrape: ->
    super                       # grab all events on *this* page, as usual
    if @nmonths > 0
      next_url = page.evaluate -> $("p.strEvntHead a:last")[0].href
      add_scrape( next_url, new CoopScraper( @nmonths - 1 ))

  await: -> document.getElementById('dynamicCOE').firstChild != null
  prep: -> page.injectJs jquery_url

  extract_events: ->

    # There's a *lot* of implicit stuff in here, with the structure
    # not well reflected (if at all) in the markup.  If you think this
    # is painful to read, imagine writing it!
    #
    # For starters, they don't bother putting the year into the text,
    # and the month is abbreviated, so we get those out of the URL if
    # present(!), and assume current month if not.

    href = document.location.toString()
    yearmatch = href.match(/eventYear=([0-9]+)/)
    monthmatch = href.match(/eventMonth=([0-9]+)/)

    year = if yearmatch then yearmatch[1] else new Date().getFullYear()
    rawmonth = if monthmatch then monthmatch[1] else new Date().getMonth()
    month = 1+1*rawmonth

    # Days and event descriptions are in a <dl>, in matched <dt><dd> pairs.
    # Someone may have thought this is semantic markup.  It's not.

    dts = $(".contBar > dl > dt")
    dds = $(".contBar > dl > dd")
    events = []

    for i in [0...dts.length]

      # Day and time information.  Markup isn't terribly helpful...

      dt = $(dts[i])
      day = dt.find("h3").text().match(/\d+/)[0]
      time = dt.find(".calEventLst").text().match(/\d\d:\d\d\w+/)[0]
      date = "#{year}/#{month}/#{day}"

      # In the <dd>, we have the closest we'll get to an identifiable
      # headline, in an <h4> element, and the rest is the description.

      dd = $(dds[i])
      head_elt = dd.find("h4")
      head_elt.remove()

      # Have as much as we can get...

      events.push({
        headline:    head_elt.text(),
        description: dd.html(),
        date:        date,
        time:        time,
        organizer:   "Harvard Coop",
        location:    "Harvard Coop"
      })

    events

add_scrape coop_url, new CoopScraper(3)

