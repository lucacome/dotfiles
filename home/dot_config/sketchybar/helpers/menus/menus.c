#include <Carbon/Carbon.h>
#include <stdlib.h>

void ax_init()
{
    if (!AXIsProcessTrusted())
        exit(1);
}

void ax_perform_click(AXUIElementRef element)
{
    if (!element)
        return;
    AXUIElementPerformAction(element, kAXCancelAction);
    usleep(150000);
    AXUIElementPerformAction(element, kAXPressAction);
}

CFStringRef ax_get_title(AXUIElementRef element)
{
    CFTypeRef title = NULL;
    AXError error = AXUIElementCopyAttributeValue(element,
                                                  kAXTitleAttribute,
                                                  &title);

    if (error != kAXErrorSuccess)
        return NULL;
    return title;
}

void ax_select_menu_option(AXUIElementRef app, int id)
{
    AXUIElementRef menubars_ref = NULL;
    CFArrayRef children_ref = NULL;

    AXError error = AXUIElementCopyAttributeValue(app,
                                                  kAXMenuBarAttribute,
                                                  (CFTypeRef *)&menubars_ref);
    if (error == kAXErrorSuccess)
    {
        error = AXUIElementCopyAttributeValue(menubars_ref,
                                              kAXVisibleChildrenAttribute,
                                              (CFTypeRef *)&children_ref);

        if (error == kAXErrorSuccess)
        {
            uint32_t count = CFArrayGetCount(children_ref);
            if (id >= 0 && id < count)
            {
                AXUIElementRef item = CFArrayGetValueAtIndex(children_ref, id);
                ax_perform_click(item);
            }
            if (children_ref)
                CFRelease(children_ref);
        }
        if (menubars_ref)
            CFRelease(menubars_ref);
    }
}

void ax_print_menu_options(AXUIElementRef app)
{
    AXUIElementRef menubars_ref = NULL;
    CFTypeRef menubar = NULL;
    CFArrayRef children_ref = NULL;

    AXError error = AXUIElementCopyAttributeValue(app,
                                                  kAXMenuBarAttribute,
                                                  (CFTypeRef *)&menubars_ref);
    if (error == kAXErrorSuccess)
    {
        error = AXUIElementCopyAttributeValue(menubars_ref,
                                              kAXVisibleChildrenAttribute,
                                              (CFTypeRef *)&children_ref);

        if (error == kAXErrorSuccess)
        {
            uint32_t count = CFArrayGetCount(children_ref);

            for (int i = 1; i < count; i++)
            {
                AXUIElementRef item = CFArrayGetValueAtIndex(children_ref, i);
                CFTypeRef title = ax_get_title(item);

                if (title)
                {
                    CFIndex buffer_len = CFStringGetMaximumSizeForEncoding(
                        CFStringGetLength(title), kCFStringEncodingUTF8) + 1;
                    char *buffer = malloc(buffer_len);
                    if (buffer)
                    {
                        CFStringGetCString(title, buffer, buffer_len, kCFStringEncodingUTF8);
                        printf("%s\n", buffer);
                        free(buffer);
                    }
                    CFRelease(title);
                }
            }
        }
        if (menubars_ref)
            CFRelease(menubars_ref);
        if (children_ref)
            CFRelease(children_ref);
    }
}

extern int SLSMainConnectionID();
extern void _SLPSGetFrontProcess(ProcessSerialNumber *psn);
extern void SLSGetConnectionIDForPSN(int cid, ProcessSerialNumber *psn, int *cid_out);
extern void SLSConnectionGetPID(int cid, pid_t *pid_out);
AXUIElementRef ax_get_front_app()
{
    ProcessSerialNumber psn;
    _SLPSGetFrontProcess(&psn);
    int target_cid;
    SLSGetConnectionIDForPSN(SLSMainConnectionID(), &psn, &target_cid);

    pid_t pid;
    SLSConnectionGetPID(target_cid, &pid);
    return AXUIElementCreateApplication(pid);
}

int main(int argc, char **argv)
{
    if (argc == 1)
    {
        printf("Usage: %s [-l | -s <index>]\n", argv[0]);
        exit(0);
    }
    ax_init();
    if (strcmp(argv[1], "-l") == 0)
    {
        AXUIElementRef app = ax_get_front_app();
        if (!app)
            return 1;
        ax_print_menu_options(app);
        CFRelease(app);
    }
    else if (argc == 3 && strcmp(argv[1], "-s") == 0)
    {
        int id = 0;
        if (sscanf(argv[2], "%d", &id) != 1)
        {
            printf("Usage: %s [-l | -s <index>]\n", argv[0]);
            return 1;
        }
        AXUIElementRef app = ax_get_front_app();
        if (!app)
            return 1;
        ax_select_menu_option(app, id);
        CFRelease(app);
    }
    return 0;
}
