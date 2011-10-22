libgeis bindings for ruby
=========================

This is currently a very crudely hacked up interface to get multitouch events in a ruby process.

The proof-of-concept code uses a webkit webview & feeds apple style touch events (without gestures or click events etc) to the underlying page.

It also has all kinds of broken (eg. scrolling).

Requires
--------
* rubber-generate >= 0.0.15
* ruby-gnome2 (including development files)
* libutouch-geis-dev

