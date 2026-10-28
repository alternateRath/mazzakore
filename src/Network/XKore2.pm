#########################################################################
#  OpenKore - X-Kore Mode 2
#  Copyright (c) 2007 OpenKore developers
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#  $Revision$
#  $Id$
#
#########################################################################
##
# MODULE DESCRIPTION: X-Kore 2.
package Network::XKore2;

use strict;
use Globals qw(%config %rpackets $masterServer $char $accountID @chars $field $net);
use Utils::Exceptions;
use Plugins;
use Base::Ragnarok::SessionStore;
use Network;
use Network::XKore2::AccountServer;
use Network::XKore2::CharServer;
use Network::XKore2::MapServer;
use Modules 'register';

our ($hooks, $sessionStore, $accountServer, $charServer, $mapServer ,$mapServerChange);

# XKore_esperarCliente 1 (mazzaro): modo classico. O kore so conecta no servidor depois que um cliente pede login no
# login falso; o login falso responde quando o kore ja tem a lista de personagens; o char falso manda o cliente para o
# map quando o kore ja entrou no mapa; o kore NAO manda o proprio LoadEndAck na primeira entrada e o do cliente segue
# para o servidor (como no XKore 1). Assim o servidor manda status, inventario e atores direto para o cliente.
our ($clienteChegou, $clienteNoMapa, @pendentes);
# o rAthena manda atores, status e inventario junto com o ZC_ACCEPT_ENTER, antes do LoadEndAck: nessa hora o cliente
# ainda escolhe personagem. O fluxo (pacotes originais, ja no formato do cliente) fica aqui ate ele carregar o mapa.
our ($bufferEntrada, $bufferBytes) = ('', 0);
use constant BUFFER_MAX => 4 * 1024 * 1024;

sub clientSendSemCliente {
	my (undef, $args) = @_;
	return unless esperarCliente() && !$clienteNoMapa;
	return unless $args->{net}->getState() == Network::IN_GAME;
	return if $bufferBytes + length($args->{data}) > BUFFER_MAX;
	$bufferEntrada .= $args->{data};
	$bufferBytes += length($args->{data});
}

sub esperarCliente {
	return $config{XKore} eq '2' && $config{XKore_esperarCliente};
}

# o kore ja tem a conta e a lista de personagens (o login falso pode responder sem sessao dummy)
sub korePersonagens {
	return $accountID && defined $config{char} && $chars[$config{char}];
}

# o kore recebeu o ZC_ACCEPT_ENTER (o char falso pode mandar o cliente para o map)
sub koreNoMapa {
	return $Globals::net && $Globals::net->getState() == Network::IN_GAME && $field && $char;
}

# guarda uma resposta de servidor falso ate a condicao valer (processada no mainLoop)
sub adiar {
	my ($condicao, $acao, $client) = @_;
	push @pendentes, { condicao => $condicao, acao => $acao, client => $client };
}

sub checkConnection {
	my (undef, $args) = @_;
	$args->{return} = 1 if esperarCliente() && !$clienteChegou;
}

