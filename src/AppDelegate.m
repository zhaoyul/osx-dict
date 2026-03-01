/*
 * AppDelegate.m
 *
 * Wires the application together:
 *  1. Creates a status-bar (menu-bar) icon with a small menu.
 *  2. Registers a global hotkey – Option-D (⌥D) – using CGEventTap so that
 *     the shortcut fires regardless of which app is in front.
 *  3. On hotkey, calls the C-level tg_grab_text() to obtain the word, then
 *     ds_lookup() to get its definition, then shows the PopupWindow.
 *  4. Prompts the user to grant Accessibility permission if not yet granted.
 */

#import "AppDelegate.h"
#import "TextGrabber.h"
#import "DictService.h"

#include <Carbon/Carbon.h>

/* ---------------------------------------------------------------------- */
/* CGEventTap callback (global hotkey)                                      */
/* ---------------------------------------------------------------------- */

static CGEventRef eventTapCallback(CGEventTapProxy proxy,
                                   CGEventType     type,
                                   CGEventRef      event,
                                   void           *refcon) {
    (void)proxy;
    if (type == kCGEventKeyDown) {
        CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(
                                event, kCGKeyboardEventKeycode);
        CGEventFlags flags = CGEventGetFlags(event);

        /* ⌥D  →  Option + D key (kVK_ANSI_D = 0x02) */
        BOOL isOptionD = (keyCode == kVK_ANSI_D) &&
                         ((flags & kCGEventFlagMaskAlternate) != 0) &&
                         ((flags & kCGEventFlagMaskCommand)   == 0) &&
                         ((flags & kCGEventFlagMaskControl)   == 0);
        if (isOptionD) {
            AppDelegate *delegate = (__bridge AppDelegate *)refcon;
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate performLookup];
            });
            /* Consume the event so it doesn't reach the frontmost app */
            return NULL;
        }
    }
    /* Pass through all other events */
    return event;
}

/* ---------------------------------------------------------------------- */
/* AppDelegate                                                              */
/* ---------------------------------------------------------------------- */

@interface AppDelegate ()
@property (nonatomic) CFMachPortRef  eventTap;
@property (nonatomic) CFRunLoopSourceRef runLoopSource;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    /* Create the popup panel once */
    self.popupWindow = [[PopupWindow alloc] init];

    /* Status bar icon */
    [self setupStatusBar];

    /* Check / request Accessibility permission */
    [self checkAccessibilityPermission];

    /* Install the global event tap for the hotkey */
    [self installEventTap];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    if (_eventTap) {
        CGEventTapEnable(_eventTap, false);
    }
    if (_runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSource,
                              kCFRunLoopCommonModes);
        CFRelease(_runLoopSource);
        _runLoopSource = NULL;
    }
    if (_eventTap) {
        CFRelease(_eventTap);
        _eventTap = NULL;
    }
}

/* ---------------------------------------------------------------------- */

- (void)setupStatusBar {
    self.statusItem = [[NSStatusBar systemStatusBar]
                           statusItemWithLength:NSVariableStatusItemLength];
    NSButton *button = self.statusItem.button;
    button.title = @"📖";
    button.toolTip = @"osx-dict  (⌥D to look up)";

    /* Build the menu */
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *lookupItem = [[NSMenuItem alloc]
        initWithTitle:@"Look Up (⌥D)"
               action:@selector(menuLookup:)
        keyEquivalent:@""];
    lookupItem.target = self;
    [menu addItem:lookupItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc]
        initWithTitle:@"Quit osx-dict"
               action:@selector(terminate:)
        keyEquivalent:@"q"];
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (void)menuLookup:(id)sender {
    (void)sender;
    [self performLookup];
}

/* ---------------------------------------------------------------------- */

- (void)checkAccessibilityPermission {
    NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
    if (!trusted) {
        NSLog(@"osx-dict: Accessibility permission not granted. "
              @"Please allow access in System Settings → Privacy → Accessibility.");
    }
}

/* ---------------------------------------------------------------------- */

- (void)installEventTap {
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown);
    _eventTap = CGEventTapCreate(kCGSessionEventTap,
                                 kCGHeadInsertEventTap,
                                 kCGEventTapOptionDefault,
                                 mask,
                                 eventTapCallback,
                                 (__bridge void *)self);
    if (!_eventTap) {
        NSLog(@"osx-dict: Failed to create event tap. "
              @"Make sure Accessibility permission is granted.");
        return;
    }

    _runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,
                                                   _eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(_eventTap, true);
}

/* ---------------------------------------------------------------------- */

- (void)performLookup {
    /* Capture mouse position before going to a background thread */
    NSPoint mouse = [NSEvent mouseLocation];

    /* Offload the blocking work (AX API + clipboard wait + DCS lookup)
     * to a background queue so the main thread (and UI) stays responsive. */
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        /* Grab text: Accessibility API → clipboard fallback */
        char *raw = tg_grab_text();
        if (!raw || *raw == '\0') {
            free(raw);
            NSLog(@"osx-dict: no text found at cursor");
            return;
        }

        /* Take only the first word for dictionary lookup */
        char *word = ds_first_words(raw, 1);
        free(raw);
        if (!word || *word == '\0') {
            free(word);
            return;
        }

        /* Look up definition (DCS loads a local database – fast) */
        char *definition = ds_lookup(word);

        NSString *nsWord = [NSString stringWithUTF8String:word];
        NSString *nsDef  = definition
                           ? [NSString stringWithUTF8String:definition]
                           : nil;
        free(word);
        free(definition);

        /* Update UI on the main thread */
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.popupWindow showWord:nsWord
                            definition:nsDef
                               atPoint:mouse];
        });
    });
}

@end
