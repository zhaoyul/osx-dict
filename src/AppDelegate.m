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
@property (nonatomic, copy, nullable) NSString *selectedDictionaryName;
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

    NSMenuItem *dictRoot = [[NSMenuItem alloc] initWithTitle:@"Dictionary"
                                                      action:nil
                                               keyEquivalent:@""];
    NSMenu *dictMenu = [[NSMenu alloc] initWithTitle:@"Dictionary"];

    NSMenuItem *defaultDict = [[NSMenuItem alloc] initWithTitle:@"System Default"
                                                          action:@selector(menuSelectDictionary:)
                                                   keyEquivalent:@""];
    defaultDict.target = self;
    defaultDict.representedObject = [NSNull null];
    [dictMenu addItem:defaultDict];
    [dictMenu addItem:[NSMenuItem separatorItem]];

    int dictCount = 0;
    char **dictNames = ds_copy_dictionary_names(&dictCount);
    NSString *autoSelectEnglish = nil;
    for (int i = 0; i < dictCount; ++i) {
        NSString *title = [NSString stringWithUTF8String:dictNames[i]];
        if (!title.length) continue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(menuSelectDictionary:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = title;
        [dictMenu addItem:item];
        if (!autoSelectEnglish &&
            ([title localizedCaseInsensitiveContainsString:@"Oxford Dictionary of English"] ||
             [title rangeOfString:@"English"
                          options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location == 0)) {
            autoSelectEnglish = title;
        }
    }
    ds_free_dictionary_names(dictNames, dictCount);

    if (autoSelectEnglish.length > 0) {
        self.selectedDictionaryName = autoSelectEnglish;
        ds_set_dictionary_name([autoSelectEnglish UTF8String]);
    } else {
        self.selectedDictionaryName = nil;
        ds_set_dictionary_name(NULL);
    }

    dictRoot.submenu = dictMenu;
    [menu addItem:dictRoot];
    [self updateDictionaryMenuState:dictMenu];

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

- (void)menuSelectDictionary:(NSMenuItem *)sender {
    id value = sender.representedObject;
    if (!value || value == [NSNull null]) {
        self.selectedDictionaryName = nil;
        ds_set_dictionary_name(NULL);
    } else {
        self.selectedDictionaryName = (NSString *)value;
        ds_set_dictionary_name([self.selectedDictionaryName UTF8String]);
    }
    [self updateDictionaryMenuState:sender.menu];
}

- (void)updateDictionaryMenuState:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) continue;
        id value = item.representedObject;
        BOOL isDefault = (!value || value == [NSNull null]);
        BOOL selected = isDefault ? (self.selectedDictionaryName == nil)
                                  : [self.selectedDictionaryName isEqualToString:(NSString *)value];
        item.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
    }
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

        if (*raw == '\0') {
            free(raw);
            return;
        }

        /* Look up definition (DCS loads a local database – fast) */
        char *definition = ds_lookup(raw);

        NSString *nsWord = [NSString stringWithUTF8String:raw];
        NSString *nsDef  = definition
                           ? [NSString stringWithUTF8String:definition]
                           : nil;
        free(raw);
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
