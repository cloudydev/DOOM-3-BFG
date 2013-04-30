/*
===========================================================================

Doom 3 BFG Edition GPL Source Code
Copyright (C) 1993-2012 id Software LLC, a ZeniMax Media company. 

This file is part of the Doom 3 BFG Edition GPL Source Code ("Doom 3 BFG Edition Source Code").  

Doom 3 BFG Edition Source Code is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Doom 3 BFG Edition Source Code is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Doom 3 BFG Edition Source Code.  If not, see <http://www.gnu.org/licenses/>.

In addition, the Doom 3 BFG Edition Source Code is also subject to certain additional terms. You should have received a copy of these additional terms immediately following the terms and conditions of the GNU General Public License which accompanied the Doom 3 BFG Edition Source Code.  If not, please request a copy in writing from id Software at the address below.

If you have questions concerning this license or the applicable additional terms, you may contact in writing id Software LLC, c/o ZeniMax Media Inc., Suite 120, Rockville, Maryland 20850 USA.

===========================================================================
*/

#import "macosx_local.h"

#import "idAppDelegate.h"

#import <IOKit/hidsystem/IOHIDShared.h>
#import <sys/types.h>
#import <sys/time.h>
#import <unistd.h>

//==============================================================================

idCVar	in_mouse( "in_mouse", "1", CVAR_SYSTEM | CVAR_BOOL, "enable mouse input" );
idCVar	in_joystick( "in_joystick", "0", CVAR_SYSTEM | CVAR_BOOL, "enable joystick input" );

bool	in_discard = false; // jeremiah sypult

static bool inputActive;

static NSDate *distantPast;
static NSDate *distantFuture;

static idCVar in_showevents( "in_showEvents", "0", CVAR_SYSTEM | CVAR_INTEGER, "show input events" );
static idCVar in_disableOSMouseScaling( "in_disableOSMouseScaling", "0", CVAR_SYSTEM | CVAR_BOOL, "disable OS acceleration" );

static void Sys_StartMouseInput();
static void Sys_StopMouseInput();

static double originalScaling = 0.0;

static unsigned int currentModifierFlags;

static io_object_t IN_MacOSXIOHIDOpen()
{
	kern_return_t			kernResult = KERN_SUCCESS;
    mach_port_t				masterPort = 0;
    CFMutableDictionaryRef	matching = NULL;
	io_iterator_t			existing = 0;
    io_object_t				service = 0;
	io_object_t				connect = 0;

	if ( ( kernResult = IOMasterPort( MACH_PORT_NULL, &masterPort ) ) != KERN_SUCCESS ) {
		common->Printf( "IOHID failed on IOMasterPort.\n" );
	}

	if ( ( matching = IOServiceMatching( "IOHIDSystem" ) ) == NULL ) {
		common->Printf( "IOHID failed on IOServiceMatching.\n" );
	}

	if ( ( kernResult = IOServiceGetMatchingServices( masterPort, matching, &existing ) ) != KERN_SUCCESS ) {
		common->Printf( "IOHID failed on IOServiceGetMatchingServices.\n" );
	}

	// TODO: handle multiple services in while loop?
	if ( ( service = IOIteratorNext( existing ) ) ) {
		if ( ( kernResult = IOServiceOpen( service, mach_task_self(), kIOHIDParamConnectType, &connect ) ) != KERN_SUCCESS ) {
			common->Printf( "IOHID failed on IOServiceOpen.\n" );
		}
	}

	return connect;
}

static void IN_MacOSXIOHIDClose(io_connect_t connect)
{
	kern_return_t			kernResult = KERN_SUCCESS;

	if ( connect ) {
		if ( ( kernResult = IOServiceClose( connect ) ) != KERN_SUCCESS ) {
			common->Printf( "IOHID failed on IOServiceClose.\n" );
		}
	}
}

static double IN_MacOSXIOHIDGetMouseAcceleration()
{
	double					mouseAcceleration = 0.0;
	kern_return_t			kernResult = KERN_SUCCESS;
	io_object_t				connect = 0;

	connect = IN_MacOSXIOHIDOpen();

	if ( ( kernResult = IOHIDGetMouseAcceleration( connect, &mouseAcceleration ) ) != KERN_SUCCESS ) {
		common->Printf( "IOHID failed on IOHIDGetMouseAcceleration.\n" );
	}

	IN_MacOSXIOHIDClose( connect );

	return mouseAcceleration;
}

static bool IN_MacOSXIOHIDSetMouseAcceleration(double mouseAcceleration)
{
	bool					result = true;
	kern_return_t			kernResult = KERN_SUCCESS;
	io_object_t				connect = 0;

	connect = IN_MacOSXIOHIDOpen();

	if ((kernResult = IOHIDSetMouseAcceleration(connect, mouseAcceleration)) != KERN_SUCCESS) {
		common->Printf( "IOHID failed on IOHIDSetMouseAcceleration.\n" );
		result = false;
	}

	IN_MacOSXIOHIDClose( connect );

	return result;
}

