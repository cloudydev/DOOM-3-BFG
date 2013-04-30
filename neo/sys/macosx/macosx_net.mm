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

#include "../../idlib/precompiled.h"
#include <ifaddrs.h>
#include <netdb.h>
#include <arpa/inet.h>         // for inet_ntoa()
#include <net/if.h>
#include <net/if_types.h>
#include <net/if_dl.h>         // for 'struct sockaddr_dl'
#include <sys/ioctl.h>
#include <sys/sockio.h>
#include <sys/socket.h>

/*
================================================================================================
Contains the NetworkSystem implementation specific to Mac OS X.
================================================================================================
*/

typedef int SOCKET;
#define closesocket(x)	close(x)
#define SOCKET_ERROR	-1
#define INVALID_SOCKET	-1

/*
================================================================================================

	Network CVars

================================================================================================
*/

idCVar net_ip( "net_ip", "localhost", 0, "local IP address" );

//static SOCKET	ip_socket; // jeremiah sypult - unused

typedef struct {
	in_addr_t ip;
	in_addr_t mask;
	char addr[16];
} net_interface;

#define 		MAX_INTERFACES	32
int				num_interfaces = 0;
net_interface	netint[MAX_INTERFACES];

/*
================================================================================================

	Free Functions

================================================================================================
*/

/*
========================
NET_ErrorString
========================
*/
const char *NET_ErrorString() {
	int		code = errno;
	return strerror( code );
}

/*
========================
Net_NetadrToSockadr
========================
*/
void Net_NetadrToSockadr( const netadr_t *a, struct sockaddr_in *s ) {
	memset( s, 0, sizeof(*s) );

	if ( a->type == NA_BROADCAST ) {
		s->sin_family = AF_INET;
		s->sin_addr.s_addr = INADDR_BROADCAST;
	} else if ( a->type == NA_IP || a->type == NA_LOOPBACK ) {
		s->sin_family = AF_INET;
		s->sin_addr.s_addr = *(int *)a->ip;
	}

	s->sin_port = htons( (short)a->port );
}

/*
========================
Net_SockadrToNetadr
========================
*/
void Net_SockadrToNetadr( struct sockaddr_in *s, netadr_t *a ) {
	unsigned int ip;
	if ( s->sin_family == AF_INET ) {
		ip = s->sin_addr.s_addr;
		*(unsigned int *)a->ip = ip;
		a->port = htons( s->sin_port );
		// we store in network order, that loopback test is host order..
		ip = ntohl( ip );
		if ( ip == INADDR_LOOPBACK ) {
			a->type = NA_LOOPBACK;
		} else {
			a->type = NA_IP;
		}
	}
}

/*
========================
Net_ExtractPort
========================
*/
static bool Net_ExtractPort( const char *src, char *buf, int bufsize, int *port ) {
	char *p;
	strncpy( buf, src, bufsize );
	p = buf; p += Min( bufsize - 1, idStr::Length( src ) ); *p = '\0';
	p = strchr( buf, ':' );
	if ( !p ) {
		return false;
	}
	*p = '\0';
	*port = strtol( p+1, NULL, 10 );
	if ( errno == ERANGE ) {
		return false;
	}
	return true;
}

/*
========================
Net_StringToSockaddr
========================
*/
static bool Net_StringToSockaddr( const char *s, struct sockaddr_in *sadr, bool doDNSResolve ) {
	struct hostent	*h;
	char buf[256];
	int port;
	
	memset( sadr, 0, sizeof( *sadr ) );

	sadr->sin_family = AF_INET;
	sadr->sin_port = 0;

	if( s[0] >= '0' && s[0] <= '9' ) {
		in_addr_t ret = inet_addr(s);
		if ( ret != INADDR_NONE ) {
			*(int *)&sadr->sin_addr = ret;
		} else {
			// check for port
			if ( !Net_ExtractPort( s, buf, sizeof( buf ), &port ) ) {
				return false;
			}
			ret = inet_addr( buf );
			if ( ret == INADDR_NONE ) {
				return false;
			}
			*(int *)&sadr->sin_addr = ret;
			sadr->sin_port = htons( port );
		}
	} else if ( doDNSResolve ) {
		// try to remove the port first, otherwise the DNS gets confused into multiple timeouts
		// failed or not failed, buf is expected to contain the appropriate host to resolve
		if ( Net_ExtractPort( s, buf, sizeof( buf ), &port ) ) {
			sadr->sin_port = htons( port );			
		}
		h = gethostbyname( buf );
		if ( h == 0 ) {
			return false;
		}
		*(int *)&sadr->sin_addr = *(int *)h->h_addr_list[0];
	}
	
	return true;
}

