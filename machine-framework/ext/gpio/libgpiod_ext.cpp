#include <ruby.h>
#include <gpiod.hpp>
#include <string>

struct GpioPin {
    ::gpiod::line line;

    GpioPin(const std::string& chip_path, unsigned int offset) {
        ::gpiod::chip chip(chip_path);
        line = chip.get_line(offset);

        ::gpiod::line_request config;
        config.consumer = "ruby-gpiod";
        config.request_type = ::gpiod::line_request::DIRECTION_OUTPUT;

        // 0を初期値(LOW)としてピンの制御をリクエスト
        line.request(config, 0);
    }

    ~GpioPin() {
        set_value(false);
        line.release();
    }

    void set_value(bool state) {
        line.set_value(state ? 1 : 0);
    }
};

// TypedData Wrapper 用の設定
static void gpiod_pin_free(void* ptr) {
    delete static_cast<GpioPin*>(ptr);
}

static const rb_data_type_t gpiod_pin_type = {
    "GPIOD/Pin",
    {nullptr, gpiod_pin_free, nullptr,},
    nullptr, nullptr,
    RUBY_TYPED_FREE_IMMEDIATELY
};

// Rubyクラスのインスタンス作成
static VALUE pin_alloc(VALUE klass) {
    return TypedData_Wrap_Struct(klass, &gpiod_pin_type, nullptr);
}

// Pin.new(chip_path, line_number)
static VALUE pin_initialize(VALUE self, VALUE chip_path, VALUE pin_num) {
    Check_Type(chip_path, T_STRING);
    
    std::string path = StringValueCStr(chip_path);
    unsigned int offset = NUM2UINT(pin_num);

    try {
        GpioPin* pin = new GpioPin(path, offset);
        DATA_PTR(self) = pin;
    } catch (const std::exception& e) {
        rb_raise(rb_eRuntimeError, "Failed to initialize GPIO pin: %s", e.what());
    }

    return self;
}

// pin.on
static VALUE pin_on(VALUE self) {
    GpioPin* pin;
    TypedData_Get_Struct(self, GpioPin, &gpiod_pin_type, pin);
    try {
        pin->set_value(true);
    } catch (const std::exception& e) {
        rb_raise(rb_eRuntimeError, "%s", e.what());
    }
    return Qnil;
}

// pin.off
static VALUE pin_off(VALUE self) {
    GpioPin* pin;
    TypedData_Get_Struct(self, GpioPin, &gpiod_pin_type, pin);
    try {
        pin->set_value(false);
    } catch (const std::exception& e) {
        rb_raise(rb_eRuntimeError, "%s", e.what());
    }
    return Qnil;
}

extern "C" void Init_libgpiod_ext() {
    VALUE mGPIOD = rb_define_module("GPIOD");
    VALUE cPin = rb_define_class_under(mGPIOD, "Pin", rb_cObject);

    rb_define_alloc_func(cPin, pin_alloc);
    rb_define_method(cPin, "initialize", RUBY_METHOD_FUNC(pin_initialize), 2);
    rb_define_method(cPin, "on", RUBY_METHOD_FUNC(pin_on), 0);
    rb_define_method(cPin, "off", RUBY_METHOD_FUNC(pin_off), 0);
}