static bool IN_MacOSXCursorLock(void)
{
	bool result = true;
    CGEventErr err;

    if ( ( err = CGAssociateMouseAndMouseCursorPosition(false)) != CGEventNoErr ) {
		result = false;
        common->Printf( "IN_MacOSXCursorLock() CGAssociateMouseAndMouseCursorPosition returned %d\n", err );
    }

	return result;
}

static bool IN_MacOSXCursorUnlock(void)
{
	bool result = true;
    CGEventErr err;

    if ((err = CGAssociateMouseAndMouseCursorPosition(true)) != CGEventNoErr) {
		result = false;
        common->Printf( "IN_MacOSXCursorLock() CGAssociateMouseAndMouseCursorPosition returned %d\n", err );
    }

	return result;
}

static bool IN_MacOSXCursorPosition(CGPoint point)
{
	bool result = true;
    CGEventErr err;

	if ( ( err = CGWarpMouseCursorPosition( point ) ) != CGEventNoErr ) {
		result = false;
        common->Printf( "IN_MacOSXSetCursorPos() CGWarpMouseCursorPosition returned %d\n", err );
    }

	// discard the next delta frame to avoid drastic cursor jumps
	in_discard = true;

	return result;
}

static void IN_MacOSXCenterCursor(void)
{
    NSScreen *screen = osx.window ? osx.window.screen : [NSScreen mainScreen];
    NSRect screenRect = screen.frame;
	CGPoint center;

    // It appears we need to flip the coordinate system here.  This means we need
    // to know the size of the screen.
	if ( osx.window ) {
		NSRect windowRect = osx.window.frame;
		NSRect contentRect = [osx.window.contentView frame];

		windowRect.origin.y = screenRect.size.height - (windowRect.origin.y + windowRect.size.height);

		CGRect rect = CGRectMake(windowRect.origin.x,
								 windowRect.origin.y,
								 contentRect.size.width,
								 windowRect.size.height + (windowRect.size.height - contentRect.size.height));

		center.x = rect.origin.x + rect.size.width / 2.0;
		center.y = rect.origin.y + rect.size.height / 2.0;
	} else {
		center.x = screenRect.size.width / 2.0;
		center.y = screenRect.size.height / 2.0;
	}

	IN_MacOSXCursorPosition( center );
}

static void IN_MacOSXCursorHide( void )
{
	const bool isCursorVisible = CGCursorIsVisible();

	if ( isCursorVisible ) {
		CGDisplayHideCursor( kCGDirectMainDisplay );
	}
}

static void IN_MacOSXCursorShow( void )
{
	const bool isCursorVisible = CGCursorIsVisible();

	if ( !isCursorVisible ) {
		CGDisplayShowCursor( kCGDirectMainDisplay );
	}
}

static void IN_MacOSXMouse( int *mx, int *my )
{
#if 1
	CGGetLastMouseDelta(mx, my);
#else
	CGPoint delta = CGPointMake(0,0);
	NSEvent *event;

	while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask
                                       untilDate:distantPast
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES])) {
		delta = CGPointMake( event.deltaX, event.deltaY );
	}

	*mx = (int)delta.x;
	*my = (int)delta.y;
#endif
}

//==============================================================================

/*
============================================================

  MOUSE CONTROL

============================================================
*/

/*
===========
IN_ActivateMouse

Called when the window gains focus or changes in some way
===========
*/
void IN_ActivateMouse( void ) 
{
	if ( !in_mouse.GetBool() || osx.mouseGrabbed ) {
		return;
	}

	osx.mouseGrabbed = true;

	IN_MacOSXCursorHide();

	Sys_StartMouseInput();
}

/*
===========
IN_DeactivateMouse

Called when the window loses focus
===========
*/
void IN_DeactivateMouse( void ) {
	if ( !osx.mouseGrabbed ) {
		return;
	}

	Sys_StopMouseInput();

	IN_MacOSXCursorShow();

	osx.mouseGrabbed = false;
}

/*
===========
IN_StartupMouse
===========
*/
void IN_StartupMouse( void )
{
	if ( in_mouse.GetBool() == 0 ) {
		common->Printf( "Mouse control not active.\n" );
		return;
	}

	Sys_StartMouseInput();
}

/*
===========
IN_MouseMove
===========
*/
void IN_MouseMove ( void ) {
	int		mx = 0, my = 0;

	//IN_MacOSXMouse( &mx, &my );
	
	if ( !mx && !my ) {
		return;
	}
	
	Sys_QueEvent( SE_MOUSE, mx, my, 0, NULL, 0 );
}

