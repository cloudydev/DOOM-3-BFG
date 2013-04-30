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
================================================================================================

Contains the windows implementation of the network session

================================================================================================
*/

#pragma hdrstop
#include "../../idlib/precompiled.h"
#include "../../framework/Common_local.h"
#include "../sys_session_local.h"
#include "../sys_stats.h"
#include "../sys_savegame.h"
#include "../sys_lobby_backend_direct.h"
#include "../sys_voicechat.h"
#include "null_achievements.h"
#include "null_signin.h"

/*
========================
Global variables
========================
*/

extern idCVar net_port;

class idLobbyToSessionCBLocal;

/*
========================
idSessionLocalNULL::idSessionLocalNULL
========================
*/
class idSessionLocalNULL : public idSessionLocal {
friend class idLobbyToSessionCBLocal;
	
public:
	idSessionLocalNULL();
	virtual ~idSessionLocalNULL();
	
	// idSessionLocal interface
	virtual void		Initialize();
	virtual void		Shutdown();
	
	virtual void		InitializeSoundRelatedSystems();
	virtual void		ShutdownSoundRelatedSystems();
	
	virtual void		PlatformPump();
	
	virtual void		InviteFriends();
	virtual void		InviteParty();
	virtual void		ShowPartySessions();
	
	virtual void		ShowSystemMarketplaceUI() const;
	
	virtual void					ListServers( const idCallback & callback );
	virtual void					CancelListServers();
	virtual int						NumServers() const;
	virtual const serverInfo_t * 	ServerInfo( int i ) const;
	virtual void					ConnectToServer( int i );
	virtual void					ShowServerGamerCardUI( int i );
	
	virtual void			ShowLobbyUserGamerCardUI( lobbyUserID_t lobbyUserID );
	
	virtual void			ShowOnlineSignin() {}
	virtual void			UpdateRichPresence() {}
	virtual void			CheckVoicePrivileges() {}
	
	virtual bool			ProcessInputEvent( const sysEvent_t * ev );
	
	// System UI
	virtual bool			IsSystemUIShowing() const;
	virtual void			SetSystemUIShowing( bool show );
	
	// Invites
	virtual void			HandleBootableInvite( int64 lobbyId = 0 );
	virtual void			ClearBootableInvite();
	virtual void			ClearPendingInvite();
	
	virtual bool			HasPendingBootableInvite();
	virtual void			SetDiscSwapMPInvite( void * parm );
	virtual void * 			GetDiscSwapMPInviteParms();
	
	virtual void			EnumerateDownloadableContent();
	
	virtual void 			HandleServerQueryRequest( lobbyAddress_t & remoteAddr, idBitMsg & msg, int msgType );
	virtual void 			HandleServerQueryAck( lobbyAddress_t & remoteAddr, idBitMsg & msg );
	
	// Leaderboards
	virtual void			LeaderboardUpload( lobbyUserID_t lobbyUserID, const leaderboardDefinition_t * leaderboard, const column_t * stats, const idFile_Memory * attachment = NULL );
	virtual void			LeaderboardDownload( int sessionUserIndex, const leaderboardDefinition_t * leaderboard, int startingRank, int numRows, const idLeaderboardCallback & callback );
	virtual void			LeaderboardDownloadAttachment( int sessionUserIndex, const leaderboardDefinition_t * leaderboard, int64 attachmentID );
	
	// Scoring (currently just for TrueSkill)
	virtual void			SetLobbyUserRelativeScore( lobbyUserID_t lobbyUserID, int relativeScore, int team ) {}
	
	virtual void			LeaderboardFlush();
	
	virtual idNetSessionPort & 	GetPort( bool dedicated = false );
	virtual idLobbyBackend * 	CreateLobbyBackend( const idMatchParameters & p, float skillLevel, idLobbyBackend::lobbyBackendType_t lobbyType );
	virtual idLobbyBackend * 	FindLobbyBackend( const idMatchParameters & p, int numPartyUsers, float skillLevel, idLobbyBackend::lobbyBackendType_t lobbyType );
	virtual idLobbyBackend * 	JoinFromConnectInfo( const lobbyConnectInfo_t & connectInfo , idLobbyBackend::lobbyBackendType_t lobbyType );
	virtual void				DestroyLobbyBackend( idLobbyBackend * lobbyBackend );
	virtual void				PumpLobbies();
	virtual void				JoinAfterSwap( void * joinID );
	
