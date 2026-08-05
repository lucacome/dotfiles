#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

#define BAND_HEIGHT 360.0

int main(void)
{
    CGEventRef event = CGEventCreate(NULL);
    CGPoint cursor = CGEventGetLocation(event);
    CFRelease(event);

    // Find the display the cursor is on; the bar + popup occupy roughly the
    // top BAND_HEIGHT pixels of it. Anything below that band that belongs to
    // another application is "elsewhere".
    CGDisplayCount display_count = 0;
    CGDirectDisplayID displays[16];
    CGGetActiveDisplayList(16, displays, &display_count);

    double band_bottom = 0.0;
    int on_display = 0;
    for (CGDisplayCount i = 0; i < display_count; i++)
    {
        CGRect d = CGDisplayBounds(displays[i]);
        if (CGRectContainsPoint(d, cursor))
        {
            on_display = 1;
            band_bottom = d.origin.y + (d.size.height < BAND_HEIGHT ? d.size.height : BAND_HEIGHT);
            break;
        }
    }
    if (!on_display)
    {
        printf("0\n");
        return 0;
    }

    CFArrayRef window_list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly
                                                            | kCGWindowListExcludeDesktopElements,
                                                        kCGNullWindowID);
    if (!window_list)
    {
        printf("0\n");
        return 0;
    }

    int elsewhere = 0;
    long window_count = CFArrayGetCount(window_list);
    for (long i = 0; i < window_count; i++)
    {
        CFDictionaryRef dict = CFArrayGetValueAtIndex(window_list, i);
        if (!dict)
            continue;

        CFStringRef owner_ref = CFDictionaryGetValue(dict, kCGWindowOwnerName);
        CFNumberRef layer_ref = CFDictionaryGetValue(dict, kCGWindowLayer);
        CFDictionaryRef bounds_ref = CFDictionaryGetValue(dict, kCGWindowBounds);
        if (!owner_ref || !layer_ref || !bounds_ref)
            continue;

        char owner[256];
        if (!CFStringGetCString(owner_ref, owner, sizeof(owner), kCFStringEncodingUTF8))
            continue;
        if (strcmp(owner, "sketchybar") == 0)
            continue;

        long long layer = 0;
        CFNumberGetValue(layer_ref, kCFNumberLongLongType, &layer);
        if (layer != 0)
            continue;

        CGRect bounds = CGRectNull;
        if (!CGRectMakeWithDictionaryRepresentation(bounds_ref, &bounds))
            continue;
        if (bounds.size.width < 8 || bounds.size.height < 8)
            continue;

        if (!CGRectContainsPoint(bounds, cursor))
            continue;
        if (cursor.y <= band_bottom)
            continue;

        elsewhere = 1;
        break;
    }

    CFRelease(window_list);
    printf("%d\n", elsewhere);
    return 0;
}