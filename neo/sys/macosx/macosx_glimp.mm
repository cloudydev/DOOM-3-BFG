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
/*
** macosx_glimp.mm
**
** This file contains ALL Mac OS X specific stuff having to do with the
** OpenGL refresh.  When a port is being made the following functions
** must be implemented by the port:
**
** GLimp_EndFrame
** GLimp_Init
** GLimp_LogComment
** GLimp_Shutdown
**
** Note that the OSXGL_xxx functions are OS X specific GL-subsystem
** related functions that are relevant ONLY to macosx_glimp.mm
*/

#include "macosx_local.h"
#include "tr_local.h"

#import "idAppDelegate.h"
#import "idWindow.h"
#import "idOpenGLView.h"

#include <pthread.h>
#include <dlfcn.h> // dlsym
#include <mach-o/dyld.h> // NSSymbol

//
// function declaration
//
bool	QGL_Init( const char *dllname );
void	QGL_Shutdown( void );
void	GLimp_SwapBuffers ( void );
void	GLimp_SaveGamma();
void	GLimp_RestoreGamma();

//
// variable declarations
//
idCVar r_useOpenGL32( "r_useOpenGL32", "1", CVAR_INTEGER, "0 = OpenGL 2.0, 1 = OpenGL 3.2 compatibility profile, 2 = OpenGL 3.2 core profile", 0, 2 );

/*
============
CheckErrors
============
*/
void CheckErrors( void )
{		
    GLenum   err;

    err = qglGetError();
    if ( err != GL_NO_ERROR ) {
        common->FatalError( "glGetError: %s\n", qglGetString( err ) );
    }
}

static void VID_Center_f( const idCmdArgs &args ) {
	if ( osx.window /* && !osx.window.isFullScreen */ ) {
		[osx.window center];
	}
}

/*
** OSXGL_PixelFormat
**
** Helper function that generates an NSOpenGLPixelFormatAttribute.
*/
#define MAX_PIXELFORMATATTRIBUTES (32)

static ID_FORCE_INLINE void OSXGL_AttributeAdd( NSOpenGLPixelFormatAttribute *attributes, NSOpenGLPixelFormatAttribute attribute, int pos )
{
	if (pos < MAX_PIXELFORMATATTRIBUTES) {
		attributes[pos] = attribute;
	} else {
		common->FatalError( "OSXGL_AttributeAdd() overflowed, increase MAX_PIXELFORMATATTRIBUTES." );
	}
}

static NSOpenGLPixelFormatAttribute *OSXGL_PixelFormat( int colorbits, int alphabits, int depthbits, int stencilbits, int multisamples, bool stereo, uint32_t profile )
{
	static NSOpenGLPixelFormatAttribute attribs[MAX_PIXELFORMATATTRIBUTES] = {0};
	int attribCount = 0;

	OSXGL_AttributeAdd( attribs, NSOpenGLPFADoubleBuffer, attribCount++ );

	// stereo
//	if ( stereo ) {
//		OSXGL_AttributeAdd( attribs, NSOpenGLPFAStereo, attribCount++ );
//	}

	// color
	OSXGL_AttributeAdd( attribs, NSOpenGLPFAColorSize, attribCount++ );
	OSXGL_AttributeAdd( attribs, colorbits, attribCount++ );
	// alpha
	OSXGL_AttributeAdd( attribs, NSOpenGLPFAAlphaSize, attribCount++ );
	OSXGL_AttributeAdd( attribs, alphabits, attribCount++ );
	// depth
	OSXGL_AttributeAdd( attribs, NSOpenGLPFADepthSize, attribCount++ );
	OSXGL_AttributeAdd( attribs, depthbits, attribCount++ );
	// stencil
	OSXGL_AttributeAdd( attribs, NSOpenGLPFAStencilSize, attribCount++ );
	OSXGL_AttributeAdd( attribs, stencilbits, attribCount++ );

	//OSXGL_AttributeAdd( attribs, NSOpenGLPFAFullScreen, attribCount++ );

	OSXGL_AttributeAdd( attribs, NSOpenGLPFASampleBuffers, attribCount++ );
	OSXGL_AttributeAdd( attribs, multisamples, attribCount++ );

//	OSXGL_AttributeAdd( attribs, NSOpenGLPFANoRecovery, attribCount++ );

//	OSXGL_AttributeAdd( attribs, NSOpenGLPFAAccelerated, attribCount++ );

//	OSXGL_AttributeAdd( attribs, NSOpenGLPFABackingStore, attribCount++ );

//	OSXGL_AttributeAdd( attribs, NSOpenGLPFAWindow, attribCount++ );

//	OSXGL_AttributeAdd( attribs, NSOpenGLPFAPixelBuffer, attribCount++ );

	OSXGL_AttributeAdd( attribs, NSOpenGLPFAOpenGLProfile, attribCount++ );
	OSXGL_AttributeAdd( attribs, profile, attribCount++ );

//	OSXGL_AttributeAdd( attribs, NSOpenGLPFAMPSafe, attribCount++ );

	// end of list - NULL terminated
	OSXGL_AttributeAdd( attribs, (NSOpenGLPixelFormatAttribute)NULL, attribCount++ );

	return attribs;
}

