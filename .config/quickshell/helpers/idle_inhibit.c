// idle_inhibit: the "please don't go idle" requests apps make over D-Bus,
// for the shell's auto-lock and auto-sleep (components/power/Idle.qml).
//
// Hyprland itself only sees Wayland idle inhibitors and its own idle_inhibit
// window rules. Plenty of apps - browsers playing a video among them - ask
// over D-Bus instead, through org.freedesktop.ScreenSaver.Inhibit, which
// something has to answer (hypridle used to). This answers it, and also
// watches for systemd "idle" inhibitor locks (systemd-inhibit --what=idle).
//
// Whatever's inhibiting is kept in a small JSON file - the path given as
// the only argument - that Idle.qml watches:
//   {"inhibitors":[{"app":"firefox","reason":"video-playing","pid":1234}],
//    "systemd":false}
// Written to a temporary file and renamed into place, so it's never seen
// half-written, and removed again on exit.
//
// Only one can run: a second one finds the name taken and exits with 2,
// which is how the shell can just start it again now and then to make sure
// it's running. It outlives the shell on purpose - a shell reload would
// otherwise forget every inhibitor, and apps only ask once.
//
// usage: idle_inhibit STATE_FILE
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-event.h>
#include <unistd.h>

struct inhibitor {
    uint32_t cookie;
    char *app;
    char *reason;
    char *sender;
    int pid;
};

static struct inhibitor *inhibitors;
static size_t count, capacity;
static uint32_t next_cookie = 1;
static int systemd_idle;
static const char *state_path;
static char *tmp_path;

static void json_string(FILE *f, const char *s) {
    fputc('"', f);
    for (const unsigned char *p = (const unsigned char *)(s ? s : ""); *p; p++) {
        if (*p == '"' || *p == '\\')
            fprintf(f, "\\%c", *p);
        else if (*p < 0x20)
            fprintf(f, "\\u%04x", *p);
        else
            fputc(*p, f);
    }
    fputc('"', f);
}

static void write_state(void) {
    FILE *f = fopen(tmp_path, "w");
    if (!f) {
        fprintf(stderr, "idle_inhibit: can't write %s: %s\n", tmp_path, strerror(errno));
        return;
    }
    fputs("{\"inhibitors\":[", f);
    for (size_t i = 0; i < count; i++) {
        fputs(i ? ",{\"app\":" : "{\"app\":", f);
        json_string(f, inhibitors[i].app);
        fputs(",\"reason\":", f);
        json_string(f, inhibitors[i].reason);
        fprintf(f, ",\"pid\":%d}", inhibitors[i].pid);
    }
    fprintf(f, "],\"systemd\":%s}\n", systemd_idle ? "true" : "false");
    if (fclose(f) != 0 || rename(tmp_path, state_path) != 0)
        fprintf(stderr, "idle_inhibit: can't update %s: %s\n", state_path, strerror(errno));
}

static void remove_at(size_t i) {
    free(inhibitors[i].app);
    free(inhibitors[i].reason);
    free(inhibitors[i].sender);
    inhibitors[i] = inhibitors[--count];
}

static int method_inhibit(sd_bus_message *m, void *userdata, sd_bus_error *error) {
    (void)userdata;
    (void)error;
    const char *app, *reason;
    int r = sd_bus_message_read(m, "ss", &app, &reason);
    if (r < 0)
        return r;

    int pid = 0;
    sd_bus_creds *creds = NULL;
    if (sd_bus_query_sender_creds(m, SD_BUS_CREDS_PID, &creds) >= 0) {
        pid_t p;
        if (sd_bus_creds_get_pid(creds, &p) >= 0)
            pid = (int)p;
        sd_bus_creds_unref(creds);
    }

    if (count == capacity) {
        size_t grown = capacity ? capacity * 2 : 8;
        struct inhibitor *more = realloc(inhibitors, grown * sizeof *more);
        if (!more)
            return -ENOMEM;
        inhibitors = more;
        capacity = grown;
    }
    struct inhibitor *in = &inhibitors[count++];
    in->cookie = next_cookie++;
    in->app = strdup(app);
    in->reason = strdup(reason);
    in->sender = strdup(sd_bus_message_get_sender(m) ? sd_bus_message_get_sender(m) : "");
    in->pid = pid;

    write_state();
    return sd_bus_reply_method_return(m, "u", in->cookie);
}

static int method_uninhibit(sd_bus_message *m, void *userdata, sd_bus_error *error) {
    (void)userdata;
    (void)error;
    uint32_t cookie;
    int r = sd_bus_message_read(m, "u", &cookie);
    if (r < 0)
        return r;
    for (size_t i = 0; i < count; i++) {
        if (inhibitors[i].cookie == cookie) {
            remove_at(i);
            write_state();
            break;
        }
    }
    return sd_bus_reply_method_return(m, "");
}

// The screen saver's own state, which the lock screen doesn't report here.
static int method_get_active(sd_bus_message *m, void *userdata, sd_bus_error *error) {
    (void)userdata;
    (void)error;
    return sd_bus_reply_method_return(m, "b", 0);
}

static int method_nothing(sd_bus_message *m, void *userdata, sd_bus_error *error) {
    (void)userdata;
    (void)error;
    return sd_bus_reply_method_return(m, "");
}

