//
//  idWindow.h
//  id Tech Mac OS X
//
//  Copyright (c) 2013 Jeremiah Sypult. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface idWindow : NSWindow <NSWindowDelegate> // TODO: NSWindowDelegate?
{
	NSString *_cachedTitle;
	NSUInteger _cachedStyleMask;
	NSRect _cachedFrame;
}

@property (assign, getter=isFullScreen) BOOL isFullScreen;
@property (assign) NSString *cachedTitle;
@property (assign) NSUInteger cachedStyleMask;
@property (assign) NSRect cachedFrame;

- (BOOL)isFullScreen;
- (void)toggleFullScreen:(id)sender;

@end