/*
** OSXGL_MakeContext
*/
static NSOpenGLContext *OSXGL_MakeContext(NSOpenGLPixelFormat *pixelFormat, NSOpenGLContext *share)
{
	NSOpenGLContext *glContext = nil;

	glContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:share];

	return glContext;
}

/*
** OSXGL_InitDriver
*/
static bool OSXGL_InitDriver( glimpParms_t parms )
{
	int		colorbits = 24;
	int		alphabits = 8;
	int		depthbits = 24;
	int		stencilbits = 8;
	int		multisamples = parms.multiSamples;
	bool	stereo = parms.stereo;
	uint32_t profile = NSOpenGLProfileVersion3_2Core; // NSOpenGLProfileVersionLegacy
	NSOpenGLPixelFormatAttribute *attribs = NULL;
	static NSOpenGLPixelFormat *glPixelFormat = NULL;
	NSOpenGLContext *glContext = NULL;

	common->Printf( "Initializing OpenGL driver\n" );

	common->Printf( "...creating GL PixelFormat: " );

retryPixelFormat:
	attribs = OSXGL_PixelFormat( colorbits, alphabits, depthbits, stencilbits, multisamples, stereo, profile );
	glPixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];

	if ( !glPixelFormat ) {
		common->Printf( "^3failed^0\n" );

		if ( profile != NSOpenGLProfileVersionLegacy ) {
			common->Printf( "...falling back to legacy profile GL PixelFormat: \n" );
			profile = NSOpenGLProfileVersionLegacy;
			goto retryPixelFormat;
		}

		return false;
	}
	common->Printf( "succeeded\n" );

	common->Printf( "...creating GL context: " );
	glContext = OSXGL_MakeContext( glPixelFormat, NULL );

	if (!glContext) {
		common->Printf( "^3failed^0\n" );
		return false;
	}
	common->Printf( "succeeded\n" );

	// get the full info after the context has been created
	// TODO: different screen?
	[glPixelFormat getValues:(GLint*)&glConfig.colorBits forAttribute:NSOpenGLPFAColorSize forVirtualScreen:0];
	[glPixelFormat getValues:(GLint*)&glConfig.depthBits forAttribute:NSOpenGLPFADepthSize forVirtualScreen:0];
	[glPixelFormat getValues:(GLint*)&glConfig.stencilBits forAttribute:NSOpenGLPFAStencilSize forVirtualScreen:0];

	common->Printf( "...making context current: " );
	osx.glPixelFormat = glPixelFormat;
	osx.glContext = glContext;
	[osx.glContext makeCurrentContext];
	common->Printf( "succeeded\n" );

	return true;
}

