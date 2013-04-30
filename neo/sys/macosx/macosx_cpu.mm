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
#import <mach-o/arch.h>
#import <sys/sysctl.h>

/*
==============================================================

	Clock ticks

==============================================================
*/

/*
================
Sys_GetClockTicks
================
*/
double Sys_GetClockTicks() {
	// TODO: this might be wrong
	// currently returning an estimate of the number of CPU cycles
	return ( Sys_ClockTicksPerSecond() * ( (double)(Sys_Microseconds()+0.5) * 0.000001 ) );
}

/*
================
Sys_ClockTicksPerSecond
================
*/
double Sys_ClockTicksPerSecond() {
	static double ticks = 0;
	static uint64_t freq = 0;
    size_t size = sizeof(freq);

	if ( !ticks ) {
		if ( sysctlbyname( "hw.cpufrequency", &freq, &size, NULL, 0 ) == 0 ) {
			ticks = (double)freq;
		} else {
			perror("sysctl");
		}
	}

	return ticks;
}


/*
==============================================================

	CPU

==============================================================
*/

/*
================
HasCPUID
================
*/
static bool HasCPUID() {
#if defined( __i386__ ) && defined( _WIN32 )
	__asm
	{
		pushfd						// save eflags
		pop		eax
		test	eax, 0x00200000		// check ID bit
		jz		set21				// bit 21 is not set, so jump to set_21
		and		eax, 0xffdfffff		// clear bit 21
		push	eax					// save new value in register
		popfd						// store new value in flags
		pushfd
		pop		eax
		test	eax, 0x00200000		// check ID bit
		jz		good
		jmp		err					// cpuid not supported
set21:
		or		eax, 0x00200000		// set ID bit
		push	eax					// store new value
		popfd						// store new value in EFLAGS
		pushfd
		pop		eax
		test	eax, 0x00200000		// if bit 21 is on
		jnz		good
		jmp		err
	}

err:
	return false;
good:
	return true;
#else
#warning implement HasCPUID
	return false;
#endif // __i386__ _WIN32
}

#define _REG_EAX		0
#define _REG_EBX		1
#define _REG_ECX		2
#define _REG_EDX		3

/*
================
CPUID
================
*/
static void CPUID( int func, unsigned regs[4] ) {
	unsigned regEAX, regEBX, regECX, regEDX;
#if defined( __i386__ ) && defined( _WIN32 )
	__asm pusha
	__asm mov eax, func
	__asm __emit 00fh
	__asm __emit 0a2h
	__asm mov regEAX, eax
	__asm mov regEBX, ebx
	__asm mov regECX, ecx
	__asm mov regEDX, edx
	__asm popa

	regs[_REG_EAX] = regEAX;
	regs[_REG_EBX] = regEBX;
	regs[_REG_ECX] = regECX;
	regs[_REG_EDX] = regEDX;
#else
#warning implement CPUID
#endif // __i386__ _WIN32
}


/*
================
IsAMD
================
*/
static bool IsAMD() {
	char pstring[16];
	char processorString[13];

	// get name of processor
	CPUID( 0, ( unsigned int * ) pstring );
	processorString[0] = pstring[4];
	processorString[1] = pstring[5];
	processorString[2] = pstring[6];
	processorString[3] = pstring[7];
	processorString[4] = pstring[12];
	processorString[5] = pstring[13];
	processorString[6] = pstring[14];
	processorString[7] = pstring[15];
	processorString[8] = pstring[8];
	processorString[9] = pstring[9];
	processorString[10] = pstring[10];
	processorString[11] = pstring[11];
	processorString[12] = 0;

	if ( strcmp( processorString, "AuthenticAMD" ) == 0 ) {
		return true;
	}
	return false;
}

/*
================
HasCMOV
================
*/
static bool HasCMOV() {
	unsigned regs[4];

	// get CPU feature bits
	CPUID( 1, regs );

	// bit 15 of EDX denotes CMOV existence
	if ( regs[_REG_EDX] & ( 1 << 15 ) ) {
		return true;
	}
	return false;
}