	virtual bool				GetLobbyAddressFromNetAddress( const netadr_t & netAddr, lobbyAddress_t & outAddr ) const;
	virtual bool				GetNetAddressFromLobbyAddress( const lobbyAddress_t & lobbyAddress, netadr_t & outNetAddr ) const;
	
public:
	void	Connect_f( const idCmdArgs & args );
	
private:
	void					EnsurePort();
	
	idLobbyBackend * 		CreateLobbyInternal( idLobbyBackend::lobbyBackendType_t lobbyType );
	
	idArray< idLobbyBackend *, 3 > lobbyBackends;
	
	idNetSessionPort		port;
	bool					canJoinLocalHost;
	
	idLobbyToSessionCBLocal *	 lobbyToSessionCB;
};

idSessionLocalNULL sessionLocalWin;
idSession * session =  &sessionLocalWin;

/*
========================
idLobbyToSessionCBLocal
========================
*/
class idLobbyToSessionCBLocal : public idLobbyToSessionCB {
public:
	idLobbyToSessionCBLocal( idSessionLocalNULL * sessionLocalWin_ ) : sessionLocalWin( sessionLocalWin_ ) { }
	
	virtual bool CanJoinLocalHost() const { sessionLocalWin->EnsurePort(); return sessionLocalWin->canJoinLocalHost; }
	virtual class idLobbyBackend * GetLobbyBackend( idLobbyBackend::lobbyBackendType_t type ) const { return sessionLocalWin->lobbyBackends[ type ]; }

private:
	idSessionLocalNULL * 			sessionLocalWin;
};

idLobbyToSessionCBLocal lobbyToSessionCBLocal( &sessionLocalWin );
idLobbyToSessionCB * lobbyToSessionCB = &lobbyToSessionCBLocal;

class idVoiceChatMgrNULL : public idVoiceChatMgr {
public:
	virtual bool	GetLocalChatDataInternal( int talkerIndex, byte * data, int & dataSize ) { return false; }
	virtual void	SubmitIncomingChatDataInternal( int talkerIndex, const byte * data, int dataSize ) { }
	virtual bool	TalkerHasData( int talkerIndex ) { return false; }
	virtual bool	RegisterTalkerInternal( int index ) { return true; }
	virtual void	UnregisterTalkerInternal( int index ) { }
};

/*
========================
idSessionLocalNULL::idSessionLocalNULL
========================
*/
idSessionLocalNULL::idSessionLocalNULL()
{
	signInManager		= new ( TAG_SYSTEM ) idSignInManagerNULL;
	saveGameManager		= new ( TAG_SAVEGAMES ) idSaveGameManager();
	voiceChat			= new ( TAG_SYSTEM ) idVoiceChatMgrNULL();
	lobbyToSessionCB	= new ( TAG_SYSTEM ) idLobbyToSessionCBLocal( this );
	
	canJoinLocalHost	= false;
	
	lobbyBackends.Zero();
}

/*
========================
idSessionLocalNULL::~idSessionLocalNULL
========================
*/
idSessionLocalNULL::~idSessionLocalNULL() {
	delete voiceChat;
	delete lobbyToSessionCB;
}

/*
========================
idSessionLocalNULL::Initialize
========================
*/
void idSessionLocalNULL::Initialize() {
	idSessionLocal::Initialize();
	
	// The shipping path doesn't load title storage
	// Instead, we inject values through code which is protected through steam DRM
	titleStorageVars.Set( "MAX_PLAYERS_ALLOWED", "8" );
	titleStorageLoaded = true;
	
	// First-time check for downloadable content once game is launched
	EnumerateDownloadableContent();
	
	GetPartyLobby().Initialize( idLobby::TYPE_PARTY, sessionCallbacks );
	GetGameLobby().Initialize( idLobby::TYPE_GAME, sessionCallbacks );
	GetGameStateLobby().Initialize( idLobby::TYPE_GAME_STATE, sessionCallbacks );
	
	achievementSystem = new ( TAG_SYSTEM ) idAchievementSystemNULL();
	achievementSystem->Init();
}

