#!/usr/bin/env ruby

require 'rubygems'
require 'gtk2'
require 'pp'

$: << 'x86_64-linux'

require 'geis'

class Obj < Geis::Object
	def gesture_event(evt)
		pp evt
	end
end

geis = Obj.new('geis-test')
geis.set_filter('foo', 2);
geis.activate

Gtk.main