/*
================
Has3DNow
================
*/
static bool Has3DNow() {
	unsigned regs[4];

	// check AMD-specific functions
	CPUID( 0x80000000, regs );
	if ( regs[_REG_EAX] < 0x80000000 ) {
		return false;
	}

	// bit 31 of EDX denotes 3DNow! support
	CPUID( 0x80000001, regs );
	if ( regs[_REG_EDX] & ( 1 << 31 ) ) {
		return true;
	}

	return false;
}

/*
================
HasMMX
================
*/
static bool HasMMX() {
	unsigned regs[4];

	// get CPU feature bits
	CPUID( 1, regs );

	// bit 23 of EDX denotes MMX existence
	if ( regs[_REG_EDX] & ( 1 << 23 ) ) {
		return true;
	}
	return false;
}

/*
================
HasSSE
================
*/
static bool HasSSE() {
	unsigned regs[4];

	// get CPU feature bits
	CPUID( 1, regs );

	// bit 25 of EDX denotes SSE existence
	if ( regs[_REG_EDX] & ( 1 << 25 ) ) {
		return true;
	}
	return false;
}

/*
================
HasSSE2
================
*/
static bool HasSSE2() {
	unsigned regs[4];

	// get CPU feature bits
	CPUID( 1, regs );

	// bit 26 of EDX denotes SSE2 existence
	if ( regs[_REG_EDX] & ( 1 << 26 ) ) {
		return true;
	}
	return false;
}

/*
================
HasSSE3
================
*/
static bool HasSSE3() {
	unsigned regs[4];

	// get CPU feature bits
	CPUID( 1, regs );

	// bit 0 of ECX denotes SSE3 existence
	if ( regs[_REG_ECX] & ( 1 << 0 ) ) {
		return true;
	}
	return false;
}

/*
================
LogicalProcPerPhysicalProc
================
*/
#define NUM_LOGICAL_BITS   0x00FF0000     // EBX[23:16] Bit 16-23 in ebx contains the number of logical
                                          // processors per physical processor when execute cpuid with 
                                          // eax set to 1
static unsigned char LogicalProcPerPhysicalProc() {
#if defined( __i386__ )
	unsigned int regebx = 0;
	__asm {
		mov eax, 1
		cpuid
		mov regebx, ebx
	}
	return (unsigned char) ((regebx & NUM_LOGICAL_BITS) >> 16);
#else
#warning implement LogicalProcPerPhysicalProc
	return 0;
#endif // __i386__
}

/*
================
GetAPIC_ID
================
*/
#define INITIAL_APIC_ID_BITS  0xFF000000  // EBX[31:24] Bits 24-31 (8 bits) return the 8-bit unique 
                                          // initial APIC ID for the processor this code is running on.
                                          // Default value = 0xff if HT is not supported
static unsigned char GetAPIC_ID() {
#if defined( __i386__ )
	unsigned int regebx = 0;
	__asm {
		mov eax, 1
		cpuid
		mov regebx, ebx
	}
	return (unsigned char) ((regebx & INITIAL_APIC_ID_BITS) >> 24);
#else
#warning implement GetAPIC_ID
	return 0;
#endif
}

/*
================
CPUCount

	logicalNum is the number of logical CPU per physical CPU
    physicalNum is the total number of physical processor
	returns one of the HT_* flags
================
*/
#define HT_NOT_CAPABLE				0
#define HT_ENABLED					1
#define HT_DISABLED					2
#define HT_SUPPORTED_NOT_ENABLED	3
#define HT_CANNOT_DETECT			4

int CPUCount( int &logicalNum, int &physicalNum ) {
#warning implement CPUCount
	return 0;
}

/*
================
HasHTT
================
*/
static bool HasHTT() {
	return false;
}

/*
================
HasDAZ
================
*/
static bool HasDAZ() {
	return false;
}

/*
================================================================================================

	CPU

================================================================================================
*/


enum LOGICAL_PROCESSOR_RELATIONSHIP_LOCAL {
    localRelationProcessorCore,
    localRelationNumaNode,
    localRelationCache,
	localRelationProcessorPackage
};

struct cpuInfo_t {
	int processorPackageCount;
	int processorCoreCount;
	int logicalProcessorCount;
	int numaNodeCount;
	struct cacheInfo_t {
		int count;
		int associativity;
		int lineSize;
		int size;
	} cacheLevel[3];
};

