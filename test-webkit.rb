#!/usr/bin/env ruby

=begin

xtreme hackiness - but works with http://samhuri.net/Chalk/index.html
(The official chalk site site currently - 22-Oct-2011 - does UA checks & then 500s on the JS payload)

=end

require 'rubygems'
require 'gtk2'
$: << 'x86_64-linux'
require 'geis'
require 'webkit'
require 'pp'
require 'json'

class Obj < Geis::Object
	def initialize(name, view)
		super(name)
		@view = view
		@last = 0
	end
	def gesture_event(evt)
		pp evt
		if frame = evt['groups'][0]['frames'][0]
			if @view.main_frame
				type = case evt['event-type']
					when 'GEIS_EVENT_GESTURE_BEGIN':
						'touchstart';
					when 'GEIS_EVENT_GESTURE_UPDATE':
						'touchmove';
					when 'GEIS_EVENT_GESTURE_END':
						'touchend';
				end
				unless type
					STDERR.puts "Failed to recognise: #{evt['event-type']}"
					return
				end
				
				if @last >= frame['timestamp']
					return
				end
				@last = frame['timestamp']
				root_x, root_y = @view.window.origin()

				p [:type, type, :root, root_x, root_y]
				x, y = frame['focus x'] - root_x, frame['focus y'] - root_y
				touches = frame['touches-list'].map do |t|
					p [:t, t]
					{ 
							'identifier' => t['touch id'],
							'screenX' => t['touch x'],
							'screenY' => t['touch y'],
							'clientX' => t['touch x'] - root_x,
							'clientY' => t['touch y'] - root_y,
							'pageX' => t['touch x'] - root_x,
							'pageY' => t['touch y'] - root_y,
					}
				end
				@view.main_frame.exec_js <<-EOJ
(function () {
	var ev = document.createEvent("CustomEvent");
	ev.initCustomEvent('#{type}', true, false, {});
	var element = document.elementFromPoint(#{x}, #{y});
	ev.touches = #{touches.to_json};
	if (element) {
		element.dispatchEvent(ev);
	}
})();
EOJ
			end
		end
	#rescue
	#	nil
	end
end

webkit = WebKit::WebView.new
scroll = Gtk::ScrolledWindow.new

geis = Obj.new('geis-test', webkit)
geis.set_filter('foo', 2);
geis.activate

if ARGV[0]
webkit.open(ARGV[0])
else
webkit.load_string(DATA.read, "text/html", "utf-8", "file:///")
end

win = Gtk::Window.new
win.add(scroll)
scroll.add(webkit)
win.signal_connect('destroy') { |w,e| Gtk.main_quit }
win.set_default_size(1024,768)

win.show_all
Gtk.main


__END__
<!DOCTYPE html>
<head>
<script>
function $(id) {
	return document.getElementById(id);
}
</script>
</head>
<body>
<canvas id="c" width="1000" height="740">
</canvas>

<script>
document.body.addEventListener("touchstart", function (e) {
	var context = $('c').getContext("2d");

	e.touches.forEach(function (touch) {
		context.save();
		context.beginPath();
		context.rect(touch.pageX - 5, touch.pageY - 5, 10, 10);
		context.closePath();
		context.fillStyle = ['#f00', '#090', '#009'][touch.identifier];
		context.fill();
		context.restore();
	});

}, true)
document.body.addEventListener("touchmove", function (e) {
	var context = $('c').getContext("2d");

	e.touches.forEach(function (touch) {
		context.save();

		//context.rect(touch.pageX - 5, touch.pageY - 5, 10, 10);
		context.beginPath();
		context.arc(touch.pageX , touch.pageY, 8, 0, Math.PI, false);
		context.closePath();

		context.fillStyle = ['#f00', '#090', '#009'][touch.identifier];
		context.fill();

		context.restore();
	});
}, true)
document.body.addEventListener("touchend", function (e) {
	var context = $('c').getContext("2d");

	e.touches.forEach(function (touch) {
		context.save();

		context.beginPath();
		context.arc(touch.pageX, touch.pageY, 10, 0, Math.PI * 2, false);
		context.closePath();

		context.fillStyle = ['#f00', '#090', '#009'][touch.identifier];
		context.fill();

		context.restore();
	});

}, true)

</script>
</body>
</html>
