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
#import "../sys_local.h"
#import <dirent.h>
#import <mach/mach_time.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/statvfs.h>
#import "idAppDelegate.h"

/*
================
Sys_Nanoseconds
================
*/
uint64 Sys_Nanoseconds() {
	static mach_timebase_info_data_t info = { .numer = 0, .denom = 0 };
	static uint64_t origin = 0;
	if ( origin == 0 ) origin = mach_absolute_time();
	if ( info.denom == 0 ) mach_timebase_info(&info);
	if ( info.numer == 1 && info.denom == 1 ) return ( mach_absolute_time() - origin );
	return ( mach_absolute_time() - origin ) * info.numer / info.denom;
}

/*
================
Sys_Milliseconds
================
*/
int Sys_Milliseconds() {
	return Sys_Nanoseconds() * 0.000001;
}

/*
========================
Sys_Microseconds
========================
*/
uint64 Sys_Microseconds() {
	return Sys_Nanoseconds() * 0.001;
}

/*
================
Sys_ProcessorCount

legacy function, unix quake 3 smp
================
*/
unsigned int Sys_ProcessorCount()
{
	static unsigned int cpuCount = 0;
    size_t size = sizeof(cpuCount);

	if ( !cpuCount ) {
		if ( sysctlbyname( "hw.ncpu", &cpuCount, &size, NULL, 0 ) == 0 ) {
			common->Printf("System processor count is %d\n", cpuCount);
		} else {
			perror("sysctl");
			cpuCount = 1;
		}
	}

    return cpuCount;
}

/*
================
Sys_GetSystemRam

	returns amount of physical memory in MB
================
*/
int Sys_GetSystemRam() {
	static int physRam = 0;
    size_t size = sizeof(physRam);

	if ( !physRam ) {
		if ( sysctlbyname( "hw.memsize", &physRam, &size, NULL, 0 ) == 0 ) {
		} else {
			perror("sysctl");
			physRam = 1073741824; // 1 GB, 1024 MB
		}
	}
	
	return physRam >> 20;
}


/*
================
Sys_GetDriveFreeSpace
returns in megabytes
================
*/
int Sys_GetDriveFreeSpace( const char *path ) {
#warning implement Sys_GetDriveFreeSpace
	int ret = 26;
	struct statvfs st;

	if( statvfs( path, &st ) == 0 ) {
		unsigned long blocksize = st.f_bsize;
		unsigned long freeblocks = st.f_bfree;
		unsigned long free = blocksize * freeblocks;

		ret = ( double )( free ) / ( 1024.0 * 1024.0 );
	}

	return ret;
}

/*
========================
Sys_GetDriveFreeSpaceInBytes
========================
*/
int64 Sys_GetDriveFreeSpaceInBytes( const char * path ) {
#warning implement Sys_GetDriveFreeSpaceInBytes
	int64 ret = 1;
	struct statvfs st;

	if( statvfs( path, &st ) == 0 ) {
		unsigned long blocksize = st.f_bsize;
		unsigned long freeblocks = st.f_bfree;
		unsigned long free = blocksize * freeblocks;

		ret = free;
	}

	return ret;
}

/*
================
Sys_GetVideoRam
returns in megabytes
================
*/
int Sys_GetVideoRam() {
#warning implement Sys_GetVideoRam
	unsigned int retSize = 256;
	return retSize;
}

/*
================
Sys_GetCurrentMemoryStatus

	returns OS mem info
	all values are in kB except the memoryload
================
*/
void Sys_GetCurrentMemoryStatus( sysMemoryStats_t &stats ) {
#warning implement Sys_GetCurrentMemoryStatus
}

/*
================
Sys_LockMemory
================
*/
bool Sys_LockMemory( void *ptr, int bytes ) {
#warning implement Sys_LockMemory
	return true;
}

/*
================
Sys_UnlockMemory
================
*/
bool Sys_UnlockMemory( void *ptr, int bytes ) {
#warning implement Sys_UnlockMemory
	return true;
}

/*
================
Sys_SetPhysicalWorkMemory
================
*/
void Sys_SetPhysicalWorkMemory( int minBytes, int maxBytes ) {
#warning implement Sys_SetPhysicalWorkMemory
}

/*
================
Sys_GetCurrentUser
================
*/
char *Sys_GetCurrentUser() {
	static char s_userName[1024];

	strncpy( s_userName, getenv( "USER" ), sizeof( s_userName ) );

	if ( !s_userName[0] ) {
		strcpy( s_userName, "player" );
	}

	return s_userName;
}	


/*
===============================================================================

	Call stack

===============================================================================
*/


#define PROLOGUE_SIGNATURE 0x00EC8B55

#if defined(_DEBUG) && 1

typedef struct symbol_s {
	int					address;
	char *				name;
	struct symbol_s *	next;
} symbol_t;

typedef struct module_s {
	int					address;
	char *				name;
	symbol_t *			symbols;
	struct module_s *	next;
} module_t;

