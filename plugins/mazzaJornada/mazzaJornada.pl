# =============================================================================
#  mazzaJornada - "vida" para os bots roleplay do MazzaRO (mazzakore, branch mazzaro)
#
#  Cada bot tem um control/ proprio (mazzaro/bots/<bot>/control) com:
#    jornada.txt  etapas de treino, mudancas de classe, turismo, opcoes
#    falas.txt    personalidade (falas por evento)
#  O plugin:
#   - escolhe lockMap/saveMap pela etapa (nivel base + classe)
#   - leva o bot ao NPC de mudanca de classe quando atinge o requisito
#   - visita pontos turisticos na 1a vez em cada cidade (inclusive as zonas de
#     2001 pelo Historiador, voltando pelo "Eco do presente")
#   - salva na Kafra de cada cidade nova
#   - faz pausas (volta pra cidade, senta, conversa, retoma)
#   - fala em level up, classe, morte, cidade nova; responde PM e quem o chama
#   - respeita o Motor de Episodios: mapa fechado vira etapa pulada por um tempo
#   - cria o personagem se a conta estiver vazia (mazzaJornada_personagem ...)
#
#  Console:  jornada [status|pausa|retomar|reset]
#  Perl 5.12 (o do start.exe): nada de s///r.
# =============================================================================
package mazzaJornada;

use strict;
use warnings;
use Time::HiRes qw(time);

use Plugins;
use Globals qw($char %config $field $net $npcsList @chars $messageSender);
use Log qw(message warning);
use Misc qw(configModify);
use Commands;
use Settings;
use Network;
use Utils qw(distance);
use AI;
use Skill;

my $NAME = 'mazzaJornada';
Plugins::register($NAME, 'Jornada roleplay dos bots do MazzaRO', \&unload, \&unload);

my $hooks = Plugins::addHooks(
	['start3',           \&loadData],
	['AI_pre',           \&tick],
	['charSelectScreen', \&onCharSelect],
	['packet_privMsg',   \&onPM],
	['packet_pubMsg',    \&onPub],
);
my $logHook = Log::addHook(\&onLog);
my $cmds = Commands::register(['jornada', 'Jornada roleplay (status|pausa|retomar|reset)', \&cmdJornada]);

sub unload {
	Plugins::delHooks($hooks);
	Log::delHook($logHook);
	Commands::unregister($cmds);
}

# ---------------------------------------------------------------- dados ----
my (@etapas, @classes, %pontos, %falas, %opt, %cidades);
my $loaded = 0;

# ---------------------------------------------------------------- estado ---
my %st = (visitado => {}, salvo => {}, turismo => {});   # persistido em logs/jornada_<nome>.txt
my %bloqueado;             # mapa => instante em que o Motor de Episodios recusou
my $bloqueioNovo;          # mapa recusado ainda nao tratado pelo tick
my $mode = 'jornada';      # jornada | classe | turismo | kafra | retorno | pausa
my %md;                    # dados do modo atual
my ($lastTick, $lastLv, $lastJobLv, $lastJob, $lastMap, $wasDead) = (0);
my ($lastPublic, $nextBreak, $lastMoveCmd) = (0, 0, 0);
my (@pending, %lastReplyTo);
my ($criouEm, $criacoes) = (0, 0);

