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
# MODULE DESCRIPTION: Character server implementation.

package Network::XKore2::CharServer;

use strict;
use Globals qw($char $masterServer %config);
use Base::Ragnarok::CharServer;
use base qw(Base::Ragnarok::CharServer);

# Modo classico (XKore_esperarCliente): a escolha de personagem do cliente espera o kore receber o ZC_ACCEPT_ENTER
# (o char_login usa $char e a posicao no mapa)
sub char_login {
	my ($self, $args, $client) = @_;
	if (Network::XKore2::esperarCliente() && !Network::XKore2::koreNoMapa()) {
		Network::XKore2::adiar(\&Network::XKore2::koreNoMapa, sub { $self->SUPER::char_login($args, $client) }, $client);
		return;
	}
	$self->SUPER::char_login($args, $client);
}

# Overrided method.
sub getCharacters {
	my ($self, $session) = @_;
	my @chars;
	# no modo classico o cliente ve a lista antes de o kore entrar no mapa ($char so existe depois)
	my $c = $char || (Network::XKore2::korePersonagens() && $Globals::chars[$config{char}]);
	if (!$session->{dummy} && $c) {
		#for (my $i = 0; $i < 5; $i++) {
		#	push @chars, $char;
		#}
		push @chars, $c;
	} else {
		$session->{dummy} = 1;
		for (my $i = 0; $i < 5; $i++) {
			push @chars, Base::Ragnarok::CharServer::DUMMY_CHARACTER;
		}
	}
	return @chars;
}

sub charBlockSize {
	my ($self) = @_;
	if ($masterServer) {
		return $masterServer->{charBlockSize} || $self->{charBlockSize} || 106;
	} else {
		return $self->SUPER::charBlockSize();
	}
}

1;

