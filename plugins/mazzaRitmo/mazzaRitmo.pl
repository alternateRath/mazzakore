# =============================================================================
#  mazzaRitmo - ritmo e agenda humanos para os bots fieis do MazzaRO
#  (mazzakore, branch mazzaro; fase F1 de mazzaro/docs/bots/PLANO-JOGADORES.md)
#
#  Regras 1-9 de mazzaro/docs/bots/pesquisa-comportamento.md:
#   - agenda: dias de jogo por semana, horas por semana lognormais, entradas por
#     Poisson seguindo a curva de horario do Brasil e o perfil do jogador, sessoes
#     35% curtas (2-15 min) + 65% Weibull; fora da sessao o bot faz "relog <s>"
#   - reacao: atrasos lognormais com cauda Pareto, nunca < 120 ms, mais lentos com
#     ping alto, aplicados pelos timeouts do timeoutRandomizer (o sorteio dele vira
#     o nosso) e sem grade fixa no laco principal (sleepTime variavel)
#   - AFK curto, uma pausa maior por hora (o mazzaJornada leva o bot pra cidade),
#     sessao que as vezes acaba no meio da luta, limiar de sentar/pocao sorteado
#
#  A agenda e deterministica: semente (conta do bot) + data. Reiniciar o OpenKore
#  no meio do dia cai na mesma sessao planejada; "ritmo simular" mostra 4 semanas.
#
#  Fala com o mazzaJornada por hooks (ele fala e anda; o mazzaRitmo decide quando):
#   mazzaRitmo_chegada {fala}       entrou numa sessao (fala = 1: acabou de comecar)
#   mazzaRitmo_saida   {luta}       hora de sair; quem falar a despedida poe falou => 1
#   mazzaRitmo_pausa   {dur}        pausa maior; quem levar o bot pra cidade poe tratado => 1
#                                   (o fim e quando mazzaJornada::emPausa() deixa de valer)
#  e mazzaRitmo::parado() (AFK/pausa/saindo) e mazzaRitmo::agenda() (a agenda manda).
#
#  config.txt do bot (todos opcionais; o gerador sorteia por bot):
#   mazzaRitmo 1                     0 desliga o plugin
#   mazzaRitmo_agenda 1              0 = sempre online (AFK, pausa e reacao seguem)
#   mazzaRitmo_perfil estudante      estudante | trabalhador | noturno | fim-de-semana
#   mazzaRitmo_deslocamento 0        minutos (-60..60): a janela propria do bot
#   mazzaRitmo_horas_semana 10       mediana de horas por semana (varia por semana)
#   mazzaRitmo_dias 4                dias de jogo por semana (3-6; +-1 por semana)
#   mazzaRitmo_curtas 0.35           fracao de passadas rapidas (2-15 min)
#   mazzaRitmo_weibull 0.8 90        forma e escala (min) das sessoes longas
#   mazzaRitmo_teto 480              minutos
#   mazzaRitmo_reacao 0.45 0.5 0.06  mediana (s), sigma do lognormal, fracao de cauda
#   mazzaRitmo_ping 40               ms; atrasos x (1 + ping/200)
#   mazzaRitmo_afk 15 40 1 5         AFK a cada 15-40 min, de 1-5 min
#   mazzaRitmo_pausa 45 75 5 20      pausa a cada 45-75 min, de 5-20 min
#   mazzaRitmo_meio_luta 0.25        chance de a sessao acabar no meio da luta
#   mazzaRitmo_limiar 25 60          % de HP para sentar e para tomar pocao
#   mazzaRitmo_sleep 4000 18000      us do laco principal (sleepTime) sorteado a cada volta
#   mazzaRitmo_timeouts <nome> <min> <max>, ...   faixas extras/trocadas
#   mazzaRitmo_semente <texto>       padrao: username
#   mazzaRitmo_teste 120 45          teste: sessao de ~120 s, volta em ~45 s (tudo em escala)
#
#  Console:  ritmo [status|agenda [dias]|simular [semanas]|sair|afk|pausa]   (afk e pausa: agora)
#  Perl 5.12 (o do start.exe): nada de s///r, e sem POSIX (nao vem no start.exe).
# =============================================================================
package mazzaRitmo;

use strict;
use warnings;
use Time::HiRes qw(time);
use Digest::MD5 qw(md5);

use Plugins;
use Globals qw($char %config %timeout $net);
use Log qw(message warning);
use Commands;
use Settings;
use Network;
use Misc;
use AI;

my $NAME = 'mazzaRitmo';
Plugins::register($NAME, 'Ritmo e agenda humanos dos bots do MazzaRO', \&unload, \&unload);

my $hooks = Plugins::addHooks(
	['start3',        \&onStart],
	['mainLoop_pre',  \&onLoop],
	['pos_load_timeouts.txt', \&onTimeoutsTxt],
);
my $cmds = Commands::register(['ritmo', 'Ritmo e agenda (status|agenda|simular|sair|afk|pausa)', \&cmdRitmo]);