# =============================================================== leitura ===
sub loadData {
	@etapas = (); @classes = (); %pontos = (); %falas = (); %cidades = ();
	%opt = (
		chance_fala_ambiente => 4,      # % por minuto em campo
		intervalo_fala       => 180,    # segundos minimos entre falas publicas
		pausa_a_cada_min     => 45,     # minutos entre pausas
		pausa_a_cada_max     => 95,
		pausa_duracao_min    => 4,      # minutos
		pausa_duracao_max    => 14,
		kafra_seq            => 'c r0 c',
		ataque_normal        => 2,
		resposta_delay_min   => 6,
		resposta_delay_max   => 22,
		bloqueio_horas       => 6,      # depois disso tenta de novo o mapa fechado
	);

	my $file = Settings::getControlFilename('jornada.txt');
	my $fh;
	unless ($file && open($fh, '<:encoding(UTF-8)', $file)) {
		warning "[$NAME] control/jornada.txt nao encontrado - plugin inativo.\n";
		return;
	}
	while (my $l = <$fh>) {
		$l =~ s/#.*//; $l =~ s/^\s+|\s+$//g; next unless length $l;
		my @t = split /\s+/, $l;
		my $k = shift @t;
		if ($k eq 'etapa' && @t >= 5) {
			my ($min, $max, $jobs, $map, $city) = @t;
			push @etapas, { min => $min, max => $max, map => $map, city => $city,
			                jobs => { map { $_ => 1 } split /,/, $jobs } };
			$cidades{$city} = 1;
		} elsif ($k eq 'classe' && @t >= 6) {
			my ($from, $to, $minJob, $map, $x, $y, @seq) = @t;
			push @classes, { from => $from, to => $to, minJob => $minJob,
			                 map => $map, x => $x, y => $y, seq => join(' ', @seq) || 'c r0 c' };
		} elsif ($k eq 'ponto' && @t >= 4) {
			my ($city, $map, $x, $y, @resto) = @t;
			my %p = (map => $map, x => $x, y => $y);
			if (@resto >= 3 && $resto[0] eq 'volta') {
				shift @resto;
				@p{qw(vx vy)} = splice(@resto, 0, 2);
				$p{vseq} = join(' ', @resto) || 'r0';
			}
			push @{ $pontos{$city} }, \%p;
			$cidades{$city} = 1;
		} elsif ($k eq 'cidade') {
			$cidades{$_} = 1 for @t;
		} elsif ($k eq 'opcao' && @t >= 2) {
			my $key = shift @t; $opt{$key} = join(' ', @t);
		}
	}
	close $fh;

	my $ffile = Settings::getControlFilename('falas.txt');
	if ($ffile && open(my $ff, '<:encoding(UTF-8)', $ffile)) {
		my $sec = 'geral';
		while (my $l = <$ff>) {
			chomp $l; $l =~ s/\r//g;
			next if $l =~ /^\s*(#|$)/;
			if ($l =~ /^\s*\[(.+?)\]\s*$/) { $sec = lc $1; next; }
			$l =~ s/^\s+|\s+$//g;
			push @{ $falas{$sec} }, $l;
		}
		close $ff;
	}

	loadState();
	$loaded = 1;
	message sprintf("[%s] %d etapas, %d mudancas de classe, %d cidades.\n",
		$NAME, scalar @etapas, scalar @classes, scalar keys %cidades), 'success';
}

sub stateFile {
	my $n = ($char && $char->{name}) ? $char->{name} : ($config{username} || 'bot');
	$n =~ s/[^\w\-]/_/g;
	return ($Settings::logs_folder || 'logs') . "/jornada_$n.txt";
}

sub loadState {
	%st = (visitado => {}, salvo => {}, turismo => {});
	open(my $fh, '<', stateFile()) or return;
	while (<$fh>) { chomp; my ($k, $v) = split / /, $_, 2; $st{$k}{$v} = 1 if $k && defined $v && $st{$k}; }
	close $fh;
}

sub saveState {
	open(my $fh, '>', stateFile()) or return;
	for my $k (sort keys %st) { print $fh "$k $_\n" for sort keys %{ $st{$k} }; }
	close $fh;
}

# =============================================================== utilidades
sub mapName { return $field ? ($field->can('baseName') ? $field->baseName : $field->name) : ''; }
sub myPos   { return $char->position; }
sub rnd     { my ($a, $b) = @_; return $a + rand($b - $a); }
sub isTown  { return $cidades{ mapName() } ? 1 : 0; }

sub fechado {
	my ($map) = @_;
	return 0 unless $map && $bloqueado{$map};
	return 1 if time - $bloqueado{$map} < 3600 * $opt{bloqueio_horas};
	delete $bloqueado{$map};
	return 0;
}

sub fala {
	my ($sec, %v) = @_;
	my $list = $falas{$sec} or return undef;
	my $txt = $list->[ int rand @$list ];
	$v{nome}   = $char->{name} unless defined $v{nome};
	$v{lv}     = $char->{lv}   unless defined $v{lv};
	$v{cidade} = mapName()     unless defined $v{cidade};
	$txt =~ s/\{(\w+)\}/defined $v{$1} ? $v{$1} : ''/ge;
	return $txt;
}

# fala em publico respeitando o intervalo; $force ignora o intervalo. Devolve 1 se falou.
sub dizer {
	my ($secs, $chance, $force, %v) = @_;
	return 0 if !$force && time - $lastPublic < $opt{intervalo_fala};
	return 0 if rand(100) >= (defined $chance ? $chance : 100);
	my $txt;
	for my $s (ref $secs ? @$secs : ($secs)) { $txt = fala($s, %v); last if defined $txt; }
	return 0 unless defined $txt;
	if ($txt =~ s/^\/e\s+(\S+)\s*//) { Commands::run("e $1"); }   # "/e 3 texto" -> emote + fala
	Commands::run("c $txt") if length $txt;
	$lastPublic = time;
	return 1;
}

sub etapaAtual {
	my ($lv, $job) = ($char->{lv}, $char->{jobID});
	my @daClasse = grep { $_->{jobs}{$job} && !fechado($_->{map}) } @etapas;
	for my $e (@daClasse) {
		return $e if $lv >= $e->{min} && $lv <= $e->{max};
	}
	# nenhuma faixa aberta serve: a etapa aberta mais alta que ja cabe no nivel, senao a primeira
	my @cabem = grep { $lv >= $_->{min} } @daClasse;
	return @cabem ? $cabem[-1] : $daClasse[0];
}

sub combate {
	my ($on) = @_;
	my $e = etapaAtual();
	if ($on) {
		configModify('attackAuto', $opt{ataque_normal}, 1) if ($config{attackAuto} || '') ne $opt{ataque_normal};
		configModify('route_randomWalk', 1, 1) unless $config{route_randomWalk};
		if ($e) {
			configModify('lockMap', $e->{map}, 1)  if ($config{lockMap} || '') ne $e->{map};
			configModify('saveMap', $e->{city}, 1) if ($config{saveMap} || '') ne $e->{city};
		}
	} else {
		configModify('attackAuto', 1, 1) if ($config{attackAuto} || '') ne '1';   # so revida
		configModify('route_randomWalk', 0, 1) if $config{route_randomWalk};
		configModify('lockMap', '', 1) if $config{lockMap};
	}
}

sub andarAte {
	my ($map, $x, $y, $dist) = @_;
	$dist = 3 unless defined $dist;
	return 1 if mapName() eq $map && distance(myPos(), { x => $x, y => $y }) <= $dist;
	if (!AI::is('route', 'mapRoute') && time - $lastMoveCmd > 8) {
		Commands::run(mapName() eq $map ? "move $x $y" : "move $x $y $map");
		$lastMoveCmd = time;
	}
	return 0;
}

sub agendarPausa { $nextBreak = time + 60 * rnd($opt{pausa_a_cada_min}, $opt{pausa_a_cada_max}); }

sub setMode { my ($m, %d) = @_; $mode = $m; %md = (%d, since => time); message "[$NAME] modo: $m\n", 'info'; }

# =================================================================== tick ===
sub tick {
	return unless $net && $net->getState() == Network::IN_GAME && $char && $field;
	return if time - $lastTick < 1; $lastTick = time;
	loadData() unless $loaded;
	return unless $loaded && @etapas;
	agendarPausa() unless $nextBreak;

	my $map = mapName();

	# ---- deteccao de eventos ----
	if (defined $lastJobLv && ($char->{lv_job} != $lastJobLv || $char->{jobID} != $lastJob)) {
		# o raiseSkill fica INATIVO quando a proxima skill da lista ainda nao existe
		# (skill de Cavaleiro sendo Espadachim): reativa a cada job up / classe nova
		configModify('skillsAddAuto', 1, 1) if $config{skillsAddAuto};
	}
	if (defined $lastLv && $char->{lv} > $lastLv) { dizer('levelup', 55, 0); }
	if (defined $lastJob && $char->{jobID} != $lastJob) {
		dizer('classe', 100, 1);
		Commands::run('e 3');
		setMode('jornada');
	}
	if (!defined $lastMap || $map ne $lastMap) { onMapChange($map); }
	if ($char->{dead} && !$wasDead) { dizer('morte', 70, 1); setMode('jornada'); }
	($lastLv, $lastJobLv, $lastJob, $lastMap, $wasDead) =
		($char->{lv}, $char->{lv_job}, $char->{jobID}, $map, $char->{dead} ? 1 : 0);
	return if $char->{dead};

	# ---- Motor de Episodios recusou um mapa ----
	if ($bloqueioNovo) {
		my $m = $bloqueioNovo; undef $bloqueioNovo;
		$bloqueado{$m} = time;
		warning "[$NAME] $m ainda nao foi descoberto (Motor de Episodios); etapa pulada por $opt{bloqueio_horas} h.\n";
		for my $city (keys %pontos) {
			for my $i (0 .. $#{ $pontos{$city} }) {
				$st{turismo}{"$city#$i"} = 1 if $pontos{$city}[$i]{map} eq $m;
			}
		}
		saveState();
		dizer('bloqueado', 100, 1, cidade => $m);
		setMode('jornada');
	}

	processarRespostas();

	# ---- maquina de estados ----
	if ($mode eq 'pausa') {
		if (time >= $md{fim}) {
			Commands::run('stand') if $char->{sitting};
			dizer('fim_pausa', 60, 0);
			agendarPausa(); setMode('jornada');
		} elsif (!$char->{sitting} && !AI::is('route', 'mapRoute', 'attack')) {
			Commands::run('sit');
		}
		return;
	}

	if ($mode eq 'classe') {
		my $c = $md{c};
		if ($char->{jobID} != $c->{from} || fechado($c->{map})) { setMode('jornada', espera => time + 1800); return; }
		if (andarAte($c->{map}, $c->{x}, $c->{y}, 4)) {
			if (!$md{falou} || time - $md{falou} > 25) {
				if (($md{tentativas} || 0) >= 3) {
					warning "[$NAME] NPC de classe nao respondeu em $c->{map} $c->{x},$c->{y}. Confira o NPC e a sequencia.\n";
					setMode('jornada', espera => time + 1800); return;
				}
				Commands::run("talknpc $c->{x} $c->{y} $c->{seq}");
				$md{falou} = time; $md{tentativas}++;
			}
		}
		return;
	}

	if ($mode eq 'turismo') {
		my $p = $md{p};
		my $fim = sub { $st{turismo}{ $md{key} } = 1; saveState(); setMode('jornada'); };
		if (!$md{chegou}) {
			if (andarAte($p->{map}, $p->{x}, $p->{y}, 3)) {
				$md{chegou} = time; $md{sai} = time + rnd(25, 70);
				Commands::run('sit') if rand() < 0.6;
				dizer(["turismo_$p->{map}", "turismo_$md{city}", 'turismo'], 100, 1);
			} elsif (time - $md{since} > 300) {     # nao conseguiu chegar
				warning "[$NAME] nao cheguei em $p->{map} $p->{x},$p->{y}; ponto marcado como visto.\n";
				$fim->();
			}
		} elsif (time >= $md{sai}) {
			Commands::run('stand') if $char->{sitting};
			if (!defined $p->{vx} || $map ne $p->{map}) { $fim->(); return; }
			# volta por NPC (ex.: "Eco do presente" nas zonas de 2001)
			if (andarAte($p->{map}, $p->{vx}, $p->{vy}, 3) && (!$md{falouVolta} || time - $md{falouVolta} > 20)) {
				if (($md{tentVolta} || 0) >= 3) { warning "[$NAME] NPC de volta nao respondeu em $p->{map}.\n"; $fim->(); return; }
				Commands::run("talknpc $p->{vx} $p->{vy} $p->{vseq}");
				$md{falouVolta} = time; $md{tentVolta}++;
			}
		}
		return;
	}

	if ($mode eq 'kafra') {
		my $k = $md{npc};
		if (andarAte($map, $k->{x}, $k->{y}, 3)) {
			Commands::run("talknpc $k->{x} $k->{y} $opt{kafra_seq}");
			$st{salvo}{$map} = 1; saveState();
			setMode('jornada');
		} elsif (time - $md{since} > 120) { $st{salvo}{$map} = 1; setMode('jornada'); }
		return;
	}

	if ($mode eq 'retorno') {
		if ($map eq $md{city} && !AI::is('route', 'mapRoute')) {
			setMode('pausa', fim => time + 60 * rnd($opt{pausa_duracao_min}, $opt{pausa_duracao_max}));
			Commands::run('sit');
			dizer('pausa', 70, 1);
		} elsif (!AI::is('route', 'mapRoute') && time - $lastMoveCmd > 15) {
			Commands::run("move $md{city}"); $lastMoveCmd = time;
		}
		return;
	}

	# ---------------- modo jornada ----------------
	# 1) mudanca de classe disponivel?
	if (!$md{espera} || time > $md{espera}) {
		for my $c (@classes) {
			next unless $char->{jobID} == $c->{from} && $char->{lv_job} >= $c->{minJob};
			next if fechado($c->{map});
			if ($c->{from} == 0) {
				next if $char->getSkillLevel(Skill->new(handle => 'NV_BASIC')) < 9;
			} elsif (($char->{points_skill} || 0) > 0) {
				next;                                   # o NPC exige gastar os pontos antes
			}
			combate(0);
			dizer('rumo_classe', 100, 1);
			setMode('classe', c => $c);
			return;
		}
	}

	# 2) coisas pra fazer na cidade
	if (isTown() && !AI::is('route', 'mapRoute', 'attack')) {
		my $list = $pontos{$map} || [];
		for my $i (0 .. $#$list) {
			my $key = "$map#$i";
			next if $st{turismo}{$key} || fechado($list->[$i]{map});
			combate(0);
			setMode('turismo', p => $list->[$i], key => $key, city => $map);
			return;
		}
		if (!$st{salvo}{$map} && $npcsList) {
			my ($kafra) = grep { ($_->{name} || '') =~ /kafra/i } $npcsList->getItems;
			if ($kafra) {
				combate(0);
				setMode('kafra', npc => { x => $kafra->{pos}{x}, y => $kafra->{pos}{y} });
				return;
			}
		}
	}

	# 3) hora da pausa?
	if (time >= $nextBreak && !AI::is('attack')) {
		my $e = etapaAtual();
		if ($e) {
			combate(0);
			setMode('retorno', city => $e->{city});
			dizer('indo_pausa', 50, 0);
			return;
		}
	}

	# 4) seguir a jornada
	combate(1);
	if ($map eq ($config{lockMap} || '') && time - ($md{ultimaAmb} || 0) >= 60) {
		$md{ultimaAmb} = time;
		dizer('ambiente', $opt{chance_fala_ambiente}, 0);
	}
}

sub onMapChange {
	my ($map) = @_;
	return unless $loaded;
	if ($cidades{$map} && !$st{visitado}{$map}) {
		$st{visitado}{$map} = 1; saveState();
		dizer('cidade_nova', 100, 1, cidade => $map);
	} elsif (($config{lockMap} || '') eq $map) {
		dizer('chegou_campo', 25, 0);
	}
}

# ======================================== Motor de Episodios (mazzathena) ===
# episodios.txt: dispbottom "[Episodios] Esta regiao ainda nao foi descoberta. ... ; <mapa> chega em ..."
sub onLog {
	my (undef, undef, undef, undef, $msg) = @_;
	return unless defined $msg && index($msg, 'ainda nao foi descoberta') >= 0;
	$bloqueioNovo = $1 if $msg =~ /;\s*(\S+)\s+chega em/;
}

# ================================================= criacao do personagem ===
# config: mazzaJornada_personagem <nome>, _cabelo, _corCabelo, _sexo (M|F); slot = config char
sub onCharSelect {
	my (undef, $args) = @_;
	my $nome = $config{mazzaJornada_personagem};
	return unless defined $nome && length $nome;
	my $slot = (defined $config{char} && $config{char} =~ /^\d+$/) ? $config{char} : 0;
	if ($chars[$slot]) {
		# logo depois de criar, o OpenKore chama a tela sem autoLogin e pergunta no console: entra sozinho
		if (!$args->{autoLogin} && $criouEm) {
			$messageSender->sendCharLogin($slot);
			$Globals::timeout{charlogin}{time} = time;
			$args->{return} = 1;
		}
		return;
	}
	return if time - $criouEm < 30;
	if ($criacoes >= 3) { warning "[$NAME] nao consegui criar '$nome' (nome em uso?).\n"; return; }
	my @extra = (defined $config{mazzaJornada_cabelo} ? $config{mazzaJornada_cabelo} : 1,
	             defined $config{mazzaJornada_corCabelo} ? $config{mazzaJornada_corCabelo} : 0);
	push @extra, 'novice', ($config{mazzaJornada_sexo} || 'M')
		if $messageSender && ($messageSender->{char_create_version} || 0) == 0x0A39;
	message "[$NAME] conta sem personagem no slot $slot: criando '$nome'.\n", 'success';
	$criouEm = time; $criacoes++;
	$args->{return} = 1 if Misc::createCharacter($slot, $nome, @extra);
}

# ============================================================ conversas ====
sub nomeEhMeu { my ($msg) = @_; my $n = quotemeta($char->{name}); return $msg =~ /\b$n\b/i; }

sub agendarResposta {
	my ($tipo, $quem, $sec) = @_;
	return if $lastReplyTo{$quem} && time - $lastReplyTo{$quem} < 90;
	$lastReplyTo{$quem} = time;
	push @pending, { tipo => $tipo, quem => $quem, sec => $sec,
	                 at => time + rnd($opt{resposta_delay_min}, $opt{resposta_delay_max}) };
}

sub processarRespostas {
	my @rest;
	for my $p (@pending) {
		if (time < $p->{at}) { push @rest, $p; next; }
		my $txt = fala($p->{sec}, jogador => $p->{quem});
		next unless defined $txt;
		if ($p->{tipo} eq 'pm') { (my $q = $p->{quem}) =~ s/"/'/g; Commands::run(qq{pm "$q" $txt}); }
		else { Commands::run("c $txt"); $lastPublic = time; }
	}
	@pending = @rest;
}

sub onPM {
	my (undef, $a) = @_;
	return unless $loaded && $char && defined $a->{privMsgUser};
	agendarResposta('pm', $a->{privMsgUser}, 'pm');
}

sub onPub {
	my (undef, $a) = @_;
	return unless $loaded && $char;
	my ($quem, $msg) = (defined $a->{pubMsgUser} ? $a->{pubMsgUser} : '', defined $a->{pubMsg} ? $a->{pubMsg} : '');
	return if $quem eq $char->{name} || $quem eq '';
	if (nomeEhMeu($msg)) {
		agendarResposta('pub', $quem, 'chamado');
	} elsif ($msg =~ /\b(oi+|ola|eae|salve|opa|bom dia|boa tarde|boa noite|hi|hello)\b/i && rand() < 0.35) {
		agendarResposta('pub', $quem, 'saudacao');
	}
}

# ============================================================== comando ====
sub cmdJornada {
	my (undef, $arg) = @_;
	$arg = 'status' unless defined $arg && length $arg;
	if ($arg eq 'pausa') {
		my $e = etapaAtual(); combate(0);
		setMode('retorno', city => $e ? $e->{city} : 'prontera');
	} elsif ($arg eq 'retomar') {
		Commands::run('stand') if $char && $char->{sitting};
		agendarPausa(); setMode('jornada');
	} elsif ($arg eq 'reset') {
		%st = (visitado => {}, salvo => {}, turismo => {}); %bloqueado = (); saveState();
		message "[$NAME] historico de viagem zerado.\n", 'success';
	} else {
		my $e = $char ? etapaAtual() : undef;
		message sprintf("[%s] modo=%s | etapa=%s -> %s | proxima pausa em %d min | visitadas: %s | fechados: %s\n",
			$NAME, $mode, $e ? "$e->{min}-$e->{max}" : '-', $e ? "$e->{map} ($e->{city})" : '-',
			$nextBreak ? ($nextBreak - time) / 60 : 0, join(', ', sort keys %{ $st{visitado} }) || 'nenhuma',
			join(', ', grep { fechado($_) } sort keys %bloqueado) || 'nenhum'), 'info';
	}
}

1;
