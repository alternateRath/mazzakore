# =============================================================================
#  mazzaRota - rotas com jeito de gente para os bots fieis do MazzaRO
#  (mazzakore, branch mazzaro; fase F2 de mazzaro/docs/bots/PLANO-JOGADORES.md)
#
#  Regras 10-12 de mazzaro/docs/bots/pesquisa-comportamento.md:
#   - no lockMap troca o randomWalk do core (hook ai_processRandomWalk, a mesma
#     porta do lockMapSweep, que ele substitui): o mapa vira uma grade de
#     sub-areas; o bot fica 10-30 min numa (com preferencia propria por sub-area,
#     "o canto dele"), e so entao passa para outra, quase sempre vizinha
#   - destino escolhido entre varios candidatos pelo que menos repete trecho da
#     ultima hora (memoria de segmentos na grade de 5x5 celulas, a mesma da regua)
#     e pelo que passa por lugar ainda nao visto
#   - paradas depois de chegar (olha em volta), as vezes volta a um ponto anterior;
#     o desvio lateral de cada rota fica com o plugin Drunk (ligado junto)
#   - 1-3 mapas por sessao: etapa do jornada.txt com "mapa1,mapa2,..." -> o
#     mazzaJornada pergunta mazzaRota::mapa(\@abertos) e este escolhe (preferencia
#     por bot) e troca de mapa depois de 15-45 min, ate o numero sorteado na sessao
#   - pausa na cidade: mazzaRota::passeio($id) leva o bot a 1-3 lugares com
#     sentido (Kafra, lojas, onde tem gente, o ponto da cidade) antes de sentar
#   - semente por bot (conta): preferencias de mapa e sub-area diferentes entre
#     bots; a sessao nova (hook mazzaRitmo_chegada) sorteia de novo o resto
#
#  config.txt do bot (todos opcionais; o gerador sorteia por bot):
#   mazzaRota 1                     0 desliga (o core volta ao randomWalk)
#   mazzaRota_grade 0 0             sub-areas em x e y (0 = pelo tamanho: 1 a cada ~60 celulas, 2-4)
#   mazzaRota_permanencia 10 30     minutos numa sub-area
#   mazzaRota_salto 8 30            distancia (celulas) do proximo destino dentro da sub-area
#   mazzaRota_candidatos 8          destinos sorteados por escolha
#   mazzaRota_memoria 60            minutos de memoria de trechos
#   mazzaRota_parada 0.35 3 20      chance de parar ao chegar, de 3-20 s
#   mazzaRota_volta 0.06            chance de voltar a um destino anterior
#   mazzaRota_longe 0.15            chance de a proxima sub-area nao ser vizinha
#   mazzaRota_mapas 45 35 20        % de sessoes com 1, 2 e 3 mapas (etapa com alternativas)
#   mazzaRota_troca 15 45           minutos num mapa antes de poder trocar
#   mazzaRota_cidade 1 3 10 60      lugares por pausa na cidade e segundos em cada
#   mazzaRota_semente <texto>       padrao: username
#   mazzaRota_teste 0               >0: minutos viram segundos x este fator (teste rapido)
#
#  Console:  rota [status|grade|memoria|trocar|passeio]
#  Perl 5.12 (o do start.exe): nada de s///r, sem POSIX, File::Spec->... e nao Functions.
# =============================================================================
package mazzaRota;

use strict;
use warnings;
use Time::HiRes qw(time);
use Digest::MD5 qw(md5);

use Plugins;
use Globals qw($char %config %timeout $field $net $npcsList $playersList);
use Log qw(message warning debug);
use AI qw(ai_route);
use Commands;
use Network;
use Utils qw(distance);

my $NAME = 'mazzaRota';
Plugins::register($NAME, 'Rotas com jeito de gente dos bots do MazzaRO', \&unload, \&unload);

my $hooks = Plugins::addHooks(
	['ai_processRandomWalk', \&onRandomWalk],
	['AI_pre',               \&onAI],
	['mazzaRitmo_chegada',   \&onChegada],
	['start3',               \&novaSessao],
);
my $cmds = Commands::register(['rota', 'Rotas do mazzaRota (status|grade|memoria|trocar|passeio)', \&cmdRota]);

