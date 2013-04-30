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
#pragma hdrstop
#include "../../idlib/precompiled.h"
#include "../snd_local.h"

idCVar s_skipHardwareSets( "s_skipHardwareSets", "0", CVAR_BOOL, "Do all calculation, but skip XA2 calls" );
idCVar s_debugHardware( "s_debugHardware", "0", CVAR_BOOL, "Print a message any time a hardware voice changes" );

// The whole system runs at this sample rate
static int SYSTEM_SAMPLE_RATE = 44100;
static float ONE_OVER_SYSTEM_SAMPLE_RATE = 1.0f / SYSTEM_SAMPLE_RATE;

/*
========================
idStreamingVoiceContext
========================
*/
class idStreamingVoiceContext /* : public IXAudio2VoiceCallback */ {
public:
//	STDMETHOD_(void, OnVoiceProcessingPassStart)( UINT32 BytesRequired ) {}
//	STDMETHOD_(void, OnVoiceProcessingPassEnd)() {}
//	STDMETHOD_(void, OnStreamEnd)() {}
//	STDMETHOD_(void, OnBufferStart)( void * pContext ) {
//		idSoundSystemLocal::bufferContext_t * bufferContext = (idSoundSystemLocal::bufferContext_t *) pContext;
//		bufferContext->voice->OnBufferStart( bufferContext->sample, bufferContext->bufferNumber );
//	}
//	STDMETHOD_(void, OnLoopEnd)( void * ) {}
//	STDMETHOD_(void, OnVoiceError)( void *, HRESULT hr ) { idLib::Warning( "OnVoiceError( %d )", hr ); }
//	STDMETHOD_(void, OnBufferEnd)( void* pContext ) {
//		idSoundSystemLocal::bufferContext_t * bufferContext = (idSoundSystemLocal::bufferContext_t *) pContext;
//		soundSystemLocal.ReleaseStreamBufferContext( bufferContext );
//	}
} streamContext;

/*
========================
idSoundVoice_NULL::idSoundVoice_NULL
========================
*/
idSoundVoice_NULL::idSoundVoice_NULL()
:	//pSourceVoice( NULL ),
	leadinSample( NULL ),
	loopingSample( NULL ),
	formatTag( 0 ),
	numChannels( 0 ),
	sampleRate( 0 ),
	paused( true ),
	hasVUMeter( false ) {

}

/*
========================
idSoundVoice_NULL::~idSoundVoice_NULL
========================
*/
idSoundVoice_NULL::~idSoundVoice_NULL() {
	DestroyInternal();
}

/*
========================
idSoundVoice_NULL::CompatibleFormat
========================
*/
bool idSoundVoice_NULL::CompatibleFormat( idSoundSample_NULL * s ) {
	return false;
}

/*
========================
idSoundVoice_NULL::Create
========================
*/
void idSoundVoice_NULL::Create( const idSoundSample * leadinSample_, const idSoundSample * loopingSample_ ) {
	if ( IsPlaying() ) {
		// This should never hit
		Stop();
		return;
	}
	leadinSample = (idSoundSample_NULL *)leadinSample_;
	loopingSample = (idSoundSample_NULL *)loopingSample_;

	sourceVoiceRate = sampleRate;
}

/*
========================
idSoundVoice_NULL::DestroyInternal
========================
*/
void idSoundVoice_NULL::DestroyInternal() {
}

