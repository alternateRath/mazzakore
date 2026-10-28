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
		# O ServerType0 escolhe estes pelo tamanho do recvpackets.txt na hora do new; os parsers do XKore 2 sao criados
		# antes da tabela carregar e caiam no formato antigo (01D7 de 11 bytes derrubava o cliente 2026). Fixos aqui.
		'00AA' => ['equip_item', 'a2 v2 C', [qw(ID type viewid success)]],# 9
		'0110' => ['skill_use_failed', 'v V2 C2', [qw(skillID btype itemId flag cause)]],# 14
		'01D7' => ['sprite_change', 'a4 C V2', [qw(ID type value1 value2)]],# 15
		'022E' => ['homunculus_property', 'Z24 C v3 V v12 V2 v2', [qw(name state level hunger intimacy accessory atk matk hit critical def mdef flee aspd hp hp_max sp sp_max exp exp_max points_skill attack_range)]],# 73
		'022F' => ['homunculus_food', 'C V', [qw(success foodID)]],# 7
		'029B' => ['mercenary_init', 'a4 v8 Z24 v V5 v V2 v', [qw(ID atk matk hit critical def mdef flee aspd name level hp hp_max sp sp_max contract_end faith summons kills attack_range)]],# 80
		'09F7' => ['homunculus_property', 'Z24 C v3 V v8 V2 v2 V2 v2', [qw(name state level hunger intimacy accessory atk matk hit critical def mdef flee aspd hp hp_max sp sp_max exp exp_max points_skill attack_range)]],# 77
		'0A98' => ['equip_item_switch', 'a2 V v', [qw(ID type success)]],# 10
	);
	$self->{packet_list}{$_} = $packets{$_} for keys %packets;

	# ids que o XKore 2 usa ao montar login/char falsos para o cliente 2026 (os mesmos que o mazzathena manda)
	my %handlers = qw(
		account_server_info 0AC4
		received_characters_info 082D
		sync_received_characters 09A0
		received_characters 0B72
		received_character_ID_and_Map 0AC5
		login_pin_code_request 08B9
	);
	$self->{packet_lut}{$_} = $handlers{$_} for keys %handlers;

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
