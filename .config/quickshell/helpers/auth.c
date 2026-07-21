// PAM-backed password check for the quickshell lock screen (components/Lock.qml).
//
// Reads one line (the candidate password) from stdin, authenticates the
// given username against the "quickshell-auth" PAM service, and exits 0 on
// success or 1 on failure. No setuid bit is needed: pam_unix already
// delegates the shadow read to the setuid-root unix_chkpwd helper, the same
// way su, i3lock and swaylock authenticate without being setuid themselves.
#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *g_password;

static int conversation(int num_msg, const struct pam_message **msg,
                         struct pam_response **resp, void *appdata_ptr) {
    (void)appdata_ptr;

    struct pam_response *replies = calloc((size_t)num_msg, sizeof(struct pam_response));
    if (!replies) {
        return PAM_BUF_ERR;
    }

    for (int i = 0; i < num_msg; i++) {
        if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF ||
            msg[i]->msg_style == PAM_PROMPT_ECHO_ON) {
            replies[i].resp = strdup(g_password);
        }
    }

    *resp = replies;
    return PAM_SUCCESS;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <username>\n", argv[0]);
        return 2;
    }

    char password[512];
    if (!fgets(password, sizeof(password), stdin)) {
        return 2;
    }
    password[strcspn(password, "\n")] = '\0';
    g_password = password;

    struct pam_conv conv = { conversation, NULL };
    pam_handle_t *pamh = NULL;

    int status = pam_start("quickshell-auth", argv[1], &conv, &pamh);
    if (status == PAM_SUCCESS) {
        status = pam_authenticate(pamh, 0);
    }

    pam_end(pamh, status);
    explicit_bzero(password, sizeof(password));

    return status == PAM_SUCCESS ? 0 : 1;
}
