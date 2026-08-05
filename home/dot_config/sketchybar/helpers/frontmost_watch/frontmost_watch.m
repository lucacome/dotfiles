#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

static void print_frontmost_window(void)
{
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!front)
    {
        printf("none\n");
        return;
    }

    pid_t pid = front.processIdentifier;
    CFArrayRef window_list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly
                                                                            | kCGWindowListExcludeDesktopElements,
                                                                        kCGNullWindowID);
    if (!window_list)
    {
        printf("none\n");
        return;
    }

    long count = CFArrayGetCount(window_list);
    for (long i = 0; i < count; i++)
    {
        CFDictionaryRef dict = CFArrayGetValueAtIndex(window_list, i);
        if (!dict)
            continue;

        CFNumberRef pid_ref = CFDictionaryGetValue(dict, kCGWindowOwnerPID);
        CFNumberRef layer_ref = CFDictionaryGetValue(dict, kCGWindowLayer);
        CFDictionaryRef bounds_ref = CFDictionaryGetValue(dict, kCGWindowBounds);
        CFNumberRef id_ref = CFDictionaryGetValue(dict, kCGWindowNumber);
        if (!pid_ref || !layer_ref || !bounds_ref || !id_ref)
            continue;

        long long layer = 0, owner_pid = 0, window_id = 0;
        CFNumberGetValue(layer_ref, kCFNumberLongLongType, &layer);
        CFNumberGetValue(pid_ref, kCFNumberLongLongType, &owner_pid);
        CFNumberGetValue(id_ref, kCFNumberLongLongType, &window_id);
        if (owner_pid != pid || layer != 0 || window_id == 0)
            continue;

        CGRect bounds = CGRectNull;
        if (!CGRectMakeWithDictionaryRepresentation(bounds_ref, &bounds))
            continue;
        if (bounds.size.width < 8 || bounds.size.height < 8)
            continue;

        printf("%d|%lld\n", pid, window_id);
        CFRelease(window_list);
        return;
    }

    CFRelease(window_list);
    printf("none\n");
}

int main(void)
{
    @autoreleasepool
    {
        print_frontmost_window();
    }
    return 0;
}