/*
========================
idSessionLocalNULL::Shutdown
========================
*/
void idSessionLocalNULL::Shutdown() {
	NET_VERBOSE_PRINT( "NET: Shutdown\n" );
	idSessionLocal::Shutdown();
	
	MoveToMainMenu();
	
	// Wait until we fully shutdown
	while( localState != STATE_IDLE && localState != STATE_PRESS_START ) {
		Pump();
	}
	
	if( achievementSystem != NULL ) {
		achievementSystem->Shutdown();
		delete achievementSystem;
		achievementSystem = NULL;
	}
}

/*
========================
idSessionLocalNULL::InitializeSoundRelatedSystems
========================
*/
void idSessionLocalNULL::InitializeSoundRelatedSystems() {
	if( voiceChat != NULL ) {
		voiceChat->Init( NULL );
	}
}

/*
========================
idSessionLocalNULL::ShutdownSoundRelatedSystems
========================
*/
void idSessionLocalNULL::ShutdownSoundRelatedSystems() {
	if( voiceChat != NULL ) {
		voiceChat->Shutdown();
	}
}

/*
========================
idSessionLocalNULL::PlatformPump
========================
*/
void idSessionLocalNULL::PlatformPump() {
}

/*
========================
idSessionLocalNULL::InviteFriends
========================
*/
void idSessionLocalNULL::InviteFriends() {
}

/*
========================
idSessionLocalNULL::InviteParty
========================
*/
void idSessionLocalNULL::InviteParty() {
}

/*
========================
idSessionLocalNULL::ShowPartySessions
========================
*/
void idSessionLocalNULL::ShowPartySessions() {
}

/*
========================
idSessionLocalNULL::ShowSystemMarketplaceUI
========================
*/
void idSessionLocalNULL::ShowSystemMarketplaceUI() const {
}

/*
========================
idSessionLocalNULL::ListServers
========================
*/
void idSessionLocalNULL::ListServers( const idCallback & callback ) {
	ListServersCommon();
}

/*
========================
idSessionLocalNULL::CancelListServers
========================
*/
void idSessionLocalNULL::CancelListServers() {
}

/*
========================
idSessionLocalNULL::NumServers
========================
*/
int idSessionLocalNULL::NumServers() const {
	return 0;
}

/*
========================
idSessionLocalNULL::ServerInfo
========================
*/
const serverInfo_t * idSessionLocalNULL::ServerInfo( int i ) const {
	return NULL;
}

/*
========================
idSessionLocalNULL::ConnectToServer
========================
*/
void idSessionLocalNULL::ConnectToServer( int i ) {
}

/*
========================
idSessionLocalNULL::Connect_f
========================
*/
void idSessionLocalNULL::Connect_f( const idCmdArgs & args ) {
	if( args.Argc() < 2 ) {
		idLib::Printf( "Usage: Connect to IP. Use IP:Port to specify port (e.g. 10.0.0.1:1234) \n" );
		return;
	}
	
	Cancel();
	
	if( signInManager->GetMasterLocalUser() == NULL ) {
		signInManager->RegisterLocalUser( 0 );
	}
	
	lobbyConnectInfo_t connectInfo;
	
	Sys_StringToNetAdr( args.Argv( 1 ), &connectInfo.netAddr, true );
	// DG: don't use net_port to select port to connect to
	//     the port can be specified in the command, else the default port is used
	if( connectInfo.netAddr.port == 0 ) {
		connectInfo.netAddr.port = 27015;
	}
	// DG end
	
	ConnectAndMoveToLobby( GetPartyLobby(), connectInfo, false );
}

/*
========================
void Connect_f
========================
*/
CONSOLE_COMMAND( connect, "Connect to the specified IP", NULL ) {
	sessionLocalWin.Connect_f( args );
}

/*
========================
idSessionLocalNULL::ShowServerGamerCardUI
========================
*/
void idSessionLocalNULL::ShowServerGamerCardUI( int i ) {
}

/*
========================
idSessionLocalNULL::ShowLobbyUserGamerCardUI(
========================
*/
void idSessionLocalNULL::ShowLobbyUserGamerCardUI( lobbyUserID_t lobbyUserID ) {
}

/*
========================
idSessionLocalNULL::ProcessInputEvent
========================
*/
bool idSessionLocalNULL::ProcessInputEvent( const sysEvent_t * ev ) {
	if( GetSignInManager().ProcessInputEvent( ev ) ) {
		return true;
	}
	return false;
}

