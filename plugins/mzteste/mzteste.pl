# mzteste - roteiro de regressao do Servidor Mazzaro dentro do OpenKore (E3).
#
# Le um roteiro (config: mzteste_roteiro) com um passo por linha:
#     nome | comando | espera | timeout_segundos
#   comando: '-' (nenhum) ou um comando do console do OpenKore (ex.: "c @warp prontera")
#   espera:  estado:ingame          | personagem no mapa, conectado ao map-server
#            mapa:<nome>            | $field->baseName igual a <nome> (e no jogo)
#            log:<regex Perl>       | alguma mensagem do console (depois do comando) casa com a regex
#            tempo:<segundos>       | so espera (para testes que derrubam um servidor no meio)
# Cada passo so comeca quando o anterior passa. Timeout ou queda da conexao no meio = falha.
# No fim grava o resultado (config: mzteste_resultado) e encerra o OpenKore. Quem chama le o arquivo.
package mzteste;

use strict;
use Time::HiRes qw(time);
use Globals qw(%config $net $field $char);
use Log qw(message warning error);
use Plugins;
use Commands;
use Misc;
use Network;

Plugins::register('mzteste', 'roteiro de regressao do Servidor Mazzaro', \&unload);

my $hooks = Plugins::addHooks(
	['start3',         \&on_start],
	['mainLoop_post',  \&on_loop],
);
my $logHook = Log::addHook(\&on_log);

my (@steps, @done, @log);
my ($cur, $stepStart, $sent, $logMark, $finished, $wasInGame, $t0);

sub unload {
	Plugins::delHooks($hooks);
	Log::delHook($logHook);
}

sub on_start {
	my $file = $config{mzteste_roteiro};
	$t0 = time;
	if (!$file || !open(my $fh, '<', $file)) {
		return finish('falha', '(inicio)', "roteiro nao encontrado: " . ($file || '(mzteste_roteiro vazio)'));
	} else {
		while (my $line = <$fh>) {
			$line =~ s/\r?\n$//;
			next if $line =~ /^\s*(#|$)/;
			# start.exe embute o Perl 5.12: sem s///r
			my ($name, $cmd, $expect, $timeout) = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /\|/, $line, 4;
			push @steps, { name => $name, cmd => $cmd, expect => $expect, timeout => $timeout || 30 };
		}
		close $fh;
	}
	$cur = 0;
	message "[mzteste] roteiro $file: " . scalar(@steps) . " passo(s)\n", 'success';
}

# @log guarda as ultimas mensagens; $logBase = indice absoluto de $log[0] (as marcas de passo sao absolutas)
my $logBase = 0;
sub on_log {
	my ($type, $domain, $level, $verbosity, $msg) = @_;
	return if $type eq 'debug';
	push @log, $msg;
	while (@log > 2000) {
		shift @log;
		$logBase++;
	}
}

sub in_game {
	return $net && $net->getState() == Network::IN_GAME && $field && $char;
}

sub on_loop {
	return if $finished || !defined $cur;
	return finish('ok') if $cur >= @steps;
	my $s = $steps[$cur];
	my $now = time;
	if (!defined $stepStart) {
		$stepStart = $now;
		$sent = 0;
		$logMark = $logBase + @log;
		message "[mzteste] passo " . ($cur + 1) . "/" . scalar(@steps) . ": $s->{name}\n", 'success';
		# progresso para quem orquestra de fora (kore.py --derrubar proc@passo)
		if ($config{mzteste_progresso} && open(my $pf, '>', $config{mzteste_progresso})) {
			print $pf "$s->{name}\n";
			close $pf;
		}
	}
	# queda de conexao depois de ter entrado no jogo = falha imediata
	$wasInGame = 1 if in_game();
	if ($wasInGame && !in_game()) {
		return finish('falha', $s->{name}, 'conexao com o map-server caiu');
	}
	if (!$sent) {
		if ($s->{cmd} ne '-' && $s->{cmd} ne '') {
			return unless in_game();          # comandos so depois de entrar
			$logMark = $logBase + @log;
			Commands::run($s->{cmd});
		}
		$sent = 1;
	}
	if (check($s)) {
		push @done, { name => $s->{name}, ok => 1, secs => sprintf('%.1f', $now - $stepStart) };
		message "[mzteste] ok: $s->{name} (" . sprintf('%.1f', $now - $stepStart) . " s)\n", 'success';
		$cur++;
		undef $stepStart;
		return;
	}
	if ($now - $stepStart > $s->{timeout}) {
		return finish('falha', $s->{name}, "timeout de $s->{timeout} s esperando '$s->{expect}'");
	}
}

sub check {
	my ($s) = @_;
	my ($kind, $arg) = split /:/, $s->{expect}, 2;
	if ($kind eq 'estado') {
		return $arg eq 'ingame' ? in_game() : 0;
	} elsif ($kind eq 'mapa') {
		return in_game() && $field->baseName eq $arg;
	} elsif ($kind eq 'tempo') {
		return time - $stepStart >= $arg;
	} elsif ($kind eq 'log') {
		my $from = $logMark - $logBase;
		for my $i (($from > 0 ? $from : 0) .. $#log) {
			return 1 if $log[$i] =~ /$arg/;
		}
		return 0;
	}
	error "[mzteste] espera desconhecida: $s->{expect}\n";
	return 0;
}

sub finish {
	my ($result, $step, $why) = @_;
	return if $finished;
	$finished = 1;
	if ($result ne 'ok') {
		push @done, { name => $step, ok => 0, secs => defined $stepStart ? sprintf('%.1f', time - $stepStart) : 0 };
	}
	my $out = $config{mzteste_resultado};
	if ($out && open(my $fh, '>', $out)) {
		print $fh "resultado: $result\n";
		print $fh "passo_falho: $step\n" if $step;
		if ($why) {
			(my $w = $why) =~ s/"/'/g;
			print $fh "motivo: \"$w\"\n";
		}
		printf $fh "segundos: %.1f\n", time - ($t0 || time);
		print $fh "passos:\n";
		print $fh "  - { nome: $_->{name}, ok: " . ($_->{ok} ? 'true' : 'false') . ", segundos: $_->{secs} }\n" for @done;
		my @tail = @log[($#log > 30 ? $#log - 30 : 0) .. $#log];
		print $fh "ultimas_mensagens:\n";
		for my $m (@tail) {
			$m =~ s/\r?\n$//;
			$m =~ s/'/''/g;
			print $fh "  - '$m'\n";
		}
		close $fh;
	}
	if ($result eq 'ok') {
		message "[mzteste] RESULTADO: ok\n", 'success';
	} else {
		error "[mzteste] RESULTADO: falha no passo '$step': $why\n";
	}
	Misc::quit();
}

1;
