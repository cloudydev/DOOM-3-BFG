//
//  idWindow.m
//  id Tech Mac OS X
//
//  Copyright (c) 2013 Jeremiah Sypult. All rights reserved.
//

#import "idWindow.h"
#import "macosx_local.h"

@implementation idWindow

@dynamic isFullScreen;
@synthesize cachedTitle = _cachedTitle;
@synthesize cachedStyleMask = _cachedStyleMask;
@synthesize cachedFrame = _cachedFrame;

- (void)update
{
	[super update];

	if ( !self.isFullScreen ) {
//		Cvar_SetValue( "vid_xpos", self.frame.origin.x );
//		Cvar_SetValue( "vid_ypos", self.frame.origin.y );
	}
}

- (void)becomeKeyWindow
{
	[super becomeKeyWindow];
	IN_Activate(self.isKeyWindow);
}
- (void)resignKeyWindow
{
	[super resignKeyWindow];
	IN_Activate(self.isKeyWindow);
}

- (void)sendEvent:(NSEvent *)theEvent
{
	if (![NSApp isHidden] &&
		common->IsInitialized() &&
		Sys_WindowEvent(theEvent)) {
		return;
	}

	[super sendEvent:theEvent];
}

- (void)performClose:(id)sender
{
	[NSApp terminate:nil];
}

- (BOOL)isFullScreen
{
	BOOL isFullScreen = NO;

	if ([super respondsToSelector:@selector(toggleFullScreen:)]) {
		isFullScreen = ((self.styleMask & NSFullScreenWindowMask) == NSFullScreenWindowMask);
	} else {
		// TODO: full screen pre-10.7
	}

	return isFullScreen;
}

- (void)toggleFullScreen:(id)sender
{
	if ([super respondsToSelector:@selector(toggleFullScreen:)]) {
		[super toggleFullScreen:sender];
	} else {
		// TODO: full screen pre-10.7
		//window.level = NSMainMenuWindowLevel + 1;
		//window.hidesOnDeactivate = YES;
	}
}

- (void)center
{
	NSScreen *screen = self.screen;
	NSView *contentView = (NSView*)self.contentView;
	NSRect screenRect = screen.frame;
	NSRect contentRect = contentView.frame;
	NSRect windowRect = self.frame;
	CGFloat windowBarHeight = windowRect.size.height - contentRect.size.height;
	NSPoint centeredOrigin = NSMakePoint((screenRect.size.width - windowRect.size.width) / 2.0,
										 ((screenRect.size.height - windowRect.size.height) / 2.0) + (windowBarHeight / 2.0));

	//[self setFrameOrigin:centeredOrigin];
	[self setFrame:NSMakeRect(centeredOrigin.x, centeredOrigin.y, windowRect.size.width, windowRect.size.height)
		   display:YES
		   animate:YES];
}

- (void)updateFullScreen:(BOOL)isFullScreen
{
//	Cvar_Set( "r_fullscreen", isFullScreen ? "1" : "0" );

	if (isFullScreen) {
		NSArray *screens = [NSScreen screens];
		for (int i = 0; i < screens.count; i++) {
			if (self.screen == [screens objectAtIndex:i]) {
				osx.cdsFullscreen = i + 1;
			}
		}
	} else {
		osx.cdsFullscreen = 0;
	}
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
	BOOL isFullScreen = self.isFullScreen;
	[self updateFullScreen:isFullScreen];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
	BOOL isFullScreen = self.isFullScreen;
	[self updateFullScreen:isFullScreen];
}

- (void)windowDidFailToEnterFullScreen:(NSWindow *)window
{
	BOOL isFullScreen = self.isFullScreen;
	[self updateFullScreen:isFullScreen];
}

- (void)windowDidFailToExitFullScreen:(NSWindow *)window
{
	BOOL isFullScreen = self.isFullScreen;
	[self updateFullScreen:isFullScreen];
}

#pragma mark - Full Screen Custom Animation Support -
#if 1
#pragma mark Entering

- (NSSize)window:(NSWindow *)window willUseFullScreenContentSize:(NSSize)proposedSize
{
	return proposedSize;
}

- (NSArray *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
	_cachedTitle = self.title;
	_cachedStyleMask = self.styleMask;

	self.styleMask = NSFullScreenWindowMask;

	_cachedFrame = self.frame;

    [self invalidateRestorableState];

    NSRect screenFrame = self.screen.frame;
    NSRect proposedFrame = screenFrame;

    proposedFrame.origin.x += floor((NSWidth(screenFrame) - NSWidth(proposedFrame))/2);
    proposedFrame.origin.y += floor((NSHeight(screenFrame) - NSHeight(proposedFrame))/2);

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		context.duration = duration;
		[window.animator setFrame:proposedFrame display:YES];
	} completionHandler:^{
		self.styleMask = NSFullScreenWindowMask;
	}];
}

#pragma mark Exiting

- (NSArray *)customWindowsToExitFullScreenForWindow:(NSWindow *)window
{
    return [NSArray arrayWithObject:window];
}

- (void)window:(NSWindow *)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
	//self.styleMask = NSFullScreenWindowMask;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		context.duration = duration;
		[window.animator setFrame:_cachedFrame display:YES];
	} completionHandler:^{
		[(NSOpenGLView*)window.contentView update]; // TODO: why????
		self.styleMask = _cachedStyleMask;
		self.title = _cachedTitle;
	}];
}
#endif

@end