/*
========================
idSoundVoice_NULL::Start
========================
*/
void idSoundVoice_NULL::Start( int offsetMS, int ssFlags ) {

	// TODO: NULL implementation
	return;
#if 0
	if ( s_debugHardware.GetBool() ) {
		idLib::Printf( "%dms: %p starting %s @ %dms\n", Sys_Milliseconds(), pSourceVoice, leadinSample ? leadinSample->GetName() : "<null>", offsetMS );
	}

	if ( !leadinSample ) {
		return;
	}
	if ( !pSourceVoice ) {
		return;
	}

	if ( leadinSample->IsDefault() ) {
		idLib::Warning( "Starting defaulted sound sample %s", leadinSample->GetName() );
	}

	bool flicker = ( ssFlags & SSF_NO_FLICKER ) == 0;

	if ( flicker != hasVUMeter ) {
		hasVUMeter = flicker;

		if ( flicker ) {
			IUnknown * vuMeter = NULL;
			if ( XAudio2CreateVolumeMeter( &vuMeter, 0 ) == S_OK ) {

				XAUDIO2_EFFECT_DESCRIPTOR descriptor;
				descriptor.InitialState = true;
				descriptor.OutputChannels = leadinSample->NumChannels();
				descriptor.pEffect = vuMeter;

				XAUDIO2_EFFECT_CHAIN chain;
				chain.EffectCount = 1;
				chain.pEffectDescriptors = &descriptor;

				pSourceVoice->SetEffectChain( &chain );

				vuMeter->Release();
			}
		} else {
			pSourceVoice->SetEffectChain( NULL );
		}
	}

	assert( offsetMS >= 0 );
	int offsetSamples = MsecToSamples( offsetMS, leadinSample->SampleRate() );
	if ( loopingSample == NULL && offsetSamples >= leadinSample->playLength ) {
		return;
	}

	RestartAt( offsetSamples );
	Update();
	UnPause();
#endif
}

/*
========================
idSoundVoice_NULL::RestartAt
========================
*/
int idSoundVoice_NULL::RestartAt( int offsetSamples ) {
	offsetSamples &= ~127;

	idSoundSample_NULL * sample = leadinSample;
	if ( offsetSamples >= leadinSample->playLength ) {
		if ( loopingSample != NULL ) {
			offsetSamples %= loopingSample->playLength;
			sample = loopingSample;
		} else {
			return 0;
		}
	}

	int previousNumSamples = 0;
	for ( int i = 0; i < sample->buffers.Num(); i++ ) {
		if ( sample->buffers[i].numSamples > sample->playBegin + offsetSamples ) {
			return SubmitBuffer( sample, i, sample->playBegin + offsetSamples - previousNumSamples );
		}
		previousNumSamples = sample->buffers[i].numSamples;
	}

	return 0;
}

/*
========================
idSoundVoice_NULL::SubmitBuffer
======================== 
*/
int idSoundVoice_NULL::SubmitBuffer( idSoundSample_NULL * sample, int bufferNumber, int offset ) {
	return 0;
}

/*
========================
idSoundVoice_NULL::Update
========================
*/
bool idSoundVoice_NULL::Update() {
	return true;
}

/*
========================
idSoundVoice_NULL::IsPlaying
========================
*/
bool idSoundVoice_NULL::IsPlaying() {
	return false;
}

/*
========================
idSoundVoice_NULL::FlushSourceBuffers
========================
*/
void idSoundVoice_NULL::FlushSourceBuffers() {
}

/*
========================
idSoundVoice_NULL::Pause
========================
*/
void idSoundVoice_NULL::Pause() {
	paused = true;
}

/*
========================
idSoundVoice_NULL::UnPause
========================
*/
void idSoundVoice_NULL::UnPause() {
	paused = false;
}

/*
========================
idSoundVoice_NULL::Stop
========================
*/
void idSoundVoice_NULL::Stop() {
	if ( !paused ) {
		if ( s_debugHardware.GetBool() ) {
//			idLib::Printf( "%dms: %p stopping %s\n", Sys_Milliseconds(), pSourceVoice, leadinSample ? leadinSample->GetName() : "<null>" );
		}
		paused = true;
	}
}

/*
========================
idSoundVoice_NULL::GetAmplitude
========================
*/
float idSoundVoice_NULL::GetAmplitude() {
	if ( !hasVUMeter ) {
		return 1.0f;
	}

	return 1.0f;
}

/*
========================
idSoundVoice_NULL::ResetSampleRate
========================
*/
void idSoundVoice_NULL::SetSampleRate( uint32 newSampleRate, uint32 operationSet ){
}

/*
========================
idSoundVoice_NULL::OnBufferStart
========================
*/
void idSoundVoice_NULL::OnBufferStart( idSoundSample_NULL * sample, int bufferNumber ) {
}