/*
** OSXGL_CreateWindow
**
** Responsible for creating the window and initializing the OpenGL driver.
*/
static bool OSXGL_CreateWindow( glimpParms_t parms )
{
	int				x, y, w, h;
	idWindow		*window = NULL;
	idOpenGLView	*glView = NULL;
	NSRect			contentRect = NSMakeRect(parms.x, parms.y, parms.width, parms.height);
	NSUInteger		styleMask = (NSTitledWindowMask|NSClosableWindowMask|NSMiniaturizableWindowMask|NSResizableWindowMask);

	window = [[idWindow alloc] initWithContentRect:contentRect
										 styleMask:styleMask
										   backing:NSBackingStoreBuffered
											 defer:NO];

	if (!window) {
		common->FatalError( "OSXGL_CreateWindow() - Couldn't create window");
		return false;
	}

	window.delegate = window; //delegate;
	window.title = @"DOOM";
	window.allowsConcurrentViewDrawing = YES;
	window.acceptsMouseMovedEvents = YES;
	window.preservesContentDuringLiveResize = YES;
	[window setOpaque:YES];
	[window setReleasedWhenClosed:NO];
	[window useOptimizedDrawing:NO];
	//[window center];

	if ([window respondsToSelector:@selector(toggleFullScreen:)]) {
		window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
	}

	x = window.frame.origin.x;
	y = window.frame.origin.y;
	w = window.frame.size.width;
	h = window.frame.size.height;

	common->Printf( "...created window @ %d,%d (%dx%d)\n", x, y, w, h );

	if ( !OSXGL_InitDriver( parms ) ) {
		[window close];
		[window release];
		window = nil;
		return false;
	}

	glView = [[idOpenGLView alloc] initWithFrame:[window.contentView bounds]]; //window.contentView;
	glView.autoresizesSubviews = YES;
	glView.autoresizingMask = (NSViewWidthSizable|NSViewHeightSizable);
	glView.canDrawConcurrently = YES;
	glView.pixelFormat = osx.glPixelFormat;
	glView.openGLContext = OSXGL_MakeContext( osx.glPixelFormat, osx.glContext ); //osx.glContext;
	glView.wantsBestResolutionOpenGLSurface = YES;
	//glView.wantsLayer = YES;

	osx.window = window;
	osx.glView = glView;

	//osx.glContext.view = osx.window.contentView;
	osx.window.contentView = osx.glView;
	[osx.glView.openGLContext makeCurrentContext];
	[osx.glView prepareOpenGL];

	[window makeKeyAndOrderFront:nil];
	[window orderFrontRegardless];
	[window makeMainWindow];

	qglClearColor( 0.1, 0.1, 0.1, 1.0 );
	qglClear( GL_COLOR_BUFFER_BIT );
	GLimp_SwapBuffers();

	if ( parms.fullScreen ) {
		[osx.window performSelectorOnMainThread:@selector(toggleFullScreen:) withObject:nil waitUntilDone:YES];
	}

	glConfig.isFullscreen = parms.fullScreen;

	return true;
}

/*
** OSXGL_StartOpenGL
**
** internal function that attempts to load and use
** a specific OpenGL DLL.
*/
static bool OSXGL_StartOpenGL( glimpParms_t parms )
{
	if ( !OSXGL_CreateWindow( parms ) ) {
		common->FatalError( "OSXGL_LoadOpenGL() - could not load OpenGL subsystem\n" );
		return false;
	}

	return true;
}

/*
** GLimp_LogComment
*/
void GLimp_LogComment( char *comment ) 
{
	if ( osx.log_fp ) {
		fprintf( osx.log_fp, "%s", comment );
	}
}

/*
========================
GLimp_TestSwapBuffers
========================
*/
void GLimp_TestSwapBuffers( const idCmdArgs &args ) {
	static const int MAX_FRAMES = 5;
	unsigned long long timestamps[MAX_FRAMES];
	//int frameMilliseconds = 16;

	common->Printf( "GLimp_TimeSwapBuffers\n" );

	qglDisable( GL_SCISSOR_TEST );

	for ( GLint swapInterval = 1 /*2*/ ; swapInterval >= 0 /*-1*/ ; swapInterval-- ) {
		[osx.glView.openGLContext setValues:(const GLint *)&swapInterval
							   forParameter:NSOpenGLCPSwapInterval];

		for ( int i = 0 ; i < MAX_FRAMES ; i++ ) {
#if 0
			if ( swapInterval == -1 ) {
				Sys_Sleep( frameMilliseconds );
			}
#endif
			if ( i & 1 ) {
				qglClearColor( 0, 1, 0, 1 );
			} else {
				qglClearColor( 1, 0, 0, 1 );
			}
			qglClear( GL_COLOR_BUFFER_BIT );
			[osx.glView.openGLContext flushBuffer];
			//qglFinish();
			timestamps[i] = Sys_Microseconds();
		}

		common->Printf( "\nswapinterval %i\n", swapInterval );
		for ( int i = 1 ; i < MAX_FRAMES ; i++ ) {
			common->Printf( "%i microseconds\n", (int)(timestamps[i] - timestamps[i-1]) );
		}
	}
}