my $TR = 'OpenKore::Plugins::timeoutRandomizer';
my $origSorteio;

# --------------------------------------------------------------- estado ---
my $estado = 'fora';       # fora | jogando | afk | pausa | saindo
my %ses;                   # sessao ao vivo: inicio fim plano afkEm afkFim pausaEm pausaFim relogEm cortaLuta
my ($iniciado, $timeoutsOk, $checouAntes, $ultimoTick, $saudouPlano) = (0, 0, 0, 0, 0);
my ($afkManual, $sentou) = (0, 0);

sub unload {
	Plugins::delHooks($hooks);
	Commands::unregister($cmds);
	if ($origSorteio) { no strict 'refs'; no warnings 'redefine'; *{"${TR}::_assign_random_timeout"} = $origSorteio; }
	AI::state(AI::AUTO) if $afkManual;
}

sub onTimeoutsTxt { instalarTimeouts() if $timeoutsOk; }   # "reload timeouts" depois da carga

# ------------------------------------------------------------ parametros ---
my %P;
my ($E_DUR, $esc) = (65, 1);   # duracao media da sessao (min, calculada); escala de tempo (teste)

# reacao pura: o timeout inteiro e um atraso humano (lognormal + cauda)
my @REACAO = qw(ai_attack_auto ai_attack_waitAfterKill ai_items_take_start ai_items_gather_start
	ai_item_use_auto ai_sit_wait ai_stand_wait);
# faixas largas (lognormal dentro da faixa)
my @FAIXAS = (
	[ai_attack => 0.7, 1.6], [ai_attack_after_skill => 0.4, 1.2], [ai_items_take_delay => 0.6, 1.8],
	[ai_items_take_end => 0.4, 1.2], [ai_take => 0.3, 0.9], [ai_items_gather_auto => 0.2, 0.8],
	[ai_sit_idle => 6, 25], [ai_skill_use => 0.6, 1.5], [ai_look => 0.2, 1.0], [ai_dead_respawn => 3, 25],
);
my %ehReacao;

