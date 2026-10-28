# mzctl - controle do OpenKore de fora, por TCP local (X1 do mazzaro).
#
# Escuta em 127.0.0.1:<mzctl_porta> (config; 0 ou vazio = desligado). Uma requisicao JSON por linha, uma resposta
# JSON por linha, na mesma conexao (varias em sequencia):
#   {"cmd": "move 150 170", "ate": "pos:150,170", "timeout": 20}
#   {"estado": true}                                   (so o estado, na hora)
#   cmd      comando do console do OpenKore (opcional)
#   ate      condicao de fim (opcional): estado:ingame | mapa:<nome> | log:<regex Perl> | pos:<x>,<y>[,<raio>] |
#            parado (sem acao de andar na fila da IA) | tempo:<s>
#   espera   sem 'ate': segundos colhendo o log depois do comando (padrao 1)
#   timeout  teto para o 'ate' (padrao 30)
# Resposta: {"ok": 1|0, "motivo": ..., "segundos": ..., "log": [mensagens desde o comando], "estado": {...}}
# O estado traz rede, mapa, posicao, atributos, inventario e o que esta em volta (NPCs, monstros, jogadores, portais).
package mzctl;

use strict;
use IO::Socket::INET;
use IO::Select;
use Time::HiRes qw(time);
use JSON::Tiny qw(encode_json decode_json);
use Globals qw(%config $net $field $char %jobs_lut $npcsList $monstersList $playersList $portalsList);
use Log qw(message warning error);
use Plugins;
use Commands;
use Network;
use AI;
use Utils qw(calcPosition blockDistance);

Plugins::register('mzctl', 'controle do OpenKore por TCP local (mazzaro)', \&unload);

my $hooks = Plugins::addHooks(
	['start3',        \&on_start],
	['mainLoop_post', \&on_loop],
);
my $logHook = Log::addHook(\&on_log);

my ($listen, $sel, %conns);
my (@log, $logBase);
$logBase = 0;

sub unload {
	Plugins::delHooks($hooks);
	Log::delHook($logHook);
	close $_->{sock} for values %conns;
	close $listen if $listen;
}

sub on_start {
	my $port = $config{mzctl_porta};
	return unless $port;
	$listen = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $port, Proto => 'tcp',
		Listen => 5, ReuseAddr => 1);
	if (!$listen) {
		error "[mzctl] nao abriu 127.0.0.1:$port: $!\n";
		return;
	}
	$sel = IO::Select->new($listen);
	message "[mzctl] ouvindo em 127.0.0.1:$port\n", 'success';
}

# @log guarda as ultimas mensagens; $logBase = indice absoluto de $log[0]
sub on_log {
	my ($type, $domain, $level, $verbosity, $msg) = @_;
	return if $type eq 'debug';
	push @log, $msg;
	while (@log > 5000) {
		shift @log;
		$logBase++;
	}
}

sub on_loop {
	return unless $sel;
	for my $s ($sel->can_read(0)) {
		if ($s == $listen) {
			my $c = $listen->accept or next;
			$sel->add($c);
			$conns{fileno $c} = { sock => $c, buf => '', req => undef };
			next;
		}
		my $c = $conns{fileno $s} or next;
		my $n = sysread($s, my $data, 65536);
		if (!$n) {
			drop($c);
			next;
		}
		$c->{buf} .= $data;
	}
	for my $c (values %conns) {
		start_request($c) if !$c->{req} && $c->{buf} =~ /\n/;
		service($c) if $c->{req};
	}
}

sub drop {
	my ($c) = @_;
	$sel->remove($c->{sock});
	delete $conns{fileno $c->{sock}};
	close $c->{sock};
}

sub start_request {
	my ($c) = @_;
	$c->{buf} =~ s/^([^\n]*)\n//;
	my $line = $1;
	$line =~ s/\r$//;
	return if $line =~ /^\s*$/;
	my $req = eval { decode_json($line) };
	if (!$req || ref $req ne 'HASH') {
		return reply($c, { ok => 0, motivo => 'JSON invalido' });
	}
	$req->{t0} = time;
	# a marca vem depois do eco do comando: um 'log:' com o texto do proprio comando nao pode casar com o eco
	message "[mzctl] comando: $req->{cmd}\n", 'success' if defined $req->{cmd} && $req->{cmd} ne '';
	$req->{mark} = $logBase + @log;
	Commands::run($req->{cmd}) if defined $req->{cmd} && $req->{cmd} ne '';
	$c->{req} = $req;
}