/*
 ===================
 GLimp_Init

 This is the platform specific OpenGL initialization function.  It
 is responsible for loading OpenGL, initializing it,
 creating a window of the appropriate size, doing
 fullscreen manipulations, etc.  Its overall responsibility is
 to make sure that a functional OpenGL subsystem is operating
 when it returns to the ref.

 If there is any failure, the renderer will revert back to safe
 parameters and try again.
 ===================
 */
bool GLimp_Init( glimpParms_t parms ) {
	//const char	*driverName;

	cmdSystem->AddCommand( "testSwapBuffers", GLimp_TestSwapBuffers, CMD_FL_SYSTEM, "Times swapbuffer options" );
	cmdSystem->AddCommand( "vid_center", VID_Center_f, CMD_FL_SYSTEM, "centers the window on the current desktop screen" );
	common->Printf( "Initializing OpenGL subsystem with multisamples:%i stereo:%i fullscreen:%i\n",
				   parms.multiSamples, parms.stereo, parms.fullScreen );
	
	// check our desktop attributes
	NSScreen *desktop = [NSScreen mainScreen];
	osx.desktopBitsPixel = (int)NSBitsPerPixelFromDepth(desktop.depth);
	osx.desktopWidth = (int)desktop.frame.size.width;
	osx.desktopHeight = (int)desktop.frame.size.height;

	// we can't run in a window unless it is 24 bpp
	if ( osx.desktopBitsPixel < 24 && parms.fullScreen <= 0 ) {
		common->Printf("^3Windowed mode requires 32 bit desktop depth^0\n");
		return false;
	}

	// save the hardware gamma so it can be
	// restored on exit
	GLimp_SaveGamma();

	// create our window classes if we haven't already
	//GLW_CreateWindowClasses();

//	r_allowSoftwareGL = ri.Cvar_Get( "r_allowSoftwareGL", "0", CVAR_LATCH );

	// load OpenGL and initialize subsystem
	if ( !OSXGL_StartOpenGL( parms ) ) {
		//GLimp_Shutdown();
		return false;
	}

	glConfig.isFullscreen = parms.fullScreen;
	glConfig.isStereoPixelFormat = parms.stereo;
	glConfig.nativeScreenWidth = parms.width;
	glConfig.nativeScreenHeight = parms.height;
	glConfig.multisamples = parms.multiSamples;

	glConfig.pixelAspect = 1.0f;	// FIXME: some monitor modes may be distorted
									// should side-by-side stereo modes be consider aspect 0.5?
#if 0
	// get the screen size, which may not be reliable...
	// If we use the windowDC, I get my 30" monitor, even though the window is
	// on a 27" monitor, so get a dedicated DC for the full screen device name.
	const idStr deviceName = GetDeviceName( Max( 0, parms.fullScreen - 1 ) );

	HDC deviceDC = CreateDC( deviceName.c_str(), deviceName.c_str(), NULL, NULL );
	const int mmWide = GetDeviceCaps( win32.hDC, HORZSIZE );
	DeleteDC( deviceDC );

	if ( mmWide == 0 ) {
		glConfig.physicalScreenWidthInCentimeters = 100.0f;
	} else {
		glConfig.physicalScreenWidthInCentimeters = 0.1f * mmWide;
	}


	// wglSwapinterval, etc
	GLW_CheckWGLExtensions( win32.hDC );
#else
	glConfig.physicalScreenWidthInCentimeters = 100.0f;
#endif

	// check logging
	GLimp_EnableLogging( ( r_logFile.GetInteger() != 0 ) );

	return true;
}

