#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <sys/select.h>
#include <sys/sysctl.h>

static char unit_str[3][6] = {
    {" Bps"},
    {"KBps"},
    {"MBps"},
};

enum unit
{
    UNIT_BPS,
    UNIT_KBPS,
    UNIT_MBPS
};
struct network
{
    uint32_t row;
    bool valid;
    char ifname[IFNAMSIZ];
    struct ifmibdata data;
    struct timeval tv_nm1, tv_n, tv_delta;

    int up;
    int down;
    enum unit up_unit, down_unit;
};

static inline bool ifdata(uint32_t net_row, struct ifmibdata *data)
{
    size_t size = sizeof(struct ifmibdata);
    int32_t data_option[] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, 0, IFDATA_GENERAL};
    data_option[4] = net_row;
    return sysctl(data_option, 6, data, &size, NULL, 0) == 0 && size == sizeof(struct ifmibdata);
}

static inline bool network_lookup(struct network *net)
{
    static int count_option[] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_SYSTEM, IFMIB_IFCOUNT};
    uint32_t interface_count = 0;
    size_t size = sizeof(uint32_t);
    if (sysctl(count_option, 5, &interface_count, &size, NULL, 0) != 0)
        return false;

    struct ifmibdata candidate;
    for (uint32_t i = 0; i < interface_count; i++)
    {
        if (!ifdata(i, &candidate))
            continue;
        if (strncmp(candidate.ifmd_name, net->ifname, IFNAMSIZ) == 0)
        {
            net->row = i;
            net->valid = true;
            net->data = candidate;
            return true;
        }
    }
    net->valid = false;
    return false;
}

static inline void network_init(struct network *net, char *ifname)
{
    memset(net, 0, sizeof(struct network));
    snprintf(net->ifname, sizeof(net->ifname), "%s", ifname);
    if (!network_lookup(net))
        fprintf(stderr, "network_load: interface %s not found\n", net->ifname);
}

static inline void set_rate(double bytes, int *value, enum unit *unit)
{
    double exponent = bytes > 0 ? log10(bytes) : 0;
    if (exponent < 3)
    {
        *unit = UNIT_BPS;
        *value = bytes;
    }
    else if (exponent < 6)
    {
        *unit = UNIT_KBPS;
        *value = bytes / 1000.0;
    }
    else
    {
        *unit = UNIT_MBPS;
        *value = bytes / 1000000.0;
    }
}

static inline void network_update(struct network *net)
{
    gettimeofday(&net->tv_n, NULL);
    timersub(&net->tv_n, &net->tv_nm1, &net->tv_delta);
    net->tv_nm1 = net->tv_n;

    if (!net->valid && !network_lookup(net))
        return;

    uint64_t ibytes_nm1 = net->data.ifmd_data.ifi_ibytes;
    uint64_t obytes_nm1 = net->data.ifmd_data.ifi_obytes;
    if (!ifdata(net->row, &net->data))
    {
        net->valid = false;
        return;
    }

    double time_scale = (net->tv_delta.tv_sec + 1e-6 * net->tv_delta.tv_usec);
    if (time_scale < 1e-6 || time_scale > 1e2)
        return;

    // Counters reset on reconnect; a decrease is not negative traffic.
    double delta_ibytes = net->data.ifmd_data.ifi_ibytes >= ibytes_nm1
                              ? (double)(net->data.ifmd_data.ifi_ibytes - ibytes_nm1) / time_scale
                              : 0;
    double delta_obytes = net->data.ifmd_data.ifi_obytes >= obytes_nm1
                              ? (double)(net->data.ifmd_data.ifi_obytes - obytes_nm1) / time_scale
                              : 0;

    set_rate(delta_ibytes, &net->down, &net->down_unit);
    set_rate(delta_obytes, &net->up, &net->up_unit);
}