/*
========================
NET_IPSocket
========================
*/
int NET_IPSocket( const char *net_interface, int port, netadr_t *bound_to ) {
	SOCKET				newsocket;
	struct sockaddr_in			address;
	unsigned long		_true = 1;
	int					i = 1;

	if ( port != PORT_ANY ) {
		if( net_interface ) {
			idLib::Printf( "Opening IP socket: %s:%i\n", net_interface, port );
		} else {
			idLib::Printf( "Opening IP socket: localhost:%i\n", port );
		}
	}

	if( ( newsocket = socket( AF_INET, SOCK_DGRAM, IPPROTO_UDP ) ) == INVALID_SOCKET ) {
		idLib::Printf( "WARNING: UDP_OpenSocket: socket: %s\n", NET_ErrorString() );
		return 0;
	}

	// make it non-blocking
	if( ioctl( newsocket, FIONBIO, &_true ) == SOCKET_ERROR ) {
		idLib::Printf( "WARNING: UDP_OpenSocket: ioctl FIONBIO: %s\n", NET_ErrorString() );
		closesocket( newsocket );
		return 0;
	}

	// make it broadcast capable
	if( setsockopt( newsocket, SOL_SOCKET, SO_BROADCAST, (char *)&i, sizeof(i) ) == SOCKET_ERROR ) {
		idLib::Printf( "WARNING: UDP_OpenSocket: setsockopt SO_BROADCAST: %s\n", NET_ErrorString() );
		closesocket( newsocket );
		return 0;
	}

	if( !net_interface || !net_interface[0] || !idStr::Icmp( net_interface, "localhost" ) ) {
		address.sin_addr.s_addr = INADDR_ANY;
	}
	else {
		Net_StringToSockaddr( net_interface, &address, true );
	}

	if( port == PORT_ANY ) {
		address.sin_port = 0;
	}
	else {
		address.sin_port = htons( (short)port );
	}

	address.sin_family = AF_INET;

	if( bind( newsocket, (const sockaddr *)&address, sizeof(address) ) == SOCKET_ERROR ) {
		idLib::Printf( "WARNING: UDP_OpenSocket: bind: %s\n", NET_ErrorString() );
		closesocket( newsocket );
		return 0;
	}

	// if the port was PORT_ANY, we need to query again to know the real port we got bound to
	// ( this used to be in idUDP::InitForPort )
	if ( bound_to ) {
		socklen_t len = sizeof( address );
		if ( getsockname( newsocket, (struct sockaddr *)&address, &len ) == SOCKET_ERROR ) {
			idLib::Printf( "WARNING: UDP_OpenSocket: getsockname: %s\n", NET_ErrorString() );
			closesocket( newsocket );
			return 0;
		}
		Net_SockadrToNetadr( &address, bound_to );
	}

	return newsocket;
}

/*
========================
Net_WaitForData
========================
*/
bool Net_WaitForData( int netSocket, int timeout ) {
	int					ret;
	fd_set				set;
	struct timeval		tv;

	if ( !netSocket ) {
		return false;
	}

	if ( timeout < 0 ) {
		return true;
	}

	FD_ZERO( &set );
	FD_SET( static_cast<unsigned int>( netSocket ), &set );

	tv.tv_sec = 0;
	tv.tv_usec = timeout * 1000;

	ret = select( netSocket + 1, &set, NULL, NULL, &tv );

	if ( ret == -1 ) {
		idLib::Printf( "Net_WaitForData select(): %s\n", strerror( errno ) );
		return false;
	}

	// timeout with no data
	if ( ret == 0 ) {
		return false;
	}

	return true;
}

