# autoshop - escolhe um lugar livre para abrir a loja (longe de outras lojas, chats e gente)
#
# Original: plugins/needs-review/autoshop/trunk (openkore/openkore), v0.8, GPLv2.
#   Autor: Arachno <arachnophobia at users dot sf dot net>.
# mazzakore (2026-11-03): reescrito para o core atual, mesma ideia do mapa de pesos 29x29 em volta do personagem:
#   - jogadores vem de $playersList (o original lia %players/@playersID, que o core nao preenche mais);
#   - lojas de %venderLists e chats de %chatRooms, pela posicao do dono;
#   - nao abre a loja sozinho: enquanto o lugar esta ocupado segura o shopAuto_open do core (empurra o
#     timeout ai_shop) e anda para um ponto livre; no ponto livre o core abre a loja com o shop.txt de sempre;
#   - comandos "autoshop" (sugere um ponto) e "autoshop mapa" (grava autoshop_mapa.txt na pasta de logs).
#
# config.txt:
#   autoshop 1                 # liga (precisa de shopAuto_open 1 para a loja abrir)
#   autoshop_maxweight 0       # 0..5: peso maximo aceito como "livre" no ponto da loja
#   autoshop_tries 16          # tentativas por raio antes de dobrar o raio
#   autoshop_radius 5          # 1..14: raio inicial da busca
#   autoshop_inTownOnly 1      # so procura lugar em cidade (padrao 1)
package autoshop;

use strict;
use Plugins;
use Globals qw(%config %timeout $char $field $playersList %venderLists %chatRooms $shopstarted $net);
use Utils qw(calcPosition timeOut);
use Log qw(message warning error debug);
use AI;
use Network;

my $maxRad = 14;
my @peso;          # [x][y], 0..2*maxRad, centro = personagem
my $alvo;          # ponto livre escolhido {x, y}
my %ajuste = (time => 0, timeout => 3);

Plugins::register('autoshop', 'escolhe lugar livre para a loja', \&Unload, \&Unload);
my $hooks = Plugins::addHooks(['AI_pre', \&tick, undef]);
my $cmds = Commands::register(['autoshop', 'autoshop [mapa]: sugere ponto livre para a loja', \&cmd]);

sub Unload {
	Plugins::delHooks($hooks);
	Commands::unregister($cmds);
}

sub opt {
	my ($k, $min, $max, $padrao) = @_;
	my $v = $config{"autoshop_$k"};
	return $padrao unless defined $v && $v =~ /^\d+$/ && $v >= $min && $v <= $max;
	return $v;
}

sub tick {
	return unless $config{autoshop} && $char && $field;
	return unless $net && $net->getState() == Network::IN_GAME;
	return if $shopstarted || $char->{sitting};
	return if opt('inTownOnly', 0, 1, 1) && !$field->isCity;
	return unless timeOut(\%ajuste);
	$ajuste{time} = time;

	if (!AI::isIdle()) {
		# andando para o ponto escolhido: a loja so abre depois de chegar
		$timeout{ai_shop}{time} = time if $alvo && AI::is('move', 'route');
		return;
	}
	montar();
	my $aqui = $peso[$maxRad][$maxRad];
	if ($aqui <= opt('maxweight', 0, 5, 0)) {
		undef $alvo;
		return;   # lugar bom: o shopAuto_open do core abre a loja
	}
	my ($x, $y) = sugerir(opt('radius', 1, $maxRad, 5));
	$timeout{ai_shop}{time} = time;   # segura o core enquanto troca de lugar
	if ($x) {
		$alvo = {x => $x, y => $y};
		message "[autoshop] lugar ocupado (peso $aqui), indo para $x $y\n", 'info';
		$char->route($field->baseName, $x, $y, noMapRoute => 1, attackOnRoute => 0);
	}
}

sub cmd {
	my (undef, $args) = @_;
	return error "[autoshop] fora do jogo\n" unless $char && $field;
	montar();
	if (($args || '') =~ /^mapa/) {
		gravarMapa();
		return;
	}
	my $aqui = $peso[$maxRad][$maxRad];
	message "[autoshop] peso aqui: $aqui (maximo aceito " . opt('maxweight', 0, 5, 0) . ")\n", 'list';
	my ($x, $y) = sugerir(opt('radius', 1, $maxRad, 5));
	message($x ? "[autoshop] ponto livre sugerido: $x $y\n" : "[autoshop] nenhum ponto livre; aumente autoshop_maxweight\n", 'list');
}

sub sugerir {
	my ($raio) = @_;
	$raio = $maxRad if $raio > $maxRad;
	my $pos = calcPosition($char);
	my $max = opt('maxweight', 0, 5, 0);
	for (my $try = 0; $try <= opt('tries', 1, 100, 16); $try++) {
		my $gx = $maxRad + $raio - int(rand($raio * 2 + 1));
		my $gy = $maxRad + $raio - int(rand($raio * 2 + 1));
		next if $peso[$gx][$gy] > $max;
		my ($x, $y) = ($pos->{x} + $gx - $maxRad, $pos->{y} + $gy - $maxRad);
		next unless $field->isWalkable($x, $y);
		return ($x, $y);
	}
	return $raio >= $maxRad ? () : sugerir($raio * 2);
}

sub montar {
	@peso = map { [(0) x (2 * $maxRad + 1)] } 0 .. 2 * $maxRad;
	my $pos = calcPosition($char);
	my %dono;   # ID do jogador => 'loja'|'chat'
	$dono{$_} = 'loja' foreach keys %venderLists;
	$dono{$_->{ownerID}} ||= 'chat' foreach grep { ref $_ && $_->{ownerID} } values %chatRooms;
	foreach my $p (@{$playersList->getItems}) {
		my $pp = calcPosition($p);
		my ($gx, $gy) = ($maxRad + $pp->{x} - $pos->{x}, $maxRad + $pp->{y} - $pos->{y});
		next if $gx < 0 || $gy < 0 || $gx > 2 * $maxRad || $gy > 2 * $maxRad;
		if ($dono{$p->{ID}}) {
			# loja/chat: 5 no ponto, caindo 1 por celula ate 4 de distancia (losango, como o original)
			for my $dx (-4 .. 4) {
				for my $dy (-4 .. 4) {
					my $d = abs($dx) + abs($dy);
					next if $d > 4;
					my ($x, $y) = ($gx + $dx, $gy + $dy);
					next if $x < 0 || $y < 0 || $x > 2 * $maxRad || $y > 2 * $maxRad;
					$peso[$x][$y] += 5 - $d;
				}
			}
		} else {
			$peso[$gx][$gy] += 5;
		}
	}
}

sub gravarMapa {
	my $pos = calcPosition($char);
	my $file = "$Settings::logs_folder/autoshop_mapa.txt";
	open(my $fh, '>', $file) or return error "[autoshop] nao gravei $file: $!\n";
	for (my $gy = 2 * $maxRad; $gy >= 0; $gy--) {
		my $linha = '';
		for my $gx (0 .. 2 * $maxRad) {
			my ($x, $y) = ($pos->{x} + $gx - $maxRad, $pos->{y} + $gy - $maxRad);
			$linha .= ($gx == $maxRad && $gy == $maxRad) ? 'X'
				: !$field->isWalkable($x, $y) ? '#'
				: $peso[$gx][$gy] ? sprintf('%X', $peso[$gx][$gy] > 15 ? 15 : $peso[$gx][$gy]) : '.';
		}
		print $fh "$linha\n";
	}
	close $fh;
	message "[autoshop] mapa em $file\n", 'list';
}

1;