/*
========================
GetCPUInfo
========================
*/
bool GetCPUInfo( cpuInfo_t & cpuInfo ) {
#warning implement GetCPUInfo
	return true;
}

/*
========================
Sys_GetCPUCacheSize
========================
*/
void Sys_GetCPUCacheSize( int level, int & count, int & size, int & lineSize ) {
//	assert( level >= 1 && level <= 3 );
//	cpuInfo_t cpuInfo;
//
//	GetCPUInfo( cpuInfo );
//
//	count = cpuInfo.cacheLevel[level - 1].count;
//	size = cpuInfo.cacheLevel[level - 1].size;
//	lineSize = cpuInfo.cacheLevel[level - 1].lineSize;
#warning implement Sys_GetCPUCacheSize
}

/*
========================
Sys_CPUCount

numLogicalCPUCores	- the number of logical CPU per core
numPhysicalCPUCores	- the total number of cores per package
numCPUPackages		- the total number of packages (physical processors)
========================
*/
void Sys_CPUCount( int & numLogicalCPUCores, int & numPhysicalCPUCores, int & numCPUPackages ) {
//	cpuInfo_t cpuInfo;
//	GetCPUInfo( cpuInfo );
//
//	numPhysicalCPUCores = cpuInfo.processorCoreCount;
//	numLogicalCPUCores = cpuInfo.logicalProcessorCount;
//	numCPUPackages = cpuInfo.processorPackageCount;
#warning implement Sys_CPUCount
}

/*
================
Sys_GetCPUId
================
*/
cpuid_t Sys_GetCPUId() {
	int flags;

	// verify we're at least a Pentium or 486 with CPUID support
	if ( !HasCPUID() ) {
		return CPUID_UNSUPPORTED;
	}

	// check for an AMD
	if ( IsAMD() ) {
		flags = CPUID_AMD;
	} else {
		flags = CPUID_INTEL;
	}

	// check for Multi Media Extensions
	if ( HasMMX() ) {
		flags |= CPUID_MMX;
	}

	// check for 3DNow!
	if ( Has3DNow() ) {
		flags |= CPUID_3DNOW;
	}

	// check for Streaming SIMD Extensions
	if ( HasSSE() ) {
		flags |= CPUID_SSE | CPUID_FTZ;
	}

	// check for Streaming SIMD Extensions 2
	if ( HasSSE2() ) {
		flags |= CPUID_SSE2;
	}

	// check for Streaming SIMD Extensions 3 aka Prescott's New Instructions
	if ( HasSSE3() ) {
		flags |= CPUID_SSE3;
	}

	// check for Hyper-Threading Technology
	if ( HasHTT() ) {
		flags |= CPUID_HTT;
	}

	// check for Conditional Move (CMOV) and fast floating point comparison (FCOMI) instructions
	if ( HasCMOV() ) {
		flags |= CPUID_CMOV;
	}

	// check for Denormals-Are-Zero mode
	if ( HasDAZ() ) {
		flags |= CPUID_DAZ;
	}

	return (cpuid_t)flags;
}


/*
===============================================================================

	FPU

===============================================================================
*/

typedef struct bitFlag_s {
	char *		name;
	int			bit;
} bitFlag_t;

static byte fpuState[128], *statePtr = fpuState;
static char fpuString[2048];
static bitFlag_t controlWordFlags[] = {
	{ "Invalid operation", 0 },
	{ "Denormalized operand", 1 },
	{ "Divide-by-zero", 2 },
	{ "Numeric overflow", 3 },
	{ "Numeric underflow", 4 },
	{ "Inexact result (precision)", 5 },
	{ "Infinity control", 12 },
	{ "", 0 }
};
static char *precisionControlField[] = {
	"Single Precision (24-bits)",
	"Reserved",
	"Double Precision (53-bits)",
	"Double Extended Precision (64-bits)"
};
static char *roundingControlField[] = {
	"Round to nearest",
	"Round down",
	"Round up",
	"Round toward zero"
};
static bitFlag_t statusWordFlags[] = {
	{ "Invalid operation", 0 },
	{ "Denormalized operand", 1 },
	{ "Divide-by-zero", 2 },
	{ "Numeric overflow", 3 },
	{ "Numeric underflow", 4 },
	{ "Inexact result (precision)", 5 },
	{ "Stack fault", 6 },
	{ "Error summary status", 7 },
	{ "FPU busy", 15 },
	{ "", 0 }
};