/*
===================
GLimp_SetScreenParms

Sets up the screen based on passed parms.. 
===================
*/
bool GLimp_SetScreenParms( glimpParms_t parms ) {
#if 0
	// Optionally ChangeDisplaySettings to get a different fullscreen resolution.
	if ( !GLW_ChangeDislaySettingsIfNeeded( parms ) ) {
		return false;
	}

	int x, y, w, h;
	if ( !GLW_GetWindowDimensions( parms, x, y, w, h ) ) {
		return false;
	}

	int exstyle;
	int stylebits;

	if ( parms.fullScreen ) {
		exstyle = WS_EX_TOPMOST;
		stylebits = WS_POPUP|WS_VISIBLE|WS_SYSMENU;
	} else {
		exstyle = 0;
		stylebits = WINDOW_STYLE|WS_SYSMENU;
	}

	SetWindowLong( win32.hWnd, GWL_STYLE, stylebits );
	SetWindowLong( win32.hWnd, GWL_EXSTYLE, exstyle );
	SetWindowPos( win32.hWnd, parms.fullScreen ? HWND_TOPMOST : HWND_NOTOPMOST, x, y, w, h, SWP_SHOWWINDOW );
#endif
	glConfig.isFullscreen = parms.fullScreen;
	glConfig.pixelAspect = 1.0f;	// FIXME: some monitor modes may be distorted

	glConfig.isFullscreen = parms.fullScreen;
	glConfig.nativeScreenWidth = parms.width;
	glConfig.nativeScreenHeight = parms.height;

	return true;
}

/*
===================
GLimp_Shutdown

This routine does all OS specific shutdown procedures for the OpenGL
subsystem.
===================
*/
void GLimp_Shutdown( void )
{
	common->Printf( "Shutting down OpenGL subsystem\n" );

	// set current context to NULL
	common->Printf( "...clearing GL context\n" );
	[NSOpenGLContext clearCurrentContext];
	[osx.glView.openGLContext clearDrawable];

	// delete context
	common->Printf( "...deleting GL context\n" );
	[osx.glContext release];
	[osx.glPixelFormat release];
	osx.glContext = NULL;
	osx.glPixelFormat = NULL;

	// destroy window
	common->Printf( "...destroying window\n" );
	[osx.glView.openGLContext release];
	[osx.glView removeFromSuperview];
	[osx.glView release];
	osx.glView = NULL;
	[osx.window close];
	[osx.window release];
	osx.window = NULL;

	// reset display settings
	if ( osx.cdsFullscreen )
	{
		common->Printf( "...resetting display\n" );
		//ChangeDisplaySettings( 0, 0 );
		osx.cdsFullscreen = 0;
	}

	// close the thread so the handle doesn't dangle
	if ( osx.renderThread )
	{
		int ret;
		common->Printf( "...closing smp thread\n" );
//		R_ShutdownCommandBuffers();
        ret = pthread_cancel( osx.renderThread );
		ret = pthread_cond_destroy( &osx.renderCommandsCondition );
		ret = pthread_cond_destroy( &osx.renderCompletedCondition );
		ret = pthread_cond_destroy( &osx.renderActiveCondition );
		ret = pthread_mutex_destroy( &osx.smpMutex );

		osx.renderThread = NULL;
	}

	// close the r_logFile
	if ( osx.log_fp )
	{
		fclose( osx.log_fp );
		osx.log_fp = 0;
	}

	// restore gamma
	GLimp_RestoreGamma();

	// shutdown QGL subsystem
	//QGL_Shutdown();

//	memset( &glConfig, 0, sizeof( glConfig ) );
//	memset( &glState, 0, sizeof( glState ) );
}

/*
=====================
GLimp_SwapBuffers
=====================
*/
void GLimp_SwapBuffers ( void )
{
	if ( r_swapInterval.IsModified() ) {
		r_swapInterval.ClearModified();
	}

	const GLint interval = r_swapInterval.GetInteger() > 0 ? 1 : 0;
	[osx.glView.openGLContext setValues:(const GLint *)&interval
						   forParameter:NSOpenGLCPSwapInterval];

	[osx.glView.openGLContext flushBuffer];
}

void GLimp_EndFrame (void) { GLimp_SwapBuffers(); }

/*
===========================================================

SMP acceleration

===========================================================
*/

/*
===================
GLimp_ActivateContext
===================
*/
void GLimp_ActivateContext() {
	[osx.glView.openGLContext makeCurrentContext];
}

