/*
 * PopupWindow.m
 *
 * Non-activating floating panel (NSPanel) implementation.
 *
 * Key design choices:
 *  – styleMask includes NSWindowStyleMaskNonactivatingPanel so the panel
 *    never takes keyboard focus away from the frontmost application.
 *  – windowLevel is set to NSFloatingWindowLevel so it floats above normal
 *    windows.
 *  – The panel auto-closes when the user clicks elsewhere (via a global
 *    event monitor) or after a configurable timeout.
 */

#import "PopupWindow.h"

/* How long (seconds) the panel stays visible before auto-dismissing. */
static const NSTimeInterval kAutoDismissDelay = 8.0;

/* Padding around text content inside the panel. */
static const CGFloat kPadding       = 12.0;
static const CGFloat kMaxPanelWidth = 420.0;
static const CGFloat kMinPanelWidth = 200.0;
static const CGFloat kMaxDefinitionViewportHeight = 180.0;

@interface PopupWindow ()
@property (nonatomic, strong) NSTextView   *wordLabel;
@property (nonatomic, strong) NSTextView   *definitionView;
@property (nonatomic, strong) NSScrollView *definitionScrollView;
@property (nonatomic, strong) NSTimer      *dismissTimer;
@property (nonatomic, strong) id            clickMonitor; /* global event monitor */
@property (nonatomic, strong) id            keyMonitor;   /* global key monitor */
@end

@implementation PopupWindow

- (instancetype)init {
    /* Create a borderless, non-activating panel */
    self = [super initWithContentRect:NSMakeRect(0, 0, kMinPanelWidth, 60)
                            styleMask:(NSWindowStyleMaskNonactivatingPanel |
                                       NSWindowStyleMaskTitled            |
                                       NSWindowStyleMaskClosable          |
                                       NSWindowStyleMaskFullSizeContentView)
                              backing:NSBackingStoreBuffered
                                defer:YES];
    if (!self) return nil;

    /* Panel behaviour */
    self.level              = NSFloatingWindowLevel;
    self.hidesOnDeactivate  = NO;
    self.releasedWhenClosed = NO;
    self.movableByWindowBackground = YES;

    /* Visual effect (translucent background like a HUD) */
    NSVisualEffectView *blur = [[NSVisualEffectView alloc] init];
    blur.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    blur.material     = NSVisualEffectMaterialPopover;
    blur.state        = NSVisualEffectStateActive;
    blur.wantsLayer   = YES;
    blur.layer.cornerRadius = 10.0;
    blur.layer.masksToBounds = YES;

    self.contentView = blur;

    /* Word / title label */
    _wordLabel = [self makeTextViewBold:YES fontSize:15.0];
    [blur addSubview:_wordLabel];

    /* Separator */
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    [blur addSubview:separator];

    /* Definition body */
    _definitionView = [self makeTextViewBold:NO fontSize:13.0];
    _definitionView.verticallyResizable = YES;
    _definitionView.horizontallyResizable = NO;

    _definitionScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _definitionScrollView.hasVerticalScroller = YES;
    _definitionScrollView.hasHorizontalScroller = NO;
    _definitionScrollView.borderType = NSNoBorder;
    _definitionScrollView.drawsBackground = NO;
    _definitionScrollView.documentView = _definitionView;
    [blur addSubview:_definitionScrollView];

    return self;
}

/* --------------------------------------------------------------------- */

- (NSTextView *)makeTextViewBold:(BOOL)bold fontSize:(CGFloat)size {
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSZeroRect];
    tv.editable             = NO;
    tv.selectable           = YES;
    tv.drawsBackground      = NO;
    tv.textContainerInset   = NSMakeSize(0, 0);
    tv.textContainer.widthTracksTextView = YES;
    tv.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    tv.font = bold ? [NSFont boldSystemFontOfSize:size]
                   : [NSFont systemFontOfSize:size];
    tv.textColor = [NSColor labelColor];
    return tv;
}

/* --------------------------------------------------------------------- */

