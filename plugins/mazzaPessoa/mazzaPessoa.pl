# =============================================================================
#  mazzaPessoa - persona e papel social dos bots fieis do MazzaRO
#  (mazzakore, branch mazzaro; fase F3 de mazzaro/docs/bots/PLANO-JOGADORES.md)
#
#  Cada bot e uma pessoa:
#   - um PAPEL tirado do bRO real (mazzaro/docs/bots/pesquisa-bro.md, secao 2), com
#     habitos e falas proprias (secoes papel_* do falas.txt, que o gerador junta da
#     mazzaro/bots/papeis/<papel>.txt):
#       novato   pergunta tudo em publico, agradece ajuda
#       mentor   (nivel 30+) puxa conversa com aprendiz perto, oferece ajuda
#       familia  chama a guilda de familia, recruta na cidade ("pai/papi")
#       vendedor anuncia S>/C> na cidade durante a pausa
#       buff     responde "buff plis" de quem esta perto com Bencao/Agilidade
#       pedinte  abre sala "Doa 7z e seja feliz" na pausa e pede pocao
#       quieto   upa calado: quase nao fala, nao passeia na cidade
#       zoeiro   implica, "huehue", fala mais com gente perto
#       casual   joga pouco (o perfil fim-de-semana do mazzaRitmo vem do gerador)
#   - um VETOR DE YEE (10 motivacoes: progresso mecanica competicao socializar
#     relacao equipe descoberta roleplay customizacao escapismo, de 0 a 1) com
#     DERIVA DIARIA (AR(1) por dia, semente = conta + data): cada dia sai diferente
#     (Lee 2016: bot e auto-semelhante entre janelas). O vetor do dia escolhe a
#     meta do dia e ajusta, so na memoria, os outros plugins (regra 20):
#       socializar/relacao/equipe -> chance de falar (mazzaJornada), lugares e tempo
#                                    do passeio na cidade (mazzaRota)
#       progresso/mecanica        -> mais tempo no mesmo canto, menos paradas (mazzaRota)
#       descoberta                -> mais mapas por sessao e sub-areas longe (mazzaRota)
#
#  config.txt do bot (o gerador sorteia):
#   mazzaPessoa 1
#   mazzaPessoa_papel novato
#   mazzaPessoa_yee 0.6 0.4 0.3 0.7 0.5 0.4 0.6 0.2 0.3 0.5
#   mazzaPessoa_deriva 0.10          desvio de cada motivacao em volta da base (AR(1) por dia, 0,5)
#   mazzaPessoa_semente <texto>      padrao: username
#
#  Console:  pessoa [status|dia|simular [dias]|papel]
#  Perl 5.12 (o do start.exe): nada de s///r, sem POSIX.
# =============================================================================
package mazzaPessoa;

use strict;
use warnings;
use Time::HiRes qw(time);
use Digest::MD5 qw(md5);

use Plugins;
use Globals qw($char %config $field $net $playersList);
use Log qw(message warning);
use Commands;
use Network;
use Utils qw(distance);
use AI;
use Skill;

my $NAME = 'mazzaPessoa';
Plugins::register($NAME, 'Persona e papel social dos bots do MazzaRO', \&unload, \&unload);

my $hooks = Plugins::addHooks(
	['AI_pre',        \&onTick],
	['packet_pubMsg', \&onPub],
);
my $cmds = Commands::register(['pessoa', 'Persona do bot (status|dia|simular [dias]|papel)', \&cmdPessoa]);

sub unload { Plugins::delHooks($hooks); Commands::unregister($cmds); }

my @YEE = qw(progresso mecanica competicao socializar relacao equipe descoberta roleplay customizacao escapismo);
my %PAPEIS = map { $_ => 1 } qw(novato mentor familia vendedor buff pedinte quieto zoeiro casual);