static const sd_bus_vtable screensaver_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Inhibit", "ss", "u", method_inhibit, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("UnInhibit", "u", "", method_uninhibit, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("GetActive", "", "b", method_get_active, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("SimulateUserActivity", "", "", method_nothing, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_SIGNAL("ActiveChanged", "b", 0),
    SD_BUS_VTABLE_END,
};

// An app that quits (or crashes) without UnInhibit loses its inhibitors.
static int on_name_owner_changed(sd_bus_message *m, void *userdata, sd_bus_error *error) {
    (void)userdata;
    (void)error;
    const char *name, *old_owner, *new_owner;
    if (sd_bus_message_read(m, "sss", &name, &old_owner, &new_owner) < 0 || *new_owner || !*old_owner)
        return 0;
    int changed = 0;
    for (size_t i = 0; i < count;) {
        if (strcmp(inhibitors[i].sender, old_owner) == 0) {
            remove_at(i);
            changed = 1;
        } else {
            i++;
        }
    }
    if (changed)
        write_state();
    return 0;
}

// ---------------- systemd idle inhibitor locks ----------------
static void read_block_inhibited(sd_bus *system) {
    char *value = NULL;
    sd_bus_error error = SD_BUS_ERROR_NULL;
    if (sd_bus_get_property_string(system, "org.freedesktop.login1", "/org/freedesktop/login1",
                                   "org.freedesktop.login1.Manager", "BlockInhibited", &error, &value) < 0) {
        sd_bus_error_free(&error);
        return;
    }
    // A colon-separated list, e.g. "sleep:idle:handle-lid-switch".
    char padded[1024];
    snprintf(padded, sizeof padded, ":%s:", value);
    int idle = strstr(padded, ":idle:") != NULL;
    free(value);
    if (idle != systemd_idle) {
        systemd_idle = idle;
        write_state();
    }
}

static int on_login1_properties(sd_bus_message *m, void *userdata, sd_bus_error *error) {
    (void)m;
    (void)error;
    read_block_inhibited(userdata);
    return 0;
}

static int on_signal(sd_event_source *s, const struct signalfd_siginfo *si, void *userdata) {
    (void)si;
    (void)userdata;
    return sd_event_exit(sd_event_source_get_event(s), 0);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s STATE_FILE\n", argv[0]);
        return 64;
    }
    state_path = argv[1];
    if (asprintf(&tmp_path, "%s.tmp", state_path) < 0)
        return 1;

    // The state file's folder, e.g. $XDG_RUNTIME_DIR/purpura.
    char *dir = strdup(state_path);
    char *last = dir ? strrchr(dir, '/') : NULL;
    if (last && last != dir) {
        *last = '\0';
        for (char *p = dir + 1; *p; p++) {
            if (*p == '/') {
                *p = '\0';
                mkdir(dir, 0700);
                *p = '/';
            }
        }
        mkdir(dir, 0700);
    }
    free(dir);

    sd_bus *bus = NULL;
    int r = sd_bus_open_user(&bus);
    if (r < 0) {
        fprintf(stderr, "idle_inhibit: no session bus: %s\n", strerror(-r));
        return 1;
    }

    if (sd_bus_add_object_vtable(bus, NULL, "/org/freedesktop/ScreenSaver", "org.freedesktop.ScreenSaver", screensaver_vtable, NULL) < 0 ||
        sd_bus_add_object_vtable(bus, NULL, "/ScreenSaver", "org.freedesktop.ScreenSaver", screensaver_vtable, NULL) < 0) {
        fprintf(stderr, "idle_inhibit: couldn't set up the ScreenSaver interface\n");
        return 1;
    }
    sd_bus_match_signal(bus, NULL, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                        "NameOwnerChanged", on_name_owner_changed, NULL);

    r = sd_bus_request_name(bus, "org.freedesktop.ScreenSaver", 0);
    if (r < 0) {
        // Another idle_inhibit, or something else (hypridle without
        // ignore_dbus_inhibit) - nothing to do here either way.
        fprintf(stderr, "idle_inhibit: org.freedesktop.ScreenSaver is already taken: %s\n", strerror(-r));
        return 2;
    }

    sd_event *event = NULL;
    sd_event_default(&event);
    sd_bus_attach_event(bus, event, 0);

    // No system bus (or no logind) only costs the systemd inhibitors.
    sd_bus *system = NULL;
    if (sd_bus_open_system(&system) >= 0) {
        sd_bus_match_signal(system, NULL, "org.freedesktop.login1", "/org/freedesktop/login1",
                            "org.freedesktop.DBus.Properties", "PropertiesChanged", on_login1_properties, system);
        sd_bus_attach_event(system, event, 0);
        read_block_inhibited(system);
    }

    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGTERM);
    sigaddset(&mask, SIGINT);
    sigaddset(&mask, SIGHUP);
    sigprocmask(SIG_BLOCK, &mask, NULL);
    sd_event_add_signal(event, NULL, SIGTERM, on_signal, NULL);
    sd_event_add_signal(event, NULL, SIGINT, on_signal, NULL);
    sd_event_add_signal(event, NULL, SIGHUP, on_signal, NULL);

    write_state();
    r = sd_event_loop(event);

    unlink(state_path);
    sd_bus_flush_close_unref(bus);
    if (system)
        sd_bus_flush_close_unref(system);
    sd_event_unref(event);
    return r < 0 ? 1 : 0;
}