/*
===============
Sys_FPU_PrintStateFlags
===============
*/
int Sys_FPU_PrintStateFlags( char *ptr, int ctrl, int stat, int tags, int inof, int inse, int opof, int opse ) {
	int i, length = 0;

	length += sprintf( ptr+length,	"CTRL = %08x\n"
									"STAT = %08x\n"
									"TAGS = %08x\n"
									"INOF = %08x\n"
									"INSE = %08x\n"
									"OPOF = %08x\n"
									"OPSE = %08x\n"
									"\n",
									ctrl, stat, tags, inof, inse, opof, opse );

	length += sprintf( ptr+length, "Control Word:\n" );
	for ( i = 0; controlWordFlags[i].name[0]; i++ ) {
		length += sprintf( ptr+length, "  %-30s = %s\n", controlWordFlags[i].name, ( ctrl & ( 1 << controlWordFlags[i].bit ) ) ? "true" : "false" );
	}
	length += sprintf( ptr+length, "  %-30s = %s\n", "Precision control", precisionControlField[(ctrl>>8)&3] );
	length += sprintf( ptr+length, "  %-30s = %s\n", "Rounding control", roundingControlField[(ctrl>>10)&3] );

	length += sprintf( ptr+length, "Status Word:\n" );
	for ( i = 0; statusWordFlags[i].name[0]; i++ ) {
		ptr += sprintf( ptr+length, "  %-30s = %s\n", statusWordFlags[i].name, ( stat & ( 1 << statusWordFlags[i].bit ) ) ? "true" : "false" );
	}
	length += sprintf( ptr+length, "  %-30s = %d%d%d%d\n", "Condition code", (stat>>8)&1, (stat>>9)&1, (stat>>10)&1, (stat>>14)&1 );
	length += sprintf( ptr+length, "  %-30s = %d\n", "Top of stack pointer", (stat>>11)&7 );

	return length;
}

/*
===============
Sys_FPU_StackIsEmpty
===============
*/
bool Sys_FPU_StackIsEmpty() {
#if defined( __i386__ ) && defined( _WIN32 )
	__asm {
		mov			eax, statePtr
		fnstenv		[eax]
		mov			eax, [eax+8]
		xor			eax, 0xFFFFFFFF
		and			eax, 0x0000FFFF
		jz			empty
	}
	return false;
empty:
	return true;
#else
	return true;
#warning implement Sys_FPU_StackIsEmpty
#endif // __i386__ _WIN32
}

/*
===============
Sys_FPU_ClearStack
===============
*/
void Sys_FPU_ClearStack() {
#if defined( __i386__ ) && defined( _WIN32 )
	__asm {
		mov			eax, statePtr
		fnstenv		[eax]
		mov			eax, [eax+8]
		xor			eax, 0xFFFFFFFF
		mov			edx, (3<<14)
	emptyStack:
		mov			ecx, eax
		and			ecx, edx
		jz			done
		fstp		st
		shr			edx, 2
		jmp			emptyStack
	done:
	}
#else
#warning implement Sys_FPU_ClearStack
#endif // __i386__ _WIN32
}

/*
===============
Sys_FPU_GetState

  gets the FPU state without changing the state
===============
*/
const char *Sys_FPU_GetState() {
	return ""; // NULL?
}

/*
===============
Sys_FPU_EnableExceptions
===============
*/
void Sys_FPU_EnableExceptions( int exceptions ) {
}

/*
===============
Sys_FPU_SetPrecision
===============
*/
void Sys_FPU_SetPrecision( int precision ) {
}

/*
================
Sys_FPU_SetRounding
================
*/
void Sys_FPU_SetRounding( int rounding ) {
}

/*
================
Sys_FPU_SetDAZ
================
*/
void Sys_FPU_SetDAZ( bool enable ) {
}

/*
================
Sys_FPU_SetFTZ
================
*/
void Sys_FPU_SetFTZ( bool enable ) {
}
