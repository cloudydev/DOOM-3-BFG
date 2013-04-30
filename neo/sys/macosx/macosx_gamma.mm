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
** macosx_gamma.m
*/
#include "macosx_local.h"

/*
========================
GLimp_GetOldGammaRamp
========================
*/
void GLimp_SaveGamma() {
	bool		success;
	uint32_t	sampleCount;
	success = ( CGGetDisplayTransferByTable( CGMainDisplayID(), 256,
								osx.oldHardwareGamma[0], osx.oldHardwareGamma[1], osx.oldHardwareGamma[2],
								&sampleCount) == CGDisplayNoErr );

	common->DPrintf( "...getting default gamma ramp: %s\n", success ? "success" : "failed" );
}

/*
========================
GLimp_RestoreGamma
========================
*/
void GLimp_RestoreGamma() {
	CGDisplayRestoreColorSyncSettings();

	// if we never read in a reasonable looking
	// table, don't write it out
	if ( osx.oldHardwareGamma[0][255] == 0 ) {
		return;
	}
}

/*
========================
GLimp_SetGamma

The renderer calls this when the user adjusts r_gamma or r_brightness
========================
*/
void GLimp_SetGamma( unsigned short red[256], unsigned short green[256], unsigned short blue[256] ) {
	CGGammaValue table[3][256];
	int i;

	if ( !osx.glView ) {
		return;
	}

	for ( i = 0; i < 256; i++ ) {
		table[0][i] = red[i]   / 65535.0; //( ( ( unsigned short ) red[i] ) << 8 ) | red[i];
		table[1][i] = green[i] / 65535.0; //( ( ( unsigned short ) green[i] ) << 8 ) | green[i];
		table[2][i] = blue[i]  / 65535.0; //( ( ( unsigned short ) blue[i] ) << 8 ) | blue[i];
	}

	if ( CGSetDisplayTransferByTable( CGMainDisplayID(), 256, table[0], table[1], table[2] ) != CGDisplayNoErr ) {
		common->Printf( "WARNING: SetDeviceGammaRamp failed.\n" );
	}
}
