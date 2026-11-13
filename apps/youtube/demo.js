.pragma library
// Made-up videos for checking the screens (ROOM_DEMO): the stills in demo/ are abstract pictures made for this.

function v(n, title, channel, views, age, dur, progress, desc) {
    return { id: "demo" + n, title: title, channel: channel, views: views, age: age, duration: dur,
             progress: progress || 0, thumb: Qt.resolvedUrl("demo/t" + (n < 10 ? "0" : "") + n + ".jpg"), desc: desc || "" }
}

var subs = [
    v(1, "Walking the ridge at golden hour: three days in the Western Ghats", "Slow Trails", "214K views", "2 days ago", "24:18", 0.35,
      "We set out before sunrise and followed the old shepherds' path along the ridge — fog, a lot of tea, and the best light of the year."),
    v(3, "One-pan summer vegetables, the way my grandmother made them", "Kitchen Notes", "1.1M views", "5 days ago", "12:04", 0,
      "Nothing fancy: what's in season, a hot pan and a little patience."),
    v(5, "How sound waves actually travel (and why your room sounds the way it does)", "Field Theory", "860K views", "1 week ago", "18:51", 0,
      "Reflections, standing waves and the one thing you can do about them for free."),
    v(4, "I rebuilt my desk setup around one idea: fewer things", "Studio Ten", "392K views", "1 week ago", "15:37", 1,
      "A year of trying to make a desk that gets out of the way."),
    v(7, "Late night synth session — live in the studio", "Night Shift Audio", "88K views", "2 weeks ago", "1:02:10", 0.6),
    v(6, "The quietest valley in the Alps", "Slow Trails", "502K views", "3 weeks ago", "21:45", 0),
    v(9, "Designing a poster in 30 minutes, start to finish", "Studio Ten", "176K views", "3 weeks ago", "31:20", 0),
    v(2, "City lights: a 4K night walk with no talking", "After Hours", "2.4M views", "1 month ago", "48:02", 0)
]
var home = [
    v(8, "The colour of sunsets, explained", "Field Theory", "3.2M views", "4 months ago", "11:26", 0),
    v(10, "Copper and wood: making a lamp from scratch", "Workbench", "640K views", "2 months ago", "26:40", 0),
    v(11, "Dusk at 4,000 metres", "Slow Trails", "1.8M views", "1 year ago", "9:58", 0),
    v(12, "Fireflies in the rain forest at night", "After Hours", "930K views", "8 months ago", "33:12", 0),
    v(1, "Walking the ridge at golden hour: three days in the Western Ghats", "Slow Trails", "214K views", "2 days ago", "24:18", 0.35),
    v(3, "One-pan summer vegetables, the way my grandmother made them", "Kitchen Notes", "1.1M views", "5 days ago", "12:04", 0)
]
var later = [
    v(5, "How sound waves actually travel (and why your room sounds the way it does)", "Field Theory", "860K views", "1 week ago", "18:51", 0),
    v(10, "Copper and wood: making a lamp from scratch", "Workbench", "640K views", "2 months ago", "26:40", 0.2),
    v(9, "Designing a poster in 30 minutes, start to finish", "Studio Ten", "176K views", "3 weeks ago", "31:20", 0)
]
var search = [
    v(7, "Lo-fi beats to focus: 2 hours, no ads in between", "Night Shift Audio", "4.6M views", "6 months ago", "2:01:44", 0),
    v(12, "Rain and lo-fi for a slow evening", "After Hours", "1.3M views", "1 year ago", "1:12:30", 0),
    v(2, "Lo-fi city: night walk with a soft soundtrack", "After Hours", "702K views", "3 months ago", "58:16", 0),
    v(4, "How I make a lo-fi beat from one sample", "Studio Ten", "264K views", "2 weeks ago", "17:09", 0),
    v(11, "Lo-fi mountain mornings", "Slow Trails", "98K views", "5 days ago", "45:00", 0)
]
var feeds = { "subs": subs, "home": home, "later": later }
var recent = ["lo-fi beats", "western ghats trek", "desk setup", "sourdough"]