/*
=========================================================================

=========================================================================
*/

/*
===========
IN_Startup
===========
*/
void IN_Startup( void ) {
	common->Printf( "\n------- Input Initialization -------\n" );
	Sys_InitInput();
	IN_StartupMouse();
	common->Printf( "------------------------------------\n" );

	in_mouse.ClearModified();
	in_joystick.ClearModified();
}

/*
===========
IN_Shutdown
===========
*/
void IN_Shutdown( void ) {
	IN_DeactivateMouse();
    Sys_ShutdownInput();
}

/*
===========
IN_Init
===========
*/
void IN_Init( void ) {
	IN_Startup();
}

/*
===========
IN_Activate

Called when the main window gains or loses focus.
The window may have been destroyed and recreated
between a deactivate and an activate.
===========
*/
void IN_Activate (bool active) {
	osx.activeApp = active;

	if ( osx.activeApp ) {
//		Key_ClearStates();	// FIXME!!!
		Sys_GrabMouseCursor( true );

		if ( common->IsInitialized() && osx.mouseGrabbed ) {
			IN_MacOSXCursorHide();
		}
	} else {
		//Sys_GrabMouseCursor( false );
	}
}

/*
==================
IN_Frame

Called every frame, even if not generating commands
==================
*/
void IN_Frame (void) {
	bool shouldGrab = true;

	if ( Sys_IsDedicatedServer() ) {
		return;
	}

	if ( !in_mouse.GetBool() ) {
		shouldGrab = false;
	}

	// if fullscreen, we always want the mouse
	if ( !osx.cdsFullscreen ) {
		if ( osx.mouseReleased ) {
			shouldGrab = false;
		}
		if ( osx.movingWindow ) {
			shouldGrab = false;
		}
		if ( !osx.activeApp ) {
			shouldGrab = false;
		}
	}

	if ( shouldGrab != osx.mouseGrabbed ) {
		if ( osx.mouseGrabbed ) {
			IN_DeactivateMouse();
		} else {
			IN_ActivateMouse();
		}
	}
}

void Sys_GrabMouseCursor( bool grabIt )
{
	osx.mouseReleased = !grabIt;
	if ( !grabIt ) {
		// release it right now
		IN_Frame();
	}
}


//==============================================================================

void Sys_InitInput(void)
{
    // no input with dedicated servers
    if ( Sys_IsDedicatedServer() ) {
            return;
    }

    if ( !distantPast ) {
        distantPast = [[NSDate distantPast] retain];
	}

	if ( !distantFuture ) {
		distantFuture = [[NSDate distantFuture] retain];
	}

    // For hide support.  If we don't do this, then the command key will get stuck on when we hide (since we won't get the flags changed event when it goes up).
    currentModifierFlags = 0;

	// don't grab the mouse on initialization
	Sys_GrabMouseCursor( false );

    inputActive = true;
}

void Sys_ShutdownInput(void)
{
    // no input with dedicated servers
    if ( !Sys_IsDedicatedServer() ) {
            return;
    }

    common->Printf( "------- Input Shutdown -------\n" );
    if ( !inputActive ) {
        return;
    }

    if ( osx.mouseGrabbed )
        Sys_StopMouseInput();

	IN_DeactivateMouse();

	if ( distantPast ) {
        [distantPast release];
		distantPast = nil;
	}

	if ( distantFuture ) {
		[distantFuture release];
		distantFuture = nil;
	}

	inputActive = false;

    common->Printf( "------------------------------\n" );
}

static void Sys_StartMouseInput()
{
    int32_t dx, dy;

	if ( !osx.activeApp && !osx.mouseGrabbed )
		return;

	if ( in_showevents.GetBool() )
		common->Printf( "Starting mouse input\n" );

	// force the mouse to the center, so there's room to move
	// TODO: jeremiah sypult - verify this works as expected
	IN_MacOSXCursorLock();
	IN_MacOSXCenterCursor();

    // Grab any mouse delta information to reset the last delta buffer
    CGGetLastMouseDelta( &dx, &dy );
    
    // Turn off mouse scaling
	if ( in_disableOSMouseScaling.GetBool() ) {
		originalScaling = IN_MacOSXIOHIDGetMouseAcceleration();
		if ( !originalScaling ) {
			common->Printf( "Failed to get mouse acceleration.\n" );
		}

		if ( !IN_MacOSXIOHIDSetMouseAcceleration( 0.0 ) ) {
			common->Printf( "Failed to set mouse acceleration.\n" );
		}
	}

// IN_MacOSXCursorHide();
}

