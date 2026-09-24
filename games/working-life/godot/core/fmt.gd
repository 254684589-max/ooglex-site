class_name Fmt
extends RefCounted
## 文字格式化：金额、百分比、时间。


static func money(v: float) -> String:
	var neg := v < 0
	var n := int(round(absf(v)))
	var s := str(n)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if neg else "") + out


static func yuan(v: float) -> String:
	return "¥" + money(v)


static func signed_yuan(v: float) -> String:
	return ("+" if v >= 0 else "-") + "¥" + money(absf(v))


static func pct(v: float, digits := 1) -> String:
	var fmt := "%+." + str(digits) + "f%%"
	return fmt % (v * 100.0)


static func clock(minute_of_day: float) -> String:
	var m := int(minute_of_day) % 1440
	return "%02d:%02d" % [int(m / 60.0), m % 60]


static func hours_text(minutes: float) -> String:
	var h := minutes / 60.0
	if absf(h - round(h)) < 0.01:
		return "%d 小时" % int(round(h))
	return "%.1f 小时" % h