##
# void Network::XKore2::start()
#
# Start the X-Kore 2 subsystem.
sub start {
	my $publicIP = $config{XKore_publicIp} || '127.0.0.1';
	my $port = $config{XKore_listenPort} || 6900;
	$sessionStore = new Base::Ragnarok::SessionStore();
	$mapServer = new Network::XKore2::MapServer(
		host => $publicIP,
		port => $config{XKore_listenPort_map} || undef,
		serverType => $masterServer->{serverType},
		rpackets => \%rpackets,
		sessionStore => $sessionStore
	);
	$charServer = new Network::XKore2::CharServer(
		host => $publicIP,
		port => $config{XKore_listenPort_char} || undef,
		serverType => $masterServer->{serverType},
		rpackets => \%rpackets,
		mapServer => $mapServer,
		sessionStore => $sessionStore,
		name => $config{XKore_ID}
	);
	eval {
		$accountServer = new Network::XKore2::AccountServer(
			host         => $publicIP,
			port         => $port,
			serverType   => $masterServer->{serverType},
			rpackets     => \%rpackets,
			charServer   => $charServer,
			sessionStore => $sessionStore
		);
	};
	if ( my $e = caught( 'SocketException' ) ) {
		die "Unable to start the X-Kore proxy ($publicIP:$port): $@\n"
			. "Make sure no other servers are running on port $port.";
	} else {
		die $@ if $@;
	}
	$hooks = Plugins::addHooks(
		['packet_pre/sync_request_ex', \&sync_request_ex],
		['packet_pre/map_loaded', \&map_loaded],
		['packet_pre/map_changed', \&map_changed],
		['packet_pre/initialize_message_id_encryption', \&initialize_message_id_encryption],
		['Network::stateChanged', \&stateChanged],
		['Network::clientAlive', \&clientAlive],
		['Network::clientSend', \&clientSend],
		['Network::clientRecv', \&clientRecv],
		['mainLoop_pre', \&mainLoop],
		['checkConnection', \&checkConnection],
		['Network::clientSend_semCliente', \&clientSendSemCliente],
		['disconnected', \&disconnectClients]
	);
}

##
# void Network::XKore2::stop()
#
# Stop the X-Kore 2 subsystem.
sub stop {
	Plugins::delHooks($hooks);
}

# let kore handle this.
sub sync_request_ex {
	my ($self, $args, $client) = @_;
	$args->{mangle} = 2;
}

sub map_loaded {
	my (undef, $args) = @_;

	$args->{mangle} = 2;
}

sub map_changed {
	my (undef, $args) = @_;

	$mapServerChange = Storable::dclone($args);

	$args->{mangle} = 2;
}

sub initialize_message_id_encryption {
	my (undef, $args) = @_;

	$args->{mangle} = 2;
}

sub stateChanged {
	$accountServer->setServerType($masterServer->{serverType});
	$charServer->setServerType($masterServer->{serverType});
	$mapServer->setServerType($masterServer->{serverType});

	if ($Globals::net->getState() == Network::IN_GAME && $mapServerChange ne '') {
		$Globals::net->clientSend($mapServer->{recvPacketParser}->reconstruct({
			%$mapServerChange,
			switch => 'map_change',
		}));

		$mapServerChange = undef;
	}
}

sub clientAlive {
	my (undef, $args) = @_;
	$args->{return} = @{$mapServer->clients} > 0 && $args->{net}->getState() == Network::IN_GAME;
}

sub clientSend {
	my (undef, $args) = @_;
	if ($args->{net}->getState() == Network::IN_GAME) {
		foreach my $client (@{$mapServer->clients}) {
			my $sendData = $args->{data};
			$client->send($sendData) if (length($sendData) > 0);
		}
	}

}

sub clientRecv {
	no encoding 'utf8';
	use bytes;
	my (undef, $args) = @_;

	if ($args->{net}->getState() != Network::IN_GAME) {
		foreach my $client (@{$mapServer->clients}) {
			$client->{outbox}->clear() if ($client->{outbox});
		}
	} else {
		my $result = '';
		foreach my $client (@{$mapServer->clients}) {
			my $type;
			while (my $message = $client->{outbox}->readNext(\$type)) {
				$result .= $message;
			}
		}
		$args->{return} = $result if (length($result) > 0);
	}
}

sub mainLoop {
	if ($accountServer) {
		$accountServer->iterate();
		$charServer->iterate();
		$mapServer->iterate();
		$sessionStore->removeTimedOutSessions();
	}
	if (@pendentes) {
		my @resto;
		for my $p (@pendentes) {
			if ($p->{condicao}->()) {
				$p->{acao}->();
			} else {
				push @resto, $p;
			}
		}
		@pendentes = @resto;
	}
}

sub disconnectClients {
	# DC clients here
}

1;

