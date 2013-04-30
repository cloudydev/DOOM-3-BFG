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
#include "../sys_local.h"

#import "idAppDelegate.h"

#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOBSD.h>
#import <IOKit/storage/IOCDMedia.h>
#import <mach/mach_error.h>

#import <unistd.h>
#import <sys/types.h>
#import <sys/param.h>
#import <sys/mount.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/statvfs.h>
#import <dirent.h>

#import <dlfcn.h>
#import <termios.h>

OSXVars_t	osx = {0};

static char	sys_cmdline[MAX_STRING_CHARS] = {0};

static sysMemoryStats_t exeLaunchMemoryStats;

bool stdin_active = true;
idCVar in_tty( "in_tty", "0", CVAR_SYSTEM | CVAR_BOOL, "TODO: terminal" );

// Used to determine CD Path
static char cdPath[PATH_MAX] = {0};

// Used to determine local installation path
static char installPath[PATH_MAX] = {0};

// Used to determine where to store user-specific files
static char homePath[PATH_MAX] = {0};

static const char *ansiColors[8] = {
	"\033[30m",	/* ANSI Black */
	"\033[31m",	/* ANSI Red */
	"\033[32m",	/* ANSI Green */
	"\033[33m",	/* ANSI Yellow */
	"\033[34m",	/* ANSI Blue */
	"\033[36m",	/* ANSI Cyan */
	"\033[35m",	/* ANSI Magenta */
	"\033[37m"	/* ANSI White */
};

//===========================================================================

/*
================
Sys_GetExeLaunchMemoryStatus
================
*/
void Sys_GetExeLaunchMemoryStatus( sysMemoryStats_t &stats ) {
	stats = exeLaunchMemoryStats;
}

/*
==================
Sys_Sentry
==================
*/
void Sys_Sentry() {
}

/*
==================
Sys_FlushCacheMemory

On windows, the vertex buffers are write combined, so they
don't need to be flushed from the cache
==================
*/
void Sys_FlushCacheMemory( void *base, int bytes ) {
}

#ifdef DEBUG

static unsigned int debug_total_alloc = 0;
static unsigned int debug_total_alloc_count = 0;
static unsigned int debug_current_alloc = 0;
static unsigned int debug_current_alloc_count = 0;
static unsigned int debug_frame_alloc = 0;
static unsigned int debug_frame_alloc_count = 0;

idCVar sys_showMallocs( "sys_showMallocs", "0", CVAR_SYSTEM, "" );

/*
==================
Sys_DebugMemory_f
==================
*/
void Sys_DebugMemory_f() {
  	common->Printf( "Total allocation %8dk in %d blocks\n", debug_total_alloc / 1024, debug_total_alloc_count );
  	common->Printf( "Current allocation %8dk in %d blocks\n", debug_current_alloc / 1024, debug_current_alloc_count );
}

/*
==================
Sys_MemFrame
==================
*/
void Sys_MemFrame() {
	if( sys_showMallocs.GetInteger() ) {
		common->Printf("Frame: %8dk in %5d blocks\n", debug_frame_alloc / 1024, debug_frame_alloc_count );
	}

	debug_frame_alloc = 0;
	debug_frame_alloc_count = 0;
}

#endif // DEBUG

/*
=============
Sys_Error

Show the early console as an error dialog
=============
*/
void Sys_Error( const char *error, ... )
{
	idAppDelegate *delegate = [NSApp delegate];
    NSString *formattedString;
    va_list argptr;

	Sys_ShowConsole( 1, true );
	[delegate.consoleController.window makeKeyAndOrderFront:nil];

    va_start( argptr, error );
    formattedString = [[NSString alloc] initWithFormat:[NSString stringWithCString:error encoding:NSUTF8StringEncoding] arguments:argptr];
    va_end( argptr );

	[delegate stopFrameTimer];

	if ( common->IsInitialized() ) {
		common->Shutdown();
		common->Quit();
	}

	Sys_ShutdownInput(); // Sys_Shutdown();
	//GLimp_Shutdown();

	Sys_Printf( [formattedString cStringUsingEncoding:NSUTF8StringEncoding] );
	NSRunCriticalAlertPanel(@"ERROR", formattedString, @"Quit", nil, nil);
	//NSBeginCriticalAlertSheet( @"ERROR", @"Quit", nil, nil, delegate.consoleController.window, nil, nil, nil, nil, [NSString stringWithCString:error encoding:NSUTF8StringEncoding], argptr );

	[formattedString release];

	[NSApp terminate:nil]; //Sys_Quit();

	// exit (1);
}