/*
========================
Net_GetUDPPacket
========================
*/
bool Net_GetUDPPacket( int netSocket, netadr_t &net_from, char *data, int &size, int maxSize ) {
	int 			ret;
	struct sockaddr_in		from;
	socklen_t				fromlen;
	int				err;

	if ( !netSocket ) {
		return false;
	}

	fromlen = sizeof(from);
	ret = recvfrom( netSocket, data, maxSize, 0, (sockaddr *)&from, &fromlen );
	if ( ret == SOCKET_ERROR ) {
		err = errno;

		if ( err == EWOULDBLOCK || err == ECONNRESET ) {
			return false;
		}
		char	buf[1024];
		sprintf( buf, "Net_GetUDPPacket: %s\n", NET_ErrorString() );
		idLib::Printf( buf );
		return false;
	}

	Net_SockadrToNetadr( &from, &net_from );

	if ( ret > maxSize ) {
		char	buf[1024];
		sprintf( buf, "Net_GetUDPPacket: oversize packet from %s\n", Sys_NetAdrToString( net_from ) );
		idLib::Printf( buf );
		return false;
	}

	size = ret;

	return true;
}

/*
========================
Net_SendUDPPacket
========================
*/
void Net_SendUDPPacket( int netSocket, int length, const void *data, const netadr_t to ) {
	int				ret;
	struct sockaddr_in		addr;

	if ( !netSocket ) {
		return;
	}

	Net_NetadrToSockadr( &to, &addr );

	ret = sendto( netSocket, (const char *)data, length, 0, (sockaddr *)&addr, sizeof(addr) );

	if ( ret == SOCKET_ERROR ) {
		int err = errno;

		// some PPP links do not allow broadcasts and return an error
		if ( ( err == EADDRNOTAVAIL ) && ( to.type == NA_BROADCAST ) ) {
			return;
		}

		// NOTE: EWOULDBLOCK used to be silently ignored,
		// but that means the packet will be dropped so I don't feel it's a good thing to ignore
		idLib::Printf( "UDP sendto error - packet dropped: %s\n", NET_ErrorString() );
	}
}

