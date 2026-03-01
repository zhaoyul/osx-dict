/*
 * TextGrabber.h
 *
 * Pure-C interface for retrieving the word under the mouse cursor or the
 * currently selected text.  Two strategies are provided:
 *
 *  1. Accessibility API  – works well for native Cocoa apps.
 *  2. Clipboard fallback – simulates Cmd-C and reads NSPasteboard; works
 *     in virtually every app that supports copying.
 *
 * Callers must free() the returned string when done.
 */

#ifndef TEXT_GRABBER_H
#define TEXT_GRABBER_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Returns the selected text of the frontmost UI element, or the text value
 * of the element directly under the mouse, whichever is non-empty.
 * Uses the Accessibility API (requires the "Accessibility" permission).
 * Returns NULL on failure.  Caller must free().
 */
char *tg_word_at_mouse_ax(void);

/*
 * Returns the currently selected text by simulating Cmd-C and reading the
 * clipboard.  The original clipboard contents are restored afterwards.
 * Returns NULL if the clipboard is empty or unchanged.  Caller must free().
 */
char *tg_selected_text_clipboard(void);

/*
 * Convenience wrapper: tries AX first, falls back to clipboard.
 * Returns NULL if neither strategy yields text.  Caller must free().
 */
char *tg_grab_text(void);

#ifdef __cplusplus
}
#endif

#endif /* TEXT_GRABBER_H */
