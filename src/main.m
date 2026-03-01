/*
 * main.m
 *
 * Entry point for osx-dict, a lightweight macOS menu-bar application that
 * displays the definition of the word under your cursor or selected text.
 *
 * Press ⌥D (Option-D) anywhere to look up the current word.
 */

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];

        /* Run as a menu-bar-only agent (LSUIElement = YES in Info.plist
         * suppresses the Dock icon; this call is an extra safety net). */
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;

        [app run];
    }
    return 0;
}
