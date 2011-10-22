
%name geis

%pkg-config libutouch-geis
%pkg-config gtk+-2.0

%include gtk/gtk.h
%include geis/geis.h

%{
#include <intern.h>

#define INIT(obj, gobj) __my_init(obj, G_OBJECT(gobj))

static inline void __my_init(VALUE obj, GObject *gobj) {
	g_object_ref(gobj);
	g_object_ref_sink(gobj);
	G_INITIALIZE(obj, gobj);
}

static inline VALUE strOrNil(const char *str) {
	if (str) {
		return rb_str_new2(str);
	} else {
		return Qnil;
	}
}


typedef struct rbGeisObject_ {
  Geis geis;
  GeisSubscription subscription;
  GeisFilter filter;
  VALUE self;
  int        fd;
  GIOChannel        *iochannel;
  int                iochannel_id;
} rbGeisObject;

static rbGeisObject *new_rbgeis_object() {
	return g_new0(rbGeisObject,1);
}

static void free_rbgeis_object(rbGeisObject *_self) {
	if (_self) {
		if (_self->subscription)
			geis_subscription_delete(_self->subscription);
		if (_self->geis)
			geis_delete(_self->geis);
		g_free(_self);
	}
}
static void mark_rbgeis_object(rbGeisObject *_self) {
}

static void check_status(GeisStatus status) {
	switch (status) {
		case GEIS_STATUS_SUCCESS:
		case GEIS_STATUS_CONTINUE:
		case GEIS_STATUS_EMPTY:
			return;
		case GEIS_STATUS_NOT_SUPPORTED:
			rb_raise(rb_eNotImpError, "Geis not implemented error");
			return;
		case GEIS_UNKNOWN_ERROR:
		case GEIS_STATUS_UNKNOWN_ERROR:
			rb_raise(rb_eRuntimeError, "Geis unknown error");
			return;
		case GEIS_BAD_ARGUMENT:
		case GEIS_STATUS_BAD_ARGUMENT:
			rb_raise(rb_eArgError, "Geis bad argument error");
			return;
	}
	return;
}

static void set_hash_val(VALUE hash, GeisAttr attr) 
{
	GeisString attr_name = geis_attr_name(attr);
	switch (geis_attr_type(attr))
	{
		case GEIS_ATTR_TYPE_BOOLEAN:
			rb_hash_aset(hash, rb_str_new2(attr_name), geis_attr_value_to_boolean(attr) ? Qtrue : Qfalse);
			break;
		case GEIS_ATTR_TYPE_FLOAT:
			rb_hash_aset(hash, rb_str_new2(attr_name), rb_float_new(geis_attr_value_to_float(attr)));
			break;
		case GEIS_ATTR_TYPE_INTEGER:
			rb_hash_aset(hash, rb_str_new2(attr_name), INT2NUM(geis_attr_value_to_integer(attr)));
			break;
		case GEIS_ATTR_TYPE_STRING:
			rb_hash_aset(hash, rb_str_new2(attr_name), rb_str_new2(geis_attr_value_to_string(attr)));
			break;
		default:
			rb_hash_aset(hash, rb_str_new2(attr_name), Qnil);
			break;
	}
}

static VALUE device_event_to_hash(GeisEvent event) {
	GeisDevice device;
	GeisAttr attr;
	GeisSize i;
	GeisInputDeviceId device_id = 0;
	VALUE hash = rb_hash_new();

	attr = geis_event_attr_by_name(event, GEIS_EVENT_ATTRIBUTE_DEVICE);
	device = geis_attr_value_to_pointer(attr);

	for (i = 0; i < geis_device_attr_count(device); ++i)
	{
		set_hash_val(hash, geis_device_attr(device, i));
	}

	return hash;
}

static VALUE gesture_event_to_hash(GeisEvent event) {
	GeisAttr attr;
	GeisSize i;
	GeisTouchSet touchset;
	GeisGroupSet groupset;
	VALUE hash = rb_hash_new(), global_hash;

	global_hash = hash;

	attr = geis_event_attr_by_name(event, GEIS_EVENT_ATTRIBUTE_TOUCHSET);
	touchset = geis_attr_value_to_pointer(attr);

	attr = geis_event_attr_by_name(event, GEIS_EVENT_ATTRIBUTE_GROUPSET);
	groupset = geis_attr_value_to_pointer(attr);

	VALUE groups_ary = rb_ary_new();

	rb_hash_aset(global_hash, rb_str_new2("groups"), groups_ary);

	for (i= 0; i < geis_groupset_group_count(groupset); ++i)
	{
		GeisSize j;
		GeisGroup group = geis_groupset_group(groupset, i);
		VALUE group_hash = rb_hash_new(), frames_ary = rb_ary_new();
		rb_ary_push(groups_ary, group_hash);

		rb_hash_aset(group_hash, rb_str_new2("frames"), frames_ary);
		//printf("+group %u\n", geis_group_id(group));
		
		for (j=0; j < geis_group_frame_count(group); ++j)
		{
			GeisSize k;
			GeisFrame frame = geis_group_frame(group, j);
			GeisSize attr_count = geis_frame_attr_count(frame);
			VALUE frame_hash = rb_hash_new(), touches_ary = rb_ary_new();

			rb_ary_push(frames_ary, frame_hash);

			rb_hash_aset(frame_hash, rb_str_new2("touches-list"), touches_ary);

			//printf("+frame %u\n", geis_frame_id(frame));
			for (k = 0; k < attr_count; ++k)
			{
				set_hash_val(frame_hash, geis_frame_attr(frame, k));
			}

			for (k = 0; k < geis_frame_touchid_count(frame); ++k)
			{
				GeisSize	touchid = geis_frame_touchid(frame, k);
				GeisTouch touch = geis_touchset_touch_by_id(touchset, touchid);
				GeisSize	n;
				VALUE touch_hash = rb_hash_new();

				rb_ary_push(touches_ary, touch_hash);
				//printf("+touch %lu\n", k);
				for (n = 0; n < geis_touch_attr_count(touch); ++n)
				{
					set_hash_val(touch_hash, geis_touch_attr(touch, n));
				}
			}
		}
	}
	return global_hash;
}

#define CE2RS(x) case x: return rb_str_new2(#x); break

static VALUE describe_geis_event_type(GeisEventType type) {
	switch(type) {
		CE2RS(GEIS_EVENT_DEVICE_AVAILABLE);
		CE2RS(GEIS_EVENT_DEVICE_UNAVAILABLE);
		CE2RS(GEIS_EVENT_CLASS_AVAILABLE);
		CE2RS(GEIS_EVENT_CLASS_CHANGED);
		CE2RS(GEIS_EVENT_CLASS_UNAVAILABLE);
		CE2RS(GEIS_EVENT_GESTURE_BEGIN);
		CE2RS(GEIS_EVENT_GESTURE_UPDATE);
		CE2RS(GEIS_EVENT_GESTURE_END);
		CE2RS(GEIS_EVENT_INIT_COMPLETE);
		CE2RS(GEIS_EVENT_USER_DEFINED);
		CE2RS(GEIS_EVENT_ERROR);
	}
}

static gboolean
io_callback (GIOChannel   *source G_GNUC_UNUSED,
             GIOCondition  condition G_GNUC_UNUSED,
             gpointer      data)
{
	rbGeisObject *_self = (rbGeisObject *)data;
	GeisStatus status;
    GeisEvent event;

	check_status(geis_dispatch_events(_self->geis));

	status = geis_next_event(_self->geis, &event);
	while (status == GEIS_STATUS_CONTINUE || status == GEIS_STATUS_SUCCESS)
	{
		VALUE e;

		switch (geis_event_type(event))
		{
		  case GEIS_EVENT_DEVICE_AVAILABLE:
		  case GEIS_EVENT_DEVICE_UNAVAILABLE:
			e = device_event_to_hash(event);
			rb_hash_aset(e, rb_str_new2("event-type"), describe_geis_event_type(geis_event_type(event)));
			
			rb_funcall(_self->self, rb_intern("device_event"), 1, e);
			break;

		  case GEIS_EVENT_GESTURE_BEGIN:
		  case GEIS_EVENT_GESTURE_UPDATE:
		  case GEIS_EVENT_GESTURE_END:
			e = gesture_event_to_hash(event);
			rb_hash_aset(e, rb_str_new2("event-type"), describe_geis_event_type(geis_event_type(event)));
			
			rb_funcall(_self->self, rb_intern("gesture_event"), 1, e);
			break;
		}
		geis_event_delete(event);
		status = geis_next_event(_self->geis, &event);
	}

	return TRUE;
}

%}