/*
========================
Sys_Launch
========================
*/
void Sys_Launch( const char * path, idCmdArgs & args,  void * data, unsigned int dataSize ) {
#warning implement Sys_Launch
	cmdSystem->AppendCommandText( "quit\n" );
}

/*
========================
Sys_GetCmdLine
========================
*/
const char * Sys_GetCmdLine() {
	return sys_cmdline;
}

/*
========================
Sys_SetCmdLine
========================
*/
void Sys_SetCmdLine( const char *cmdline ) {
	if ( strlen(cmdline) > sizeof(sys_cmdline) ) {
		// TODO: print a warning? error?
	}
	strncpy( sys_cmdline, cmdline, sizeof(sys_cmdline) );
}

/*
========================
Sys_ReLaunch
========================
*/
void Sys_ReLaunch( void * data, const unsigned int dataSize ) {
#warning implement Sys_ReLaunch
	cmdSystem->AppendCommandText( "quit\n" );
}

void Sys_Quit(void)
{
	idAppDelegate *delegate = [NSApp delegate];

	[delegate stopFrameTimer];
	Sys_ShutdownInput();

	[NSApp terminate:nil];

	//exit( 0 );
}


/*
==============
Sys_Printf
==============
*/
#define MAXPRINTMSG 4096
void Sys_Printf( const char *fmt, ... ) {
	char		msg[MAXPRINTMSG];

	va_list argptr;
	va_start( argptr, fmt );
	idStr::vsnPrintf( msg, MAXPRINTMSG-1, fmt, argptr );
	va_end( argptr );
	msg[ sizeof( msg ) - 1 ] = '\0';

	if ( in_tty.GetBool() ) {
		/* TODO: check that this actually outputs/echoes right */
		/* TODO: filter out the ANSI control character text */
		/* Okay, this is a stupid hack, but what the hell, I was bored. ;) */
		const char *scan = msg;
		int index;

		/* Make sure terminal mode is reset at the start of the line... */
		fputs( "\033[0m", stdout );

		while( *scan ) {
			/* See if we have a color control code.  If so, snarf the character,
			 print what we have so far, print the ANSI Terminal color code,
			 skip over the color control code and continue */
			if( idStr::IsColor( scan ) ) {
				index = idStr::ColorIndex( scan[1] );

				/* Flush current message */
				if( scan != msg ) {
					fwrite( msg, scan - msg, 1, stdout );
				}

				/* Write ANSI color code */
				fputs( ansiColors[index], stdout );

				/* Reset search */
				scan += 2;
				continue;
			}
			scan++;
		}

		/* Flush whatever's left */
		fputs(scan, stdout);

		/* Make sure terminal mode is reset at the end of the line too... */
		fputs("\033[0m", stdout);
	} else {
		fputs( msg, stdout );
	}

	//	if ( osx.win_outputEditString.GetBool() && idLib::IsMainThread() ) {
	//		Conbuf_AppendText( msg );
	//	}

	idAppDelegate *delegate = (idAppDelegate*)[NSApp delegate];
	idConsoleWindowController *console = delegate.consoleController;

	if ( console && console.window && console.window.isVisible ) {
		NSString *string = [NSString stringWithUTF8String:msg];
		[console performSelectorOnMainThread:@selector(consoleOutput:)
								  withObject:string
							   waitUntilDone:YES]; // TODO: wait or not?
	}
}

/*
==============
Sys_DebugPrintf
==============
*/
#define MAXPRINTMSG 4096
void Sys_DebugPrintf( const char *fmt, ... ) {
	char msg[MAXPRINTMSG];

	va_list argptr;
	va_start( argptr, fmt );
	idStr::vsnPrintf( msg, MAXPRINTMSG-1, fmt, argptr );
	msg[ sizeof(msg)-1 ] = '\0';
	va_end( argptr );

	fputs( msg, stdout );
}

/*
==============
Sys_DebugVPrintf
==============
*/
void Sys_DebugVPrintf( const char *fmt, va_list arg ) {
	char msg[MAXPRINTMSG];

	idStr::vsnPrintf( msg, MAXPRINTMSG-1, fmt, arg );
	msg[ sizeof(msg)-1 ] = '\0';

	fputs( msg, stdout );
}

