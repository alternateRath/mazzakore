# Drunk - rotas menos retas: o personagem nao anda sempre pela linha otima entre dois pontos
#
# Ideia do plugin Drunk de Henrybk (https://github.com/Henrybk/Plugins/tree/master/Drunk, commit 473f544,
# 2022-09-29), que trocava o pathfinding inteiro por uma DLL XS propria (DrunkPath.dll) com custo aleatorio.
# A DLL nao carrega com seguranca no Perl 5.12 do start.exe, entao aqui e uma reescrita em Perl puro, sem
# codigo do original: usa o que o pathfinding do core ja aceita no hook getRoute:
#   - randomFactor: ruido por celula (o A* do core soma rand() % randomFactor ao custo), desvios pequenos;
#   - customWeights/secondWeightMap: uma ou duas "manchas" de custo alto perto da linha reta entre a origem e o
#     destino, de um lado sorteado, para a rota fazer curva como quem desvia de alguma coisa.
# mazzakore (2026-11-03).
#
# config.txt:
#   drunk 4               # 0 desliga; ruido por celula (o custo de um passo reto e 10)
#   drunk_curves 1        # 0..3 manchas por rota (padrao 1)
#   drunk_curveWeight 40  # custo extra dentro da mancha (padrao 40)
#   drunk_chance 70       # % das rotas que ganham curva (padrao 70); o ruido vale para todas
#   drunk_minDist 15      # so rotas com pelo menos esse tanto de celulas (padrao 15)
#
# Nao mexe em rotas de seguir, fugir, pegar item, voltar para o mestre/slave, LOS de ataque etc.
package Drunk;

use strict;
use Plugins;
use Globals qw(%config);
use Log qw(debug);

Plugins::register('Drunk', 'rotas menos retas (Perl puro)', \&Unload, \&Unload);
my $hooks = Plugins::addHooks(['getRoute', \&getRoute, undef]);

sub Unload { Plugins::delHooks($hooks); }

our %conta = (ruido => 0, curva => 0);   # rotas mexidas desde o load (para conferir: eval $Drunk::conta{curva})

my @PULA = qw(LOSSubRoute meetingSubRoute isIdleWalk isSlaveRescue isMoveNearSlave isEscape isItemTake
	isItemGather runFromTarget isFollow isDeath);

sub getRoute {
	my (undef, $args) = @_;
	my $drunk = $config{drunk};
	return unless $drunk && $drunk > 0;
	my $task = $args->{self};
	return unless ref $task;   # chamada estatica (so medir distancia): deixa como esta
	return if grep { $task->{$_} } @PULA;

	my ($s, $d, $field) = @{$args}{qw(start dest field)};
	return unless $s && $d && $field;
	my ($dx, $dy) = ($d->{x} - $s->{x}, $d->{y} - $s->{y});
	my $dist = sqrt($dx * $dx + $dy * $dy);
	return if $dist < (defined $config{drunk_minDist} ? $config{drunk_minDist} : 15);

	$args->{randomFactor} = int($drunk) if !$args->{randomFactor} || $args->{randomFactor} < $drunk;
	$conta{ruido}++;

	my $chance = defined $config{drunk_chance} ? $config{drunk_chance} : 70;
	return unless rand(100) < $chance;
	my $n = defined $config{drunk_curves} ? $config{drunk_curves} : 1;
	$n = 3 if $n > 3;
	return unless $n > 0;

	my $peso = $config{drunk_curveWeight} || 40;
	my ($w, $h) = ($field->width, $field->height);
	my %cel;   # "x,y" => peso
	# o que outro plugin (avoidObstacles) ja pos fica, com o maior peso por celula
	if ($args->{customWeights} && ref $args->{secondWeightMap} eq 'ARRAY') {
		$cel{"$_->{x},$_->{y}"} = $_->{weight} foreach @{$args->{secondWeightMap}};
	}
	my ($px, $py) = (-$dy / $dist, $dx / $dist);   # perpendicular unitaria
	my $lado = rand() < 0.5 ? -1 : 1;
	my $r = int($dist * 0.15);
	$r = 3 if $r < 3;
	$r = 10 if $r > 10;
	for my $k (1 .. $n) {
		my $t = ($k - 0.5) / $n * 0.5 + 0.25 + (rand(0.2) - 0.1);   # entre 25% e 75% do caminho
		my $off = $lado * $r * (0.3 + rand(0.7));                   # a mancha encosta na linha reta
		my $cx = int($s->{x} + $dx * $t + $px * $off);
		my $cy = int($s->{y} + $dy * $t + $py * $off);
		for my $x ($cx - $r .. $cx + $r) {
			next if $x < 0 || $x >= $w;
			for my $y ($cy - $r .. $cy + $r) {
				next if $y < 0 || $y >= $h;   # o XS nao confere limite: celula fora do mapa corromperia memoria
				next if ($x - $cx) ** 2 + ($y - $cy) ** 2 > $r * $r;
				# nao bloqueia origem nem destino
				next if abs($x - $s->{x}) + abs($y - $s->{y}) < 2 || abs($x - $d->{x}) + abs($y - $d->{y}) < 2;
				my $k2 = "$x,$y";
				$cel{$k2} = $peso if !defined $cel{$k2} || $cel{$k2} < $peso;
			}
		}
		$lado = -$lado if rand() < 0.5;
	}
	return unless %cel;
	$conta{curva}++;
	$args->{customWeights} = 1;
	$args->{secondWeightMap} = [map { my ($x, $y) = split /,/; +{x => $x, y => $y, weight => $cel{$_}} } keys %cel];
	debug sprintf("[Drunk] rota %d,%d -> %d,%d com %d celulas de desvio\n",
		$s->{x}, $s->{y}, $d->{x}, $d->{y}, scalar keys %cel), 'route';
}

1;