- (void)showWord:(NSString *)word
      definition:(nullable NSString *)definition
         atPoint:(NSPoint)screenPoint {

    /* Update text */
    _wordLabel.string     = word ?: @"";
    _definitionView.string = definition ?: @"(No definition found)";

    /* Layout: fixed width, compute required height */
    CGFloat contentWidth = kMaxPanelWidth - 2 * kPadding;
    [self layoutWithContentWidth:contentWidth];

    /* Position the panel near the mouse, keeping it on screen */
    NSPoint origin = NSMakePoint(screenPoint.x + 16, screenPoint.y - self.frame.size.height - 8);
    NSScreen *screen = [NSScreen mainScreen];
    if (screen) {
        NSRect visible = screen.visibleFrame;
        if (origin.x + self.frame.size.width > NSMaxX(visible))
            origin.x = NSMaxX(visible) - self.frame.size.width - 4;
        if (origin.x < NSMinX(visible))
            origin.x = NSMinX(visible) + 4;
        if (origin.y < NSMinY(visible))
            origin.y = screenPoint.y + 20;
        if (origin.y + self.frame.size.height > NSMaxY(visible))
            origin.y = NSMaxY(visible) - self.frame.size.height - 4;
    }
    [self setFrameOrigin:origin];

    /* Show */
    [self orderFrontRegardless];

    /* Auto-dismiss timer */
    [_dismissTimer invalidate];
    _dismissTimer = [NSTimer scheduledTimerWithTimeInterval:kAutoDismissDelay
                                                     target:self
                                                   selector:@selector(hidePanel)
                                                   userInfo:nil
                                                    repeats:NO];

    /* Dismiss on click outside */
    if (!_clickMonitor) {
        __weak PopupWindow *weakSelf = self;
        _clickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
                             (NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown)
                                                                handler:^(NSEvent *event) {
            (void)event;
            [weakSelf hidePanel];
        }];
    }
    if (!_keyMonitor) {
        __weak PopupWindow *weakSelf = self;
        _keyMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                              handler:^(NSEvent *event) {
            if (event.keyCode == 53) { /* Escape */
                [weakSelf hidePanel];
            }
        }];
    }
}

- (void)hidePanel {
    [_dismissTimer invalidate];
    _dismissTimer = nil;

    if (_clickMonitor) {
        [NSEvent removeMonitor:_clickMonitor];
        _clickMonitor = nil;
    }
    if (_keyMonitor) {
        [NSEvent removeMonitor:_keyMonitor];
        _keyMonitor = nil;
    }

    [self orderOut:nil];
}

/* --------------------------------------------------------------------- */

- (void)layoutWithContentWidth:(CGFloat)width {
    /* Measure word label height */
    [_wordLabel setFrameSize:NSMakeSize(width, 1)];
    [_wordLabel.layoutManager
        glyphRangeForTextContainer:_wordLabel.textContainer];
    CGFloat wordH = [_wordLabel.layoutManager
                        usedRectForTextContainer:_wordLabel.textContainer].size.height;
    wordH = MAX(wordH, 20);

    /* Measure definition full content height */
    [_definitionView setFrameSize:NSMakeSize(width, 1)];
    [_definitionView.layoutManager
        glyphRangeForTextContainer:_definitionView.textContainer];
    CGFloat defContentH = [_definitionView.layoutManager
                       usedRectForTextContainer:_definitionView.textContainer].size.height;
    defContentH = MAX(defContentH, 20);
    CGFloat defViewportH = MIN(defContentH, kMaxDefinitionViewportHeight);

    CGFloat sepH    = 1.0;
    CGFloat totalH  = kPadding + wordH + kPadding/2 + sepH + kPadding/2 + defViewportH + kPadding;
    CGFloat panelW  = MAX(kMinPanelWidth, MIN(kMaxPanelWidth, width + 2 * kPadding));

    [self setContentSize:NSMakeSize(panelW, totalH)];

    /* Place subviews */
    CGFloat y = totalH - kPadding - wordH;
    _wordLabel.frame  = NSMakeRect(kPadding, y, width, wordH);

    y -= kPadding / 2 + sepH;
    /* find the separator (NSBox) and position it */
    for (NSView *v in self.contentView.subviews) {
        if ([v isKindOfClass:[NSBox class]]) {
            v.frame = NSMakeRect(kPadding, y, width, sepH);
            break;
        }
    }

    y -= kPadding / 2 + defViewportH;
    _definitionScrollView.frame = NSMakeRect(kPadding, y, width, defViewportH);
    _definitionView.frame = NSMakeRect(0, 0, width, defContentH);
}

/* Keep the panel from becoming key even if the user clicks on it */
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }

@end
