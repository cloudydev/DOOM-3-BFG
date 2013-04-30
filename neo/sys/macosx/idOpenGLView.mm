//
//  idOpenGLView.m
//  id Tech Mac OS X
//
//  Copyright (c) 2013 Jeremiah Sypult. All rights reserved.
//

#import "idOpenGLView.h"
#import "idWindow.h"
#include "macosx_local.h"

@implementation idOpenGLView

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent { return YES; }
//- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
//- (BOOL)mouseDownCanMoveWindow { return YES; }

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];

    if (self) {
    }
    
    return self;
}

- (void)update
{
	idWindow *window = (idWindow*)self.window;
	NSRect backingRect = [self convertRectToBacking:self.bounds];
	[self.openGLContext makeCurrentContext];
	[self.openGLContext update];
	GLimp_UpdateGLConfig( backingRect.size.width, backingRect.size.height, window.isFullScreen );
	[super update];
}

- (void)drawRect:(NSRect)dirtyRect
{
	if ( osx.glContext != NULL && common->IsInitialized() && !common->IsShuttingDown() ) {
		common->Frame();
	}
}

@end
