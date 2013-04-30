/*
===========================================================================

Doom 3 BFG Edition GPL Source Code
Copyright (C) 1993-2012 id Software LLC, a ZeniMax Media company. 
Copyright (C) 2012-2013 Robert Beckebans
Copyright (C) 2013 Daniel Gibson

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
#pragma hdrstop
#include "../../precompiled.h"

#if defined( __FreeBSD__ )
// for pthread_set_name_np
#include <pthread_ng.h>
#endif // __FreeBSD__

#if defined( __MACH__ )
//#include <pthread.h>
static int clock_gettime(int clk_id, struct timespec* t) {
    struct timeval now;
    int rv = gettimeofday(&now, NULL);
    if (rv) return rv;
    t->tv_sec  = now.tv_sec;
    t->tv_nsec = now.tv_usec * 1000;
    return 0;
}
#endif // __MACH__

/*
================================================================================================
================================================================================================
*/

/*
========================
Sys_SetThreadName
========================
*/
void Sys_SetThreadName( pthread_t thread, const char * name ) {
	// TODO: verify this can set the thread name beyond
	pthread_setname_np( name );
}

/*
========================
Sys_SetCurrentThreadName
========================
*/
void Sys_SetCurrentThreadName( const char * name ) {
	Sys_SetThreadName( (pthread_t)Sys_GetCurrentThreadID(), name ); // TODO: current thread
}

/*
========================
Sys_Createthread
========================
*/
uintptr_t Sys_CreateThread( xthread_t function, void *parms, xthreadPriority priority, const char *name, core_t core, int stackSize, bool suspended ) {
	pthread_attr_t attr;
	pthread_t handle;
	pthread_attr_init( &attr );

	if( pthread_attr_setdetachstate( &attr, PTHREAD_CREATE_JOINABLE ) != 0 ) {
		idLib::common->FatalError( "ERROR: pthread_attr_setdetachstate %s failed\n", name );
		return (uintptr_t)0;
	}

	if( pthread_create( ( pthread_t* )&handle, &attr, ( void *(*)(void *) )function, parms ) != 0 ) {
		idLib::common->FatalError( "ERROR: pthread_create %s failed\n", name );
		return (uintptr_t)0;
	}

#if defined(DEBUG_THREADS)
	if( Sys_SetThreadName( handle, name ) != 0 ) {
		idLib::common->Warning( "Warning: pthread_setname_np %s failed\n", name );
		return (uintptr_t)0;
	}
#endif

	pthread_attr_destroy( &attr );

	// unix does not set the thread affinity -- let the OS deal with scheduling
	return (uintptr_t)handle;
}


/*
========================
Sys_GetCurrentThreadID
========================
*/
uintptr_t Sys_GetCurrentThreadID() {
	return (uintptr_t)pthread_self();
}

/*
========================
Sys_WaitForThread
========================
*/
void Sys_WaitForThread( uintptr_t threadHandle ) {
	// TODO: unix wait for thread
}

/*
========================
Sys_DestroyThread
========================
*/
void Sys_DestroyThread( uintptr_t threadHandle ) {
	char	name[128] = {0};
	if( threadHandle == 0 ) {
		return;
	}

#if defined(DEBUG_THREADS)
	pthread_getname_np( threadHandle, name, sizeof( name ) );
#endif

	if( pthread_join( ( pthread_t )threadHandle, NULL ) != 0 ) {
		idLib::common->FatalError( "ERROR: pthread_join %s failed\n", name );
	}
}

/*
========================
Sys_Yield
========================
*/
void Sys_Yield() {
#if defined( __MACH__ )
	sched_yield();
#else
	pthread_yield();
#endif // __MACH__
}

/*
================================================================================================

	Signal

================================================================================================
*/

/*
========================
Sys_SignalCreate
========================
*/
void Sys_SignalCreate( signalHandle_t & handle, bool manualReset ) {
	handle.manualReset = manualReset;
	// if this is true, the signal is only set to nonsignaled when Clear() is called,
	// else it's "auto-reset" and the state is set to !signaled after a single waiting
	// thread has been released

	// the inital state is always "not signaled"
	handle.signaled = false;
	handle.waiting = 0;

	pthread_mutex_init( &handle.mutex, NULL );
	pthread_cond_init( &handle.cond, NULL );
}

/*
========================
Sys_SignalDestroy
========================
*/
void Sys_SignalDestroy( signalHandle_t &handle ) {
	handle.signaled = false;
	handle.waiting = 0;
	pthread_mutex_destroy( &handle.mutex );
	pthread_cond_destroy( &handle.cond );
}

/*
========================
Sys_SignalRaise
========================
*/
void Sys_SignalRaise( signalHandle_t & handle ) {
	pthread_mutex_lock( &handle.mutex );

	if( handle.manualReset ) {
		// signaled until reset
		handle.signaled = true;
		// wake *all* threads waiting on this cond
		pthread_cond_broadcast( &handle.cond );
	} else {
		// automode: signaled until first thread is released
		if( handle.waiting > 0 ) {
			// there are waiting threads => release one
			pthread_cond_signal( &handle.cond );
		} else {
			// no waiting threads, save signal
			handle.signaled = true;
			// while the MSDN documentation is a bit unspecific about what happens
			// when SetEvent() is called n times without a wait inbetween
			// (will only one wait be successful afterwards or n waits?)
			// it seems like the signaled state is a flag, not a counter.
			// http://stackoverflow.com/a/13703585 claims the same.
		}
	}

	pthread_mutex_unlock( &handle.mutex );
}

