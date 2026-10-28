# mzmapa - o mazzakore como instrumento de mapeamento do servidor e do protocolo (mazzaro).
#
# Enquanto o bot joga (sozinho ou com o roteiro do mzteste), anota:
#   pacotes recebidos: id, quantas vezes, tamanhos vistos, tamanho esperado no recvpackets, handler do OpenKore e se
#                      o OpenKore trata (tratado | sem_handler | sem_nome); ids fora do recvpackets (desconhecido)
#   pacotes enviados:  id, quantas vezes, tamanhos
#   mundo:             por mapa, NPCs (nome, posicao, sprite), monstros (id, nome, quantos vistos) e portais
# e grava tudo em YAML (config: mzmapa_saida) a cada poucos segundos e ao sair. O mazzaro le com tools/kore_mapa.py.
package mzmapa;

use strict;
use Time::HiRes qw(time);
use Globals qw(%config %rpackets $field $packetParser);
use Log qw(message);
use Plugins;
use Network::PacketParser;
use Network::Send;

Plugins::register('mzmapa', 'mapeamento de pacotes e do mundo para o mazzaro', \&unload);

my $hooks = Plugins::addHooks(
	['parseMsg/pre',     \&on_recv],
	['add_npc_list',     \&on_npc],
	['add_monster_list', \&on_monster],
	['add_portal_list',  \&on_portal],
	['mainLoop_post',    \&on_loop],
);

my (%rx, %tx, %unk, %mundo);
my ($dirty, $lastWrite, $t0) = (0, 0, time);

# envio e id fora do recvpackets nao tem gancho geral: embrulha os dois metodos
my $origSend = \&Network::Send::sendToServer;
my $origUnknown = \&Network::PacketParser::unknownMessage;
{
	no warnings 'redefine';
	*Network::Send::sendToServer = sub {
		my ($self, $msg) = @_;
		if (length($msg) >= 2) {
			my $id = sprintf('%04X', unpack('v', $msg));
			my $e = $tx{$id} ||= { n => 0, tam => {} };
			$e->{n}++;
			$e->{tam}{length $msg}++;
			$dirty = 1;
		}
		return $origSend->(@_);
	};
	*Network::PacketParser::unknownMessage = sub {
		my ($self, $args) = @_;
		my $e = $unk{$args->{switch}} ||= { n => 0, tam => {} };
		$e->{n}++;
		$e->{tam}{length $args->{RAW_MSG}}++;
		$dirty = 1;
		return $origUnknown->(@_);
	};
}

sub unload {
	gravar();
	Plugins::delHooks($hooks);
	no warnings 'redefine';
	*Network::Send::sendToServer = $origSend;
	*Network::PacketParser::unknownMessage = $origUnknown;
}

sub on_recv {
	my (undef, $args) = @_;
	my $id = $args->{switch};
	my $e = $rx{$id};
	if (!$e) {
		my $h = $packetParser && $packetParser->{packet_list}{$id};
		my $estado = !$h ? 'sem_nome' : ($packetParser->can($h->[0]) ? 'tratado' : 'sem_handler');
		$e = $rx{$id} = { n => 0, tam => {}, handler => ($h ? $h->[0] : ''), estado => $estado,
		                  esperado => (exists $rpackets{$id} ? $rpackets{$id}{length} : '') };
	}
	$e->{n}++;
	$e->{tam}{$args->{msg_size}}++;
	$dirty = 1;
}

sub mapa {
	return $field ? $field->baseName : '?';
}

sub on_npc {
	my (undef, $npc) = @_;
	return unless $npc && $npc->{pos_to};
	my $m = mapa();
	my $k = "$npc->{pos_to}{x},$npc->{pos_to}{y}";
	$mundo{$m}{npcs}{$k} ||= { nome => $npc->{name}, x => $npc->{pos_to}{x}, y => $npc->{pos_to}{y},
	                           sprite => $npc->{type} };
	$dirty = 1;
}

sub on_monster {
	my (undef, $mob) = @_;
	return unless $mob;
	my $e = $mundo{mapa()}{monstros}{$mob->{nameID}} ||= { nome => $mob->{name}, vistos => 0 };
	$e->{vistos}++;
	$dirty = 1;
}

sub on_portal {
	my (undef, $p) = @_;
	return unless $p && $p->{pos_to};
	$mundo{mapa()}{portais}{"$p->{pos_to}{x},$p->{pos_to}{y}"} = 1;
	$dirty = 1;
}

sub on_loop {
	return unless $dirty && time - $lastWrite >= 3;
	gravar();
}

sub yq {
	my ($s) = @_;
	$s = '' unless defined $s;
	$s =~ s/\\/\\\\/g;
	$s =~ s/"/\\"/g;
	return "\"$s\"";
}

sub tams {
	my ($h) = @_;
	return '{' . join(', ', map { "$_: $h->{$_}" } sort { $a <=> $b } keys %$h) . '}';
}

sub gravar {
	my $file = $config{mzmapa_saida} or return;
	open(my $fh, '>', $file) or return;
	binmode $fh, ':utf8';
	printf $fh "# mzmapa (mazzakore) - %d s de sessao\n", time - $t0;
	print $fh "recebidos:\n";
	for my $id (sort keys %rx) {
		my $e = $rx{$id};
		printf $fh "  '%s': {n: %d, tam: %s, esperado: %s, handler: %s, estado: %s}\n",
			$id, $e->{n}, tams($e->{tam}), yq($e->{esperado}), yq($e->{handler}), $e->{estado};
	}
	print $fh "desconhecidos:\n";
	printf $fh "  '%s': {n: %d, tam: %s}\n", $_, $unk{$_}{n}, tams($unk{$_}{tam}) for sort keys %unk;
	print $fh "enviados:\n";
	printf $fh "  '%s': {n: %d, tam: %s}\n", $_, $tx{$_}{n}, tams($tx{$_}{tam}) for sort keys %tx;
	print $fh "mundo:\n";
	for my $m (sort keys %mundo) {
		print $fh "  $m:\n";
		my $w = $mundo{$m};
		print $fh "    npcs:\n";
		for my $k (sort keys %{$w->{npcs} || {}}) {
			my $n = $w->{npcs}{$k};
			printf $fh "      - {nome: %s, x: %d, y: %d, sprite: %s}\n", yq($n->{nome}), $n->{x}, $n->{y}, yq($n->{sprite});
		}
		print $fh "    monstros:\n";
		for my $id (sort { $a <=> $b } keys %{$w->{monstros} || {}}) {
			my $e = $w->{monstros}{$id};
			printf $fh "      %d: {nome: %s, vistos: %d}\n", $id, yq($e->{nome}), $e->{vistos};
		}
		print $fh "    portais: [" . join(', ', map { yq($_) } sort keys %{$w->{portais} || {}}) . "]\n";
	}
	close $fh;
	($dirty, $lastWrite) = (0, time);
}

1;