/*
========================
idSessionLocalNULL::IsSystemUIShowing
========================
*/
bool idSessionLocalNULL::IsSystemUIShowing() const {
	// DG: pausing here when window is out of focus like originally done on windows is hacky
	// it's done with com_pause now.
	return isSysUIShowing;
}

/*
========================
idSessionLocalNULL::SetSystemUIShowing
========================
*/
void idSessionLocalNULL::SetSystemUIShowing( bool show ) {
	isSysUIShowing = show;
}

/*
========================
idSessionLocalNULL::HandleServerQueryRequest
========================
*/
void idSessionLocalNULL::HandleServerQueryRequest( lobbyAddress_t & remoteAddr, idBitMsg & msg, int msgType ) {
	NET_VERBOSE_PRINT( "HandleServerQueryRequest from %s\n", remoteAddr.ToString() );
}

/*
========================
idSessionLocalNULL::HandleServerQueryAck
========================
*/
void idSessionLocalNULL::HandleServerQueryAck( lobbyAddress_t & remoteAddr, idBitMsg & msg ) {
	NET_VERBOSE_PRINT( "HandleServerQueryAck from %s\n", remoteAddr.ToString() );
}

/*
========================
idSessionLocalNULL::ClearBootableInvite
========================
*/
void idSessionLocalNULL::ClearBootableInvite() {
}

/*
========================
idSessionLocalNULL::ClearPendingInvite
========================
*/
void idSessionLocalNULL::ClearPendingInvite() {
}

/*
========================
idSessionLocalNULL::HandleBootableInvite
========================
*/
void idSessionLocalNULL::HandleBootableInvite( int64 lobbyId ) {
}

/*
========================
idSessionLocalNULL::HasPendingBootableInvite
========================
*/
bool idSessionLocalNULL::HasPendingBootableInvite()
{
	return false;
}

/*
========================
idSessionLocal::SetDiscSwapMPInvite
========================
*/
void idSessionLocalNULL::SetDiscSwapMPInvite( void * parm ) {
}

/*
========================
idSessionLocal::GetDiscSwapMPInviteParms
========================
*/
void * idSessionLocalNULL::GetDiscSwapMPInviteParms() {
	return NULL;
}

/*
========================
idSessionLocalNULL::EnumerateDownloadableContent
========================
*/
void idSessionLocalNULL::EnumerateDownloadableContent() {
}

/*
========================
idSessionLocalNULL::LeaderboardUpload
========================
*/
void idSessionLocalNULL::LeaderboardUpload( lobbyUserID_t lobbyUserID, const leaderboardDefinition_t * leaderboard, const column_t * stats, const idFile_Memory * attachment ) {
}

/*
========================
idSessionLocalNULL::LeaderboardFlush
========================
*/
void idSessionLocalNULL::LeaderboardFlush() {
}

/*
========================
idSessionLocalNULL::LeaderboardDownload
========================
*/
void idSessionLocalNULL::LeaderboardDownload( int sessionUserIndex, const leaderboardDefinition_t * leaderboard, int startingRank, int numRows, const idLeaderboardCallback & callback ) {
}

/*
========================
idSessionLocalNULL::LeaderboardDownloadAttachment
========================
*/
void idSessionLocalNULL::LeaderboardDownloadAttachment( int sessionUserIndex, const leaderboardDefinition_t * leaderboard, int64 attachmentID ) {
}

/*
========================
idSessionLocalNULL::EnsurePort
========================
*/
void idSessionLocalNULL::EnsurePort() {
	// Init the port using reqular sockets
	if ( port.IsOpen() ) {
		return;		// Already initialized
	}
	
	if ( port.InitPort( net_port.GetInteger(), false ) ) {
		// TODO: what about canJoinLocalHost when running two instances with different net_port values?
		canJoinLocalHost = false;
	} else {
		// Assume this is another instantiation on the same machine, and just init using any available port
		port.InitPort( PORT_ANY, false );
		canJoinLocalHost = true;
	}
}

/*
========================
idSessionLocalNULL::GetPort
========================
*/
idNetSessionPort & idSessionLocalNULL::GetPort( bool dedicated ) {
	EnsurePort();
	return port;
}

