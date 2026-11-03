# onMonsterKill - roda um comando quando o alvo morre (emote de comemoracao, fala, sentar...)
#
# Origem: https://github.com/Henrybk/Plugins/tree/master/onMonsterKill (commit 473f544, 2022-09-29), de Henrybk.
# O repositorio nao declara licenca; o autor mantem o core do OpenKore (GPL) e o plugin roda dentro dele.
# mazzakore (2026-11-03): mesmas condicoes do original e mais
#   - _chance <0..100> (padrao 100): nem toda morte vira emote;
#   - _delay <min> <max> (segundos, padrao "0.4 1.5"): o comando sai depois de um tempo, nao no mesmo pacote;
#   - _timeout <s>: intervalo minimo entre dois disparos do mesmo bloco;
#   - "@monsterName" no comando vira o nome do monstro.
#
# config.txt:
#   onMonsterKill e 2 {          # comando do console
#       chance 15
#       delay 0.5 2
#       timeout 60
#       name Poring              # opcional: nome do monstro
#       nameID 1002              # opcional
#       dmgFromYou > 50          # opcional (faixa)
#       numAtkFromYou < 3        # opcional (faixa)
#       moblv 5                  # opcional
#       # + condicoes de checkSelfCondition
#   }
package onMonsterKill;

use strict;
use Plugins;
use Globals qw(%config);
use Utils qw(inRange);
use Log qw(debug message);
use Time::HiRes qw(time);

Plugins::register('onMonsterKill', 'comando quando o alvo morre', \&on_unload, \&on_unload);
my $hooks = Plugins::addHooks(
	['target_died', \&morreu, undef],
	['AI_pre',      \&tick,   undef],
);

my @fila;      # [quando, comando]
my %ultimo;    # bloco => time

sub on_unload { Plugins::delHooks($hooks); }

sub morreu {
	my (undef, $args) = @_;
	my $monster = $args->{monster} or return;
	for (my $i = 0; exists $config{"onMonsterKill_$i"}; $i++) {
		my $p = "onMonsterKill_$i";
		next unless $config{$p};
		next unless checkMonster($p, $monster) && Misc::checkSelfCondition($p);
		next if $config{"${p}_timeout"} && $ultimo{$p} && time - $ultimo{$p} < $config{"${p}_timeout"};
		my $chance = defined $config{"${p}_chance"} ? $config{"${p}_chance"} : 100;
		last unless rand(100) < $chance;   # o primeiro bloco que casa decide, como no original
		my ($min, $max) = split /\s+/, (defined $config{"${p}_delay"} ? $config{"${p}_delay"} : '0.4 1.5');
		$max = $min unless defined $max;
		my $cmd = $config{$p};
		my $nome = $monster->{name};
		$cmd =~ s/\@monsterName/$nome/g;
		push @fila, [time + $min + rand($max - $min), $cmd];
		$ultimo{$p} = time;
		debug "[onMonsterKill] $p: $cmd\n", 'onMonsterKill';
		last;
	}
}

sub tick {
	while (@fila && time >= $fila[0][0]) {
		my $item = shift @fila;
		Commands::run($item->[1]);
	}
}

sub checkMonster {
	my ($prefix, $monster) = @_;
	return 0 if $config{"${prefix}_disabled"};
	return 0 if $config{"${prefix}_name"} && $monster->{name} ne $config{"${prefix}_name"};
	return 0 if $config{"${prefix}_name_given"} && $monster->{name_given} ne $config{"${prefix}_name_given"};
	return 0 if $config{"${prefix}_nameID"} && $monster->{nameID} ne $config{"${prefix}_nameID"};
	return 0 if $config{"${prefix}_dmgFromYou"} && !inRange($monster->{dmgFromYou}, $config{"${prefix}_dmgFromYou"});
	return 0 if $config{"${prefix}_numAtkFromYou"} && !inRange($monster->{numAtkFromYou}, $config{"${prefix}_numAtkFromYou"});
	return 0 if $config{"${prefix}_moblv"} && $monster->{lv} != $config{"${prefix}_moblv"};
	return 1;
}

1;
