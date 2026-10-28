#########################################################################
#  OpenKore - Packet Receiveing
#  This module contains functions for Receiveing packets to the server.
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
########################################################################
# Korea (kRO) 2026-02-19 # mazzakore (alternateRath/mazzakore, branch mazzaro)
# Protocolo do MazzaRO: mazzathena (rAthena) com PACKETVER 20260219 e o cliente kRO 2026-02-19.
# Tamanhos em tables/kRO/RagexeRE_2026_02_19/recvpackets.txt (gerado pelo mazzaro: tools/kore_recvpackets.py).
package Network::Receive::kRO::RagexeRE_2026_02_19;
use strict;
use base qw(Network::Receive::kRO::RagexeRE_2021_11_03);
use Globals qw($char);
use Log qw(message debug);

use constant CONFIG_DISABLE_SHOWCOSTUMES => 5;

sub new {
	my ($class) = @_;
	my $self = $class->SUPER::new(@_);

	my %packets = (
		'0B8D' => ['repute_info', 'v C a*', [qw(len success list)]],# -1 ZC_REPUTE_INFO
	);
	$self->{packet_list}{$_} = $packets{$_} for keys %packets;

	return $self;
}

# 02D9 tipo 5 (CONFIG_DISABLE_SHOWCOSTUMES do rAthena): o mazzathena manda na entrada do mapa
sub misc_config_reply {
	my ($self, $args) = @_;
	if ($args->{type} == CONFIG_DISABLE_SHOWCOSTUMES) {
		debug "Config: mostrar trajes " . ($args->{flag} ? "desligado" : "ligado") . "\n", "parseMsg";
		return;
	}
	$self->SUPER::misc_config_reply($args);
}

# 0B8D <len>.W <success>.B { <type>.Q <points>.Q }* (ZC_REPUTE_INFO, reputacao por faccao)
sub repute_info {
	my ($self, $args) = @_;
	my %repute;
	for (my $i = 0; $i + 16 <= length $args->{list}; $i += 16) {
		my ($tlo, $thi, $plo, $phi) = unpack('V V V l', substr($args->{list}, $i, 16));
		$repute{$tlo + $thi * 4294967296} = $plo + $phi * 4294967296;
	}
	$char->{repute} = \%repute if $char;
	debug "Reputacao: " . scalar(keys %repute) . " faccoes (success $args->{success})\n", "parseMsg";
}

1;