/*
===================
GLimp_DeactivateContext
===================
*/
void GLimp_DeactivateContext() {
	qglFinish();
	[NSOpenGLContext clearCurrentContext];
}

/*
===================
GLimp_RenderThreadWrapper
===================
*/
static void *GLimp_RenderThreadWrapper(void *arg)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	common->Printf( "...Render thread starting\n" );

	osx.glimpRenderThread(); // ((void (*)())arg)();

	// unbind the context before we die
	//[NSOpenGLContext clearCurrentContext];

	common->Printf( "...Render thread terminating\n" );

	[pool release];

	return arg;
}

/*
=======================
GLimp_SpawnRenderThread

Returns false if the system only has a single processor
=======================
*/
bool GLimp_SpawnRenderThread( void (*function)( void ) )
{
    int ret;

	// check number of processors
	if ( Sys_ProcessorCount() < 2 ) {
		return false;
	}

	// create the IPC elements
	pthread_mutex_init( &osx.smpMutex, NULL );

 	pthread_cond_init( &osx.renderCommandsCondition, NULL );
	pthread_cond_init( &osx.renderCompletedCondition, NULL );
	pthread_cond_init( &osx.renderActiveCondition, NULL );

	osx.glimpRenderThread = function;

	ret = pthread_create( &osx.renderThread, NULL, GLimp_RenderThreadWrapper, &osx.glimpRenderThread );

	if ( !osx.renderThread ) {
		common->Printf( "GLimp_SpawnRenderThread: failed" );
	}

	//SetThreadPriority( win32.renderThreadHandle, THREAD_PRIORITY_ABOVE_NORMAL );

    if ( ret ) {
        common->Printf( "pthread_create returned %d: %s", ret, strerror( ret ) );
        return false;
    } else {
        ret = pthread_detach( osx.renderThread );
        if (ret) {
            common->Printf( "pthread_detach returned %d: %s", ret, strerror( ret ) );
        }
    }

    return true;
}

//#define	DEBUG_PRINTS

/*
===================
GLimp_BackEndSleep
 Called in the rendering thread to wait until a command buffer is ready.
 The command buffer returned might be NULL, indicating that the rendering thread should exit.
===================
*/
void *GLimp_BackEndSleep(void)
{
    void *data;
    
#ifdef DEBUG_PRINTS
	OutputDebugString( "-->GLimp_BackEndSleep\n" );
#endif

    // Clear the current context while we sleep so the main thread can access it
	//[NSOpenGLContext clearCurrentContext];

    pthread_mutex_lock( &osx.smpMutex ); {
        // Clear out any data we had and signal the main thread that we are no longer busy
        osx.smpData = NULL;
        osx.smpDataChanged = false;
        pthread_cond_signal( &osx.renderCompletedCondition );
        
        // Wait until we get something new to work on
        while ( !osx.smpDataChanged ) {
            pthread_cond_wait( &osx.renderCommandsCondition, &osx.smpMutex );
		}

        // Record the data (if any).
        data = osx.smpData;
    } pthread_mutex_unlock( &osx.smpMutex );

    // We are going to render a frame... retake the context
	[osx.glView.openGLContext makeCurrentContext];

#ifdef DEBUG_PRINTS
	OutputDebugString( "<--GLimp_BackEndSleep\n" );
#endif
    return data;
}

void *GLimp_RendererSleep(void) { return GLimp_BackEndSleep(); }

// Called from the main thread to wait until the rendering thread is done with the command buffer.
void GLimp_FrontEndSleep(void)
{
#ifdef DEBUG_PRINTS
	OutputDebugString( "-->GLimp_FrontEndSleep\n" );
#endif
    pthread_mutex_lock( &osx.smpMutex ); {
        while ( osx.smpData ) {
            pthread_cond_wait( &osx.renderCompletedCondition, &osx.smpMutex );
        }
    } pthread_mutex_unlock( &osx.smpMutex );

	// We are done waiting for the background thread, take the current context back.
	[osx.glView.openGLContext makeCurrentContext];

#ifdef DEBUG_PRINTS
	OutputDebugString( "<--GLimp_FrontEndSleep\n" );
#endif
}