static void Sys_StopMouseInput()
{
    if ( in_showevents.GetBool() )
		common->Printf( "Stopping mouse input\n" );

	// Restore mouse scaling
	if ( in_disableOSMouseScaling.GetBool() ) {
		if ( !IN_MacOSXIOHIDSetMouseAcceleration( originalScaling ) ) {
			common->Printf( "Failed to set mouse acceleration.\n" );
		}
	}

	IN_MacOSXCenterCursor();
	IN_MacOSXCursorUnlock();
//	IN_MacOSXCursorShow();
}

//===========================================================================

char *Sys_ConsoleInput(void)
{
	idAppDelegate *delegate = (idAppDelegate*)[NSApp delegate];
	NSWindow *console = delegate.consoleController.window;
    extern bool stdin_active;
    static char text[256];
    int     len;
    fd_set	fdset;
    struct timeval timeout;

    if ( !Sys_IsDedicatedServer() )
        return NULL;

	if ( delegate && console && console.isVisible ) {
		extern char consoleText[1024];
		extern char returnedText[1024];

		if ( consoleText[0] != 0 ) {
			strcpy( returnedText, consoleText );
			memset( consoleText, 0, strlen( consoleText ) );
			return returnedText;
		}
	}

    if ( stdin_active ) {
		FD_ZERO( &fdset );
		FD_SET( fileno(stdin), &fdset ) ;
		timeout.tv_sec = 0;
		timeout.tv_usec = 0;
		if ( select( 1, &fdset, NULL, NULL, &timeout ) == -1 || !FD_ISSET( fileno(stdin), &fdset ) )
			return NULL;

		len = read( fileno(stdin), text, sizeof(text) );
		if (len == 0) { // eof!
			stdin_active = false;
			return NULL;
		}

		if (len < 1)
			return NULL;

		text[len] = 0;    // rip off the /n and terminate

		return text;
	}

	return NULL;
}

//===========================================================================
// Mouse input
//===========================================================================

static bool processMouseButtonEvent(NSEvent *mouseEvent, int currentTime)
{
	bool isDown = false;
	int temp = 0;

	if ( !osx.mouseGrabbed )
        return false;

	switch ( mouseEvent.type ) {
		case NSLeftMouseDown:
		case NSRightMouseDown:
		case NSOtherMouseDown:
			isDown = true;
			break;

		case NSLeftMouseUp:
		case NSRightMouseUp:
		case NSOtherMouseUp:
			isDown = false;
			break;

		default:
			break;
	}

	// perform button actions
#if 0
	Sys_QueEvent( SE_KEY, K_MOUSE1 + mouseEvent.buttonNumber, isDown, 0, NULL, 0 );
#else
	temp = (1 << mouseEvent.buttonNumber);
#endif

	if ( in_showevents.GetBool() ) {
		common->Printf( "MOUSE%i: %s\n", mouseEvent.buttonNumber + 1, isDown ? "down" : "up" );
	}

	return true;
}

static bool processMouseMovedEvent(NSEvent *mouseMovedEvent, int currentTime)
{
	const bool isShellActive = ( game && ( game->Shell_IsActive() || game->IsPDAOpen() ) );
	const bool isConsoleActive = console->Active();
	CGPoint delta = CGPointMake(0,0);

	if ( !common->IsInitialized() || !osx.mouseGrabbed ) {
		return false;
	}

	if ( osx.activeApp ) {
		if ( isShellActive ) {
			// If the shell is active, it will display its own cursor.
			IN_MacOSXCursorHide();
		} else if ( isConsoleActive ) {
			// The console is active but the shell is not.
			// Show the Windows cursor.
			IN_MacOSXCursorShow();
		} else {
			// The shell not active and neither is the console.
			// This is normal gameplay, hide the cursor.
			IN_MacOSXCursorHide();
		}
	} else {
		if ( !isShellActive ) {
			// Always show the cursor when the window is in the background
			IN_MacOSXCursorShow();
		} else {
			IN_MacOSXCursorHide();
		}
	}

	// find mouse movement
    delta.x = mouseMovedEvent.deltaX;
    delta.y = mouseMovedEvent.deltaY;

    if ( in_showevents.GetBool() )
        common->Printf( "MOUSE MOVED: %.1f, %.1f\n", delta.x, delta.y );

	// jeremiah sypult: discard the first frame of input after we reactivate.
	// this ensures that there are no sudden jumps from the mouse delta
	if ( in_discard ) {
		if ( in_showevents.GetBool() )
			common->Printf("**** DISCARDED ****\n");

		in_discard = false;
		return false; // TODO: true?
	}

    Sys_QueEvent( SE_MOUSE, (int)delta.x, (int)delta.y, 0, NULL, 0 );

	return true;
}

// If we are 'paused' (i.e., in any state that our normal key bindings aren't in effect), then interpret cmd-h and cmd-tab as hiding the application.
static bool maybeHide()
{
    if ( ( currentModifierFlags & NSCommandKeyMask) == 0 )
        return false;

    return false; // TODO: jeremiah sypult was Sys_Hide();
}

