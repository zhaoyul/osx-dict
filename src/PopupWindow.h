/*
 * PopupWindow.h
 *
 * A non-activating floating NSPanel that displays a dictionary definition
 * near the current mouse position.  It does not steal keyboard focus from
 * the frontmost application.
 */

#ifndef POPUP_WINDOW_H
#define POPUP_WINDOW_H

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PopupWindow : NSPanel

/*
 * Show the panel with `word` as the title and `definition` as the body,
 * positioned near `screenPoint` (global screen coordinates).
 * Pass NULL/nil for definition to show a "not found" message.
 */
- (void)showWord:(NSString *)word
      definition:(nullable NSString *)definition
         atPoint:(NSPoint)screenPoint;

/*
 * Hide the panel.
 */
- (void)hidePanel;

@end

NS_ASSUME_NONNULL_END

#endif /* POPUP_WINDOW_H */