/*
===================
GLimp_WakeBackEnd
===================
*/
void GLimp_WakeBackEnd( void *data )
{
#ifdef DEBUG_PRINTS
	OutputDebugString( "-->GLimp_WakeBackEnd\n" );
#endif

	// We want the background thread to draw stuff.  Give up the current context
	//[NSOpenGLContext clearCurrentContext];

    pthread_mutex_lock( &osx.smpMutex ); {
        // Store the new data pointer and wake up the rendering thread
        assert( osx.smpData == NULL );
        osx.smpData = data;
        osx.smpDataChanged = true;

		// after this, the renderer can continue through GLimp_RendererSleep
        pthread_cond_signal( &osx.renderCommandsCondition );
    } pthread_mutex_unlock( &osx.smpMutex) ;
#ifdef DEBUG_PRINTS
	OutputDebugString( "<--GLimp_WakeBackEnd\n" );
#endif
}

// This is called in the main thread to issue another command
// buffer to the rendering thread.  This is always called AFTER
// GLimp_FrontEndSleep, so we know that there is no command
// pending in 'smpData'.
void GLimp_WakeRenderer( void *data ) { GLimp_WakeBackEnd( data ); }

/*
===================
GLimp_ExtensionPointer

Returns a function pointer for an OpenGL extension entry point
===================
*/
GLExtension_t GLimp_ExtensionPointer( const char *name )
{
	static void		*handle = NULL;
	GLExtension_t	proc = NULL; // void (*proc)() = NULL;

	if ( handle == NULL ) {
		handle = dlopen( "/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL", RTLD_LAZY );
	}

	proc = (GLExtension_t)dlsym( handle ? handle : RTLD_DEFAULT, name );

	if ( !proc ) {
		common->Printf( "Couldn't find proc address for: %s\n", name );
	}

	return proc;
}

void GLimp_UpdateGLConfig(int width, int height, bool isFullscreen)
{
	glConfig.nativeScreenWidth = width;
	glConfig.nativeScreenHeight = height;
//	glConfig.windowAspect = (float)glConfig.nativeScreenWidth / glConfig.nativeScreenHeight;
	glConfig.isFullscreen = isFullscreen;

	//GLint dim[2] = {glConfig.nativeScreenWidth, glConfig.nativeScreenHeight};
	//[osx.glView.openGLContext setValues:(const GLint *)&dim forParameter:NSOpenGLCPSurfaceBackingSize];
	//CGLSetParameter(osx.glView.openGLContext.CGLContextObj, kCGLCPSurfaceBackingSize, dim);
	//CGLEnable (osx.glView.openGLContext.CGLContextObj, kCGLCESurfaceBackingSize);
}

/*
==================
GLimp_EnableLogging
==================
*/
void GLimp_EnableLogging( bool enable ) {
}

/*
====================
DumpAllDisplayDevices
====================
*/
void DumpAllDisplayDevices()
{
	common->Printf( "TODO: DumpAllDisplayDevices\n" );
}
#if 0
class idSort_VidMode : public idSort_Quick< vidMode_t, idSort_VidMode >
{
public:
	int Compare( const vidMode_t& a, const vidMode_t& b ) const
	{
		int wd = a.width - b.width;
		int hd = a.height - b.height;
		int fd = a.displayHz - b.displayHz;
		return ( hd != 0 ) ? hd : ( wd != 0 ) ? wd : fd;
	}
};

