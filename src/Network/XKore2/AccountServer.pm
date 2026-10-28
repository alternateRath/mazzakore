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
#########################################################################
##
# MODULE DESCRIPTION: Account server implementation.

package Network::XKore2::AccountServer;

use strict;
use Globals;
use Base::Ragnarok::AccountServer;
use base qw(Base::Ragnarok::AccountServer);

# Modo classico (XKore_esperarCliente): o pedido de login do cliente libera a conexao do kore e a resposta espera o
# kore ter a lista de personagens (conta e sexo verdadeiros, sem sessao dummy)
sub master_login {
	my ($self, $args, $client) = @_;
	if (Network::XKore2::esperarCliente() && !Network::XKore2::korePersonagens()) {
		$Network::XKore2::clienteChegou = 1;
		Log::message("[XKore 2] cliente pediu login; conectando o kore no servidor\n", 'connection');
		Network::XKore2::adiar(\&Network::XKore2::korePersonagens,
			sub { $self->SUPER::master_login($args, $client) }, $client);
		return;
	}
	$Network::XKore2::clienteChegou = 1;
	$self->SUPER::master_login($args, $client);
}

# Overrided method.
sub login {
	my ($self, $session, $username, $password_check_callback) = @_;
	my $c = $char || (Network::XKore2::korePersonagens() && $chars[$config{char}]);
	if ($c) {
		$session->{accountID} = $accountID;
		$session->{sex} = defined $c->{sex} ? $c->{sex} : $accountSex2;
	} else {
		$session->{accountID} = pack("V", 123456);
		$session->{sex} = 0;
		$session->{dummy} = 1;
	}

	#return Base::Ragnarok::AccountServer::SERVER_REFUSED unless ($net->getState() == Network::IN_GAME);
	return Base::Ragnarok::AccountServer::ACCOUNT_NOT_FOUND unless $config{username} eq $username;
	return Base::Ragnarok::AccountServer::PASSWORD_INCORRECT unless $password_check_callback->($config{adminPassword});

	return Base::Ragnarok::AccountServer::LOGIN_SUCCESS;
}

1;