sub cfg { my ($k, $d) = @_; my $v = $config{"mazzaRitmo_$k"}; return defined $v && length $v ? $v : $d; }
sub nums { my ($k, @d) = @_; my @v = grep { length } split /[\s,]+/, cfg($k, ''); return @v >= @d ? @v[0 .. $#d] : @d; }

sub lerParametros {
	%P = ();
	$P{ligado}  = defined $config{mazzaRitmo} && length $config{mazzaRitmo} ? ($config{mazzaRitmo} ? 1 : 0) : 1;
	$P{agenda}  = cfg('agenda', 1) ? 1 : 0;
	$P{perfil}  = lc cfg('perfil', 'estudante');
	$P{perfil}  = 'estudante' unless $P{perfil} =~ /^(estudante|trabalhador|noturno|fim-de-semana)$/;
	$P{desloc}  = cfg('deslocamento', 0);
	$P{horas}   = cfg('horas_semana', 10);
	$P{dias}    = cfg('dias', 4);
	$P{curtas}  = cfg('curtas', 0.35);
	@P{qw(forma escala)} = nums('weibull', 0.8, 90);
	$P{teto}    = cfg('teto', 480);
	@P{qw(mediana sigma cauda)} = nums('reacao', 0.45, 0.5, 0.06);
	$P{ping}    = cfg('ping', 40);
	@P{qw(afkA afkB afkD afkE)} = nums('afk', 15, 40, 1, 5);
	@P{qw(pauA pauB pauD pauE)} = nums('pausa', 45, 75, 5, 20);
	$P{meioLuta} = cfg('meio_luta', 0.25);
	@P{qw(limA limB)} = nums('limiar', 25, 60);
	@P{qw(sleepA sleepB)} = nums('sleep', 4000, 18000);
	$P{semente} = cfg('semente', $config{username} || 'bot');
	my @t = nums('teste', 0, 0);
	@P{qw(testeS testeV)} = @t;
	$esc = $t[0] > 0 ? $t[0] / 5400 : 1;          # teste: uma sessao de 90 min vira <testeS> s
	%ehReacao = map { $_ => 1 } @REACAO;
	$E_DUR = duracaoMedia();
}

# ---------------------------------------------------------- aleatorios ---
# uniforme em (0,1) de uma semente; fluxo(@chave) devolve um gerador deterministico
sub _u4 { return map { ($_ + 0.5) / 4294967296 } unpack('N4', md5($_[0])); }
sub fluxo {
	my $base = join('|', $P{semente}, @_);
	my ($n, @buf) = (0);
	return sub { @buf = _u4($base . '|' . $n++) unless @buf; return shift @buf; };
}
my $vivo = sub { my $r = rand(); $r = rand() while $r <= 0; return $r; };   # para o que acontece ao vivo

sub entre  { my ($u, $a, $b) = @_; return $a + ($b - $a) * $u->(); }
sub normal { my ($u) = @_; return sqrt(-2 * log($u->())) * cos(6.283185307179586 * $u->()); }
sub escolhePeso {
	my ($u, @w) = @_;
	my $s = 0; $s += $_ for @w;
	my $x = $u->() * $s;
	for my $i (0 .. $#w) { $x -= $w[$i]; return $i if $x < 0; }
	return $#w;
}

# regra 5-6: lognormal com cauda Pareto (forma 1,2) ate ~10 s, nunca < 120 ms, x (1 + ping/200)
sub reacao {
	my ($u) = @_; $u ||= $vivo;
	my $v = $u->() < $P{cauda}
		? 1.0 * $u->() ** (-1 / 1.2)
		: $P{mediana} * exp($P{sigma} * normal($u));
	$v *= 1 + $P{ping} / 200;
	$v = 9.5 + $u->() if $v > 10;
	return $v < 0.12 ? 0.12 + 0.05 * $u->() : $v;
}

# regra 1: minutos de uma sessao
sub duracaoSessao {
	my ($u) = @_;
	return entre($u, 2, 15) if $u->() < $P{curtas};
	for (1 .. 30) {
		my $d = $P{escala} * (-log($u->())) ** (1 / $P{forma});
		next if $d < 15 || $d > $P{teto};          # as curtas ja sao os 35%
		next if $d > 300 && $u->() < 0.6;          # < 2% acima de 5 h
		return $d;
	}
	return $P{escala};
}

sub duracaoMedia {
	my $u = fluxo('media');
	my $s = 0; $s += duracaoSessao($u) for 1 .. 3000;
	return $s / 3000;
}

# ------------------------------------------------------------- agenda ---
# regra 2: curva de horario do Brasil (peso por hora de inicio; 0=domingo .. 6=sabado)
my @UTIL = (6, 3, 1.5, .8, .5, .4, .5, .7, .9, 1, 1.2, 1.5, 2.2, 2.5, 3, 3.2, 3.5, 4, 5, 7, 8.5, 9, 8.5, 7.5);
my @SAB  = (7, 5, 3, 1.5, .8, .4, .4, .6, 1, 2, 3, 4, 5, 6, 7.5, 8, 8, 7.5, 7, 7.5, 8, 8.5, 8.5, 8);
my @DOM  = (7, 5, 3, 1.5, .8, .4, .4, .6, 1, 2, 3, 4, 5, 6, 7, 7.5, 7.5, 7, 6.5, 6.5, 6.5, 6, 5, 3.5);
my %DIAS = (                    # peso de cada dia da semana na escolha dos dias de jogo
	'estudante'     => [1.3, 1, 1, 1, 1, 1.1, 1.4],
	'trabalhador'   => [1.5, .8, .8, .9, .9, 1.2, 1.6],
	'noturno'       => [1, .9, .9, 1, 1, 1.3, 1.4],
	'fim-de-semana' => [4, .4, .4, .5, .6, 1.5, 4],
);

sub curva {
	my ($dow) = @_;
	my @c = $dow == 0 ? @DOM : $dow == 6 ? @SAB : @UTIL;
	my $util = $dow >= 1 && $dow <= 5;
	my $p = $P{perfil};
	for my $h (0 .. 23) {
		my $m = 1;
		if ($p eq 'estudante') {           # aula de manha, tarde livre
			$m = $h >= 7 && $h <= 11 ? .25 : $h == 12 ? .8 : $h >= 13 && $h <= 18 ? 1.5 : $h >= 1 && $h <= 5 ? .5 : 1 if $util;
		} elsif ($p eq 'trabalhador') {    # quase nada em horario comercial
			if ($util) {
				$m = ($h >= 8 && $h <= 11) || ($h >= 13 && $h <= 17) ? .04 : $h == 12 ? .35 : $h == 18 ? .5
				   : $h >= 19 ? 1.15 : $h == 0 ? .8 : $h <= 6 ? .25 : 1;
			} else { $m = $h <= 8 ? .8 : 1.1; }
		} elsif ($p eq 'noturno') {        # madrugada
			$m = { 22 => 1.5, 23 => 1.5, 0 => 2, 1 => 2.5, 2 => 3, 3 => 3, 4 => 2.5, 5 => 1.5 }->{$h}
			  || ($h >= 8 && $h <= 17 ? .3 : 1);
		} elsif ($p eq 'fim-de-semana') {
			$m = $util ? 1 : 1.2;
		}
		$c[$h] *= $m;
	}
	return @c;
}

# (o start.exe nao traz o POSIX: datas na mao)
sub meiaNoite { my ($t) = @_; my @l = localtime($t); return int($t) - $l[0] - 60 * $l[1] - 3600 * $l[2]; }
sub proxDia   { return meiaNoite(meiaNoite($_[0]) + 86400 + 7200); }
sub segunda   { my $d = meiaNoite($_[0]); return meiaNoite($d - 86400 * (((localtime($d + 43200))[6] + 6) % 7) + 43200); }
sub semanaDe  { return strftime('%Y-%m-%d', localtime(segunda($_[0]) + 43200)); }   # chave: a segunda-feira
my @DIASEM = qw(dom seg ter qua qui sex sab);
sub strftime {
	my ($f, @l) = @_;
	my %v = (Y => $l[5] + 1900, m => sprintf('%02d', $l[4] + 1), d => sprintf('%02d', $l[3]), H => sprintf('%02d', $l[2]),
	         M => sprintf('%02d', $l[1]), S => sprintf('%02d', $l[0]), a => $DIASEM[ $l[6] ]);
	$f =~ s/%(\w)/defined $v{$1} ? $v{$1} : "%$1"/ge;
	return $f;
}

our %cacheSemana;
# regras 3-4: horas da semana (lognormal em volta da mediana do bot), quais dias joga e as
# duracoes das sessoes da semana (sorteadas ate encher as horas), repartidas entre os dias
sub paramSemana {
	my ($w) = @_;
	return $cacheSemana{$w} if $cacheSemana{$w};
	my $u = fluxo('semana', $w);
	my $h = $P{horas} * exp(0.35 * normal($u));
	my $n = int($P{dias} + 0.5) + (-1, 0, 0, 1)[int($u->() * 4)];
	$n = 1 if $n < 1; $n = 7 if $n > 7;
	my @w = @{ $DIAS{ $P{perfil} } };
	my @dias;
	for (1 .. $n) { my $d = escolhePeso($u, @w); push @dias, $d; $w[$d] = 0; }
	my (%dur, $soma, $i);
	for ($soma = 0, $i = 0; $soma < 60 * $h; $i++) {
		my $d = duracaoSessao($u);
		last if $i && $soma + $d > 60 * $h * 1.15 && $u->() < .5;   # nao estoura muito a semana
		push @{ $dur{ $dias[$i % $n] } }, $d;
		$soma += $d;
	}
	return $cacheSemana{$w} = { horas => $h, ndias => $n, dur => \%dur };
}

# sessoes cruas de um dia (sem tirar sobreposicao): [inicio, fim]; o inicio de cada uma e
# sorteado na curva do dia (Poisson condicionado ao numero de sessoes)
sub planoDia {
	my ($d0) = @_;
	my $dow = (localtime($d0 + 43200))[6];
	my $W = paramSemana(semanaDe($d0));
	my $durs = $W->{dur}{$dow} or return ();
	my $u = fluxo('dia', strftime('%Y-%m-%d', localtime($d0 + 43200)));
	my @c = curva($dow);
	my @s;
	for my $d (@$durs) {
		my $h = escolhePeso($u, @c);
		my $ini = $d0 + 3600 * ($h + $u->()) + 60 * $P{desloc};
		push @s, [$ini, $ini + 60 * $d];
	}
	return @s;
}

# agenda entre dois instantes: sessoes ordenadas, a seguinte comeca 3-25 min depois da anterior
sub agendaEntre {
	my ($de, $ate) = @_;
	my @s;
	for (my $d = meiaNoite($de - 2 * 86400); $d < $ate; $d = proxDia($d)) { push @s, planoDia($d); }
	@s = sort { $a->[0] <=> $b->[0] } @s;
	my ($fimAnt, @out) = (0);
	for my $x (@s) {
		my $gap = 60 * (3 + 22 * fluxo('gap', int $x->[0])->());
		if ($x->[0] < $fimAnt + $gap) { my $d = $fimAnt + $gap - $x->[0]; $x->[0] += $d; $x->[1] += $d; }
		$fimAnt = $x->[1];
		push @out, $x if $x->[1] > $de && $x->[0] < $ate;
	}
	return @out;
}

# (sessao em andamento ou undef, inicio da proxima)
sub agendaAgora {
	my ($t) = @_;
	my ($cur, $prox);
	for my $s (agendaEntre($t - 86400, $t + 15 * 86400)) {
		if ($s->[0] <= $t && $t < $s->[1]) { $cur = $s; next; }
		if ($s->[0] > $t) { $prox = $s->[0]; last; }
	}
	return ($cur, defined $prox ? $prox : $t + 86400);
}

# ------------------------------------------------------- timeouts (reacao) ---
# Usa o timeoutRandomizer do clone: as faixas vao pro load_range_file dele e o sorteio
# dele (_assign_random_timeout, uniforme) e trocado por lognormal/reacao.
sub sortearTimeout {
	my ($entry, $meta) = @_;
	return unless $meta && defined $meta->{min} && defined $meta->{max};
	my ($min, $max) = sort { $a <=> $b } @$meta{qw(min max)};
	my $v;
	if ($ehReacao{ $meta->{name} || '' }) {
		$v = reacao();
	} else {
		my $sig = log($max / $min) / 4;
		$v = sqrt($min * $max) * exp($sig * normal($vivo));
	}
	$v = $min if $v < $min; $v = $max if $v > $max;
	$entry->{timeout} = $v;
	$meta->{last_value} = $v;
}

sub instalarTimeouts {
	return unless $P{ligado};
	no strict 'refs';
	unless (defined &{"${TR}::load_range_file"} && defined &{"${TR}::_assign_random_timeout"}) {
		warning "[$NAME] timeoutRandomizer nao carregado (sys.txt): timeouts ficam fixos.\n";
		return;
	}
	unless ($origSorteio) {
		no warnings 'redefine';
		$origSorteio = \&{"${TR}::_assign_random_timeout"};
		*{"${TR}::_assign_random_timeout"} = \&sortearTimeout;
	}
	# faixas: as nossas, depois as do config (mazzaRitmo_timeouts), depois o control/timeout_randomizer.txt do bot
	my %f = map { $_->[0] => "$_->[1] $_->[2]" } @FAIXAS;
	$f{$_} = '0.12 10' for @REACAO;
	for my $e (split /\s*,\s*/, cfg('timeouts', '')) {
		my ($n, $a, $b) = split /\s+/, $e;
		$f{$n} = "$a " . (defined $b ? $b : $a) if defined $a;
	}
	my $ctl = Settings::getControlFilename('timeout_randomizer.txt');
	if ($ctl && open(my $fh, '<', $ctl)) {
		while (<$fh>) { s/#.*//; s/^\s+|\s+$//g; my ($n, $r) = /^(\S+)\s+(.+)$/ or next; $f{$n} = $r; }
		close $fh;
	}
	my $arq = ($Settings::logs_folder || 'logs') . '/ritmo_timeouts.txt';
	open(my $out, '>', $arq) or return warning "[$NAME] nao consegui escrever $arq\n";
	print $out "# GERADO pelo mazzaRitmo a cada carga (faixas do timeoutRandomizer)\n";
	print $out "$_ $f{$_}\n" for sort keys %f;
	close $out;
	&{"${TR}::load_range_file"}($arq);
	message sprintf("[%s] %d timeouts com atraso humano (%d de reacao).\n", $NAME, scalar keys %f, scalar @REACAO), 'success';
}

# ------------------------------------------------------------ ao vivo ---
sub parado { return $estado eq 'afk' || $estado eq 'pausa' || $estado eq 'saindo' ? 1 : 0; }
sub agenda { return $P{ligado} ? 1 : 0; }
sub estado { return $estado; }

sub registro {
	my ($ev, $txt) = @_;
	my $n = $config{username} || 'bot'; $n =~ s/[^\w\-]/_/g;
	if (open(my $fh, '>>', ($Settings::logs_folder || 'logs') . "/ritmo_$n.log")) {
		printf $fh "%d %s %s %s\n", time, strftime('%Y-%m-%d %H:%M:%S', localtime), $ev, defined $txt ? $txt : '';
		close $fh;
	}
}

sub hms { my $s = int(shift); return $s >= 3600 ? sprintf('%.1f h', $s / 3600) : $s >= 60 ? sprintf('%d min', $s / 60) : "$s s"; }

sub onStart {
	lerParametros();
	$iniciado = 1;
	message sprintf("[%s] %s, perfil %s, ~%.0f h/semana em %s dias, sessao media %.0f min%s.\n", $NAME,
		$P{ligado} ? 'ligado' : 'DESLIGADO', $P{perfil}, $P{horas}, $P{dias}, $E_DUR,
		$P{testeS} ? " (TESTE: sessao ~$P{testeS} s, volta ~$P{testeV} s)" : !$P{agenda} ? ' (sem agenda: sempre on)' : ''), 'success';
}

sub onLoop {
	return unless $iniciado && $P{ligado};
	# depois de todos os start3 (o do timeoutRandomizer recarrega as faixas dele)
	instalarTimeouts() unless $timeoutsOk++;
	# sem grade fixa: o laco principal dorme um tempo diferente a cada volta
	$config{sleepTime} = int($P{sleepA} + rand($P{sleepB} - $P{sleepA}));
	return unless $net;
	my $st = $net->getState();
	if ($st == Network::NOT_CONNECTED && !$checouAntes) {
		# antes do primeiro login: fora de sessao nem entra
		$checouAntes = 1;
		if ($P{agenda} && !$P{testeS}) {
			my ($cur, $prox) = agendaAgora(time);
			if (!$cur && $prox - time > 120) {
				message sprintf("[%s] fora de sessao; entra %s (em %s).\n", $NAME,
					strftime('%a %d/%m %H:%M', localtime $prox), hms($prox - time)), 'success';
				registro('fora', 'proxima ' . int $prox);
				Misc::relog(int($prox - time), 1);
			}
		}
		return;
	}
	return unless $st == Network::IN_GAME && $char;
	return if time - $ultimoTick < 0.5; $ultimoTick = time;
	tickJogo();
}

sub hpPct { return $char->{hp_max} ? 100 * $char->{hp} / $char->{hp_max} : 100; }
sub lutando { return AI::is('attack') || AI::inQueue('attack') ? 1 : 0; }
sub manual { my ($on) = @_; AI::state($on ? AI::MANUAL : AI::AUTO); $afkManual = $on ? 1 : 0; }

# regra 9: limiar de sentar e de pocao sorteados a cada sessao (so na memoria, nada gravado)
sub sortearLimiares {
	my $sit = int entre($vivo, $P{limA}, $P{limB});
	my $poc = int entre($vivo, $P{limA}, $P{limB});
	$config{sitAuto_hp_lower} = $sit if defined $config{sitAuto_hp_lower};
	$config{sitAuto_hp_upper} = $sit + 30 if ($config{sitAuto_hp_upper} || 0) < $sit + 20;
	for (my $i = 0; exists $config{"useSelf_item_$i"}; $i++) {
		my $k = "useSelf_item_${i}_hp";
		$config{$k} = "< $poc%" if defined $config{$k} && $config{$k} =~ /^\s*<\s*\d+\s*%\s*$/;
	}
	return "sentar $sit%, pocao $poc%";
}

sub entrar {
	my $t = time;
	my ($ini, $fim, $plano) = ($t, undef, 0);
	if ($P{testeS}) {
		$fim = $t + $P{testeS} * entre($vivo, .7, 1.3);
	} elsif (!$P{agenda}) {
		$fim = $t + 10 * 365 * 86400;
	} else {
		my ($cur, $prox) = agendaAgora($t);
		if (!$cur || $cur->[1] - $t < 120) {
			(undef, $prox) = agendaAgora($cur->[1] + 1) if $cur;
			my $s = int($prox - $t); $s = 60 if $s < 60;
			message sprintf("[%s] fora de sessao; volta %s (em %s).\n", $NAME, strftime('%a %d/%m %H:%M', localtime $prox), hms($s)), 'success';
			registro('fora', 'proxima ' . int $prox);
			Commands::run("relog $s");
			return;
		}
		($ini, $fim, $plano) = (@$cur, int $cur->[0]);
	}
	my $lim = sortearLimiares();
	%ses = (inicio => $t, fim => $fim, plano => $plano, cortaLuta => $vivo->() < $P{meioLuta});
	agendarAfk($t);
	$ses{pausaEm} = $t + 60 * $esc * entre($vivo, $P{pauA} * .6, $P{pauB});
	$estado = 'jogando';
	my $nova = !$plano || ($plano != $saudouPlano && $t - $ini < 600);
	$saudouPlano = $plano;
	Plugins::callHook('mazzaRitmo_chegada', { fala => $nova ? 1 : 0 });
	message sprintf("[%s] sessao ate %s (%s); %s.\n", $NAME, strftime('%H:%M:%S', localtime $fim), hms($fim - $t), $lim), 'success';
	registro('entrada', sprintf('fim %d dur %d %s', $fim, $fim - $t, $lim));
}

sub agendarAfk { $ses{afkEm} = $_[0] + 60 * $esc * entre($vivo, $P{afkA}, $P{afkB}); }

sub voltarAfk {
	Commands::run('stand') if $sentou && $char->{sitting};
	manual(0) if $afkManual;
	$sentou = 0;
	$estado = 'jogando';
}

sub despedir {
	my ($luta) = @_;
	voltarAfk() if $estado eq 'afk' || ($estado eq 'pausa' && $afkManual);
	my $a = { luta => $luta, falou => 0 };
	Plugins::callHook('mazzaRitmo_saida', $a);
	if (!$a->{falou} && $vivo->() < .7) {
		my @f = $luta ? ('opa tenho q ir', 'eita, fui', 'xiii me chamaram, flw') : ('flw', 'vou nessa', 'fui galera', 'ate mais');
		Commands::run('c ' . $f[int rand @f]);
	}
	$estado = 'saindo';
	$ses{relogEm} = time + ($luta ? entre($vivo, 1, 3) : entre($vivo, 4, 12));
	registro('saida_fala', $luta ? 'no meio da luta' : '');
}

sub sairRelog {
	my $t = time;
	my $prox;
	if ($P{testeS}) { $prox = $t + $P{testeV} * entre($vivo, .7, 1.3); }
	elsif (!$P{agenda}) { $prox = $t + 60 * entre($vivo, 5, 30); }
	else {
		my ($cur, $p) = agendaAgora($t);
		$prox = $cur && $cur->[0] > ($ses{plano} || 0) + 1 ? $t + 60 : $p;   # (sessao seguinte ja colada)
	}
	my $s = int($prox - $t); $s = 30 if $s < 30;
	message sprintf("[%s] fim da sessao (%s jogados); volta %s (em %s).\n", $NAME, hms($t - $ses{inicio}),
		strftime('%a %d/%m %H:%M', localtime($t + $s)), hms($s)), 'success';
	registro('saida', sprintf('jogou %d volta %d', $t - $ses{inicio}, $t + $s));
	%ses = (); $estado = 'fora';
	Commands::run("relog $s");
}

sub tickJogo {
	my $t = time;
	unless (%ses) { entrar(); return; }
	if ($estado eq 'saindo') { sairRelog() if $t >= $ses{relogEm}; return; }

	# fim da sessao (regra 8: as vezes no meio da luta)
	if ($t >= $ses{fim}) {
		my $luta = lutando();
		if (!$luta || $ses{cortaLuta} || $t - $ses{fim} > 120) { despedir($luta); return; }
	}

	if ($estado eq 'afk') {
		# apanhando no AFK: "volta pro teclado" depois de um tempo de reacao
		if (!$ses{acorda} && hpPct() < $ses{afkHp} - 12) { $ses{acorda} = $t + 2 * reacao(); }
		if ($t >= $ses{afkFim} || ($ses{acorda} && $t >= $ses{acorda})) {
			registro('afk_fim', sprintf('%d s', $t - $ses{afkIni}));
			voltarAfk(); delete $ses{acorda}; agendarAfk($t);
		}
		return;
	}

	if ($estado eq 'pausa') {
		my $fim;
		if ($ses{pausaJornada}) {
			$fim = !(defined &mazzaJornada::emPausa && mazzaJornada::emPausa()) || $t - $ses{pausaIni} > 60 * $esc * 45;
		} else {
			$fim = $t >= $ses{pausaFim} || hpPct() < 40;
		}
		if ($fim) {
			registro('pausa_fim', sprintf('%d s', $t - $ses{pausaIni}));
			voltarAfk();
			$ses{pausaEm} = $t + 60 * $esc * entre($vivo, $P{pauA}, $P{pauB});
			agendarAfk($t);
		}
		return;
	}

	# pausa maior (uma por hora; o mazzaJornada leva pra cidade e senta)
	if ($t >= $ses{pausaEm} && !lutando()) {
		my $dur = 60 * $esc * entre($vivo, $P{pauD}, $P{pauE});
		if ($ses{fim} - $t < $dur + 300 * $esc) { $ses{pausaEm} = $ses{fim} + 1; return; }
		my $a = { dur => $dur, tratado => 0 };
		Plugins::callHook('mazzaRitmo_pausa', $a);
		%ses = (%ses, pausaIni => $t, pausaFim => $t + $dur, pausaJornada => $a->{tratado});
		$estado = 'pausa';
		unless ($a->{tratado}) { manual(1); if (!$char->{sitting}) { Commands::run('sit'); $sentou = 1; } }
		registro('pausa', sprintf('%d s%s', $dur, $a->{tratado} ? ' (jornada)' : ''));
		return;
	}

	# AFK curto (regra 8)
	if ($t >= $ses{afkEm}) {
		if (lutando() || AI::is('route', 'mapRoute') && $vivo->() < .7) { $ses{afkEm} = $t + 20 * $esc + 10; return; }
		my $dur = 60 * $esc * entre($vivo, $P{afkD}, $P{afkE});
		%ses = (%ses, afkIni => $t, afkFim => $t + $dur, afkHp => hpPct());
		$estado = 'afk';
		manual(1);
		if (!$char->{sitting} && !AI::ai_getAggressives() && $vivo->() < .45) { Commands::run('sit'); $sentou = 1; }
		registro('afk', sprintf('%d s', $dur));
	}
}

# --------------------------------------------------------------- console ---
sub simular {
	my ($semanas) = @_;
	my $de = segunda(time);                        # semanas de segunda a domingo, como a agenda
	my $ate = $de + $semanas * 7 * 86400;
	my @s = agendaEntre($de, $ate);
	my (@dur, %porSemana, %diasSemana, @hora, @horaFds, %dow);
	for my $x (@s) {
		my $d = ($x->[1] - $x->[0]) / 60;
		push @dur, $d;
		my $w = int(($x->[0] - $de) / 604800);
		$porSemana{$w}{h} += $d / 60; $porSemana{$w}{n}++;
		$diasSemana{$w}{ strftime('%Y-%m-%d', localtime $x->[0]) } = 1;
		my @lt = localtime $x->[0];
		$dow{ $lt[6] } += $d / 60;
		if ($lt[6] == 0 || $lt[6] == 6) { $horaFds[ $lt[2] ]++ } else { $hora[ $lt[2] ]++ }
	}
	my @o = sort { $a <=> $b } @dur;
	my $pct = sub { my $p = shift; return @o ? $o[ int($p * $#o + .5) ] : 0; };
	my $media = 0; $media += $_ for @o; $media /= @o || 1;
	my $out = sprintf("[%s] agenda simulada: %d semanas a partir de %s, perfil %s, deslocamento %+d min, semente '%s'\n",
		$NAME, $semanas, strftime('%d/%m/%Y', localtime $de), $P{perfil}, $P{desloc}, $P{semente});
	$out .= sprintf("  sessoes: %d | curtas (<15 min) %.0f%% | mediana %.0f min | media %.0f | p90 %.0f | max %.0f | >5 h %.1f%%\n",
		scalar @o, 100 * (grep { $_ < 15 } @o) / (@o || 1), $pct->(.5), $media, $pct->(.9), $o[-1] || 0,
		100 * (grep { $_ > 300 } @o) / (@o || 1));
	$out .= "  semana   horas  dias  sessoes\n";
	$out .= sprintf("  %4d   %6.1f  %4d  %7d\n", $_ + 1, $porSemana{$_}{h} || 0, scalar keys %{ $diasSemana{$_} || {} },
		$porSemana{$_}{n} || 0) for 0 .. $semanas - 1;
	my @nd = qw(dom seg ter qua qui sex sab);
	$out .= '  horas por dia da semana: ' . join(' ', map { sprintf('%s %.1f', $nd[$_], $dow{$_} || 0) } 1 .. 6, 0) . "\n";
	$out .= "  inicio de sessao por hora (# = dia util, * = fim de semana):\n";
	my $mx = 1; for (0 .. 23) { my $v = ($hora[$_] || 0) + ($horaFds[$_] || 0); $mx = $v if $v > $mx; }
	for my $h (0 .. 23) {
		my ($a, $b) = ($hora[$h] || 0, $horaFds[$h] || 0);
		$out .= sprintf("   %02dh %3d %s%s\n", $h, $a + $b, '#' x int(40 * $a / $mx + .5), '*' x int(40 * $b / $mx + .5));
	}
	# reacao (regras 5-6): forma e ausencia de grade de 16 ms
	my $u = fluxo('reacao_sim');
	my @r = sort { $a <=> $b } map { reacao($u) } 1 .. 20000;
	my $grade = grep { my $ms = $_ * 1000; my $f = $ms / 16 - int($ms / 16); $f < 1 / 16 || $f > 15 / 16 } @r;
	$out .= sprintf("  reacao (ping %d ms): min %.0f ms | p5 %.0f | mediana %.0f | p95 %.0f | p99 %.0f | max %.0f | a <=1 ms da grade de 16 ms: %.1f%% (sem grade ~12,5%%)\n",
		$P{ping}, (map { 1000 * $_ } @r[0, 1000, 10000, 19000, 19800, -1]), 100 * $grade / @r);
	my $arq = ($Settings::logs_folder || 'logs') . '/ritmo_simulado.csv';
	if (open(my $fh, '>', $arq)) {
		print $fh "inicio,fim,minutos\n";
		printf $fh "%s,%s,%.1f\n", strftime('%Y-%m-%d %H:%M', localtime $_->[0]), strftime('%Y-%m-%d %H:%M', localtime $_->[1]),
			($_->[1] - $_->[0]) / 60 for @s;
		close $fh;
		$out .= "  sessoes em $arq\n";
	}
	return $out;
}

sub cmdRitmo {
	my (undef, $arg) = @_;
	$arg = 'status' unless defined $arg && length $arg;
	my ($c, $n) = split /\s+/, $arg;
	lerParametros() unless %P;
	if ($c eq 'simular') {
		message simular($n && $n =~ /^\d+$/ ? $n : 4), 'info';
	} elsif ($c eq 'agenda') {
		my $dias = $n && $n =~ /^\d+$/ ? $n : 3;
		my $out = "[$NAME] proximas sessoes ($dias dias):\n";
		$out .= sprintf("  %s - %s  (%s)\n", strftime('%a %d/%m %H:%M', localtime $_->[0]), strftime('%H:%M', localtime $_->[1]),
			hms($_->[1] - $_->[0])) for agendaEntre(time, time + $dias * 86400);
		message $out, 'info';
	} elsif ($c eq 'sair') {
		if (%ses && $estado ne 'saindo') { despedir(lutando()); } else { message "[$NAME] nao estou numa sessao.\n", 'info'; }
	} elsif ($c eq 'afk') {
		$ses{afkEm} = time if %ses;
	} elsif ($c eq 'pausa') {
		$ses{pausaEm} = time if %ses;
	} else {
		my $t = time;
		message sprintf("[%s] %s | estado %s | sessao %s | proximo AFK %s | proxima pausa %s | perfil %s, %s h/sem, %s dias, ping %s ms\n",
			$NAME, $P{ligado} ? 'ligado' : 'desligado', $estado,
			%ses ? 'acaba em ' . hms($ses{fim} - $t) : '-',
			%ses && $ses{afkEm} ? hms($ses{afkEm} - $t) : '-', %ses && $ses{pausaEm} ? hms($ses{pausaEm} - $t) : '-',
			$P{perfil}, $P{horas}, $P{dias}, $P{ping}), 'info';
	}
}

1;
