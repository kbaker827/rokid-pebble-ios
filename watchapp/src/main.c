#include <pebble.h>

// Message keys (must match PebbleKey enum in iOS app)
#define KEY_SOURCE_NAME  0
#define KEY_LINE1        1
#define KEY_LINE2        2
#define KEY_LINE3        3
#define KEY_STATUS_CODE  4
#define KEY_BUTTON       5

// Button values sent to phone
#define BUTTON_UP        0
#define BUTTON_SELECT    1
#define BUTTON_DOWN      2

static Window   *s_window;
static TextLayer *s_source_layer;
static TextLayer *s_line1_layer;
static TextLayer *s_line2_layer;
static TextLayer *s_line3_layer;
static TextLayer *s_time_layer;

// Persistent display strings
static char s_source_buf[32];
static char s_line1_buf[64];
static char s_line2_buf[64];
static char s_line3_buf[64];
static char s_time_buf[16];

// ── Helpers ─────────────────────────────────────────────────────────────────

static void update_time(void) {
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    strftime(s_time_buf, sizeof(s_time_buf), "%H:%M", t);
    text_layer_set_text(s_time_layer, s_time_buf);
}

// ── AppMessage callbacks ─────────────────────────────────────────────────────

static void inbox_received_cb(DictionaryIterator *iter, void *ctx) {
    Tuple *t;

    t = dict_find(iter, KEY_SOURCE_NAME);
    if (t) { snprintf(s_source_buf, sizeof(s_source_buf), "%s", t->value->cstring); }

    t = dict_find(iter, KEY_LINE1);
    if (t) { snprintf(s_line1_buf, sizeof(s_line1_buf), "%s", t->value->cstring); }

    t = dict_find(iter, KEY_LINE2);
    if (t) { snprintf(s_line2_buf, sizeof(s_line2_buf), "%s", t->value->cstring); }

    t = dict_find(iter, KEY_LINE3);
    if (t) { snprintf(s_line3_buf, sizeof(s_line3_buf), "%s", t->value->cstring); }

    text_layer_set_text(s_source_layer, s_source_buf);
    text_layer_set_text(s_line1_layer,  s_line1_buf);
    text_layer_set_text(s_line2_layer,  s_line2_buf);
    text_layer_set_text(s_line3_layer,  s_line3_buf);
}

static void inbox_dropped_cb(AppMessageResult reason, void *ctx) {
    APP_LOG(APP_LOG_LEVEL_ERROR, "Inbox dropped: %d", (int)reason);
}

// ── Button event → phone ─────────────────────────────────────────────────────

static void send_button(int button_id) {
    DictionaryIterator *out;
    AppMessageResult result = app_message_outbox_begin(&out);
    if (result != APP_MSG_OK) return;
    dict_write_uint8(out, KEY_BUTTON, (uint8_t)button_id);
    dict_write_end(out);
    app_message_outbox_send();
}

static void up_click_cb(ClickRecognizerRef r, void *ctx) {
    send_button(BUTTON_UP);
}

static void select_click_cb(ClickRecognizerRef r, void *ctx) {
    send_button(BUTTON_SELECT);
}

static void down_click_cb(ClickRecognizerRef r, void *ctx) {
    send_button(BUTTON_DOWN);
}

static void click_config_provider(void *ctx) {
    window_single_click_subscribe(BUTTON_ID_UP,     up_click_cb);
    window_single_click_subscribe(BUTTON_ID_SELECT, select_click_cb);
    window_single_click_subscribe(BUTTON_ID_DOWN,   down_click_cb);
}

// ── Tick timer ───────────────────────────────────────────────────────────────

static void tick_cb(struct tm *t, TimeUnits units) {
    update_time();
}

// ── Window load / unload ─────────────────────────────────────────────────────