/*
========================
Sys_SignalClear
========================
*/
void Sys_SignalClear( signalHandle_t & handle ) {
	// events are created as auto-reset so this should never be needed
	pthread_mutex_lock( &handle.mutex );
	// TODO: probably signaled could be atomically changed?
	handle.signaled = false;
	pthread_mutex_unlock( &handle.mutex );
}

/*
========================
Sys_SignalWait
========================
*/
bool Sys_SignalWait( signalHandle_t & handle, int timeout ) {
	int status;
	pthread_mutex_lock( &handle.mutex );

	if( handle.signaled ) {
		// there is a signal that hasn't been used yet
		if( ! handle.manualReset ) // for auto-mode only one thread may be released - this one.
			handle.signaled = false;

		status = 0; // success!
	} else {
		// we'll have to wait for a signal
		++handle.waiting;
		if( timeout == idSysSignal::WAIT_INFINITE ) {
			status = pthread_cond_wait( &handle.cond, &handle.mutex );
		} else {
			timespec ts;
			clock_gettime( CLOCK_REALTIME, &ts );
			ts.tv_nsec += ( timeout % 1000 ) * 1000000; // millisec to nanosec
			ts.tv_sec  += timeout / 1000;

			// nanoseconds are more than one second
			if( ts.tv_nsec >= 1000000000 ) {
				ts.tv_nsec -= 1000000000;	// remove one second in nanoseconds
				ts.tv_sec += 1;				// add one second to seconds
			}

			status = pthread_cond_timedwait( &handle.cond, &handle.mutex, &ts );
		}
		--handle.waiting;
	}

	pthread_mutex_unlock( &handle.mutex );

	assert( status == 0 || ( timeout != idSysSignal::WAIT_INFINITE && status == ETIMEDOUT ) );

	return ( status == 0 );
}

/*
================================================================================================

	Mutex

================================================================================================
*/

/*
========================
Sys_MutexCreate
========================
*/
void Sys_MutexCreate( mutexHandle_t & handle ) {
	pthread_mutexattr_t attr;

	pthread_mutexattr_init( &attr );
	pthread_mutexattr_settype( &attr, PTHREAD_MUTEX_ERRORCHECK );
	pthread_mutex_init( &handle, &attr );

	pthread_mutexattr_destroy( &attr );
}

/*
========================
Sys_MutexDestroy
========================
*/
void Sys_MutexDestroy( mutexHandle_t & handle ) {
	pthread_mutex_destroy( &handle );
}

/*
========================
Sys_MutexLock
========================
*/
bool Sys_MutexLock( mutexHandle_t & handle, bool blocking ) {
	if ( pthread_mutex_trylock( &handle ) != 0 ) {
		if ( !blocking ) {
			return false;
		}
		pthread_mutex_lock( &handle );
	}
	return true;
}

/*
========================
Sys_MutexUnlock
========================
*/
void Sys_MutexUnlock( mutexHandle_t & handle ) {
	pthread_mutex_unlock( & handle );
}

/*
================================================================================================

	Interlocked Integer

================================================================================================
*/

/*
========================
Sys_InterlockedIncrement
========================
*/
interlockedInt_t Sys_InterlockedIncrement( interlockedInt_t & value ) {
	return __sync_add_and_fetch( &value, 1 );
}

/*
========================
Sys_InterlockedDecrement
========================
*/
interlockedInt_t Sys_InterlockedDecrement( interlockedInt_t & value ) {
	return __sync_sub_and_fetch( &value, 1 );
}

/*
========================
Sys_InterlockedAdd
========================
*/
interlockedInt_t Sys_InterlockedAdd( interlockedInt_t & value, interlockedInt_t i ) {
	return __sync_add_and_fetch( &value, i );
}

/*
========================
Sys_InterlockedSub
========================
*/
interlockedInt_t Sys_InterlockedSub( interlockedInt_t & value, interlockedInt_t i ) {
	return __sync_sub_and_fetch( &value, i );
}

/*
========================
Sys_InterlockedExchange
========================
*/
interlockedInt_t Sys_InterlockedExchange( interlockedInt_t & value, interlockedInt_t exchange ) {
	// source: http://gcc.gnu.org/onlinedocs/gcc-4.1.1/gcc/Atomic-Builtins.html
	// These builtins perform an atomic compare and swap. That is, if the current value of *ptr is oldval, then write newval into *ptr.
	return __sync_val_compare_and_swap( &value, value, exchange );
}

/*
========================
Sys_InterlockedCompareExchange
========================
*/
interlockedInt_t Sys_InterlockedCompareExchange( interlockedInt_t & value, interlockedInt_t comparand, interlockedInt_t exchange ) {
	return __sync_val_compare_and_swap( &value, comparand, exchange );
}

/*
================================================================================================

	Interlocked Pointer

================================================================================================
*/

/*
========================
Sys_InterlockedExchangePointer
========================
*/
void *Sys_InterlockedExchangePointer( void *& ptr, void * exchange ) {
	return __sync_val_compare_and_swap( &ptr, ptr, exchange );
}

/*
========================
Sys_InterlockedCompareExchangePointer
========================
*/
void * Sys_InterlockedCompareExchangePointer( void * & ptr, void * comparand, void * exchange ) {
	return __sync_val_compare_and_swap( &ptr, comparand, exchange );
}