/*
==============
Sys_Sleep
==============
*/
void Sys_Sleep( int msec ) {
	usleep( msec * 1000 ); //sleep( msec );
}

/*
==============
Sys_ShowWindow
==============
*/
void Sys_ShowWindow( bool show ) {
	if ( osx.window ) {
		// TODO: hide vs. orderBack?
		show ? [osx.window makeKeyAndOrderFront:nil] : [osx.window orderBack:nil];
	}
}

/*
==============
Sys_IsWindowVisible
==============
*/
bool Sys_IsWindowVisible() {
	return (osx.window && osx.window.isVisible);
}

/*
==============
Sys_Mkdir
==============
*/
void Sys_Mkdir( const char *path ) {
	mkdir( path, 0777 );
}

/*
=================
Sys_FileTimeStamp
=================
*/
ID_TIME_T Sys_FileTimeStamp( idFileHandle fp ) {
	struct stat st;
	fstat( fileno( fp ), &st );
	return st.st_mtime;
}

/*
========================
Sys_Rmdir
========================
*/
bool Sys_Rmdir( const char *path ) {
	return ( rmdir( path ) == 0 );
}

/*
========================
Sys_IsFileWritable
========================
*/
bool Sys_IsFileWritable( const char *path ) {
	struct stat st;

	if( stat( path, &st ) == -1 ) {
		return true;
	}

	return ( st.st_mode & S_IWRITE ) != 0;
}

/*
========================
Sys_IsFolder
========================
*/
sysFolder_t	 Sys_IsFolder( const char* path ) {
	struct stat buffer;

	if( stat( path, &buffer ) < 0 ) {
		return FOLDER_ERROR;
	}

	return ( buffer.st_mode & S_IFDIR ) != 0 ? FOLDER_YES : FOLDER_NO;
}

/*
==============
Sys_Cwd
==============
*/
const char *Sys_Cwd() {
	static char cwd[PATH_MAX];

	getcwd( cwd, sizeof( cwd ) - 1 );
	cwd[PATH_MAX-1] = 0;

	return cwd;
}

void Sys_SetDefaultCDPath( const char *path ) {
	strncpy( cdPath, path, sizeof( cdPath ) );
}

const char *Sys_DefaultCDPath() {
	if ( *cdPath )
		return cdPath;
	else
        return "";
}

void Sys_SetDefaultInstallPath( const char *path ) {
	strncpy( installPath, path, sizeof( installPath ) );
}

const char *Sys_DefaultInstallPath( void ) {
	if ( *installPath )
		return installPath;
	else
		return Sys_Cwd();
}

void Sys_SetDefaultHomePath( const char *path ) {
	strncpy( homePath, path, sizeof( homePath ) );
}

const char *Sys_DefaultHomePath( void ) {
	char *p;

	if ( *homePath )
		return homePath;

	if ( (p = getenv("HOME") ) != NULL ) {
		strncpy( homePath, p, sizeof( homePath ) );
		strncat( homePath, kLibraryApplicationSupportPath, sizeof( homePath ) - strlen( homePath ) - 1 );

		if ( mkdir( homePath, 0777 ) ) {
//			if (errno != EEXIST)
//				Sys_Error("Unable to create directory \"%s\", error is %s(%d)\n", homePath, strerror(errno), errno);
		}
		return homePath;
	}

	// assume current dir
	return "";
}

/*
==============
Sys_DefaultBasePath
==============
*/
const char *Sys_DefaultBasePath() {
	// TODO: verify this is correct
	return Sys_DefaultInstallPath();
}

/*
==============
Sys_DefaultSavePath
==============
*/
const char *Sys_DefaultSavePath() {
	// TODO: verify this is correct
	return Sys_DefaultHomePath();
}

/*
==============
Sys_EXEPath
==============
*/
const char *Sys_EXEPath() {
#warning implement Sys_EXEPath
	static char exe[ PATH_MAX ] = {0};
	return exe;
}

