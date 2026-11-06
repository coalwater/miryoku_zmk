/*
 * Print each split peripheral's battery level to the console.
 *
 * The levels are already cached on the central by
 * CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING; ZMK only ever exposes
 * them again over BLE (central_bas_proxy.c), which is useless for a dongle
 * that talks to the host over USB. One log line is all the host needs.
 */

#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/init.h>
#include <zephyr/logging/log.h>

#include <zmk/split/central.h>

LOG_MODULE_REGISTER(zmk_battery_log, LOG_LEVEL_INF);

#define PERIPHERAL_COUNT ZMK_SPLIT_CENTRAL_PERIPHERAL_COUNT

// Slot order is connection/bond order, so the side each slot belongs to is a
// local fact - see CONFIG_ZMK_BATTERY_LOG_LABELS.
static char labels_buf[] = CONFIG_ZMK_BATTERY_LOG_LABELS;
static const char *labels[PERIPHERAL_COUNT];

static void battery_log_report(struct k_work *work);

static K_WORK_DELAYABLE_DEFINE(battery_log_work, battery_log_report);

static void battery_log_report(struct k_work *work) {
    char buf[24 * PERIPHERAL_COUNT];
    char slot[8];
    size_t off = 0;

    for (uint8_t i = 0; i < PERIPHERAL_COUNT; i++) {
        uint8_t level = 0;
        int rc = zmk_split_central_get_peripheral_battery_level(i, &level);
        const char *name = labels[i];

        if (!name) {
            snprintk(slot, sizeof(slot), "%u", i);
            name = slot;
        }

        off += snprintk(buf + off, sizeof(buf) - off, " %s=%d", name, rc == 0 ? (int)level : -1);
    }

    LOG_INF("batt%s", buf);

    k_work_schedule(&battery_log_work, K_SECONDS(CONFIG_ZMK_BATTERY_LOG_INTERVAL_S));
}

static int battery_log_init(void) {
    char *state = NULL;

    for (uint8_t i = 0; i < PERIPHERAL_COUNT; i++) {
        labels[i] = strtok_r(i == 0 ? labels_buf : NULL, ",", &state);
    }

    // The peripherals have not connected yet at init; the cached levels are
    // zero until they do, so the first line is worth delaying a little.
    k_work_schedule(&battery_log_work, K_SECONDS(5));
    return 0;
}

SYS_INIT(battery_log_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
