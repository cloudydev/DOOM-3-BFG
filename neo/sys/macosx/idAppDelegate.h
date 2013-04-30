//
//  idAppDelegate.h
//  id Tech Mac OS X
//
//  Copyright (c) 2013 Jeremiah Sypult. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "idConsoleWindowController.h"

#define kLibraryApplicationSupportPath	("/Library/Application Support/Doom3BFG")
#define kInstallPathValidationFileName	("_common.resources")
#define kHomePath						(@"homePath")

@interface idAppDelegate : NSObject <NSApplicationDelegate,NSWindowDelegate>
{
	NSWindow *_window;
	NSTimer *_frameTimer;

	idConsoleWindowController *_consoleController;
}

@property (assign) IBOutlet NSWindow *window;
@property (assign) NSTimer *frameTimer;
@property (assign) idConsoleWindowController *consoleController;
@property (assign) NSString *homePath;

- (void)initConsoleController;
- (void)shutdownConsoleController;

- (void)runFrame;
- (void)runFrameTimer;
- (void)stopFrameTimer;

- (void)idTechMain:(BOOL)isDedicatedServer;

@end
