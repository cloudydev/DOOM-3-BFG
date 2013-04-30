//
//  idAppDelegate.m
//  id Tech Mac OS X
//
//  Copyright (c) 2013 Jeremiah Sypult. All rights reserved.
//

#import "idAppDelegate.h"
#import "idWindow.h"
#import "macosx_local.h"

//==============================================================================

static bool pathExists( const char *path )
{
	FILE *f = NULL;

	if ( ( f = fopen( path, "r" ) ) != NULL ) {
		fclose( f );
		return true;
	}

	return false;
}

static bool gameExists( const char *installPath, const char *gameName )
{
	char gamePath[PATH_MAX] = {0};

	if ( installPath && installPath[0] && pathExists( installPath ) ) {
		idStr::snPrintf( gamePath, sizeof( gamePath ), "%s/%s", installPath, gameName );

		if ( gamePath[0] && pathExists( gamePath ) ) {
			return true;
		}
	}

	return false;
}

static bool installExists( const char *installPath )
{
	if ( installPath && installPath[0] && pathExists( installPath ) ) {
		if ( gameExists( installPath, BASE_GAMEDIR ) ) {
			return true;
		}
	}

	return false;
}

static bool installFileExists( const char *installPath, const char *filename )
{
	
	char gameFilePath[PATH_MAX] = {0};

	if ( installPath && installPath[0] && pathExists( installPath ) ) {
		int attempt = 0;

		for ( attempt = 0; attempt < 3; attempt++ ) {
			const char *gameName = NULL;
			switch ( attempt ) {
				default:
				case 0: gameName = BASE_GAMEDIR; break;
			}

			idStr::snPrintf( gameFilePath, sizeof( gameFilePath ), "%s/%s/%s", installPath, gameName, filename );
			if ( gameFilePath[0] && pathExists( gameFilePath ) ) {
				return true;
			}
		}
	}

	return false;
}

static const char *promptHomePath( void )
{
	static char homePath[PATH_MAX] = {0};
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	NSInteger result = NSFileHandlingPanelCancelButton;

	// TODO: be more descriptive about why the user is being presented with an open panel?
	// ...in case their attention isn't drawn to the title?

	memset( homePath, 0, sizeof(homePath) );

	openPanel.title = @"Select Installation Folder"; // not applicable to sheets attached to window
	openPanel.canChooseFiles = NO;
	openPanel.canChooseDirectories = YES;
	openPanel.allowsMultipleSelection = NO;
	openPanel.allowedFileTypes = nil;

	result = [openPanel runModal];

	switch ( result ) {
		default: break;
		case NSFileHandlingPanelCancelButton: [NSApp terminate:nil]; break;
		case NSFileHandlingPanelOKButton:
			strncpy( homePath, openPanel.URL.path.fileSystemRepresentation, sizeof(homePath) );
			return homePath;
			break;
	}

	return NULL;
}

