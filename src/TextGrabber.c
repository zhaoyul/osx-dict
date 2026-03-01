/*
 * TextGrabber.c
 *
 * Implements two strategies for obtaining the word / text under the cursor:
 *
 *  Strategy A – Accessibility API (pure C via ApplicationServices)
 *  Strategy B – Clipboard  (Objective-C allowed because .m not required;
 *               we keep this file as .c and use CFPasteboard / CGEvent only)
 *
 * Both strategies are pure-C compatible (no ObjC runtime calls here).
 */

#include "TextGrabber.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>

/* Delay (microseconds) after simulating ⌘C before reading the clipboard.
 * 150 ms is empirically sufficient for most applications. */
#define CLIPBOARD_SYNC_DELAY_US 150000

/* -------------------------------------------------------------------------
 * Internal helpers
 * ---------------------------------------------------------------------- */

/* Convert a CFStringRef to a newly malloc'd C string (UTF-8).
 * Returns NULL on failure.  Caller must free(). */
static char *cf_string_to_cstr(CFStringRef str) {
    if (str == NULL) return NULL;
    CFIndex len  = CFStringGetLength(str);
    if (len == 0) return NULL;
    CFIndex size = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
    char   *buf  = malloc((size_t)size);
    if (!buf) return NULL;
    if (!CFStringGetCString(str, buf, size, kCFStringEncodingUTF8)) {
        free(buf);
        return NULL;
    }
    return buf;
}

/* Trim leading/trailing ASCII whitespace in-place.
 * Returns the (possibly advanced) pointer; the original allocation must
 * still be freed. */
static char *trim_whitespace(char *s) {
    if (!s) return NULL;
    /* leading */
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    if (*s == '\0') return s;
    /* trailing */
    char *end = s + strlen(s) - 1;
    while (end > s && (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r'))
        *end-- = '\0';
    return s;
}

/* -------------------------------------------------------------------------
 * Strategy A – Accessibility API
 * ---------------------------------------------------------------------- */

char *tg_word_at_mouse_ax(void) {
    /* Current mouse position in global screen coordinates */
    CGEventRef evt = CGEventCreate(NULL);
    if (!evt) return NULL;
    CGPoint mouse = CGEventGetLocation(evt);
    CFRelease(evt);

    /* System-wide accessibility element */
    AXUIElementRef system = AXUIElementCreateSystemWide();
    if (!system) return NULL;

    AXUIElementRef element = NULL;
    AXError err = AXUIElementCopyElementAtPosition(system, mouse.x, mouse.y, &element);
    CFRelease(system);

    if (err != kAXErrorSuccess || element == NULL) {
        if (element) CFRelease(element);
        return NULL;
    }

    /* 1. Prefer AXSelectedText (what the user has highlighted). */
    CFStringRef selectedText = NULL;
    AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute,
                                  (CFTypeRef *)&selectedText);

    char *result = NULL;

    if (selectedText) {
        result = cf_string_to_cstr(selectedText);
        CFRelease(selectedText);
    }

    /* 2. Fall back to AXValue (the full text content of the element). */
    if (!result || *trim_whitespace(result) == '\0') {
        free(result);
        result = NULL;

        CFStringRef value = NULL;
        AXUIElementCopyAttributeValue(element, kAXValueAttribute,
                                      (CFTypeRef *)&value);
        if (value) {
            result = cf_string_to_cstr(value);
            CFRelease(value);
        }
    }

    CFRelease(element);
    return result;
}

/* -------------------------------------------------------------------------
 * Strategy B – Clipboard  (simulate Cmd-C, read, then restore)
 * ---------------------------------------------------------------------- */

/*
 * We use Core Graphics CGEvent to post a synthetic Cmd-C.
 * Clipboard access uses Core Foundation's CFPasteboard equivalent, which
 * is bridged through the Pasteboard Manager (Carbon/HIToolbox).
 * To stay pure-C we read the pasteboard through CF APIs exposed by the
 * Pasteboard framework (available as part of ApplicationServices).
 */

char *tg_selected_text_clipboard(void) {
    /* Open the general pasteboard */
    PasteboardRef pb = NULL;
    if (PasteboardCreate(kPasteboardClipboard, &pb) != noErr || !pb)
        return NULL;

    PasteboardSynchronize(pb);

    /* Save current clipboard text so we can restore it */
    char *saved = NULL;
    ItemCount item_count = 0;
    PasteboardGetItemCount(pb, &item_count);
    if (item_count > 0) {
        PasteboardItemID itemID = 0;
        PasteboardGetItemIdentifier(pb, 1, &itemID);
        CFDataRef data = NULL;
        if (PasteboardCopyItemFlavorData(pb, itemID,
                                         CFSTR("public.utf8-plain-text"),
                                         &data) == noErr && data) {
            CFIndex sz = CFDataGetLength(data);
            saved = malloc((size_t)sz + 1);
            if (saved) {
                memcpy(saved, CFDataGetBytePtr(data), (size_t)sz);
                saved[sz] = '\0';
            }
            CFRelease(data);
        }
    }

    /* Clear the pasteboard so we can detect a new copy */
    PasteboardClear(pb);

    /* Simulate Cmd-C */
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

    CGEventRef keyDown = CGEventCreateKeyboardEvent(src, kVK_ANSI_C, true);
    CGEventRef keyUp   = CGEventCreateKeyboardEvent(src, kVK_ANSI_C, false);
    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    CGEventSetFlags(keyUp,   kCGEventFlagMaskCommand);

    CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
    CGEventPost(kCGAnnotatedSessionEventTap, keyUp);

    CFRelease(keyDown);
    CFRelease(keyUp);
    if (src) CFRelease(src);

    /* Wait for the app to process the keystroke and update the clipboard */
    usleep(CLIPBOARD_SYNC_DELAY_US);
    PasteboardSynchronize(pb);

    /* Read new clipboard content */
    char *result = NULL;
    item_count = 0;
    PasteboardGetItemCount(pb, &item_count);
    if (item_count > 0) {
        PasteboardItemID itemID = 0;
        PasteboardGetItemIdentifier(pb, 1, &itemID);
        CFDataRef data = NULL;
        if (PasteboardCopyItemFlavorData(pb, itemID,
                                         CFSTR("public.utf8-plain-text"),
                                         &data) == noErr && data) {
            CFIndex sz = CFDataGetLength(data);
            result = malloc((size_t)sz + 1);
            if (result) {
                memcpy(result, CFDataGetBytePtr(data), (size_t)sz);
                result[sz] = '\0';
            }
            CFRelease(data);
        }
    }

    /* Restore the original clipboard */
    PasteboardClear(pb);
    if (saved && *saved) {
        CFDataRef restoreData = CFDataCreate(NULL,
                                             (const UInt8 *)saved,
                                             (CFIndex)strlen(saved));
        if (restoreData) {
            PasteboardPutItemFlavor(pb, (PasteboardItemID)1,
                                    CFSTR("public.utf8-plain-text"),
                                    restoreData, 0);
            CFRelease(restoreData);
        }
    }
    free(saved);
    CFRelease(pb);

    /* Return NULL if nothing new was copied */
    if (!result || *result == '\0') {
        free(result);
        return NULL;
    }
    return result;
}

/* -------------------------------------------------------------------------
 * Convenience wrapper
 * ---------------------------------------------------------------------- */

char *tg_grab_text(void) {
    /* Try Accessibility API first (works without simulating keystrokes) */
    char *text = tg_word_at_mouse_ax();
    if (text && *trim_whitespace(text) != '\0')
        return text;
    free(text);

    /* Fall back to clipboard */
    return tg_selected_text_clipboard();
}
