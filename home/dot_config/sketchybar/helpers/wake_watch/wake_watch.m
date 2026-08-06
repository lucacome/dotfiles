#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <stdarg.h>
#include <sys/wait.h>
#include <stdbool.h>
#include <fcntl.h>

// Standalone watchdog for sketchybar, decoupled from the bar and the lua
// config. A wedged bar (after system wake, but also anytime) blocks its own
// event loop AND the lua loop feeding it, so nothing running in the bar can
// recover. This process:
//   - reacts to NSWorkspaceDidWakeNotification,
//   - verifies the bar answers a --query within a timeout,
//   - reloads it if it comes back, or force-kills it on a sustained wedge
//     (launchd KeepAlive restarts it),
//   - runs its own periodic liveness check so any wedge gets reaped even if
//     no wake notification ever arrives.
// All actions are logged to <config_dir>/wake_watch.log.

static const char *bar_bin = "/opt/homebrew/opt/sketchybar/bin/sketchybar";

static const char *config_dir(void)
{
    static char buf[1024];
    const char *cfg = getenv("CONFIG_DIR");
    if (cfg && *cfg)
    {
        return cfg;
    }
    snprintf(buf, sizeof(buf), "%s/.config/sketchybar", getenv("HOME") ?: "");
    return buf;
}

static void log_msg(const char *fmt, ...)
{
    char path[2048];
    snprintf(path, sizeof(path), "%s/wake_watch.log", config_dir());
    FILE *f = fopen(path, "a");
    if (!f)
        return;
    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    char ts[32];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &tmv);
    fprintf(f, "[%s] ", ts);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

// Last time we acted (killed/reloaded) or recovered, used as a cooldown so
// the wake path and the periodic path do not fight each other or a legit
// bar restart. If -1, "just started" (no cooldown yet).
static time_t g_last_action = 0;

static void write_stamp(void)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/.wake-state", config_dir());
    FILE *f = fopen(path, "w");
    if (f)
    {
        fprintf(f, "%ld", (long)time(NULL));
        fclose(f);
    }
}

// Returns true if the bar answers "sketchybar --query front_app" with real
// JSON within probe_timeout seconds. Exit status alone is not enough: a wedged
// bar lets the client exit 0 but produce no output. Drain the child's stdout
// and require at least some bytes.
static bool bar_responsive(int probe_timeout)
{
    int fds[2];
    if (pipe(fds) != 0)
        return false;
    pid_t pid = fork();
    if (pid == 0)
    {
        close(fds[0]);
        dup2(fds[1], STDOUT_FILENO);
        dup2(fds[1], STDERR_FILENO);
        close(fds[1]);
        (void)execv(bar_bin, (char *[]){(char *)bar_bin, "--query", "front_app", (char *)NULL});
        _exit(127);
    }
    close(fds[1]);
    fcntl(fds[0], F_SETFL, O_NONBLOCK);

    for (int i = 0; i < probe_timeout; i++)
    {
        char buf[4096];
        ssize_t n;
        while ((n = read(fds[0], buf, sizeof(buf))) > 0)
        {
            if (n > 0)
            {
                close(fds[0]);
                kill(pid, SIGKILL);
                waitpid(pid, NULL, 0);
                return true;
            }
        }
        int status;
        pid_t r = waitpid(pid, &status, WNOHANG);
        if (r == -1)
        {
            close(fds[0]);
            return false;
        }
        if (r == pid && (WIFEXITED(status) || WIFSIGNALED(status)))
        {
            close(fds[0]);
            return false;
        }
        sleep(1);
    }
    kill(pid, SIGKILL);
    waitpid(pid, NULL, 0);
    close(fds[0]);
    return false;
}

static void kill_bar(const char *why)
{
    g_last_action = time(NULL);
    log_msg("kill -9 due to: %s", why);
    system("/usr/bin/killall -9 sketchybar 2>/dev/null");
}

static void reload_bar(const char *why)
{
    g_last_action = time(NULL);
    log_msg("reload due to: %s", why);
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "%s --reload 2>/dev/null", bar_bin);
    system(cmd);
}

// Recovery after a wake. Reload when the bar comes back, and only if a
// post-reload probe also fails do we hard-kill. A hard kill is provisional
// safety: a responsive bar can still be visually stuck (IPC works but the UI
// is hung), and killing a bar that is mid-reload is harmless because launchd
// relaunches it.
static void recover_after_wake(void)
{
    log_msg("wake notification");
    time_t now = time(NULL);
    if (now - g_last_action < 15)
    {
        log_msg("skip: recovery cooldown active");
        return;
    }
    sleep(2); // let window server / network settle

    write_stamp();

    const int attempts = 4;
    bool recovered = false;
    for (int attempt = 1; attempt <= attempts; attempt++)
    {
        if (bar_responsive(4))
        {
            log_msg("bar responsive on attempt %d -> reload", attempt);
            reload_bar("wake, bar responsive");
            sleep(3);
            if (bar_responsive(4))
            {
                log_msg("bar healthy after reload");
                recovered = true;
                break;
            }
            log_msg("bar wedged again right after reload -> kill");
            kill_bar("post-reload unresponsive");
            recovered = true; // a kill+relaunch IS the recovery
            break;
        }
        log_msg("bar not responsive on attempt %d/%d", attempt, attempts);
        sleep(2);
    }
    if (!recovered)
    {
        log_msg("bar never responded in %d attempts -> kill", attempts);
        kill_bar("wake, bar never responded");
    }
}

// Periodic health check so probes are self-healing even without a wake event:
// sustained unresponsiveness over two probes ~4s apart reaps the bar. Cooldown
// prevents fighting with a legit restart/reload cycle.
static bool health_check_due(time_t now)
{
    return now - g_last_action > 20;
}

static void periodic_check(void)
{
    time_t now = time(NULL);
    if (!health_check_due(now))
        return;
    if (bar_responsive(4))
        return; // healthy
    log_msg("periodic probe: bar unresponsive");
    sleep(4);
    if (bar_responsive(4))
        return; // hard-to-say blip, fine now
    g_last_action = now;
    kill_bar("sustained unresponsiveness (periodic)");
}

int main(void)
{
    // Detach: a bar reload tears down the lua/process group this was spawned
    // from; fork+setsid gives the watchdog its own session.
    pid_t pid = fork();
    if (pid > 0)
        _exit(0);
    setsid();

    log_msg("wake_watch started pid=%d", (int)getpid());

    @autoreleasepool
    {
        [[NSWorkspace sharedWorkspace].notificationCenter
            addObserverForName:NSWorkspaceDidWakeNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *_Nonnull note) {
                        dispatch_async(
                            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                                recover_after_wake();
                            });
                    }];

        dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
        dispatch_source_t timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
        if (timer)
        {
            dispatch_source_set_timer(
                timer, dispatch_walltime(NULL, 0),
                10 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
            dispatch_source_set_event_handler(timer, ^{
                periodic_check();
            });
            dispatch_resume(timer);
        }

        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}