static void _scanInstallationData( void )
{
	idAppDelegate	*delegate = (idAppDelegate*)[NSApp delegate];
	NSBundle		*mainBundle = [NSBundle mainBundle];
	NSURL			*installURL = nil;
	char			installPath[PATH_MAX] = {0};
	char			homePath[PATH_MAX] = {0};
	const char		*promptedPath = NULL;

	// scan installation data exists in this order
	// 1. within the app bundle? (various locations, explained below)
	// 2. default "install" path on the file system (kLibraryApplicationSupportPath)
	// 3. current working directory (Doom3BFG3.app, base, etc.)
	// 4. preferences (NSUserDefaults installPath)
	// 5. prompt user to choose (storing installPath in NSUserDefaults)
	// TODO: use security scoped bookmark?

	// first try locations within the application bundle
	// sharedSupportURL	${EXECUTABLE_NAME}.app/Contents/SharedSupport/<base>
	// resourceURL		${EXECUTABLE_NAME}.app/Contents/Resources/<base>
	// bundleURL		${EXECUTABLE_NAME}.app/<base>
	// executableURL	${EXECUTABLE_NAME}.app/Contents/MacOS/<base>

	for ( int i = 0; i < 4; i++ ) {
		switch ( i ) {
			default: installURL = nil; break;
			case 0: installURL = mainBundle.sharedSupportURL;	break;
			case 1: installURL = mainBundle.resourceURL;		break;
			case 2: installURL = mainBundle.bundleURL;			break;
			case 3: installURL = mainBundle.executableURL;		break;
		}

		if ( installURL && [installURL checkResourceIsReachableAndReturnError:NULL]) {
			strncpy( installPath, installURL.path.fileSystemRepresentation, sizeof(installPath) );

			if ( installExists( installPath ) ) {
				goto setInstallPath;
			}
		}
	}

	// then try default install path, which is the users Application Support
	if ( getenv( "HOME" ) ) {
		strncpy( installPath, getenv( "HOME" ), sizeof(installPath) );
		strncat( installPath, kLibraryApplicationSupportPath, sizeof(installPath) - strlen(installPath) - 1 );

		if ( installExists( installPath ) ) {
			goto setInstallPath;
		}
	}

	// next try current working directory
	// TODO: compare against kLibraryApplicationSupportPath attempt?
	if ( Sys_Cwd() ) {
		strncpy( installPath, Sys_Cwd(), sizeof(installPath) );

		if ( installExists( installPath ) ) {
			goto setInstallPath;
		}
	}

setInstallPath:
	Sys_SetDefaultInstallPath( installPath );

	// skip setting the home path if the data is located
	if ( installFileExists( installPath, kInstallPathValidationFileName ) ) {
		return;
	}

	// stored preferences in NSUserDefaults
	if ( delegate.homePath ) {
		strncpy( homePath, [delegate.homePath cStringUsingEncoding:NSUTF8StringEncoding], sizeof(homePath) );

		if ( installExists( homePath ) ) {
			goto setHomePath;
		}
	}

	// prompt user to select
	if ( ( promptedPath = promptHomePath() ) && installExists( promptedPath ) ) {
		// save in prefs
		delegate.homePath = [NSString stringWithCString:promptedPath encoding:NSUTF8StringEncoding];
		strncpy( homePath, promptedPath, sizeof(homePath) );
		goto setHomePath;
	}

setHomePath:
	Sys_SetDefaultHomePath( homePath );
}

static ID_FORCE_INLINE void GameFrame(void)
{
	static int totalMsec = 0, countMsec = 0;
	static int startTime = 0, endTime = 0;

	// if not running as a game client, sleep a bit
	if ( !osx.activeApp || Sys_IsDedicatedServer() ) {
		usleep( 5 );
	}

	startTime = Sys_Milliseconds();

	{
		// run the game
		common->Frame();
	}

	endTime = Sys_Milliseconds();
	totalMsec += endTime - startTime;
	countMsec++;
}

@implementation idAppDelegate

@synthesize window = _window;
@synthesize frameTimer = _frameTimer;
@synthesize consoleController = _consoleController;

@dynamic homePath;

- (void)dealloc
{
    [super dealloc];
}

- (NSString*)homePath
{
	NSString *homePath = NULL;
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	homePath = [defaults objectForKey:kHomePath];

	return homePath;
}

- (void)setHomePath:(NSString *)homePath
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:homePath forKey:kHomePath];
	[defaults synchronize];
}

- (void)initConsoleController
{
	if (!self.consoleController) {
		self.consoleController = [[idConsoleWindowController alloc] initWithWindowNibName:@"idConsoleWindowController"];

		if (!self.consoleController) {
			NSRunAlertPanel(@"DOOM ERROR",
							@"idAppDelegate could not initialize console window controller.",
							@"Quit", nil, nil);
			[NSApp terminate:nil];
		}

		// for hud panels
		//self.consoleController.window.hidesOnDeactivate = NO;
	}
}

- (void)shutdownConsoleController
{
	if (self.consoleController) {
		[self.consoleController.window close];
		[self.consoleController close];
		[self.consoleController release];
		self.consoleController = nil;
	}
}