/*
==============
Sys_ListFiles
==============
*/
int Sys_ListFiles( const char *directory, const char *extension, idStrList &list ) {
	struct dirent *d;
	DIR *fdir;
	bool dironly = false;
	char search[PATH_MAX];
	struct stat st;
	bool debug;

	list.Clear();

	debug = cvarSystem->GetCVarBool( "fs_debug" );

	if (!extension)
		extension = "";

	// passing a slash as extension will find directories
	if (extension[0] == '/' && extension[1] == 0) {
		extension = "";
		dironly = true;
	}

	// search
	// NOTE: case sensitivity of directory path can screw us up here
	if ((fdir = opendir(directory)) == NULL) {
		if (debug) {
			common->Printf("Sys_ListFiles: opendir %s failed\n", directory);
		}
		return -1;
	}

	while ((d = readdir(fdir)) != NULL) {
		idStr::snPrintf(search, sizeof(search), "%s/%s", directory, d->d_name);
		if (stat(search, &st) == -1)
			continue;
		if (!dironly) {
			idStr look(search);
			idStr ext;
			look.ExtractFileExtension(ext);
			if (extension[0] != '\0' && ext.Icmp(&extension[1]) != 0) {
				continue;
			}
		}
		if ((dironly && !(st.st_mode & S_IFDIR)) ||
			(!dironly && (st.st_mode & S_IFDIR)))
			continue;

		list.Append(d->d_name);
	}

	closedir(fdir);

	if ( debug ) {
		common->Printf( "Sys_ListFiles: %d entries in %s\n", list.Num(), directory );
	}

	return list.Num();
}