static ID_FORCE_INLINE void sendEventForCharacter(NSEvent *event, unichar character, bool keyDownFlag, int currentTime)
{
    if ( in_showevents.GetBool() ) {
        common->Printf("CHARACTER: 0x%02x down=%d\n", character, keyDownFlag);
	}

    switch ( character ) {
        case 0x03:
            Sys_QueEvent( SE_KEY, K_KP_ENTER, keyDownFlag, 0, NULL, 0 );
            break;
        case '\b':
        case '\177':
            Sys_QueEvent( SE_KEY, K_BACKSPACE, keyDownFlag, 0, NULL, 0 );
            if ( keyDownFlag ) {
               Sys_QueEvent( SE_CHAR, '\b', 0, 0, NULL, 0 );
            }
            break;
        case '\t':
            if ( maybeHide() )
                return;
            Sys_QueEvent( SE_KEY, K_TAB, keyDownFlag, 0, NULL, 0 );
            if (keyDownFlag) {
                Sys_QueEvent( SE_CHAR, '\t', 0, 0, NULL, 0 );
            }
            break;
        case '\r':
        case '\n':
            Sys_QueEvent( SE_KEY, K_ENTER, keyDownFlag, 0, NULL, 0 );
            if ( keyDownFlag ) {
                Sys_QueEvent( SE_CHAR, '\r', 0, 0, NULL, 0 );
            }
            break;
        case '\033':
            Sys_QueEvent( SE_KEY, K_ESCAPE, keyDownFlag, 0, NULL, 0 );
            break;
        case ' ':
            Sys_QueEvent( SE_KEY, K_SPACE, keyDownFlag, 0, NULL, 0 );
            if ( keyDownFlag ) {
                Sys_QueEvent( SE_CHAR, ' ', 0, 0, NULL, 0 );
            }
            break;
        case NSUpArrowFunctionKey:
            Sys_QueEvent( SE_KEY, K_UPARROW, keyDownFlag, 0, NULL, 0 );
            break;
        case NSDownArrowFunctionKey:
            Sys_QueEvent( SE_KEY, K_DOWNARROW, keyDownFlag, 0, NULL, 0 );
            break;
        case NSLeftArrowFunctionKey:
            Sys_QueEvent( SE_KEY, K_LEFTARROW, keyDownFlag, 0, NULL, 0 );
            break;
        case NSRightArrowFunctionKey:
            Sys_QueEvent( SE_KEY, K_RIGHTARROW, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF1FunctionKey:
            Sys_QueEvent( SE_KEY, K_F1, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF2FunctionKey:
            Sys_QueEvent( SE_KEY, K_F2, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF3FunctionKey:
            Sys_QueEvent( SE_KEY, K_F3, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF4FunctionKey:
            Sys_QueEvent( SE_KEY, K_F4, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF5FunctionKey:
            Sys_QueEvent( SE_KEY, K_F5, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF6FunctionKey:
            Sys_QueEvent( SE_KEY, K_F6, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF7FunctionKey:
            Sys_QueEvent( SE_KEY, K_F7, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF8FunctionKey:
            Sys_QueEvent( SE_KEY, K_F8, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF9FunctionKey:
            Sys_QueEvent( SE_KEY, K_F9, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF10FunctionKey:
            Sys_QueEvent( SE_KEY, K_F10, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF11FunctionKey:
            Sys_QueEvent( SE_KEY, K_F11, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF12FunctionKey:
            Sys_QueEvent( SE_KEY, K_F12, keyDownFlag, 0, NULL, 0 );
            break;
        case NSF13FunctionKey:
            Sys_QueEvent( SE_KEY, '`', keyDownFlag, 0, NULL, 0 );
            if ( keyDownFlag ) {
                Sys_QueEvent( SE_CHAR, '`', 0, 0, NULL, 0 );
            }
            break;
        case NSInsertFunctionKey:
            Sys_QueEvent( SE_KEY, K_INS, keyDownFlag, 0, NULL, 0 );
            break;
        case NSDeleteFunctionKey:
            Sys_QueEvent( SE_KEY, K_DEL, keyDownFlag, 0, NULL, 0 );
            break;
        case NSPageDownFunctionKey:
            Sys_QueEvent( SE_KEY, K_PGDN, keyDownFlag, 0, NULL, 0 );
            break;
        case NSPageUpFunctionKey:
            Sys_QueEvent( SE_KEY, K_PGUP, keyDownFlag, 0, NULL, 0 );
            break;
        case NSHomeFunctionKey:
            Sys_QueEvent( SE_KEY, K_HOME, keyDownFlag, 0, NULL, 0 );
            break;
        case NSEndFunctionKey:
            Sys_QueEvent( SE_KEY, K_END, keyDownFlag, 0, NULL, 0 );
            break;
        case NSPauseFunctionKey:
            Sys_QueEvent( SE_KEY, K_PAUSE, keyDownFlag, 0, NULL, 0 );
            break;
        default:
            if ( event.modifierFlags & NSNumericPadKeyMask ) {
#if 0
#warning implement Keypad input
                switch ( character ) {
						
                    case '0':
                        Sys_QueEvent( SE_KEY, K_KP_INS, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '1':
                        Sys_QueEvent( SE_KEY, K_KP_END, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '2':
                        Sys_QueEvent( SE_KEY, K_KP_DOWNARROW, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '3':
                        Sys_QueEvent( SE_KEY, K_KP_PGDN, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '4':
                        Sys_QueEvent( SE_KEY, K_KP_LEFTARROW, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '5':
                        Sys_QueEvent( SE_KEY, K_KP_5, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '6':
                        Sys_QueEvent( SE_KEY, K_KP_RIGHTARROW, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '7':
                        Sys_QueEvent( SE_KEY, K_KP_HOME, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '8':
                        Sys_QueEvent( SE_KEY, K_KP_UPARROW, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '9':
                        Sys_QueEvent( SE_KEY, K_KP_PGUP, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '.':
                    case ',':
                        Sys_QueEvent( SE_KEY, K_KP_DEL, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '+':
                        Sys_QueEvent( SE_KEY, K_KP_PLUS, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '-':
                        Sys_QueEvent( SE_KEY, K_KP_MINUS, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '*':
                        Sys_QueEvent( SE_KEY, K_KP_STAR, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '/':
                        Sys_QueEvent( SE_KEY, K_KP_SLASH, keyDownFlag, 0, NULL, 0 );
                        break;
                    case '=':
                        Sys_QueEvent( SE_KEY, K_KP_EQUALS, keyDownFlag, 0, NULL, 0 );
                        break;
                    default:
                        //NSLog(@"TODO: Implement character %d", (int)character);
                        break;
                 }
#endif
            } else if ( character >= 'a' && character <= 'z' ) {
                if ( character == 'h' ) {
                    if ( maybeHide() )
                        return;
                }
                Sys_QueEvent( SE_KEY, character, keyDownFlag, 0, NULL, 0 );
                if ( keyDownFlag ) {
                    Sys_QueEvent( SE_CHAR, (char)character, 0, 0, NULL, 0 );
                }
            } else if ( character >= 'A' && character <= 'Z' ) {
                Sys_QueEvent( SE_KEY, 'a' + (character - 'A'), keyDownFlag, 0, NULL, 0 );
                if ( keyDownFlag ) {
                    Sys_QueEvent( SE_CHAR, character, 0, 0, NULL, 0 );
                }
            } else if ( character >= 32 && character < 127 ) {
                Sys_QueEvent( SE_KEY, character, keyDownFlag, 0, NULL, 0 );
                if ( keyDownFlag ) {
                    Sys_QueEvent( SE_CHAR, (char)character, 0, 0, NULL, 0 );
                }
            } else {
                //NSLog(@"TODO: Implement character %d", (int)character);
            }
            break;
    }
}

static ID_FORCE_INLINE void processKeyEvent(NSEvent *keyEvent, int currentTime)
{
    NSEventType eventType = keyEvent.type;
    NSString *characters = keyEvent.charactersIgnoringModifiers;
    NSUInteger characterIndex = 0;
	NSUInteger characterCount = characters.length;
	bool keyDownFlag = (eventType == NSKeyDown);

    for ( characterIndex = 0; characterIndex < characterCount; characterIndex++ ) {
        sendEventForCharacter(keyEvent, [characters characterAtIndex:characterIndex], keyDownFlag, currentTime);
    }
}

static ID_FORCE_INLINE void sendEventForMaskChangeInFlags(int keyNum, unsigned int modifierMask, unsigned int newModifierFlags, int currentTime)
{
    BOOL oldHadModifier, newHasModifier;

    oldHadModifier = (currentModifierFlags & modifierMask) != 0;
    newHasModifier = (newModifierFlags & modifierMask) != 0;
    if ( oldHadModifier != newHasModifier ) {
        // NSLog(@"Key %d posted for modifier mask modifierMask", keyNum);
        Sys_QueEvent( SE_KEY, keyNum, newHasModifier, 0, NULL, 0 );
    }
}

static ID_FORCE_INLINE void processFlagsChangedEvent(NSEvent *flagsChangedEvent, int currentTime)
{
    int newModifierFlags;

    newModifierFlags = [flagsChangedEvent modifierFlags];
    sendEventForMaskChangeInFlags(K_LWIN, NSCommandKeyMask, newModifierFlags, currentTime);
    sendEventForMaskChangeInFlags(K_CAPSLOCK, NSAlphaShiftKeyMask, newModifierFlags, currentTime);
    sendEventForMaskChangeInFlags(K_LALT, NSAlternateKeyMask, newModifierFlags, currentTime);
    sendEventForMaskChangeInFlags(K_LCTRL, NSControlKeyMask, newModifierFlags, currentTime);
    sendEventForMaskChangeInFlags(K_LSHIFT, NSShiftKeyMask, newModifierFlags, currentTime);
    currentModifierFlags = newModifierFlags;
}

static ID_FORCE_INLINE void processSystemDefinedEvent(NSEvent *systemDefinedEvent, int currentTime)
{
	static int oldButtons = 0;
    int buttonsDelta;
    int buttons;
    int isDown;

    if ( systemDefinedEvent.subtype == 7 ) {

        if ( !osx.mouseGrabbed )
            return;

		buttons = systemDefinedEvent.data2;
        buttonsDelta = oldButtons ^ buttons;

        //common->Printf("uberbuttons: %08lx %08lx\n",buttonsDelta,buttons);

		if (buttonsDelta & 1) {
            isDown = buttons & 1;
            Sys_QueEvent( SE_KEY, K_MOUSE1, isDown, 0, NULL, 0 );
            if (in_showevents.GetBool()) {
                common->Printf("MOUSE2: %s\n", isDown ? "down" : "up");
            }
		}

		if (buttonsDelta & 2) {
            isDown = buttons & 2;
            Sys_QueEvent( SE_KEY, K_MOUSE2, isDown, 0, NULL, 0 );
            if (in_showevents.GetBool()) {
                common->Printf("MOUSE3: %s\n", isDown ? "down" : "up");
            }
		}

		if (buttonsDelta & 4) {
            isDown = buttons & 4;
            Sys_QueEvent( SE_KEY, K_MOUSE3, isDown, 0, NULL, 0 );
            if (in_showevents.GetBool()) {
                common->Printf("MOUSE1: %s\n", isDown ? "down" : "up");
            }
		}

		if (buttonsDelta & 8) {
            isDown = buttons & 8;
            Sys_QueEvent( SE_KEY, K_MOUSE4, isDown, 0, NULL, 0 );
            if (in_showevents.GetBool()) {
                common->Printf("MOUSE4: %s\n", isDown ? "down" : "up");
            }
        }

		if (buttonsDelta & 16) {
            isDown = buttons & 16;
            Sys_QueEvent( SE_KEY, K_MOUSE5, isDown, 0, NULL, 0 );
            if (in_showevents.GetBool()) {
                common->Printf("MOUSE5: %s\n", isDown ? "down" : "up");
            }
		}

        oldButtons = buttons;
    }
}

static ID_FORCE_INLINE void processEvent(NSEvent *event, int currentTime)
{
    NSEventType eventType;

    if (!inputActive)
        return;

    eventType = event.type;

    if (in_showevents.GetBool() > 1)
        NSLog(@"event = %@", event);
    
    switch (eventType) {
		// These six event types are ignored since we do all of our mouse down/up process via the uber-mouse system defined event.  We have to accept these events however since they get enqueued and the queue will fill up if we don't.
        case NSLeftMouseDown:
            //Sys_QueEvent( SE_KEY, K_MOUSE1, true, 0, NULL, 0 );
            return;
        case NSLeftMouseUp:
            //Sys_QueEvent( SE_KEY, K_MOUSE1, false, 0, NULL, 0 );
            return;
        case NSRightMouseDown:
            //Sys_QueEvent( SE_KEY, K_MOUSE2, true, 0, NULL, 0 );
            return;
        case NSRightMouseUp:
            //Sys_QueEvent( SE_KEY, K_MOUSE2, false, 0, NULL, 0 );
            return;
        case NSOtherMouseDown:
            return;
        case NSOtherMouseUp:
            return;

        case NSMouseMoved:
        case NSLeftMouseDragged:
        case NSRightMouseDragged:
        case NSOtherMouseDragged:
            processMouseMovedEvent(event, currentTime);
            return;
        case NSKeyDown:
        case NSKeyUp:
            processKeyEvent(event, currentTime);
            return;
        case NSFlagsChanged:
            processFlagsChangedEvent(event, currentTime);
            return;
		case NSSystemDefined:
			processSystemDefinedEvent(event, currentTime);
			return;
        case NSScrollWheel:
            if ([event deltaY] < 0.0) {
                Sys_QueEvent( SE_KEY, K_MWHEELDOWN, true, 0, NULL, 0 );
                Sys_QueEvent( SE_KEY, K_MWHEELDOWN, false, 0, NULL, 0 );
            } else {
                Sys_QueEvent( SE_KEY, K_MWHEELUP, true, 0, NULL, 0 );
                Sys_QueEvent( SE_KEY, K_MWHEELUP, false, 0, NULL, 0 );
            }
            return;
        default:
            break;
    }
    //[NSApp sendEvent:event];
}

bool Sys_MouseInContentView(NSEvent *event)
{
	NSView *contentView = (NSView*)event.window.contentView;
	NSPoint point = [contentView convertPoint:event.locationInWindow fromView:nil];

	if (point.x >= 0 &&
		point.x <= contentView.frame.size.width &&
		point.y >= 0 &&
		point.y <= contentView.frame.size.height) {
		return true;
	}

	return false;
}

bool Sys_WindowEvent(NSEvent *event)
{
	int currentTime = osx.sysMsgTime;//event.timestamp * 1000.0;//Sys_Milliseconds();

	if ( in_showevents.GetInteger() > 1 ) {
        NSLog(@"event = %@", event);
	}

	switch ( event.type ) {
		case NSLeftMouseDown:
        case NSRightMouseDown:
        case NSOtherMouseDown:
        case NSLeftMouseUp:
        case NSRightMouseUp:
        case NSOtherMouseUp:
			if ( osx.mouseGrabbed && Sys_MouseInContentView(event) ) {
				return processMouseButtonEvent(event, currentTime);
			}
			break;
		case NSMouseMoved:
		case NSLeftMouseDragged:
		case NSRightMouseDragged:
		case NSOtherMouseDragged:
			if ( osx.mouseGrabbed ) {
				return processMouseMovedEvent(event, currentTime);
			}
			break;
		case NSKeyDown:
        case NSKeyUp:
            processKeyEvent(event, currentTime);
			return true;
            break;
        case NSFlagsChanged:
            processFlagsChangedEvent(event, currentTime);
            break;
		case NSSystemDefined:
			processSystemDefinedEvent(event, currentTime);
			return true;
			break;
        case NSScrollWheel:
		case NSEventTypeBeginGesture:
		case NSEventTypeEndGesture:
            if (event.deltaY < 0.0) {
                Sys_QueEvent( SE_KEY, K_MWHEELDOWN, true, 0, NULL, 0 );
                Sys_QueEvent( SE_KEY, K_MWHEELDOWN, false, 0, NULL, 0 );
            } else if (event.deltaY > 0.0) {
                Sys_QueEvent( SE_KEY, K_MWHEELUP, true, 0, NULL, 0 );
                Sys_QueEvent( SE_KEY, K_MWHEELUP, false, 0, NULL, 0 );
            }
			return true;
            break;

		default:
			return false;
			break;
	}

	return false;
}

//===========================================================================
//
//===========================================================================

/*
================
Sys_PollMouseInputEvents
================
*/
struct mouse_poll_t
{
	int action;
	int value;
	
	mouse_poll_t()
	{
	}
	
	mouse_poll_t( int a, int v )
	{
		action = a;
		value = v;
	}
};
static idList<mouse_poll_t> mouse_polls;

/*
================
Sys_PollKeyboardInputEvents
================
*/
int Sys_PollKeyboardInputEvents()
{
	return 0;//kbd_polls.Num();

}
/*
================
Sys_ReturnKeyboardInputEvent
================
*/
int Sys_ReturnKeyboardInputEvent( const int n, int& key, bool& state )
{
//	if( n >= kbd_polls.Num() )
//		return 0;
//		
//	key = kbd_polls[n].key;
//	state = kbd_polls[n].state;
//	return 1;
	return 0;
}

/*
================
Sys_EndKeyboardInputEvents
================
*/
void Sys_EndKeyboardInputEvents()
{
	//kbd_polls.SetNum( 0 );
}

int Sys_PollMouseInputEvents( int mouseEvents[MAX_MOUSE_EVENTS][2] )
{
	int numEvents = mouse_polls.Num();
	
	if( numEvents > MAX_MOUSE_EVENTS )
	{
		numEvents = MAX_MOUSE_EVENTS;
	}
	
	for( int i = 0; i < numEvents; i++ )
	{
		const mouse_poll_t& mp = mouse_polls[i];
		
		mouseEvents[i][0] = mp.action;
		mouseEvents[i][1] = mp.value;
	}
	
	mouse_polls.SetNum( 0 );
	
	return numEvents;
}


//=====================================================================================
//	Joystick Input Handling
//=====================================================================================

void Sys_SetRumble( int device, int low, int hi ) {
//	return win32.g_Joystick.SetRumble( device, low, hi );
}

int Sys_PollJoystickInputEvents( int deviceNum ) {
//	return win32.g_Joystick.PollInputEvents( deviceNum );
	return 0;
}


int Sys_ReturnJoystickInputEvent( const int n, int &action, int &value ) {
//	return win32.g_Joystick.ReturnInputEvent( n, action, value );
	return 0;
}


void Sys_EndJoystickInputEvents() {
}

//================================================================