/*
========================
idSessionLocalNULL::CreateLobbyBackend
========================
*/
idLobbyBackend * idSessionLocalNULL::CreateLobbyBackend( const idMatchParameters & p, float skillLevel, idLobbyBackend::lobbyBackendType_t lobbyType ) {
	idLobbyBackend * lobbyBackend = CreateLobbyInternal( lobbyType );
	lobbyBackend->StartHosting( p, skillLevel, lobbyType );
	return lobbyBackend;
}

/*
========================
idSessionLocalNULL::FindLobbyBackend
========================
*/
idLobbyBackend * idSessionLocalNULL::FindLobbyBackend( const idMatchParameters & p, int numPartyUsers, float skillLevel, idLobbyBackend::lobbyBackendType_t lobbyType ) {
	idLobbyBackend * lobbyBackend = CreateLobbyInternal( lobbyType );
	lobbyBackend->StartFinding( p, numPartyUsers, skillLevel );
	return lobbyBackend;
}

/*
========================
idSessionLocalNULL::JoinFromConnectInfo
========================
*/
idLobbyBackend * idSessionLocalNULL::JoinFromConnectInfo( const lobbyConnectInfo_t & connectInfo, idLobbyBackend::lobbyBackendType_t lobbyType ) {
	idLobbyBackend * lobbyBackend = CreateLobbyInternal( lobbyType );
	lobbyBackend->JoinFromConnectInfo( connectInfo );
	return lobbyBackend;
}

/*
========================
idSessionLocalNULL::DestroyLobbyBackend
========================
*/
void idSessionLocalNULL::DestroyLobbyBackend( idLobbyBackend * lobbyBackend ) {
	assert( lobbyBackend != NULL );
	assert( lobbyBackends[lobbyBackend->GetLobbyType()] == lobbyBackend );
	
	lobbyBackends[lobbyBackend->GetLobbyType()] = NULL;
	
	lobbyBackend->Shutdown();
	delete lobbyBackend;
}

/*
========================
idSessionLocalNULL::PumpLobbies
========================
*/
void idSessionLocalNULL::PumpLobbies() {
	assert( lobbyBackends[idLobbyBackend::TYPE_PARTY] == NULL || lobbyBackends[idLobbyBackend::TYPE_PARTY]->GetLobbyType() == idLobbyBackend::TYPE_PARTY );
	assert( lobbyBackends[idLobbyBackend::TYPE_GAME] == NULL || lobbyBackends[idLobbyBackend::TYPE_GAME]->GetLobbyType() == idLobbyBackend::TYPE_GAME );
	assert( lobbyBackends[idLobbyBackend::TYPE_GAME_STATE] == NULL || lobbyBackends[idLobbyBackend::TYPE_GAME_STATE]->GetLobbyType() == idLobbyBackend::TYPE_GAME_STATE );
	
	// Pump lobbyBackends
	for( int i = 0; i < lobbyBackends.Num(); i++ ) {
		if( lobbyBackends[i] != NULL ) {
			lobbyBackends[i]->Pump();
		}
	}
}

/*
========================
idSessionLocalNULL::CreateLobbyInternal
========================
*/
idLobbyBackend * idSessionLocalNULL::CreateLobbyInternal( idLobbyBackend::lobbyBackendType_t lobbyType ) {
	EnsurePort();
	idLobbyBackend * lobbyBackend = new ( TAG_NETWORKING ) idLobbyBackendDirect();
	
	lobbyBackend->SetLobbyType( lobbyType );
	
	assert( lobbyBackends[lobbyType] == NULL );
	lobbyBackends[lobbyType] = lobbyBackend;
	
	return lobbyBackend;
}

/*
========================
idSessionLocalNULL::JoinAfterSwap
========================
*/
void idSessionLocalNULL::JoinAfterSwap( void * joinID ) {
}

/*
========================
idSessionLocalNULL::GetLobbyAddressFromNetAddress
========================
*/
bool idSessionLocalNULL::GetLobbyAddressFromNetAddress( const netadr_t & netAddr, lobbyAddress_t & outAddr ) const {
	return false;
}

/*
========================
idSessionLocalNULL::GetNetAddressFromLobbyAddress
========================
*/
bool idSessionLocalNULL::GetNetAddressFromLobbyAddress( const lobbyAddress_t & lobbyAddress, netadr_t & outNetAddr ) const {
	return false;
}
