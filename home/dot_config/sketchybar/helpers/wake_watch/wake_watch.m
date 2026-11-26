#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <stdarg.h>
#include <sys/wait.h>
#include <sys/stat.h>
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
// All actions are logged to <state_dir>/wake_watch.log.

static char g_bar_bin[1024];
static dispatch_queue_t g_queue;

static const char *home_dir(void)
{
    static char buf[1024];
    const char *home = getenv("HOME");
    if (home && *home)
    {
        return home;
    }
    snprintf(buf, sizeof(buf), "/Users/%s", getenv("USER") ?: "");
    return buf;
}

// State and log live outside the config dir so a copied config cannot carry a
// stale wake timestamp. Created once at startup.
static const char *state_dir(void)
{
    static char buf[1024];
    snprintf(buf, sizeof(buf), "%s/.local/state/sketchybar", home_dir());
    return buf;
}

// Prefer an explicit override, then PATH, then the two brew layouts. launchd
// starts us with a minimal PATH, so PATH alone is not enough.
static void resolve_bar_bin(void)
{
    const char *env = getenv("SKETCHYBAR_BIN");
    if (env && *env && access(env, X_OK) == 0)
    {
        snprintf(g_bar_bin, sizeof(g_bar_bin), "%s", env);
        return;
    }

    FILE *p = popen("/usr/bin/which sketchybar 2>/dev/null", "r");
    if (p)
    {
        if (fgets(g_bar_bin, sizeof(g_bar_bin), p))
        {
            char *nl = strchr(g_bar_bin, '\n');
            if (nl)
            {
                *nl = '\0';
            }
        }
        pclose(p);
    }
    if (g_bar_bin[0] && access(g_bar_bin, X_OK) == 0)
    {
        return;
    }

    const char *candidates[] = {
        "/opt/homebrew/bin/sketchybar",
        "/usr/local/bin/sketchybar",
        "/opt/homebrew/opt/sketchybar/bin/sketchybar",
        "/usr/local/opt/sketchybar/bin/sketchybar",
    };
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++)
    {
        if (access(candidates[i], X_OK) == 0)
        {
            snprintf(g_bar_bin, sizeof(g_bar_bin), "%s", candidates[i]);
            return;
        }
    }
    snprintf(g_bar_bin, sizeof(g_bar_bin), "/opt/homebrew/opt/sketchybar/bin/sketchybar");
}

static void log_msg(const char *fmt, ...)
{
    char path[2048];
    snprintf(path, sizeof(path), "%s/wake_watch.log", state_dir());

    struct stat st;
    if (stat(path, &st) == 0 && st.st_size > 1024 * 1024)
    {
        char old[2048];
        snprintf(old, sizeof(old), "%s.1", path);
        rename(path, old);
    }

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
// Bar start grace: the first periodic probe must not catch a freshly started
// bar while it is still loading its config.
static time_t g_started_at = 0;

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
        (void)execv(g_bar_bin, (char *[]){g_bar_bin, "--query", "front_app", (char *)NULL});
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

// True if a sketchybar process exists right now.
static bool bar_alive(void)
{
    pid_t pid = fork();
    if (pid == 0)
    {
        execl("/usr/bin/pgrep", "pgrep", "-x", "sketchybar", (char *)NULL);
        _exit(127);
    }
    int status;
    for (int i = 0; i < 3; i++)
    {
        pid_t r = waitpid(pid, &status, WNOHANG);
        if (r == pid)
            return WIFEXITED(status) && WEXITSTATUS(status) == 0;
        if (r == -1)
            return false;
        sleep(1);
    }
    kill(pid, SIGKILL);
    waitpid(pid, NULL, 0);
    return false;
}

// Elapsed seconds of the current bar process, or -1 when it is not running.
// Used to tell a bar that is still starting up from a wedged one: reloading or
// killing a bar launchd just restarted throws away a healthy start and can
// leave the wake-time window server with no bar at all.
static long bar_uptime(void)
{
    FILE *p = popen("/bin/ps -o etime= -p $(/usr/bin/pgrep -x sketchybar | /usr/bin/head -1) 2>/dev/null", "r");
    if (!p)
        return -1;
    char buf[64] = "";
    if (!fgets(buf, sizeof(buf), p))
    {
        pclose(p);
        return -1;
    }
    pclose(p);

    char *s = buf;
    long days = 0, h = 0, m = 0, sec = 0;
    char *dash = strchr(s, '-');
    if (dash)
    {
        days = atol(s);
        s = dash + 1;
    }
    int parts = sscanf(s, "%ld:%ld:%ld", &h, &m, &sec);
    if (parts == 2)
        return days * 86400 + h * 60 + m;
    if (parts == 3)
        return days * 86400 + h * 3600 + m * 60 + sec;
    return -1;
}

static void kill_bar(const char *why)
{
    g_last_action = time(NULL);
    log_msg("kill -9 due to: %s", why);
    system("/usr/bin/killall -9 sketchybar 2>/dev/null");

    // launchd (KeepAlive) usually revives it within a second or two. Wait a
    // bounded time for that; if nothing comes back, kick the launchd job and
    // as a last resort launch the bar ourselves. This keeps recovery working
    // even on machines where the brew plist was never bootstrapped.
    for (int i = 0; i < 6 && !bar_alive(); i++)
        sleep(1);
    if (bar_alive())
    {
        log_msg("bar relaunched (launchd)");
        return;
    }

    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
             "/bin/launchctl kickstart gui/%u/homebrew.mxcl.sketchybar 2>/dev/null",
             (unsigned)getuid());
    if (system(cmd) == 0)
    {
        for (int i = 0; i < 6 && !bar_alive(); i++)
            sleep(1);
        if (bar_alive())
        {
            log_msg("bar relaunched via launchctl kickstart");
            return;
        }
    }

    log_msg("no launchd job; spawning sketchybar directly");
    pid_t pid = fork();
    if (pid == 0)
    {
        setsid();
        execv(g_bar_bin, (char *[]){g_bar_bin, (char *)NULL});
        _exit(127);
    }
}

