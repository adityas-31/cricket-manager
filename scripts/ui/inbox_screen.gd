extends ScrollContainer
## Inbox: every news item this season, newest first.

var app: Node

var _list: VBoxContainer


func title() -> String:
	return "Inbox"


func subtitle() -> String:
	return "%d messages" % app.season.news.size()


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var c := UIKit.card("Messages")
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(c)
	_list = UIKit.content(c)


func on_shown() -> void:
	UIKit.clear(_list)
	var items: Array = app.season.news.duplicate()
	items.reverse()
	for n in items:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		var date := UIKit.label(app.season.news_date(n), 12, UIKit.TEXT_DIM)
		date.custom_minimum_size.x = 130
		h.add_child(date)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(UIKit.label(n.title, 15))
		body.add_child(UIKit.wrapped(n.body, 13))
		h.add_child(body)
		_list.add_child(h)
		_list.add_child(HSeparator.new())