static void FillStaticVidModes( idList<vidMode_t>& modeList )
{
	modeList.AddUnique( vidMode_t( 640,   480, 60 ) );
	modeList.AddUnique( vidMode_t( 800,   600, 60 ) );
	modeList.AddUnique( vidMode_t( 960,   720, 60 ) );
	modeList.AddUnique( vidMode_t( 1024,  768, 60 ) );
	modeList.AddUnique( vidMode_t( 1280,  720, 60 ) );
	modeList.AddUnique( vidMode_t( 1280,  768, 60 ) );
	modeList.AddUnique( vidMode_t( 1360,  768, 60 ) );
	modeList.AddUnique( vidMode_t( 1920, 1080, 60 ) );
	modeList.AddUnique( vidMode_t( 1920, 1200, 60 ) );

	modeList.SortWithTemplate( idSort_VidMode() );
}
#endif
/*
====================
R_GetModeListForDisplay
====================
*/
bool R_GetModeListForDisplay( const int requestedDisplayNum, idList<vidMode_t> & modeList ) {
#warning implement R_GetModeListForDisplay
	modeList.Clear();
#if 0
	bool	verbose = false;

	for ( int displayNum = requestedDisplayNum; ; displayNum++ ) {
		DISPLAY_DEVICE	device;
		device.cb = sizeof( device );
		if ( !EnumDisplayDevices(
				0,			// lpDevice
				displayNum,
				&device,
				0 /* dwFlags */ ) ) {
			return false;
		}

		// get the monitor for this display
		if ( ! (device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP ) ) {
			continue;
		}

		DISPLAY_DEVICE	monitor;
		monitor.cb = sizeof( monitor );
		if ( !EnumDisplayDevices(
				device.DeviceName,
				0,
				&monitor,
				0 /* dwFlags */ ) ) {
			continue;
		}

		DEVMODE	devmode;
		devmode.dmSize = sizeof( devmode );

		if ( verbose ) {
			common->Printf( "display device: %i\n", displayNum );
			common->Printf( "  DeviceName  : %s\n", device.DeviceName );
			common->Printf( "  DeviceString: %s\n", device.DeviceString );
			common->Printf( "  StateFlags  : 0x%x\n", device.StateFlags );
			common->Printf( "  DeviceID    : %s\n", device.DeviceID );
			common->Printf( "  DeviceKey   : %s\n", device.DeviceKey );
			common->Printf( "      DeviceName  : %s\n", monitor.DeviceName );
			common->Printf( "      DeviceString: %s\n", monitor.DeviceString );
			common->Printf( "      StateFlags  : 0x%x\n", monitor.StateFlags );
			common->Printf( "      DeviceID    : %s\n", monitor.DeviceID );
			common->Printf( "      DeviceKey   : %s\n", monitor.DeviceKey );
		}

		for ( int modeNum = 0 ; ; modeNum++ ) {
			if ( !EnumDisplaySettings( device.DeviceName,modeNum, &devmode ) ) {
				break;
			}

			if ( devmode.dmBitsPerPel != 32 ) {
				continue;
			}
			if ( ( devmode.dmDisplayFrequency != 60 ) && ( devmode.dmDisplayFrequency != 120 ) ) {
				continue;
			}
			if ( devmode.dmPelsHeight < 720 ) {
				continue;
			}
			if ( verbose ) {
				common->Printf( "          -------------------\n" );
				common->Printf( "          modeNum             : %i\n", modeNum );
				common->Printf( "          dmPosition.x        : %i\n", devmode.dmPosition.x );
				common->Printf( "          dmPosition.y        : %i\n", devmode.dmPosition.y );
				common->Printf( "          dmBitsPerPel        : %i\n", devmode.dmBitsPerPel );
				common->Printf( "          dmPelsWidth         : %i\n", devmode.dmPelsWidth );
				common->Printf( "          dmPelsHeight        : %i\n", devmode.dmPelsHeight );
				common->Printf( "          dmDisplayFixedOutput: %s\n", DMDFO( devmode.dmDisplayFixedOutput ) );
				common->Printf( "          dmDisplayFlags      : 0x%x\n", devmode.dmDisplayFlags );
				common->Printf( "          dmDisplayFrequency  : %i\n", devmode.dmDisplayFrequency );
			}
			vidMode_t mode;
			mode.width = devmode.dmPelsWidth;
			mode.height = devmode.dmPelsHeight;
			mode.displayHz = devmode.dmDisplayFrequency;
			modeList.AddUnique( mode );
		}
		if ( modeList.Num() > 0 ) {

			class idSort_VidMode : public idSort_Quick< vidMode_t, idSort_VidMode > {
			public:
				int Compare( const vidMode_t & a, const vidMode_t & b ) const {
					int wd = a.width - b.width;
					int hd = a.height - b.height;
					int fd = a.displayHz - b.displayHz;
					return ( hd != 0 ) ? hd : ( wd != 0 ) ? wd : fd;
				}
			};

			// sort with lowest resolution first
			modeList.SortWithTemplate( idSort_VidMode() );

			return true;
		}
	}
	// Never gets here
#else
	return true;
#endif
}