/*
========================
Sys_InitNetworking
========================
*/
void Sys_InitNetworking() {
	bool foundloopback;

	num_interfaces = 0;
	foundloopback = false;
#if 0
	pAdapterInfo = (IP_ADAPTER_INFO *)malloc( sizeof( IP_ADAPTER_INFO ) );
	if( !pAdapterInfo ) {
		idLib::FatalError( "Sys_InitNetworking: Couldn't malloc( %d )", sizeof( IP_ADAPTER_INFO ) );
	}
	ulOutBufLen = sizeof( IP_ADAPTER_INFO );

	// Make an initial call to GetAdaptersInfo to get
	// the necessary size into the ulOutBufLen variable
	if( GetAdaptersInfo( pAdapterInfo, &ulOutBufLen ) == ERROR_BUFFER_OVERFLOW ) {
		free( pAdapterInfo );
		pAdapterInfo = (IP_ADAPTER_INFO *)malloc( ulOutBufLen ); 
		if( !pAdapterInfo ) {
			idLib::FatalError( "Sys_InitNetworking: Couldn't malloc( %ld )", ulOutBufLen );
		}
	}

	if( ( dwRetVal = GetAdaptersInfo( pAdapterInfo, &ulOutBufLen) ) != NO_ERROR ) {
		// happens if you have no network connection
		idLib::Printf( "Sys_InitNetworking: GetAdaptersInfo failed (%ld).\n", dwRetVal );
	} else {
		pAdapter = pAdapterInfo;
		while( pAdapter ) {
			idLib::Printf( "Found interface: %s %s - ", pAdapter->AdapterName, pAdapter->Description );
			pIPAddrString = &pAdapter->IpAddressList;
			while( pIPAddrString ) {
				unsigned long ip_a, ip_m;
				if( !idStr::Icmp( "127.0.0.1", pIPAddrString->IpAddress.String ) ) {
					foundloopback = true;
				}
				ip_a = ntohl( inet_addr( pIPAddrString->IpAddress.String ) );
				ip_m = ntohl( inet_addr( pIPAddrString->IpMask.String ) );
				//skip null netmasks
				if( !ip_m ) {
					idLib::Printf( "%s NULL netmask - skipped\n", pIPAddrString->IpAddress.String );
					pIPAddrString = pIPAddrString->Next;
					continue;
				}
				idLib::Printf( "%s/%s\n", pIPAddrString->IpAddress.String, pIPAddrString->IpMask.String );
				netint[num_interfaces].ip = ip_a;
				netint[num_interfaces].mask = ip_m;
				idStr::Copynz( netint[num_interfaces].addr, pIPAddrString->IpAddress.String, sizeof( netint[num_interfaces].addr ) );
				num_interfaces++;
				if( num_interfaces >= MAX_INTERFACES ) {
					idLib::Printf( "Sys_InitNetworking: MAX_INTERFACES(%d) hit.\n", MAX_INTERFACES );
					free( pAdapterInfo );
					return;
				}
				pIPAddrString = pIPAddrString->Next;
			}
			pAdapter = pAdapter->Next;
		}
	}
#endif
#define MAX_IPS (16)
#define IFR_NEXT(ifr) ((struct ifreq *) ((char *) (ifr) + sizeof(*(ifr)) + MAX(0, (int) (ifr)->ifr_addr.sa_len - (int) sizeof((ifr)->ifr_addr))))

	struct ifreq requestBuffer[MAX_IPS], *linkInterface, *inetInterface;
	struct ifconf ifc;
	struct ifreq ifr;
	SOCKET interfaceSocket;

	ifc.ifc_len = sizeof(requestBuffer);
	ifc.ifc_buf = (caddr_t)requestBuffer;

	if ( ( interfaceSocket = socket( AF_INET, SOCK_DGRAM, 0 ) ) == SOCKET_ERROR ) {
		idLib::Printf( "WARNING: Sys_InitNetworking: socket: %s\n", NET_ErrorString() );
		closesocket( interfaceSocket );
		return;
	}

	if ( ioctl( interfaceSocket, SIOCGIFCONF, &ifc ) == SOCKET_ERROR ) {
		idLib::Printf( "WARNING: Sys_InitNetworking: ioctl: %s\n", NET_ErrorString() );
		closesocket( interfaceSocket );
		return;
	}

	linkInterface = (struct ifreq *) ifc.ifc_buf;
	while ( (char*)linkInterface < &ifc.ifc_buf[ifc.ifc_len] ) {
		if (linkInterface->ifr_addr.sa_family == AF_LINK) {
			inetInterface = (struct ifreq *) ifc.ifc_buf;
			while ( (char*)inetInterface < &ifc.ifc_buf[ifc.ifc_len] ) {
				if ( inetInterface->ifr_addr.sa_family == AF_INET &&
					!idStr::Cmpn( inetInterface->ifr_name, linkInterface->ifr_name, sizeof( linkInterface->ifr_name ) ) ) {
					net_interface nif = {0};
					in_addr_t ip_a;
					in_addr_t ip_m;
					char maskaddrstr[16] = {0};
					struct sockaddr_in *ipaddr;
					struct sockaddr_in *maskaddr;
					in_addr_t ip;
					in_addr_t mask;
					const char *ipstr = NULL;
					const char *maskstr = NULL;

					memset(&ifr, 0, sizeof(ifr));
					strncpy(ifr.ifr_name, inetInterface->ifr_name, sizeof(ifr.ifr_name));

					idLib::Printf( "Found interface: %s - ", ifr.ifr_name );

					// interface ip address
					if ( ioctl( interfaceSocket, SIOCGIFADDR, (caddr_t)&ifr ) == SOCKET_ERROR ) {
						idLib::Printf( "ioctl error: %s\n", NET_ErrorString() );
					} else {
						// ioctl( interfaceSocket, SIOCGIFNETMASK, (caddr_t)&ifr ) == SOCKET_ERROR
						ipaddr = (struct sockaddr_in *)&ifr.ifr_addr;
						ip = ipaddr->sin_addr.s_addr;
						ipstr = inet_ntop( AF_INET, &ip, nif.addr, sizeof(nif.addr) );
					}

					// interface netmask
					if ( ioctl( interfaceSocket, SIOCGIFNETMASK, (caddr_t)&ifr ) == SOCKET_ERROR ) {
						idLib::Printf( "ioctl error: %s\n", NET_ErrorString() );
					} else {
						maskaddr = (struct sockaddr_in *)&ifr.ifr_addr;
						mask = maskaddr->sin_addr.s_addr;
						maskstr = inet_ntop( AF_INET, &mask, maskaddrstr, sizeof(maskaddrstr) );
					}

					if( !idStr::Icmp( "127.0.0.1", ipstr ) ) {
						foundloopback = true;
					}

					ip_a = ntohl( inet_addr( ipstr ) );
					ip_m = ntohl( inet_addr( maskstr ) );

					// skip null netmasks
					if( !ip_m ) {
						idLib::Printf( "%s NULL netmask - skipped\n", ipstr );
					} else {
						idLib::Printf( "%s/%s \n", ipstr, maskstr );
						netint[num_interfaces].ip = ip_a;
						netint[num_interfaces].mask = ip_m;
						idStr::Copynz( netint[num_interfaces].addr, ipstr, sizeof( netint[num_interfaces].addr ) );
						num_interfaces++;
						if( num_interfaces >= MAX_INTERFACES ) {
							idLib::Printf( "Sys_InitNetworking: MAX_INTERFACES(%d) hit.\n", MAX_INTERFACES );
							return;
						}
					}
				}
				inetInterface = IFR_NEXT(inetInterface);
			}
		}
		linkInterface = IFR_NEXT( linkInterface );
	}

	closesocket( interfaceSocket );

	// add loopback as an adapter if it wasn't found...
	if( !foundloopback && num_interfaces < MAX_INTERFACES ) {
		idLib::Printf( "Sys_InitNetworking: adding loopback interface\n" );
		netint[num_interfaces].ip = ntohl( inet_addr( "127.0.0.1" ) );
		netint[num_interfaces].mask = ntohl( inet_addr( "255.0.0.0" ) );
		num_interfaces++;
	}
}