# ------------------------------------------------------------ parametros ---
sub cfg { my ($k, $d) = @_; my $v = $config{"${NAME}_$k"}; return defined $v && length $v ? $v : $d; }
sub ligado { return !defined $config{$NAME} || !length $config{$NAME} || $config{$NAME} ? 1 : 0; }
sub papel { my $p = lc cfg('papel', 'quieto'); return $PAPEIS{$p} ? $p : 'quieto'; }
sub base {
	my @v = grep { length } split /[\s,]+/, cfg('yee', '');
	@v = (0.5) x 10 unless @v == 10;
	return map { $_ < 0 ? 0 : $_ > 1 ? 1 : $_ } @v;
}
sub rnd { my ($a, $b) = @_; return $a + rand($b - $a); }

# normal(0,1) deterministica por chave (Box-Muller sobre md5)
sub gauss {
	my ($a, $b) = unpack('N2', md5(join('|', cfg('semente', $config{username} || 'bot'), @_)));
	($a, $b) = (($a + 0.5) / 4294967296, ($b + 0.5) / 4294967296);
	return sqrt(-2 * log($a)) * cos(6.283185307179586 * $b);
}

sub dataDe { my @t = localtime($_[0]); return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]); }

# vetor do dia: base + deriva AR(1) dos ultimos 20 dias (cada dia puxa metade do anterior)
sub vetorDoDia {
	my ($t) = @_;
	my @b = base();
	my $sd = cfg('deriva', 0.10);
	my @d = (0) x 10;
	for my $k (reverse 0 .. 20) {
		my $dia = dataDe($t - 86400 * $k);
		@d = map { 0.5 * $d[$_] + 0.866 * $sd * gauss('yee', $dia, $_) } 0 .. 9;   # desvio estacionario = $sd
	}
	return map { my $x = $b[$_] + $d[$_]; $x < 0 ? 0 : $x > 1 ? 1 : $x } 0 .. 9;
}

sub media { my $s = 0; $s += $_ for @_; return @_ ? $s / @_ : 0; }

# o que o dia muda (regra 20): devolve {meta, valores para os outros plugins}
sub planoDoDia {
	my ($t) = @_;
	my @v = vetorDoDia($t);
	my %y; @y{@YEE} = @v;
	my $soc  = media(@y{qw(socializar relacao equipe)});
	my $prog = media(@y{qw(progresso mecanica competicao)});
	my $desc = $y{descoberta};
	# meta do dia: a motivacao mais forte do dia, com um pouco de sorte
	my %meta = (upar => $prog, conversar => $soc, explorar => $desc, enrolar => $y{escapismo} * 0.8,
	            enfeitar => $y{customizacao} * 0.7);
	my ($meta) = sort { $meta{$b} + 0.25 * gauss('meta', dataDe($t), $b) <=> $meta{$a} + 0.25 * gauss('meta', dataDe($t), $a) } keys %meta;
	my $quieto = papel() eq 'quieto';
	my $um = int(75 - 55 * $desc); my $dois = int(20 + 25 * $desc);
	my %p = (
		chance_fala_ambiente => $quieto ? 1 : sprintf('%.0f', 1 + 9 * $soc),
		mazzaRota_cidade     => $quieto ? '0 0 10 20' : sprintf('1 %d 10 %d', 1 + int(3 * $soc + 0.5), 30 + int(90 * $soc)),
		mazzaRota_mapas      => sprintf('%d %d %d', $um, $dois, 100 - $um - $dois),
		mazzaRota_longe      => sprintf('%.2f', 0.05 + 0.25 * $desc),
		mazzaRota_permanencia => sprintf('%d %d', 6 + int(10 * $prog), 18 + int(20 * $prog)),
		mazzaRota_parada     => sprintf('%.2f 3 %d', 0.15 + 0.4 * (1 - $prog), 10 + int(20 * $y{escapismo})),
	);
	return { data => dataDe($t), meta => $meta, social => $soc, progresso => $prog, descoberta => $desc,
	         vetor => \@v, params => \%p };
}

# --------------------------------------------------------------- estado ---
my ($ultTick, $hoje, $plano) = (0, '', undef);
my %ult;             # proxima vez de cada habito
my %visto;           # nome -> 1 (mentor: ja falou com este aprendiz hoje)
my @fila;            # [quando, coderef] acoes com atraso de reacao
my ($salaAberta, $salaFeita, $estavaEmPausa, $pausaDesde) = (0, 0, 0, 0);