- (void)runFrame
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	GameFrame();
	[pool release];
}

- (void)runFrameTimer
{
	static const NSTimeInterval frameTimeInterval = 1.0/600; // 600 Hz

	if ( Sys_IsDedicatedServer() ) {
		// allow a dedicated console to go full screen on Mac OS X >= 10.7
		if ([self.consoleController.window respondsToSelector:@selector(toggleFullScreen:)]) {
			self.consoleController.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
		}
	}

	self.frameTimer = [NSTimer timerWithTimeInterval:frameTimeInterval
											  target:self
											selector:@selector(runFrame)
											userInfo:nil
											 repeats:YES];

	[[NSRunLoop mainRunLoop] addTimer:self.frameTimer forMode:NSRunLoopCommonModes];
}

- (void)stopFrameTimer
{
	[self.frameTimer invalidate];
	self.frameTimer = nil;
}

- (void)idTechMain:(BOOL)isDedicatedServer
{
	NSArray		*args = [[NSProcessInfo processInfo] arguments];
	NSUInteger	argc = args.count;
	NSUInteger	argIndex = 0;
	NSString	*argString = nil;
	char		cmdline[MAX_STRING_CHARS] = {0};

	// argIndex = 1 to skip the invoking program name
    for ( argIndex = 1; argIndex < argc; argIndex++ ) {
        argString = [args objectAtIndex:argIndex];
		const char *arg = [[NSString stringWithFormat:@"%@ ", argString] cStringUsingEncoding:NSUTF8StringEncoding];

        // skip process serial number argument
        if ( [argString hasPrefix: @"-psn_"] ) {
            continue;
		} else if ( [argString hasPrefix: @"-NSDocumentRevisionsDebugMode"] ) {
			// skip the following argment because it is either 'YES' or 'NO'
			argIndex++;
			continue;
		}

		// strcat(cmdline, a);
		strncat( cmdline, arg, sizeof(cmdline) - strlen(cmdline) - 1 );
    }

	if ( isDedicatedServer ) {
		// TODO: check for pre-existing dedicated arg and overwrite the value
		// versus appending to the end?
		//strcat(cmdline, "+set dedicated 1");
		strncat( cmdline, "+set dedicated 1", sizeof(cmdline) - strlen(cmdline) - 1 );
	}

	Sys_SetCmdLine( cmdline );

	// done before Com/Sys_Init since we need this for error output
	Sys_CreateConsole();

	// get the initial time base
	Sys_Milliseconds();

	// scan for installation data
	_scanInstallationData();

	common->Init( 0, NULL, cmdline );

	common->Printf( "Working directory: %s\n", Sys_Cwd() );

	// hide the early console since we've reached the point where we
	// have a working graphics subsystems
	if ( !Sys_IsDedicatedServer() ) {
		// shut down & release the console controller when starting a client game
		[self shutdownConsoleController];
	}

	// hide or show the early console as necessary
//	if ( win32.win_viewlog.GetInteger() ) {
//		Sys_ShowConsole( 1, true );
//	} else {
//		Sys_ShowConsole( 0, false );
//	}

	[NSApp activateIgnoringOtherApps:YES];
	// TODO: center the mouse cursor?
	[osx.window makeKeyAndOrderFront:self];

	// main game loop
	[self runFrameTimer];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// start up the game normally
	[self idTechMain:NO];
}

- (void)applicationWillHide:(NSNotification *)notification
{
}

- (void)applicationDidUnhide:(NSNotification *)notification;
{
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	if ( common->IsInitialized() && !common->IsShuttingDown() ) {
		common->Shutdown();
		common->Quit();
		return NSTerminateCancel;
	} else {
		[self stopFrameTimer];
		return NSTerminateNow;
	}

	return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	// dealloc welcome window
	Sys_DestroyConsole();

	// save out the preferences
	[[NSUserDefaults standardUserDefaults] synchronize];
}

@end