/*
========================
Sys_ShutdownNetworking
========================
*/
void Sys_ShutdownNetworking() {
}

/*
========================
Sys_StringToNetAdr
========================
*/
bool Sys_StringToNetAdr( const char *s, netadr_t *a, bool doDNSResolve ) {
	struct sockaddr_in sadr;
	
	if ( !Net_StringToSockaddr( s, &sadr, doDNSResolve ) ) {
		return false;
	}
	
	Net_SockadrToNetadr( &sadr, a );
	return true;
}

/*
========================
Sys_NetAdrToString
========================
*/
const char *Sys_NetAdrToString( const netadr_t a ) {
	static int index = 0;
	static char buf[ 4 ][ 64 ];	// flip/flop
	char *s;

	s = buf[index];
	index = (index + 1) & 3;

	if ( a.type == NA_LOOPBACK ) {
		if ( a.port ) {
			idStr::snPrintf( s, 64, "localhost:%i", a.port );
		} else {
			idStr::snPrintf( s, 64, "localhost" );
		}
	} else if ( a.type == NA_IP ) {
		idStr::snPrintf( s, 64, "%i.%i.%i.%i:%i", a.ip[0], a.ip[1], a.ip[2], a.ip[3], a.port );
	}
	return s;
}

/*
========================
Sys_IsLANAddress
========================
*/
bool Sys_IsLANAddress( const netadr_t adr ) {
	if ( adr.type == NA_LOOPBACK ) {
		return true;
	}

	if ( adr.type != NA_IP ) {
		return false;
	}

	if ( num_interfaces ) {
		int i;
		in_addr_t *p_ip;
		in_addr_t ip;
		p_ip = (in_addr_t *)&adr.ip[0];
		ip = ntohl( *p_ip );

		for( i = 0; i < num_interfaces; i++ ) {
			if( ( netint[i].ip & netint[i].mask ) == ( ip & netint[i].mask ) ) {
				return true;
			}
		}
	}
	return false;
}