sub aplicar {
	$plano = planoDoDia(time);
	my $p = $plano->{params};
	if (defined &mazzaJornada::opcao) { mazzaJornada::opcao('chance_fala_ambiente', $p->{chance_fala_ambiente}); }
	for my $k (grep { /^mazzaRota_/ } keys %$p) { $config{$k} = $p->{$k}; }   # so na memoria
	message sprintf("[%s] %s, %s: meta do dia %s (social %.2f, progresso %.2f, descoberta %.2f)\n", $NAME,
		papel(), $plano->{data}, $plano->{meta}, @$plano{qw(social progresso descoberta)}), 'info';
	%visto = ();
}

# API (mazzaPapo, F4): o plano do dia {meta, social, progresso, descoberta, vetor, params}
sub plano { $plano ||= planoDoDia(time); return $plano; }

sub perto {   # jogadores a ate $d celulas
	my ($d) = @_;
	return () unless $playersList && $char;
	my $pos = $char->position;
	return grep { $_->{pos_to} && distance($pos, $_->{pos_to}) <= $d } @{ $playersList->getItems };
}

sub falar { my ($sec, %v) = @_; return defined &mazzaJornada::falar ? mazzaJornada::falar("papel_$sec", 100, $v{_force} || 0, %v) : 0; }
sub vez { my ($k, $a, $b) = @_; return 0 if time < ($ult{$k} || 0); $ult{$k} = time + 60 * rnd($a, $b); return 1; }
sub pausa { return defined &mazzaJornada::modo && mazzaJornada::modo() eq 'pausa'; }
sub cidade { return $field && $field->isCity; }

# ---------------------------------------------------------------- tique ---
sub onTick {
	return unless ligado() && $net && $net->getState() == Network::IN_GAME && $char && $field;
	while (@fila && $fila[0][0] <= time) { my $a = shift @fila; $a->[1]->(); }
	return if time - $ultTick < 1;
	$ultTick = time;
	my $d = dataDe(time);
	if ($d ne $hoje) { $hoje = $d; aplicar(); }
	return if $char->{dead} || (defined &mazzaRitmo::parado && mazzaRitmo::parado());
	my $papel = papel();
	my @gente = perto(10);

	if ($papel eq 'novato') {
		falar('pergunta') if @gente && $char->{lv} < 40 && vez('pergunta', 8, 25);
	} elsif ($papel eq 'mentor') {
		if ($char->{lv} >= 30) {
			my ($ap) = grep { ($_->{jobID} || 0) == 0 && !$visto{ $_->{name} || '' } } perto(8);
			if ($ap && vez('mentor', 3, 8)) {
				$visto{ $ap->{name} } = 1;
				my $n = $ap->{name};
				push @fila, [time + rnd(2, 6), sub { falar('mentor', quem => $n, _force => 1); }];
			}
		}
	} elsif ($papel eq 'familia') {
		falar('recruta') if cidade() && @gente && vez('recruta', 6, 15);
	} elsif ($papel eq 'vendedor') {
		falar('anuncio', _force => 1) if pausa() && cidade() && vez('anuncio', 3, 6);
	} elsif ($papel eq 'pedinte') {
		pedinte(\@gente);
	} elsif ($papel eq 'zoeiro') {
		falar('zoeira') if @gente && vez('zoeira', 5, 15);
	}
}