%map strOrNil > VALUE : strOrNil(%%)

module Geis
	class Object
		def __alloc__
			return Data_Wrap_Struct(self, mark_rbgeis_object, free_rbgeis_object, new_rbgeis_object());
		end
		def initialize(char *subscription_name)
			rbGeisObject *_self;
			Data_Get_Struct(self, rbGeisObject, _self);

			_self->self = self;
			_self->geis = geis_new(GEIS_INIT_TRACK_DEVICES, NULL);
			geis_get_configuration(_self->geis, GEIS_CONFIGURATION_FD, &(_self->fd));

			_self->iochannel = g_io_channel_unix_new(_self->fd);
			_self->iochannel_id = g_io_add_watch (_self->iochannel,
                                      G_IO_IN,
                                      io_callback,
                                      _self);

 			_self->subscription = geis_subscription_new(_self->geis, subscription_name, GEIS_SUBSCRIPTION_CONT);
		end

		def set_filter(char *name, gint max_touches = 2)
			rbGeisObject *_self;
			GeisStatus status;

			Data_Get_Struct(self, rbGeisObject, _self);

			if (_self->filter) {
				rb_raise(rb_eRuntimeError, "Attempt to redefine filter is not supported.");
			}

			_self->filter = geis_filter_new(_self->geis, name);

			geis_filter_add_term(_self->filter,
							GEIS_FILTER_CLASS,
							GEIS_GESTURE_ATTRIBUTE_TOUCHES, GEIS_FILTER_OP_LE, max_touches,
							NULL);

			status = geis_subscription_add_filter(_self->subscription, _self->filter);

			check_status(status);
		end

		def activate()
			rbGeisObject *_self;
			GeisStatus status;
			Data_Get_Struct(self, rbGeisObject, _self);

			status = geis_subscription_activate(_self->subscription);
			check_status(status);
		end

		def device_event(VALUE event)
			rb_p(event);
		end
		def gesture_event(VALUE event)
			rb_p(event);
		end
	end
end