sub unload { Plugins::delHooks($hooks); Commands::unregister($cmds); }

# ------------------------------------------------------------ parametros ---
sub cfg  { my ($k, $d) = @_; my $v = $config{"${NAME}_$k"}; return defined $v && length $v ? $v : $d; }
sub nums { my ($k, @d) = @_; my @v = grep { length } split /[\s,]+/, cfg($k, ''); return @v >= @d ? @v[0 .. $#d] : @d; }
sub ligado { return !defined $config{$NAME} || !length $config{$NAME} || $config{$NAME} ? 1 : 0; }
sub semente { return cfg('semente', $config{username} || 'bot'); }
# minutos -> segundos (no teste, minutos viram segundos x fator)
sub minS { my $t = cfg('teste', 0); return $_[0] * ($t > 0 ? $t : 60); }

# uniforme deterministico em [0,1) por chave (preferencias fixas do bot)
sub u { return unpack('N', md5(join('|', semente(), @_))) / 4294967296; }
sub rnd { my ($a, $b) = @_; return $a + rand($b - $a); }
sub sorteio {   # (\%peso) -> chave
	my ($w) = @_;
	my $tot = 0; $tot += $_ for values %$w;
	return (keys %$w)[0] unless $tot > 0;
	my $r = rand($tot);
	for my $k (sort keys %$w) { $r -= $w->{$k}; return $k if $r < 0; }
	return (sort keys %$w)[-1];
}

# --------------------------------------------------------------- estado ---
my %S;          # sessao: mapas => {m=>1}, maxMapas, mapa, mapaDesde, trocaApos, etapa
my %G;          # grade do mapa atual: mapa w h bits nx ny bx0 by0 bw bh sub=>[{n, x0..}], pref=>[]
my %A;          # andar: sub, subAte, alvo, alvos(ultimos), paradaAte, chegouEm, decisoes
my @SEG;        # [t, chave] na ordem
my %SEGN;       # chave -> vezes na memoria
my %VISTO;      # "mapa|qx,qy" -> ultima vez
my ($ultQ, $ultQmapa, $ultPos, $ultPoda) = ('', '', 0, 0);
my %P;          # passeio na cidade: id plano(i) chegou sai desde
my %conta = (destinos => 0, subareas => 0, paradas => 0, voltas => 0, trocas => 0, passeios => 0);
my $CEL = 5;    # grade de 5x5 celulas da regua (tools/mz/bots_regua.py)

sub novaSessao {
	my @pct = nums('mapas', 45, 35, 20);
	my $r = rand($pct[0] + $pct[1] + $pct[2]);
	my $max = $r < $pct[0] ? 1 : $r < $pct[0] + $pct[1] ? 2 : 3;
	%S = (mapas => {}, maxMapas => $max, mapa => '', etapa => '', mapaDesde => time, trocaApos => 0);
	%A = ();
}

sub onChegada { my (undef, $a) = @_; novaSessao() if $a && $a->{fala}; }

# ------------------------------------------------- mapas da etapa (API) ---
# mazzaJornada: mazzaRota::mapa(\@abertos) -> mapa desta sessao
sub mapa {
	my ($lista) = @_;
	return undef unless $lista && @$lista;
	return $lista->[0] if @$lista == 1 || !ligado();
	novaSessao() unless %S;
	my $k = join(',', @$lista);
	if ($S{etapa} ne $k || !grep { $_ eq $S{mapa} } @$lista) {
		$S{etapa} = $k;
		$S{mapas} = {};
		escolherMapa($lista);
	}
	return $S{mapa};
}

sub escolherMapa {
	my ($lista) = @_;
	my %w;
	for my $m (@$lista) {
		next if $m eq $S{mapa};
		# o primeiro da lista e o "classico" da etapa: peso maior; o resto pela preferencia do bot
		$w{$m} = ($m eq $lista->[0] ? 1.5 : 0.4) * exp(2 * (u('mapa', $m) - 0.5));
		$w{$m} *= 0.25 if $S{mapas}{$m};    # ja passou por ele nesta sessao
	}
	return unless %w;
	my $novo = sorteio(\%w);
	message "[$NAME] mapa da sessao: $novo" . ($S{mapa} ? " (antes $S{mapa})" : '') . "\n", 'info' if $S{mapa};
	$S{mapa} = $novo;
	$S{mapas}{$novo} = 1;
	$S{mapaDesde} = time;
	my ($a, $b) = nums('troca', 15, 45);
	$S{trocaApos} = minS(rnd($a, $b));
}

# chamado na troca de sub-area: hora de mudar de mapa?
sub talvezTrocarMapa {
	my @lista = split /,/, $S{etapa} || '';
	return 0 unless @lista > 1;
	return 0 if keys %{ $S{mapas} } >= $S{maxMapas};
	return 0 if time - $S{mapaDesde} < $S{trocaApos};
	escolherMapa(\@lista);
	$conta{trocas}++;
	return 1;    # o mazzaJornada poe o lockMap novo no proximo tique
}

# -------------------------------------------------------------- grade ---
sub montarGrade {
	my $m = $field->baseName;
	return 1 if $G{mapa} && $G{mapa} eq $m;
	my ($w, $h) = ($field->width, $field->height);
	# maior componente conexa de celulas andaveis (como o lockMapSweep), em bits
	my ($bits, $vis) = ('', '');
	vec($bits, $w * $h, 1) = 0; vec($vis, $w * $h, 1) = 0;
	my ($melhor, $melhorN) = ('', 0);
	for my $y (1 .. $h - 2) {
		for my $x (1 .. $w - 2) {
			my $i = $y * $w + $x;
			next if vec($vis, $i, 1) || !$field->isWalkable($x, $y);
			my ($comp, $n) = ('', 0);
			vec($comp, $w * $h, 1) = 0;
			my @fila = ($i);
			vec($vis, $i, 1) = 1;
			while (@fila) {
				my $j = shift @fila;
				vec($comp, $j, 1) = 1; $n++;
				my ($cx, $cy) = ($j % $w, int($j / $w));
				for my $d ([-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]) {
					my ($nx, $ny) = ($cx + $d->[0], $cy + $d->[1]);
					next if $nx < 1 || $ny < 1 || $nx >= $w - 1 || $ny >= $h - 1;
					my $k = $ny * $w + $nx;
					next if vec($vis, $k, 1) || !$field->isWalkable($nx, $ny);
					vec($vis, $k, 1) = 1;
					push @fila, $k;
				}
			}
			($melhor, $melhorN) = ($comp, $n) if $n > $melhorN;
		}
	}
	return 0 unless $melhorN;
	my ($x0, $y0, $x1, $y1) = ($w, $h, 0, 0);
	for my $y (1 .. $h - 2) {
		for my $x (1 .. $w - 2) {
			next unless vec($melhor, $y * $w + $x, 1);
			$x0 = $x if $x < $x0; $x1 = $x if $x > $x1;
			$y0 = $y if $y < $y0; $y1 = $y if $y > $y1;
		}
	}
	my ($gx, $gy) = nums('grade', 0, 0);
	my $auto = sub { my $n = int($_[0] / 60 + 0.5); return $n < 2 ? 2 : $n > 4 ? 4 : $n; };
	$gx = $auto->($x1 - $x0 + 1) unless $gx > 0;
	$gy = $auto->($y1 - $y0 + 1) unless $gy > 0;
	%G = (mapa => $m, w => $w, h => $h, bits => $melhor, n => $melhorN, nx => $gx, ny => $gy,
	      x0 => $x0, y0 => $y0, bw => ($x1 - $x0 + 1) / $gx, bh => ($y1 - $y0 + 1) / $gy, sub => [], pref => []);
	for my $s (0 .. $gx * $gy - 1) {
		my ($sx, $sy) = ($s % $gx, int($s / $gx));
		my %b = (x0 => int($x0 + $sx * $G{bw}), y0 => int($y0 + $sy * $G{bh}));
		$b{x1} = int($x0 + ($sx + 1) * $G{bw}) - 1; $b{y1} = int($y0 + ($sy + 1) * $G{bh}) - 1;
		my $c = 0;
		for my $y ($b{y0} .. $b{y1}) { for my $x ($b{x0} .. $b{x1}) { $c++ if vec($melhor, $y * $w + $x, 1); } }
		$b{n} = $c;
		push @{ $G{sub} }, \%b;
		# "o canto dele": preferencia lognormal fixa por bot, mapa e sub-area (0,3x a 3,3x)
		push @{ $G{pref} }, $c < 30 ? 0 : exp(2.4 * (u('sub', $m, $s) - 0.5)) * sqrt($c);
	}
	%A = ();
	message sprintf("[%s] %s: %dx%d sub-areas, %d celulas andaveis\n", $NAME, $m, $gx, $gy, $melhorN), 'info';
	return 1;
}

sub anda { my ($x, $y) = @_; return $x > 0 && $y > 0 && $x < $G{w} && $y < $G{h} && vec($G{bits}, $y * $G{w} + $x, 1); }
sub subDe {
	my ($x, $y) = @_;
	my $sx = int(($x - $G{x0}) / $G{bw}); my $sy = int(($y - $G{y0}) / $G{bh});
	$sx = 0 if $sx < 0; $sy = 0 if $sy < 0;
	$sx = $G{nx} - 1 if $sx >= $G{nx}; $sy = $G{ny} - 1 if $sy >= $G{ny};
	return $sy * $G{nx} + $sx;
}

sub proximaSub {
	my ($de) = @_;
	my ($dx, $dy) = ($de % $G{nx}, int($de / $G{nx}));
	my %w;
	my $longe = rand() < cfg('longe', 0.15);
	for my $s (0 .. $#{ $G{sub} }) {
		next if $s == $de || !$G{pref}[$s];
		my ($sx, $sy) = ($s % $G{nx}, int($s / $G{nx}));
		my $viz = abs($sx - $dx) + abs($sy - $dy) == 1;
		next if !$viz && !$longe;
		my $p = $G{pref}[$s];
		$p *= 0.3 if $A{subVista}{$s} && time - $A{subVista}{$s} < minS(cfg('memoria', 60));
		$w{$s} = $p;
	}
	return %w ? sorteio(\%w) : $de;
}

# ----------------------------------------------------- memoria de trechos ---
sub qc { return int($_[0] / $CEL) . ',' . int($_[1] / $CEL); }

sub registrar {   # posicao propria, ~2x por segundo
	return unless $char && $field;
	my $m = $field->baseName;
	my $p = $char->position or return;
	my $q = qc($p->{x}, $p->{y});
	if ($ultQmapa eq $m && $ultQ ne '' && $q ne $ultQ) {
		my $k = "$m|$ultQ>$q";
		push @SEG, [time, $k];
		$SEGN{$k}++;
	}
	$VISTO{"$m|$q"} = time;
	($ultQ, $ultQmapa) = ($q, $m);
	if (time - $ultPoda > 30) {
		$ultPoda = time;
		my $lim = time - minS(cfg('memoria', 60));
		while (@SEG && $SEG[0][0] < $lim) { my $k = (shift @SEG)->[1]; delete $SEGN{$k} unless --$SEGN{$k} > 0; }
		for (keys %VISTO) { delete $VISTO{$_} if $VISTO{$_} < $lim; }
	}
}

# custo de ir em linha reta de $a a $b: trechos repetidos (ida 1, volta 0,5) menos celulas novas
sub custo {
	my ($a, $b) = @_;
	my $m = $G{mapa};
	my ($dx, $dy) = ($b->{x} - $a->{x}, $b->{y} - $a->{y});
	my $n = abs($dx) > abs($dy) ? abs($dx) : abs($dy);
	$n = 1 if $n < 1;
	my ($rep, $novo, $ant) = (0, 0, qc($a->{x}, $a->{y}));
	for my $i (1 .. $n) {
		my $q = qc(int($a->{x} + $dx * $i / $n + 0.5), int($a->{y} + $dy * $i / $n + 0.5));
		next if $q eq $ant;
		$rep += 1 if $SEGN{"$m|$ant>$q"};
		$rep += 0.5 if $SEGN{"$m|$q>$ant"};
		$novo++ unless $VISTO{"$m|$q"};
		$ant = $q;
	}
	return 3 * $rep - $novo;
}

# ------------------------------------------------------------ destino ---
sub celulaNa {   # celula andavel ao acaso na sub-area $s, a $d1-$d2 de $de (se der)
	my ($s, $de, $d1, $d2) = @_;
	my $b = $G{sub}[$s] or return;
	for my $t (1 .. 60) {
		my $x = $b->{x0} + int(rand($b->{x1} - $b->{x0} + 1));
		my $y = $b->{y0} + int(rand($b->{y1} - $b->{y0} + 1));
		next unless anda($x, $y);
		if ($de && $t <= 40) {
			my $d = distance($de, { x => $x, y => $y });
			next if $d < $d1 || $d > $d2;
		}
		return { x => $x, y => $y };
	}
	return;
}

sub escolherDestino {
	my $pos = $char->position;
	my $s = $A{sub};
	# volta a um destino de antes (gente volta pra onde tinha monstro)
	if (@{ $A{alvos} || [] } > 2 && rand() < cfg('volta', 0.06)) {
		my @c = grep { subDe($_->{x}, $_->{y}) == $s } @{ $A{alvos} }[0 .. $#{ $A{alvos} } - 1];
		if (@c) { $conta{voltas}++; return $c[int rand @c]; }
	}
	my ($d1, $d2) = nums('salto', 8, 30);
	my $mudou = subDe($pos->{x}, $pos->{y}) != $s;     # indo para a sub-area nova: qualquer distancia
	my ($melhor, $mc);
	for (1 .. cfg('candidatos', 8)) {
		my $c = celulaNa($s, $mudou ? undef : $pos, $d1, $d2) or next;
		my $k = custo($pos, $c) + rand(2);
		($melhor, $mc) = ($c, $k) if !defined $mc || $k < $mc;
	}
	return $melhor;
}

sub onRandomWalk {
	my (undef, $args) = @_;
	return unless ligado() && $char && $field && $config{lockMap};
	return unless $field->baseName eq $config{lockMap};
	return unless montarGrade();
	my $pos = $char->position;
	if (!defined $A{sub}) {
		$A{sub} = subDe($pos->{x}, $pos->{y});
		$A{sub} = proximaSub($A{sub}) unless $G{pref}[$A{sub}];
		my ($a, $b) = nums('permanencia', 10, 30);
		$A{subAte} = time + minS(rnd($a, $b));
		$A{subVista}{$A{sub}} = time;
	}
	# HP baixo e sem poder sentar (aprendiz sem Habilidades Basicas 3): espera em pe ate passar do limite de levantar
	my $hp = $char->{hp_max} ? 100 * $char->{hp} / $char->{hp_max} : 100;
	if (!$char->{sitting} && ($config{sitAuto_hp_lower} || 0) > 0
	    && ($hp < $config{sitAuto_hp_lower} || ($A{descansando} && $hp < ($config{sitAuto_hp_upper} || 85)))) {
		$A{descansando} = 1;
		$args->{return} = 1;
		return;
	}
	$A{descansando} = 0;
	# parado (olhando em volta): o core fica quieto, o ataque automatico continua
	if ($A{paradaAte} && time < $A{paradaAte}) {
		if ($A{olhar} && time >= $A{olhar}) {
			Commands::run('look ' . int(rand 8) . ' ' . int(rand 3));
			$A{olhar} = rand() < 0.5 ? time + rnd(2, 6) : 0;
		}
		$args->{return} = 1;
		return;
	}
	# chegou ao destino anterior: talvez parar
	if ($A{alvo} && !$A{paradaAte} && distance($pos, $A{alvo}) <= 3) {
		my ($pc, $pa, $pb) = nums('parada', 0.35, 3, 20);
		undef $A{alvo};    # uma decisao por destino
		if (rand() < $pc) {
			$A{paradaAte} = time + rnd($pa, $pb) * (cfg('teste', 0) > 0 ? cfg('teste', 0) / 60 : 1);
			$A{olhar} = rand() < 0.6 ? time + rnd(1, 4) : 0;
			$conta{paradas}++;
			$args->{return} = 1;
			return;
		}
	}
	$A{paradaAte} = 0;
	# hora de mudar de sub-area (ou de mapa)
	if (time >= $A{subAte}) {
		if (talvezTrocarMapa()) { $args->{return} = 1; return; }
		my $ant = $A{sub};
		$A{sub} = proximaSub($ant);
		my ($a, $b) = nums('permanencia', 10, 30);
		$A{subAte} = time + minS(rnd($a, $b));
		$A{subVista}{$A{sub}} = time;
		$conta{subareas}++;
		message sprintf("[%s] sub-area %d -> %d (%d min)\n", $NAME, $ant, $A{sub}, ($A{subAte} - time) / 60), 'route';
	}
	my $alvo = escolherDestino() or return;    # sem destino: o core sorteia como antes
	$A{alvo} = $alvo;
	push @{ $A{alvos} }, $alvo; shift @{ $A{alvos} } while @{ $A{alvos} } > 6;
	$conta{destinos}++;
	$args->{return} = 1;
	debug sprintf("[%s] destino %d,%d na sub-area %d\n", $NAME, $alvo->{x}, $alvo->{y}, $A{sub}), 'route';
	my $aa = $config{attackAuto};
	ai_route($field->baseName, $alvo->{x}, $alvo->{y},
		maxRouteTime => $config{route_randomWalk_maxRouteTime},
		attackOnRoute => (!defined $aa || $aa < 0) ? 0 : ($aa >= 2 ? 2 : 1),
		noMapRoute => ($config{route_randomWalk} == 2 ? 1 : 0),
		isRandomWalk => 1);
}

# ------------------------------------------------------ passeio na cidade ---
# mazzaJornada (pausa): mazzaRota::passeio($id) -> 1 enquanto passeia, 0 quando acabou (ai senta)
sub passeio {
	my ($id) = @_;
	return 0 unless ligado() && $char && $field;
	my $m = $field->baseName;
	if (!defined $P{id} || $P{id} ne $id || $P{mapa} ne $m) {
		my ($n1, $n2) = nums('cidade', 1, 3, 10, 60);
		%P = (id => $id, mapa => $m, i => 0, plano => [lugares($n1 + int rand($n2 - $n1 + 1))]);
		$conta{passeios}++ if @{ $P{plano} };
		message sprintf("[%s] passeio: %s\n", $NAME,
			join(', ', map { $_->{nome} } @{ $P{plano} }) || 'nenhum lugar'), 'info';
	}
	my $l = $P{plano}[ $P{i} ] or return 0;
	my $pos = $char->position;
	if (!$P{chegou}) {
		if (distance($pos, $l) <= 2) {
			my (undef, undef, $s1, $s2) = nums('cidade', 1, 3, 10, 60);
			($P{chegou}, $P{sai}) = (time, time + rnd($s1, $s2));
			Commands::run('look ' . int(rand 8)) if rand() < 0.5;
		} elsif (time - ($P{desde} ||= time) > 120) {   # nao chegou: proximo
			($P{desde}, $P{chegou}) = (undef, 0); $P{i}++;
		} elsif (!AI::is('route', 'mapRoute') && time - ($P{mov} || 0) > 6) {
			Commands::run('stand') if $char->{sitting};
			Commands::run("move $l->{x} $l->{y}");
			$P{mov} = time;
		}
		return 1;
	}
	if (time >= $P{sai}) { ($P{chegou}, $P{desde}) = (0, undef); $P{i}++; }
	return 1;
}

# lugares com sentido no mapa atual: Kafra, lojas, perto de quem esta parado, ponto da cidade
sub lugares {
	my ($n) = @_;
	my @c;
	my $perto = sub {   # uma celula andavel a 2-4 do ponto, de um lado sorteado
		my ($x, $y) = @_;
		for (1 .. 20) {
			my ($cx, $cy) = ($x + int(rnd(-4, 5)), $y + int(rnd(-4, 5)));
			next if abs($cx - $x) + abs($cy - $y) < 2;
			return ($cx, $cy) if $field->isWalkable($cx, $cy);
		}
		return;
	};
	if ($npcsList) {
		for my $npc (@{ $npcsList->getItems }) {
			my $nome = $npc->{name} || '';
			next unless $nome =~ /kafra|ferrament|utilidade|armas|armadura|loja|vendedor|mercador|tool|weapon|armor|dealer|merchant/i;
			my @p = $perto->($npc->{pos}{x}, $npc->{pos}{y}) or next;
			push @c, { nome => $nome, x => $p[0], y => $p[1], w => $nome =~ /kafra/i ? 3 : 2 };
		}
	}
	if ($playersList) {
		for my $pl (@{ $playersList->getItems }) {
			next unless $pl->{pos_to};
			my @p = $perto->($pl->{pos_to}{x}, $pl->{pos_to}{y}) or next;
			push @c, { nome => 'perto de ' . ($pl->{name} || 'alguem'), x => $p[0], y => $p[1], w => 1.5 };
		}
	}
	if (defined &mazzaJornada::pontoDaCidade) {
		if (my $pt = mazzaJornada::pontoDaCidade($field->baseName)) {
			push @c, { nome => 'ponto', x => $pt->{x}, y => $pt->{y}, w => 2.5 };
		}
	}
	my @plano;
	while (@plano < $n && @c) {
		my %w = map { $_ => $c[$_]{w} } 0 .. $#c;
		my $i = sorteio(\%w);
		push @plano, splice(@c, $i, 1);
	}
	return @plano;
}

# --------------------------------------------------------------- tique ---
sub onAI {
	return unless ligado() && $net && $net->getState() == Network::IN_GAME;
	# descansando: nao puxa briga nova (revidar continua: so segura quando ninguem esta batendo)
	if ($A{descansando} && $timeout{ai_attack_auto} && !AI::ai_getAggressives()) {
		$timeout{ai_attack_auto}{time} = time;
	}
	return if time - $ultPos < 0.5;
	$ultPos = time;
	registrar();
}

sub cmdRota {
	my (undef, $arg) = @_;
	$arg = '' unless defined $arg;
	if ($arg eq 'grade') {
		return message "[$NAME] grade ainda nao montada (so no lockMap)\n" unless $G{mapa};
		for my $s (0 .. $#{ $G{sub} }) {
			my $b = $G{sub}[$s];
			message sprintf("  %d: %d,%d-%d,%d  %d celulas  pref %.2f%s\n", $s, @$b{qw(x0 y0 x1 y1 n)}, $G{pref}[$s],
				defined $A{sub} && $A{sub} == $s ? '  <- aqui' : ''), 'list';
		}
		return;
	}
	if ($arg eq 'memoria') {
		my %por; $por{$_->[1]}++ for @SEG;
		my $dist = scalar keys %por;
		message sprintf("[%s] memoria: %d trechos, %d distintos (indice %.2f), %d celulas vistas\n", $NAME,
			scalar @SEG, $dist, $dist ? @SEG / $dist : 0, scalar keys %VISTO), 'info';
		return;
	}
	if ($arg eq 'trocar') { $A{subAte} = 0; $S{trocaApos} = 0; message "[$NAME] troca no proximo destino\n"; return; }
	if ($arg eq 'passeio') {
		return message "[$NAME] passeio: nenhum\n" unless $P{plano};
		message sprintf("[%s] passeio %s: %d/%d %s\n", $NAME, $P{mapa}, $P{i}, scalar @{ $P{plano} },
			join(', ', map { "$_->{nome} ($_->{x},$_->{y})" } @{ $P{plano} })), 'info';
		return;
	}
	message sprintf("[%s] %s | sub-area %s (mais %d s) | sessao: mapa %s, %d de ate %d mapas | %s\n", $NAME,
		ligado() ? 'ligado' : 'desligado', defined $A{sub} ? $A{sub} : '-', $A{subAte} ? $A{subAte} - time : 0,
		$S{mapa} || '-', scalar keys %{ $S{mapas} || {} }, $S{maxMapas} || 0,
		join(' ', map { "$_=$conta{$_}" } sort keys %conta)), 'info';
}

1;