/*
================
Sys_GetClipboardData
================
*/
char *Sys_GetClipboardData() {
#warning implement Sys_GetClipboardData
	NSPasteboard *pasteboard;
    NSArray *pasteboardTypes;

    pasteboard = [NSPasteboard generalPasteboard];
    pasteboardTypes = [pasteboard types];
    if ([pasteboardTypes containsObject:NSStringPboardType]) {
        NSString *clipboardString;

        clipboardString = [pasteboard stringForType:NSStringPboardType];
        if (clipboardString && [clipboardString length] > 0) {
            return strdup([clipboardString cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }

    return NULL;
}

/*
================
Sys_SetClipboardData
================
*/
void Sys_SetClipboardData( const char *string ) {
#warning implement Sys_SetClipboardData
}

/*
========================
Sys_Exec

if waitMsec is INFINITE, completely block until the process exits
If waitMsec is -1, don't wait for the process to exit
Other waitMsec values will allow the workFn to be called at those intervals.
========================
*/
bool Sys_Exec(	const char * appPath, const char * workingPath, const char * args, 
	execProcessWorkFunction_t workFn, execOutputFunction_t outputFn, const int waitMS,
	unsigned int & exitCode ) {
	return false;
}

/*
========================================================================

DLL Loading

========================================================================
*/

/*
=================
Sys_DLL_Load
=================
*/
int Sys_DLL_Load( const char* path ) {
	void *handle = dlopen( path, RTLD_NOW );
	if( !handle ) {
		Sys_Printf( "dlopen '%s' failed: %s\n", path, dlerror() );
	}
	return (int)handle;
}

/*
=================
Sys_DLL_GetProcAddress
=================
*/
void* Sys_DLL_GetProcAddress( int handle, const char* sym ) {
	const char* error;
	void* ret = dlsym( (void*)handle, sym );
	if( ( error = dlerror() ) != NULL ) {
		Sys_Printf( "dlsym '%s' failed: %s\n", sym, error );
	}
	return ret;
}

/*
=================
Sys_DLL_Unload
=================
*/
void Sys_DLL_Unload( int handle ) {
	dlclose( (void*)handle );
}

/*
========================================================================

EVENT LOOP

========================================================================
*/

#define	MAX_QUED_EVENTS		256
#define	MASK_QUED_EVENTS	( MAX_QUED_EVENTS - 1 )

sysEvent_t	eventQue[MAX_QUED_EVENTS];
int			eventHead = 0;
int			eventTail = 0;

/*
================
Sys_QueEvent

Ptr should either be null, or point to a block of data that can
be freed by the game later.
================
*/
void Sys_QueEvent( sysEventType_t type, int value, int value2, int ptrLength, void *ptr, int inputDeviceNum ) {
	sysEvent_t * ev = &eventQue[ eventHead & MASK_QUED_EVENTS ];

	if ( eventHead - eventTail >= MAX_QUED_EVENTS ) {
		common->Printf("Sys_QueEvent: overflow\n");
		// we are discarding an event, but don't leak memory
		if ( ev->evPtr ) {
			Mem_Free( ev->evPtr );
		}
		eventTail++;
	}

	eventHead++;

	ev->evType = type;
	ev->evValue = value;
	ev->evValue2 = value2;
	ev->evPtrLength = ptrLength;
	ev->evPtr = ptr;
	ev->inputDevice = inputDeviceNum;
}

/*
=============
Sys_PumpEvents

This allows windows to be moved during renderbump
=============
*/
void Sys_PumpEvents() {
#warning implement Sys_PumpEvents
#if 0
    MSG msg;

	// pump the message loop
	while( PeekMessage( &msg, NULL, 0, 0, PM_NOREMOVE ) ) {
		if ( !GetMessage( &msg, NULL, 0, 0 ) ) {
			common->Quit();
		}

		// save the msg time, because wndprocs don't have access to the timestamp
		if ( osx.sysMsgTime && osx.sysMsgTime > (int)msg.time ) {
			// don't ever let the event times run backwards
			//			common->Printf( "Sys_PumpEvents: osx.sysMsgTime (%i) > msg.time (%i)\n", osx.sysMsgTime, msg.time );
		} else {
			osx.sysMsgTime = msg.time;
		}

		TranslateMessage (&msg);
      	DispatchMessage (&msg);
	}
#endif
}

/*
================
Sys_GenerateEvents
================
*/
void Sys_GenerateEvents() {
	static int entered = false;
	char *s;

	if ( entered ) {
		return;
	}
	entered = true;

	// pump the message loop
	Sys_PumpEvents();

	// grab or release the mouse cursor if necessary
	IN_Frame();

	// check for console commands
	s = Sys_ConsoleInput();
	if ( s ) {
		char	*b;
		int		len;

		len = strlen( s ) + 1;
		b = (char *)Mem_Alloc( len, TAG_EVENTS );
		strcpy( b, s );
		Sys_QueEvent( SE_CONSOLE, 0, 0, len, b, 0 );
	}

	entered = false;
}

/*
================
Sys_ClearEvents
================
*/
void Sys_ClearEvents() {
	eventHead = eventTail = 0;
}

/*
================
Sys_GetEvent
================
*/
sysEvent_t Sys_GetEvent() {
	sysEvent_t	ev;

	// return if we have data
	if ( eventHead > eventTail ) {
		eventTail++;
		return eventQue[ ( eventTail - 1 ) & MASK_QUED_EVENTS ];
	}

	// return the empty event 
	memset( &ev, 0, sizeof( ev ) );

	return ev;
}

//================================================================

/*
=================
Sys_In_Restart_f

Restart the input subsystem
=================
*/
void Sys_In_Restart_f( const idCmdArgs &args ) {
	Sys_ShutdownInput();
	Sys_InitInput();
}

/*
================
Sys_AlreadyRunning
return true if there is a copy of D3 running already
================
*/
bool Sys_AlreadyRunning() {
#warning implement Sys_AlreadyRunning
	return false;
}

/*
================
Sys_Init

The cvar and file system has been setup, so configurations are loaded
================
*/
void Sys_Init() {
	cmdSystem->AddCommand( "in_restart", Sys_In_Restart_f, CMD_FL_SYSTEM, "restarts the input system" );
	//cmdSystem->AddCommand( "net_restart", Sys_Net_Restart_f, CMD_FL_SYSTEM, "restarts the network system" );

	// TODO: user name?

	// TODO: OS Version?
#if 0
	//
	// TODO: CPU type
	//
	if ( !idStr::Icmp( osx.sys_cpustring.GetString(), "detect" ) ) {
		idStr string;

		common->Printf( "%1.0f MHz ", Sys_ClockTicksPerSecond() / 1000000.0f );

		osx.cpuid = Sys_GetCPUId();

		string.Clear();

		if ( osx.cpuid & CPUID_AMD ) {
			string += "AMD CPU";
		} else if ( osx.cpuid & CPUID_INTEL ) {
			string += "Intel CPU";
		} else if ( osx.cpuid & CPUID_UNSUPPORTED ) {
			string += "unsupported CPU";
		} else {
			string += "generic CPU";
		}

		string += " with ";
		if ( osx.cpuid & CPUID_MMX ) {
			string += "MMX & ";
		}
		if ( osx.cpuid & CPUID_3DNOW ) {
			string += "3DNow! & ";
		}
		if ( osx.cpuid & CPUID_SSE ) {
			string += "SSE & ";
		}
		if ( osx.cpuid & CPUID_SSE2 ) {
            string += "SSE2 & ";
		}
		if ( osx.cpuid & CPUID_SSE3 ) {
			string += "SSE3 & ";
		}
		if ( osx.cpuid & CPUID_HTT ) {
			string += "HTT & ";
		}
		string.StripTrailing( " & " );
		string.StripTrailing( " with " );
		osx.sys_cpustring.SetString( string );
	} else {
		common->Printf( "forcing CPU type to " );
		idLexer src( osx.sys_cpustring.GetString(), idStr::Length( osx.sys_cpustring.GetString() ), "sys_cpustring" );
		idToken token;

		int id = CPUID_NONE;
		while( src.ReadToken( &token ) ) {
			if ( token.Icmp( "generic" ) == 0 ) {
				id |= CPUID_GENERIC;
			} else if ( token.Icmp( "intel" ) == 0 ) {
				id |= CPUID_INTEL;
			} else if ( token.Icmp( "amd" ) == 0 ) {
				id |= CPUID_AMD;
			} else if ( token.Icmp( "mmx" ) == 0 ) {
				id |= CPUID_MMX;
			} else if ( token.Icmp( "3dnow" ) == 0 ) {
				id |= CPUID_3DNOW;
			} else if ( token.Icmp( "sse" ) == 0 ) {
				id |= CPUID_SSE;
			} else if ( token.Icmp( "sse2" ) == 0 ) {
				id |= CPUID_SSE2;
			} else if ( token.Icmp( "sse3" ) == 0 ) {
				id |= CPUID_SSE3;
			} else if ( token.Icmp( "htt" ) == 0 ) {
				id |= CPUID_HTT;
			}
		}
		if ( id == CPUID_NONE ) {
			common->Printf( "WARNING: unknown sys_cpustring '%s'\n", osx.sys_cpustring.GetString() );
			id = CPUID_GENERIC;
		}
		osx.cpuid = (cpuid_t) id;
	}

	common->Printf( "%s\n", osx.sys_cpustring.GetString() );
	common->Printf( "%d MB System Memory\n", Sys_GetSystemRam() );
	common->Printf( "%d MB Video Memory\n", Sys_GetVideoRam() );
	if ( ( osx.cpuid & CPUID_SSE2 ) == 0 ) {
		common->Error( "SSE2 not supported!" );
	}
#endif

	if ( Sys_IsDedicatedServer() )
		return;

	IN_Init(); // osx.g_Joystick.Init();
}

/*
=================
Sys_Shutdown
=================
*/
void Sys_Shutdown(void) {
}

/*
===============
Sys_GetProcessorId
===============
*/
cpuid_t Sys_GetProcessorId() {
#warning implement Sys_GetProcessorId
	return CPUID_GENERIC; // osx.cpuid
}

/*
===============
Sys_GetProcessorString
===============
*/
const char* Sys_GetProcessorString() {
#warning implement Sys_GetProcessorString
	return "Generic CPU"; // osx.sys_cpustring.GetString();
}

//===========================================================================

/*
====================
OSX_Frame
====================
*/
void OSX_Frame() {
#warning implement OSX_Frame
	// if "viewlog" has been modified, show or hide the log console
//	if ( osx.win_viewlog.IsModified() ) {
//		osx.win_viewlog.ClearModified();
//	}
}

#define TEST_FPU_EXCEPTIONS	/*	FPU_EXCEPTION_INVALID_OPERATION |		*/	\
							/*	FPU_EXCEPTION_DENORMALIZED_OPERAND |	*/	\
							/*	FPU_EXCEPTION_DIVIDE_BY_ZERO |			*/	\
							/*	FPU_EXCEPTION_NUMERIC_OVERFLOW |		*/	\
							/*	FPU_EXCEPTION_NUMERIC_UNDERFLOW |		*/	\
							/*	FPU_EXCEPTION_INEXACT_RESULT |			*/	\
								0

/*
==================
OSXMain
==================
*/
int OSXMain( const char *lpCmdLine ) {
	Sys_SetPhysicalWorkMemory( 192 << 20, 1024 << 20 );

	Sys_GetCurrentMemoryStatus( exeLaunchMemoryStats );
	
	idStr::Copynz( sys_cmdline, lpCmdLine, sizeof( sys_cmdline ) );

	// done before Com/Sys_Init since we need this for error output
	Sys_CreateConsole();

	// get the initial time base
	Sys_Milliseconds();

	//	Sys_FPU_EnableExceptions( TEST_FPU_EXCEPTIONS );
	Sys_FPU_SetPrecision( FPU_PRECISION_DOUBLE_EXTENDED );

	common->Init( 0, NULL, lpCmdLine );

#if TEST_FPU_EXCEPTIONS != 0
	common->Printf( Sys_FPU_GetState() );
#endif

	// hide or show the early console as necessary
//	if ( osx.win_viewlog.GetInteger() ) {
//		Sys_ShowConsole( 1, true );
//	} else {
//		Sys_ShowConsole( 0, false );
//	}

    // main game loop
	while( 1 ) {

		OSX_Frame();

#ifdef DEBUG
		Sys_MemFrame();
#endif

		// set exceptions, even if some crappy syscall changes them!
		Sys_FPU_EnableExceptions( TEST_FPU_EXCEPTIONS );

		// run the game
		common->Frame();
	}

	// never gets here
	return 0;
}

/*
==================
idSysLocal::OpenURL
==================
*/
void idSysLocal::OpenURL( const char *url, bool doexit ) {
#warning implement idSysLocal::OpenURL
	static bool doexit_spamguard = false;

	if (doexit_spamguard) {
		common->DPrintf( "OpenURL: already in an exit sequence, ignoring %s\n", url );
		return;
	}

	common->Printf("Open URL: %s\n", url);

	if ( doexit ) {
		doexit_spamguard = true;
		cmdSystem->BufferCommandText( CMD_EXEC_APPEND, "quit\n" );
	}
}

/*
==================
idSysLocal::StartProcess
==================
*/
void idSysLocal::StartProcess( const char *exePath, bool doexit ) {
#warning implement idSysLocal::StartProcess
	if ( doexit ) {
		cmdSystem->BufferCommandText( CMD_EXEC_APPEND, "quit\n" );
	}
}

/*
==================
Sys_SetFatalError
==================
*/
void Sys_SetFatalError( const char* error ) {
}

/*
================
Sys_SetLanguageFromSystem
================
*/
extern idCVar sys_lang;
void Sys_SetLanguageFromSystem() {
	sys_lang.SetString( Sys_DefaultLanguage() );
}

//=======================================================================

//=======================================================================

/*
** Sys_CreateConsole
*/
void Sys_CreateConsole( void ) {
	idAppDelegate *delegate = [NSApp delegate];

	if (!delegate.consoleController) {
		[delegate initConsoleController];
	}

	//[delegate.consoleController.window center];
	[delegate.consoleController showWindow:delegate];
	//[delegate.consoleController.window makeKeyAndOrderFront:nil];
}

/*
** Sys_DestroyConsole
*/
void Sys_DestroyConsole( void )
{
	idAppDelegate *delegate = [NSApp delegate];

	[delegate shutdownConsoleController];
}

/*
** Sys_ShowConsole
*/
void Sys_ShowConsole( int visLevel, bool quitOnClose )
{
	idAppDelegate *delegate = [NSApp delegate];
	idConsoleWindowController *console = delegate.consoleController;

	if (!console && visLevel) {
		[delegate initConsoleController];
		console = delegate.consoleController;
		//[console.window orderWindow:NSWindowBelow relativeTo:delegate.window.windowNumber];
	}

	if (console) {
		switch ( visLevel )
		{
			case 0:
				// close/hide
				[console.window close];
				break;
			case 1:
				// show and scroll to bottom
				[console.window orderWindow:NSWindowBelow relativeTo:delegate.window.windowNumber];
				[delegate.window makeKeyAndOrderFront:nil];
				[console.textView scrollRangeToVisible:NSMakeRange(console.textView.string.length, 0)];
				//[console.window orderFront:nil];
				break;
			case 2:
				// minimize
				[console.window miniaturize:nil];
				break;
			default:
				common->Printf( "Invalid visLevel %d sent to Sys_ShowConsole\n", visLevel );
				break;
		}
	}
}

//===========================================================================

//===================================================================

bool Sys_IsDedicatedServer( void)
{
// TODO: does Doom3BFG even have a dedicated server?
//	return common->IsServer();
	return false;
}

//===================================================================
