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
		#pp evt
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
				
				if @last > frame['timestamp']
					return
				end
				@last = frame['timestamp']
				root_x, root_y = @view.window.origin()

				#pp frame.sort_by{|k,v|k}
				#p [:type, type, :root, root_x, root_y]
				x, y = frame['focus x'] - root_x, frame['focus y'] - root_y
				touches = frame['touches-list'].map do |t|
					#p [:t, t]
					{ 
							'identifier' => t['touch id'],
							'screenX' => t['touch x'],
							'screenY' => t['touch y'],
							'clientX' => t['touch x'] - root_x,
							'clientY' => t['touch y'] - root_y,
							# Correct for scroll?
							'pageX' => t['touch x'] - root_x,
							'pageY' => t['touch y'] - root_y,
					}
				end
				pageX = frame['touches-list'][0]['touch x'] - root_x
				pageY = frame['touches-list'][0]['touch y'] - root_y
				@view.main_frame.exec_js <<-EOJ
(function () {
	var ev = document.createEvent("CustomEvent");
	ev.initCustomEvent('#{type}', true, false, {});
	var element = document.elementFromPoint(#{x}, #{y});
	ev.touches = #{touches.to_json};
	ev.touches.item = function (i) { return this[i] };
	ev.pageX = #{pageX};
	ev.pageY = #{pageY};
	ev.angleDelta = #{frame['angle delta'] || 'null'};
	ev.radiusDelta = #{frame['radius delta'] || 'null'};
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

webkit.settings.user_agent = 'Mozilla/5.0 (iPad; U; CPU OS 3_2 like Mac OS X; en-us) AppleWebKit/531.21.10 (KHTML, like Gecko) Version/4.0.4 Mobile/7B334b Safari/531.21.10'
		settings_hash = {
			'user-agent' => 'Mozilla/5.0 (iPad; U; CPU OS 3_2 like Mac OS X; LiveLink Kiosk; U; en-gb) '+
				'AppleWebKit/531.21.10 (KHTML, like Gecko) ' +
				'Version/4.0.4 Safari/531.21.10',
			'enable-file-access-from-file-uris' => true,
			'enable-universal-access-from-file-uris' => true,
			'enable-default-context-menu' => false,
			'enable-plugins' => false,
			'enable-spell-checking' => true,
			'enable-webgl' => true,
			'enable-xss-auditor' => false
		}

		webkit.settings.class.properties.each do |prop|
			if settings_hash[prop]
				webkit.settings.set_property(prop, settings_hash[prop])
			end
		end
geis = Obj.new('geis-test', webkit)
geis.set_filter('foo', 2);
geis.activate

#webkit.signal_connect("window-object-cleared") do |wv, obj|
#	p [:cleared, wv, obj]
#	obj.exec_js("window.navigator.platform = 'iPad';console.log(window.navigator.platform);");
#end

if ARGV[0]
webkit.open(ARGV[0])
else
webkit.load_string(DATA.read.sub(/%%url/, GLib.filename_to_uri(File.expand_path("demo.jpg"))), "text/html", "utf-8", "file:///")
end

win = Gtk::Window.new
win.add(scroll)
scroll.add(webkit)
win.signal_connect('destroy') { |w,e| Gtk.main_quit }
win.set_default_size(1024,798)

win.show_all
Gtk.main


__END__
<!DOCTYPE html>
<head>
<script>
function $(id) { return document.getElementById(id); }
function c(id) { return $(id).getContext('2d'); }
</script>
</head>
<body>
<button onClick="$('c').width=1014;return false;">Clear</button>
<button onClick="size=500;angle=0;return false;">Reset</button>
<button onClick="size=500;angle=(Math.PI/2);return false;">Reset</button>
<button onClick="size=500;angle=(Math.PI);return false;">Reset</button>
<button onClick="size=500;angle=(Math.PI/2)+Math.PI;return false;">Reset</button>
<input id="sz"><input id="an"><input id="pc">
<canvas id="c" width="1014" height="740" style="position:absolute;top:40px;left:0;z-index:5;">
</canvas>
<canvas id="b" width="1014" height="740" style="position:absolute;top:40px;left:0;">
</canvas>
<script>
var COLS = ['rgba(255,0,0,0.5)', 'rgba(0,200,0,0.5)', 'rgba(0,0,0,0.5)']
document.body.addEventListener("touchstart", function (e) {
	var context = c('c');
	if (e.touches.length == 1) {
		last.pageX = e.pageX
		last.pageY = e.pageY
	}

	e.touches.forEach(function (touch) {
		touch.pageX -= $('c').offsetLeft;
		touch.pageY -= $('c').offsetTop;

		context.save();
		context.beginPath();
		context.rect(touch.pageX - 5, touch.pageY - 5, 10, 10);
		context.closePath();
		context.fillStyle = COLS[touch.identifier];
		context.fill();
		context.restore();
	});
}, true);

var size = 500;
var angle = 0;
var cx = 1040 / 2
var cy = 740 / 2
var im = new Image();
im.onload = function () { size = 505; };
im.src = '%%url'

var ctx = c('b');

ctx.lineWidth = 8;
setInterval(function () {
		//console.log("Angle: "+angle+" - size: "+size);
	var f = arguments.callee;

	if (f.size == size && f.angle == angle && f.cx == cx && f.cy == cy)
		return;
	f.size = size;
	f.angle = angle;
	f.cx = cx
	f.cy = cy
	$('an').value = angle;
	$('sz').value = size;
	$('pc').value = angle / (Math.PI*2);
	var ctx = c('b');
	ctx.clearRect(0,0,1014,740);
	ctx.save()
	ctx.translate(cx, cy);
	ctx.rotate(angle);
	ctx.scale(size / im.width, size / im.width);
	//if (angle >= (Math.PI/2) && angle <= () {
	//	ctx.drawImage(im, (-im.height / 2), (-im.width / 2));
	//} else {
		ctx.translate((-im.width / 2), (-im.height / 2));

		if (angle >= (Math.PI/3.5))
			ctx.strokeStyle = "orange";
		else
			ctx.strokeStyle = "blue";
			
		//ctx.save();
		ctx.drawImage(im, 0, 0, im.width, im.height);
		//ctx.restore();
		ctx.strokeRect(0,0, im.width, im.height);
	//}
	//ctx.fillRect(-size/2, -size/2, size, size);
	ctx.restore();

}, 30);

var last = { pageX : 0, pageY : 0 };
document.body.addEventListener("touchmove", function (e) {
	if (!! e.radiusDelta) {
		size += (e.radiusDelta * 2)
	} else if (!! e.angleDelta) {
		angle += e.angleDelta;
		while (angle>(2*Math.PI))
			angle -= (2*Math.PI);
		while (angle<0)
			angle += (2*Math.PI);
	} else if (e.touches.length == 1) {
		if (last.pageX !== 0 && last.pageY !== 0) {
			var dx = e.pageX - last.pageX;
			var dy = e.pageY - last.pageY;
			cx += dx
			cy += dy
		}
		last.pageX = e.pageX
		last.pageY = e.pageY
	}

	var context = c('c');

	e.touches.forEach(function (touch) {
		context.save();
		touch.pageX -= $('c').offsetLeft;
		touch.pageY -= $('c').offsetTop;

		//context.rect(touch.pageX - 5, touch.pageY - 5, 10, 10);
		context.beginPath();
		context.arc(touch.pageX , touch.pageY, 8, 0, Math.PI, false);
		context.closePath();

		context.fillStyle = COLS[touch.identifier];
		context.fill();

		context.restore();
	});


}, true);
document.body.addEventListener("touchend", function (e) {
	var context = c('c');

	e.touches.forEach(function (touch) {
		touch.pageX -= $('c').offsetLeft;
		touch.pageY -= $('c').offsetTop;

		context.save();

		context.beginPath();
		context.arc(touch.pageX, touch.pageY, 10, 0, Math.PI * 2, false);
		context.closePath();

		context.fillStyle = COLS[touch.identifier];
		context.fill();

		context.restore();
	});
}, true);

</script>
</body>
</html>