// Recovery after a wake. SketchyBar's SkyLight connection can wedge on wake:
// SLSRemoveSurface (window reset) and SLSConnectionGetPID (window event
// handling) both block in mach_msg waiting for the window server, so the bar
// usually does not recover in-process. Probe briefly, then restart it.
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

    const int attempts = 3;
    bool recovered = false;
    for (int attempt = 1; attempt <= attempts; attempt++)
    {
        if (bar_responsive(4))
        {
            log_msg("bar responsive on attempt %d/%d", attempt, attempts);
            recovered = true;
            break;
        }
        log_msg("bar not responsive on attempt %d/%d", attempt, attempts);
        sleep(2);
    }
    if (!recovered)
    {
        log_msg("bar silent for %d attempts -> kill", attempts);
        kill_bar("wake, bar never responded");
    }
}

// Periodic health check so probes are self-healing even without a wake event:
// sustained unresponsiveness over two probes ~4s apart reaps the bar. Cooldown
// prevents fighting with a legit restart/reload cycle.
static bool health_check_due(time_t now)
{
    return now - g_last_action > 20 && now - g_started_at > 30;
}

static void periodic_check(void)
{
    time_t now = time(NULL);
    if (!health_check_due(now))
        return;
    if (bar_responsive(4))
        return; // healthy
    long uptime = bar_uptime();
    if (uptime >= 0 && uptime < 20)
    {
        log_msg("periodic probe: bar restarted %lds ago, giving it time", uptime);
        return;
    }
    log_msg("periodic probe: bar unresponsive");
    sleep(4);
    if (bar_responsive(4))
        return; // hard-to-say blip, fine now
    g_last_action = now;
    kill_bar("sustained unresponsiveness (periodic)");
}

static void log_bar_version(void)
{
    char cmd[1200];
    snprintf(cmd, sizeof(cmd), "%s --version 2>/dev/null", g_bar_bin);
    FILE *p = popen(cmd, "r");
    if (!p)
        return;
    char buf[128] = "";
    if (fgets(buf, sizeof(buf), p))
    {
        char *nl = strchr(buf, '\n');
        if (nl)
            *nl = '\0';
        log_msg("bar version: %s", buf);
    }
    pclose(p);
}

int main(void)
{
    // Detach: a bar reload tears down the lua/process group this was spawned
    // from; fork+setsid gives the watchdog its own session.
    pid_t pid = fork();
    if (pid > 0)
        _exit(0);
    setsid();

    resolve_bar_bin();
    system("/bin/mkdir -p \"$HOME/.local/state/sketchybar\" 2>/dev/null");
    // One serial queue for the wake path and the periodic path: they must never
    // probe, kill and reload the bar at the same time (that caused duplicate
    // kill/reload bursts after wake).
    g_queue = dispatch_queue_create("wake_watch", DISPATCH_QUEUE_SERIAL);
    g_started_at = time(NULL);

    log_msg("wake_watch started pid=%d", (int)getpid());
    log_msg("bar binary: %s", g_bar_bin);
    log_bar_version();

    @autoreleasepool
    {
        [[NSWorkspace sharedWorkspace].notificationCenter
            addObserverForName:NSWorkspaceDidWakeNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *_Nonnull note) {
                        dispatch_async(g_queue, ^{
                            recover_after_wake();
                        });
                    }];

        dispatch_source_t timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0, g_queue);
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