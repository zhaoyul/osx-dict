/*
 * AppDelegate.h
 *
 * Application delegate that wires together all components:
 *  – Installs a status-bar icon (menu-bar agent; no Dock icon)
 *  – Registers a global hotkey (⌥D) to trigger a lookup
 *  – Checks Accessibility permission on launch
 */

#ifndef APP_DELEGATE_H
#define APP_DELEGATE_H

#import <Cocoa/Cocoa.h>
#import "PopupWindow.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) PopupWindow    *popupWindow;
@property (nonatomic, strong) NSStatusItem   *statusItem;

/* Trigger a lookup at the current mouse position */
- (void)performLookup;

@end

NS_ASSUME_NONNULL_END

#endif /* APP_DELEGATE_H */