sub service {
	my ($c) = @_;
	my $req = $c->{req};
	my $dt = time - $req->{t0};
	if ($req->{estado} && !defined $req->{cmd} && !$req->{ate}) {
		return reply($c, { ok => 1 });
	}
	if ($req->{ate}) {
		my $r = check($req);
		if (!defined $r) {
			return reply($c, { ok => 0, motivo => "condicao desconhecida: $req->{ate}" });
		}
		return reply($c, { ok => 1 }) if $r;
		my $teto = $req->{timeout} || 30;
		return reply($c, { ok => 0, motivo => "timeout de $teto s esperando '$req->{ate}'" }) if $dt > $teto;
		return;
	}
	my $espera = defined $req->{espera} ? $req->{espera} : 1;
	reply($c, { ok => 1 }) if $dt >= $espera;
}

sub in_game {
	return $net && $net->getState() == Network::IN_GAME && $field && $char;
}

# 1 = passou, 0 = ainda nao, undef = condicao desconhecida
sub check {
	my ($req) = @_;
	my ($kind, $arg) = split /:/, $req->{ate}, 2;
	if ($kind eq 'estado') {
		return $arg eq 'ingame' ? (in_game() ? 1 : 0) : undef;
	} elsif ($kind eq 'mapa') {
		return in_game() && $field->baseName eq $arg ? 1 : 0;
	} elsif ($kind eq 'tempo') {
		return time - $req->{t0} >= $arg ? 1 : 0;
	} elsif ($kind eq 'parado') {
		return 0 unless in_game();
		return (AI::inQueue('move', 'route', 'mapRoute') ? 0 : 1);
	} elsif ($kind eq 'pos') {
		return 0 unless in_game();
		my ($x, $y, $raio) = split /,/, $arg;
		my $p = calcPosition($char);
		return blockDistance($p, { x => $x, y => $y }) <= ($raio || 0) ? 1 : 0;
	} elsif ($kind eq 'log') {
		my $from = $req->{mark} - $logBase;
		for my $i (($from > 0 ? $from : 0) .. $#log) {
			return 1 if $log[$i] =~ /$arg/;
		}
		return 0;
	}
	return undef;
}

sub reply {
	my ($c, $res) = @_;
	my $req = $c->{req};
	if ($req) {
		$res->{segundos} = sprintf('%.1f', time - $req->{t0}) + 0;
		my $from = $req->{mark} - $logBase;
		my @l = @log[($from > 0 ? $from : 0) .. $#log];
		s/\r?\n$// for @l;
		$res->{log} = \@l;
	}
	$res->{estado} = estado();
	my $out = eval { encode_json($res) };
	$out = encode_json({ ok => 0, motivo => "falha ao montar a resposta: $@" }) unless defined $out;
	my $sock = $c->{sock};
	syswrite($sock, $out . "\n");
	$c->{req} = undef;
}

sub atores {
	my ($list, $me) = @_;
	return [] unless $list;
	my @out;
	for my $a (@{$list->getItems}) {
		next unless $a && $a->{pos_to};
		my $p = calcPosition($a);
		push @out, { nome => $a->{name}, id => $a->{binID}, x => $p->{x} + 0, y => $p->{y} + 0,
			dist => $me ? blockDistance($me, $p) + 0 : undef, ($a->{nameID} ? (tipo => $a->{nameID} + 0) : ()) };
	}
	return [sort { ($a->{dist} || 0) <=> ($b->{dist} || 0) } @out];
}

sub estado {
	my %e = (rede => $net ? $net->getState() + 0 : -1, no_jogo => in_game() ? 1 : 0);
	return \%e unless $char;
	my $p = $field && $char->{pos_to} ? calcPosition($char) : undef;
	%e = (%e,
		nome => $char->{name}, classe => $jobs_lut{$char->{jobID}}, lv => $char->{lv} + 0, lv_classe => $char->{lv_job} + 0,
		hp => $char->{hp} + 0, hp_max => $char->{hp_max} + 0, sp => $char->{sp} + 0, sp_max => $char->{sp_max} + 0,
		zeny => $char->{zeny} + 0, peso => $char->{weight} + 0, peso_max => $char->{weight_max} + 0,
		morto => $char->{dead} ? 1 : 0, sentado => $char->{sitting} ? 1 : 0, ia => AI::action() || '',
	);
	if ($field) {
		$e{mapa} = $field->baseName;
	}
	if ($p) {
		$e{x} = $p->{x} + 0;
		$e{y} = $p->{y} + 0;
	}
	my $inv = $char->inventory;
	if ($inv && $inv->isReady) {
		$e{inventario} = [map { { id => $_->{nameID} + 0, nome => $_->{name}, qtd => $_->{amount} + 0,
			($_->{equipped} ? (equipado => 1) : ()) } } @{$inv->getItems}];
	}
	$e{npcs} = atores($npcsList, $p);
	$e{monstros} = atores($monstersList, $p);
	$e{jogadores} = atores($playersList, $p);
	$e{portais} = atores($portalsList, $p);
	return \%e;
}

1;
