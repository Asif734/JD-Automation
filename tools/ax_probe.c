#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>

static void dump(AXUIElementRef element, int depth) {
  if (depth > 4) return;
  CFTypeRef role = NULL, title = NULL, children = NULL;
  AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role);
  AXUIElementCopyAttributeValue(element, kAXTitleAttribute, &title);
  for (int i = 0; i < depth; i++) fputs("  ", stdout);
  if (role) CFShow(role); else puts("AXUnknown");
  if (title) { for (int i = 0; i <= depth; i++) fputs("  ", stdout); CFShow(title); }
  if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &children) == kAXErrorSuccess &&
      children && CFGetTypeID(children) == CFArrayGetTypeID()) {
    CFArrayRef array = (CFArrayRef)children;
    CFIndex count = CFArrayGetCount(array);
    for (CFIndex i = 0; i < count; i++) dump((AXUIElementRef)CFArrayGetValueAtIndex(array, i), depth + 1);
  }
  if (role) CFRelease(role);
  if (title) CFRelease(title);
  if (children) CFRelease(children);
}

int main(int argc, char **argv) {
  printf("AX trusted: %s\n", AXIsProcessTrusted() ? "true" : "false");
  if (argc != 2) return 0;
  AXUIElementRef app = AXUIElementCreateApplication((pid_t)atoi(argv[1]));
  dump(app, 0);
  CFRelease(app);
  return 0;
}