/*
========================
Sys_CompareNetAdrBase

Compares without the port.
========================
*/
bool Sys_CompareNetAdrBase( const netadr_t a, const netadr_t b ) {
	if ( a.type != b.type ) {
		return false;
	}

	if ( a.type == NA_LOOPBACK ) {
		if ( a.port == b.port ) {
			return true;
		}

		return false;
	}

	if ( a.type == NA_IP ) {
		if ( a.ip[0] == b.ip[0] && a.ip[1] == b.ip[1] && a.ip[2] == b.ip[2] && a.ip[3] == b.ip[3] ) {
			return true;
		}
		return false;
	}

	idLib::Printf( "Sys_CompareNetAdrBase: bad address type\n" );
	return false;
}

/*
========================
Sys_GetLocalIPCount
========================
*/
int	Sys_GetLocalIPCount() {
	return num_interfaces;
}

/*
========================
Sys_GetLocalIP
========================
*/
const char * Sys_GetLocalIP( int i ) {
	if ( ( i < 0 ) || ( i >= num_interfaces ) ) {
		return NULL;
	}
	return netint[i].addr;
}

/*
================================================================================================

	idUDP

================================================================================================
*/

/*
========================
idUDP::idUDP
========================
*/
idUDP::idUDP() {
	netSocket = 0;
	memset( &bound_to, 0, sizeof( bound_to ) );
	silent = false;
	packetsRead = 0;
	bytesRead = 0;
	packetsWritten = 0;
	bytesWritten = 0;
}

/*
========================
idUDP::~idUDP
========================
*/
idUDP::~idUDP() {
	Close();
}

/*
========================
idUDP::InitForPort
========================
*/
bool idUDP::InitForPort( int portNumber ) {
	netSocket = NET_IPSocket( net_ip.GetString(), portNumber, &bound_to );
	if ( netSocket <= 0 ) {
		netSocket = 0;
		memset( &bound_to, 0, sizeof( bound_to ) );
		return false;
	}

	return true;
}

/*
========================
idUDP::Close
========================
*/
void idUDP::Close() {
	if ( netSocket ) {
		closesocket( netSocket );
		netSocket = 0;
		memset( &bound_to, 0, sizeof( bound_to ) );
	}
}

/*
========================
idUDP::GetPacket
========================
*/
bool idUDP::GetPacket( netadr_t &from, void *data, int &size, int maxSize ) {
	bool ret;

	while ( 1 ) {

		ret = Net_GetUDPPacket( netSocket, from, (char *)data, size, maxSize );
		if ( !ret ) {
			break;
		}

		packetsRead++;
		bytesRead += size;

		break;
	}

	return ret;
}

/*
========================
idUDP::GetPacketBlocking
========================
*/
bool idUDP::GetPacketBlocking( netadr_t &from, void *data, int &size, int maxSize, int timeout ) {

	if ( !Net_WaitForData( netSocket, timeout ) ) {
		return false;
	}

	if ( GetPacket( from, data, size, maxSize ) ) {
		return true;
	}

	return false;
}

/*
========================
idUDP::SendPacket
========================
*/
void idUDP::SendPacket( const netadr_t to, const void *data, int size ) {
	if ( to.type == NA_BAD ) {
		idLib::Warning( "idUDP::SendPacket: bad address type NA_BAD - ignored" );
		return;
	}

	packetsWritten++;
	bytesWritten += size;

	if ( silent ) {
		return;
	}

	Net_SendUDPPacket( netSocket, size, data, to );
}