module_t *modules;

/*
==================
SkipRestOfLine
==================
*/
void SkipRestOfLine( const char **ptr ) {
	while( (**ptr) != '\0' && (**ptr) != '\n' && (**ptr) != '\r' ) {
		(*ptr)++;
	}
	while( (**ptr) == '\n' || (**ptr) == '\r' ) {
		(*ptr)++;
	}
}

/*
==================
SkipWhiteSpace
==================
*/
void SkipWhiteSpace( const char **ptr ) {
	while( (**ptr) == ' ' ) {
		(*ptr)++;
	}
}

/*
==================
ParseHexNumber
==================
*/
int ParseHexNumber( const char **ptr ) {
	int n = 0;
	while( (**ptr) >= '0' && (**ptr) <= '9' || (**ptr) >= 'a' && (**ptr) <= 'f' ) {
		n <<= 4;
		if ( **ptr >= '0' && **ptr <= '9' ) {
			n |= ( (**ptr) - '0' );
		} else {
			n |= 10 + ( (**ptr) - 'a' );
		}
		(*ptr)++;
	}
	return n;
}

/*
==================
Sym_Init
==================
*/
void Sym_Init( long addr ) {
}

/*
==================
Sym_Shutdown
==================
*/
void Sym_Shutdown() {
	module_t *m;
	symbol_t *s;

	for ( m = modules; m != NULL; m = modules ) {
		modules = m->next;
		for ( s = m->symbols; s != NULL; s = m->symbols ) {
			m->symbols = s->next;
			free( s->name );
			free( s );
		}
		free( m->name );
		free( m );
	}
	modules = NULL;
}

/*
==================
Sym_GetFuncInfo
==================
*/
void Sym_GetFuncInfo( long addr, idStr &module, idStr &funcName ) {
}

#elif defined(_DEBUG)

/*
==================
Sym_Init
==================
*/
void Sym_Init( long addr ) {
}

/*
==================
Sym_Shutdown
==================
*/
void Sym_Shutdown() {
}

/*
==================
Sym_GetFuncInfo
==================
*/
void Sym_GetFuncInfo( long addr, idStr &module, idStr &funcName ) {
}

#else

/*
==================
Sym_Init
==================
*/
void Sym_Init( long addr ) {
}

/*
==================
Sym_Shutdown
==================
*/
void Sym_Shutdown() {
}

/*
==================
Sym_GetFuncInfo
==================
*/
void Sym_GetFuncInfo( long addr, idStr &module, idStr &funcName ) {
	module = "";
	sprintf( funcName, "0x%08x", addr );
}

#endif

/*
==================
GetFuncAddr
==================
*/
address_t GetFuncAddr( address_t midPtPtr ) {
	long temp;
	do {
		temp = (long)(*(long*)midPtPtr);
		if ( (temp&0x00FFFFFF) == PROLOGUE_SIGNATURE ) {
			break;
		}
		midPtPtr--;
	} while(true);

	return midPtPtr;
}

/*
==================
GetCallerAddr
==================
*/
address_t GetCallerAddr( long _ebp ) {
	long res = 0;
	return res;
}

/*
==================
Sys_GetCallStack

 use /Oy option
==================
*/
void Sys_GetCallStack( address_t *callStack, const int callStackSize ) {
	int i = 0;
	while( i < callStackSize ) {
		callStack[i++] = 0;
	}
}

/*
==================
Sys_GetCallStackStr
==================
*/
const char *Sys_GetCallStackStr( const address_t *callStack, const int callStackSize ) {
	static char string[MAX_STRING_CHARS*2];
	int index, i;
	idStr module, funcName;

	index = 0;
	for ( i = callStackSize-1; i >= 0; i-- ) {
		Sym_GetFuncInfo( callStack[i], module, funcName );
		index += sprintf( string+index, " -> %s", funcName.c_str() );
	}
	return string;
}

/*
==================
Sys_GetCallStackCurStr
==================
*/
const char *Sys_GetCallStackCurStr( int depth ) {
	address_t *callStack;

	callStack = (address_t *) _alloca( depth * sizeof( address_t ) );
	Sys_GetCallStack( callStack, depth );
	return Sys_GetCallStackStr( callStack, depth );
}

/*
==================
Sys_GetCallStackCurAddressStr
==================
*/
const char *Sys_GetCallStackCurAddressStr( int depth ) {
	static char string[MAX_STRING_CHARS*2];
	address_t *callStack;
	int index, i;

	callStack = (address_t *) _alloca( depth * sizeof( address_t ) );
	Sys_GetCallStack( callStack, depth );

	index = 0;
	for ( i = depth-1; i >= 0; i-- ) {
		index += sprintf( string+index, " -> 0x%08x", callStack[i] );
	}
	return string;
}

/*
==================
Sys_ShutdownSymbols
==================
*/
void Sys_ShutdownSymbols() {
	Sym_Shutdown();
}