static void window_load(Window *win) {
    Layer *root = window_get_root_layer(win);
    GRect bounds = layer_get_bounds(root);

    // Source name bar (top, 18px)
    s_source_layer = text_layer_create(GRect(0, 0, bounds.size.w, 18));
    text_layer_set_background_color(s_source_layer, GColorBlack);
    text_layer_set_text_color(s_source_layer, GColorWhite);
    text_layer_set_font(s_source_layer, fonts_get_system_font(FONT_KEY_GOTHIC_14_BOLD));
    text_layer_set_text_alignment(s_source_layer, GTextAlignmentCenter);
    snprintf(s_source_buf, sizeof(s_source_buf), "RokidHub");
    text_layer_set_text(s_source_layer, s_source_buf);
    layer_add_child(root, text_layer_get_layer(s_source_layer));

    // Time (top-right, inside source bar)
    s_time_layer = text_layer_create(GRect(bounds.size.w - 40, 2, 40, 16));
    text_layer_set_background_color(s_time_layer, GColorClear);
    text_layer_set_text_color(s_time_layer, GColorLightGray);
    text_layer_set_font(s_time_layer, fonts_get_system_font(FONT_KEY_GOTHIC_14));
    text_layer_set_text_alignment(s_time_layer, GTextAlignmentRight);
    layer_add_child(root, text_layer_get_layer(s_time_layer));

    // Line 1 (large, primary data)
    s_line1_layer = text_layer_create(GRect(4, 22, bounds.size.w - 8, 60));
    text_layer_set_background_color(s_line1_layer, GColorClear);
    text_layer_set_text_color(s_line1_layer, GColorBlack);
    text_layer_set_font(s_line1_layer, fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD));
    text_layer_set_overflow_mode(s_line1_layer, GTextOverflowModeWordWrap);
    snprintf(s_line1_buf, sizeof(s_line1_buf), "Waiting...");
    text_layer_set_text(s_line1_layer, s_line1_buf);
    layer_add_child(root, text_layer_get_layer(s_line1_layer));

    // Line 2 (secondary data)
    s_line2_layer = text_layer_create(GRect(4, 86, bounds.size.w - 8, 36));
    text_layer_set_background_color(s_line2_layer, GColorClear);
    text_layer_set_text_color(s_line2_layer, GColorDarkGray);
    text_layer_set_font(s_line2_layer, fonts_get_system_font(FONT_KEY_GOTHIC_18));
    text_layer_set_overflow_mode(s_line2_layer, GTextOverflowModeWordWrap);
    snprintf(s_line2_buf, sizeof(s_line2_buf), "");
    text_layer_set_text(s_line2_layer, s_line2_buf);
    layer_add_child(root, text_layer_get_layer(s_line2_layer));

    // Line 3 (tertiary)
    s_line3_layer = text_layer_create(GRect(4, 126, bounds.size.w - 8, 20));
    text_layer_set_background_color(s_line3_layer, GColorClear);
    text_layer_set_text_color(s_line3_layer, GColorDarkGray);
    text_layer_set_font(s_line3_layer, fonts_get_system_font(FONT_KEY_GOTHIC_14));
    snprintf(s_line3_buf, sizeof(s_line3_buf), "");
    text_layer_set_text(s_line3_layer, s_line3_buf);
    layer_add_child(root, text_layer_get_layer(s_line3_layer));

    update_time();
}

static void window_unload(Window *win) {
    text_layer_destroy(s_source_layer);
    text_layer_destroy(s_time_layer);
    text_layer_destroy(s_line1_layer);
    text_layer_destroy(s_line2_layer);
    text_layer_destroy(s_line3_layer);
}

// ── App lifecycle ─────────────────────────────────────────────────────────────

static void init(void) {
    s_window = window_create();
    window_set_window_handlers(s_window, (WindowHandlers){
        .load   = window_load,
        .unload = window_unload
    });
    window_set_click_config_provider(s_window, click_config_provider);
    window_stack_push(s_window, true);

    app_message_open(256, 64);
    app_message_register_inbox_received(inbox_received_cb);
    app_message_register_inbox_dropped(inbox_dropped_cb);

    tick_timer_service_subscribe(MINUTE_UNIT, tick_cb);
}

static void deinit(void) {
    tick_timer_service_unsubscribe();
    app_message_deregister_callbacks();
    window_destroy(s_window);
}

int main(void) {
    init();
    app_event_loop();
    deinit();
    return 0;
}