# pedinte: na pausa, parado na cidade, abre a sala e pede de vez em quando; fecha ao sair da pausa
sub pedinte {
	my ($gente) = @_;
	my $emPausa = pausa() && cidade();
	($salaFeita, $pausaDesde) = (0, time) if $emPausa && !$estavaEmPausa;
	$estavaEmPausa = $emPausa;
	# sala de chat pede Habilidades Basicas 4; abre uma vez por pausa, depois do passeio da cidade (sentado, ou
	# parado ha 20 s para quem ainda nao senta)
	my $basico = $char->getSkillLevel(Skill->new(handle => 'NV_BASIC'));
	my $assentado = $char->{sitting} || (time - $pausaDesde > 20 && !AI::is('route', 'mapRoute', 'move'));
	if ($emPausa && !$salaAberta && !$salaFeita && $basico >= 4 && $assentado) {
		my $t = defined &mazzaJornada::texto ? mazzaJornada::texto('papel_sala') : undef;
		if (defined $t && length $t) {
			$t =~ s/"//g;
			Commands::run(qq{chat create "$t" 20 1});
			($salaAberta, $salaFeita) = (1, 1);
		}
	} elsif (!$emPausa && $salaAberta) {
		Commands::run('chat leave');
		$salaAberta = 0;
	}
	falar('pedido') if $emPausa && @$gente && vez('pedido', 2, 6);
}

# buff: "buff plis", "bless", "agi" de quem esta perto -> Bencao e/ou Agilidade, com atraso de gente
my %pediuEm;
sub onPub {
	my (undef, $args) = @_;
	return unless ligado() && $char && papel() eq 'buff';
	my ($quem, $msg) = ($args->{pubMsgUser} || '', $args->{pubMsg} || '');
	return if $quem eq '' || $quem eq $char->{name};
	return unless $msg =~ /\b(buff|buf|bless|bencao|benca|agi|agil|inc agi)\b/i;
	return if time - ($pediuEm{$quem} || 0) < 30;
	$pediuEm{$quem} = time;
	my ($pl) = grep { ($_->{name} || '') eq $quem } perto(14);
	return unless $pl;
	my @sk = grep { ($char->{skills}{$_}{lv} || 0) > 0 } qw(AL_BLESSING AL_INCAGI);
	if (!@sk || $char->{sp} < 30) {
		push @fila, [time + rnd(2, 5), sub { falar('buff_sem', quem => $quem, _force => 1); }];
		return;
	}
	my $t = time + rnd(1.5, 4);
	push @fila, [$t, sub { falar('buff_ok', quem => $quem, _force => 1); }];
	for my $s (@sk) {
		$t += rnd(1.2, 2.5);
		push @fila, [$t, sub {
			my ($alvo) = grep { ($_->{name} || '') eq $quem } perto(14);
			Commands::run("sp $s $alvo->{binID}") if $alvo;
		}];
	}
	@fila = sort { $a->[0] <=> $b->[0] } @fila;
}

# --------------------------------------------------------------- console ---
sub cmdPessoa {
	my (undef, $arg) = @_;
	$arg = '' unless defined $arg;
	my ($sub, $n) = split /\s+/, $arg;
	$sub ||= 'status';
	if ($sub eq 'simular') {
		$n ||= 14;
		message "[$NAME] $n dias de " . papel() . " (vetor do dia e o que muda):\n", 'list';
		message sprintf("  %-10s %-9s %s  %s\n", 'dia', 'meta', join(' ', map { substr($_, 0, 4) } @YEE), 'fala/cidade/mapas'), 'list';
		for my $k (0 .. $n - 1) {
			my $p = planoDoDia(time + 86400 * $k);
			message sprintf("  %-10s %-9s %s  %s / %s / %s\n", $p->{data}, $p->{meta},
				join(' ', map { sprintf('%.2f', $_) } @{ $p->{vetor} }), $p->{params}{chance_fala_ambiente},
				$p->{params}{mazzaRota_cidade}, $p->{params}{mazzaRota_mapas}), 'list';
		}
		return;
	}
	if ($sub eq 'dia') { aplicar(); return; }
	$plano ||= planoDoDia(time);
	message sprintf("[%s] %s | papel %s | meta do dia %s | vetor %s | %s\n", $NAME, ligado() ? 'ligado' : 'desligado',
		papel(), $plano->{meta}, join(' ', map { sprintf('%s %.2f', substr($YEE[$_], 0, 4), $plano->{vetor}[$_]) } 0 .. 9),
		join(', ', map { "$_ $plano->{params}{$_}" } sort keys %{ $plano->{params} })), 'info';
}

1;
