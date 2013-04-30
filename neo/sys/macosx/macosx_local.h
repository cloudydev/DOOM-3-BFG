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

#ifndef __MACOSX_LOCAL_H__
#define __MACOSX_LOCAL_H__

#import "../../idlib/precompiled.h"

// In macosx_input.m
extern void Sys_InitInput(void);
extern void Sys_ShutdownInput(void);
extern void Sys_SetMouseInputRect(CGRect newRect);

void	IN_MouseEvent (int mstate);
	
// In macosx_sys.m
void	Sys_QueEvent( sysEventType_t type, int value, int value2, int ptrLength, void* ptr, int inputDeviceNum );

void	Sys_CreateConsole( void );
void	Sys_DestroyConsole( void );
char	*Sys_ConsoleInput( void );

void Conbuf_AppendText( const char *msg );

// TODO: mixture of macosx_sys & unix_shared
const char		*Sys_Cwd();
void			Sys_SetDefaultCDPath( const char *path );
const char		*Sys_DefaultCDPath();
void			Sys_SetDefaultInstallPath(const char *path);
void			Sys_SetDefaultHomePath(const char *path);
const char		*Sys_DefaultHomePath(void);
bool			Sys_IsDedicatedServer( void );
int				Sys_Milliseconds (void);
unsigned int	Sys_ProcessorCount();
void			Sys_SetCmdLine( const char *cmdline );

// Input subsystem

void	IN_Init (void);
void	IN_Shutdown (void);
void	IN_JoystickCommands (void);

//void	IN_Move (usercmd_t *cmd);
// add additional non keyboard / non mouse movement on top of the keyboard move cmd

void	IN_DeactivateWin32Mouse( void);

void	IN_Activate (bool active);
void	IN_Frame (void);

// In macosx_glimp.m
extern bool Sys_IsHidden;
extern bool Sys_Hide();
extern bool Sys_Unhide();

typedef struct {
    CGGammaValue	 *red;
    CGGammaValue	 *blue;
    CGGammaValue	 *green;
} glwgamma_t;

extern void Sys_PauseGL();
extern void Sys_ResumeGL();

typedef struct {
	bool			activeApp;			// changed with WM_ACTIVATE messages
	bool			mouseReleased;		// when the game has the console down or is doing a long operation
	bool			movingWindow;		// inhibit mouse grab when dragging the window
	bool			mouseGrabbed;		// current state of grab and hide

	cpuid_t			cpuid;

	// when we get a windows message, we store the time off so keyboard processing
	// can know the exact time of an event (not really needed now that we use async direct input)
	int				sysMsgTime;

	NSWindow		*window;
	NSOpenGLView	*glView;
	NSOpenGLPixelFormat	*glPixelFormat;
	NSOpenGLContext *glContext;

	int				desktopBitsPixel;
	int				desktopWidth, desktopHeight;

	int				cdsFullscreen;	// 0 = not fullscreen, otherwise monitor number

    idFileHandle	log_fp;

	// desktop gamma is saved here for restoration at exit
	CGGammaValue	oldHardwareGamma[3][256];

	// SMP acceleration vars
	pthread_mutex_t	smpMutex;
	pthread_cond_t	renderCommandsCondition;
	pthread_cond_t	renderCompletedCondition;
	pthread_cond_t	renderActiveCondition;
	pthread_t		renderThread;
	void			(*glimpRenderThread)();
	void			*smpData;
	int				osxglErrors;
	volatile bool	smpDataChanged;
} OSXVars_t;

extern OSXVars_t	osx;

extern void			Sys_GrabMouseCursor( bool grabIt );
extern bool			Sys_WindowEvent(NSEvent *event);
void				GLimp_UpdateGLConfig(int width, int height, bool isFullscreen);

#endif // __MACOSX_LOCAL_H__
