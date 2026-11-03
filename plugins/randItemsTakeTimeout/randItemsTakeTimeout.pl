# randItemsTakeTimeout - tempo de pegar o loot com variacao, como gente (nem sempre na mesma fracao de segundo)
#
# Origem: https://github.com/Henrybk/Plugins/tree/master/randItemsTakeTimeout (commit 473f544, 2022-09-29), de
# Henrybk. O repositorio nao declara licenca; o autor mantem o core do OpenKore (GPL) e o plugin roda dentro dele.
# mazzakore (2026-11-03):
#   - o original so mexia no intervalo entre dois itens (ai_items_take_delay) e chamava Plugins::delHook com a
#     lista de hooks (o unload falhava); aqui tambem a espera antes do primeiro item (ai_items_take_start,
#     "olhar o drop antes de pegar") e a faixa e configuravel;
#   - cada item_take sorteia de novo; o timeouts.txt nao muda.
#
# config.txt:
#   randItemsTakeTimeout 1
#   randItemsTakeTimeout_min -60     # % minimo sobre o timeouts.txt (padrao -60)
#   randItemsTakeTimeout_max 40      # % maximo (padrao +40)
#   randItemsTakeTimeout_startMax 1.5  # teto em segundos para a espera antes do primeiro item (padrao 1.5)
package randItemsTakeTimeout;

use strict;
use Plugins;
use Globals qw(%config %timeout);
use Log qw(debug);
use AI;

Plugins::register('randItemsTakeTimeout', 'tempo de pegar loot com variacao', \&Unload, \&Unload);
my $hooks = Plugins::addHooks(
	['AI_pre',        \&tick,     undef],
	['ai_items_take', \&pegouUm,  undef],
);

sub Unload { Plugins::delHooks($hooks); }

sub sortear {
	my ($base) = @_;
	my $min = defined $config{randItemsTakeTimeout_min} ? $config{randItemsTakeTimeout_min} : -60;
	my $max = defined $config{randItemsTakeTimeout_max} ? $config{randItemsTakeTimeout_max} : 40;
	($min, $max) = ($max, $min) if $max < $min;
	my $v = ($base || 0) * (1 + ($min + rand($max - $min)) / 100);
	return $v < 0 ? 0 : int($v * 100) / 100;
}

# items_take recem-enfileirado: sorteia a espera inicial e o primeiro intervalo
sub tick {
	return unless $config{randItemsTakeTimeout};
	return unless AI::action() eq 'items_take';
	my $args = AI::args();
	return if $args->{randItemsTakeTimeout};
	$args->{randItemsTakeTimeout} = 1;
	# a espera inicial vem pequena no timeouts.txt (0.3): soma um "olhar" de ate startMax segundos
	my $teto = defined $config{randItemsTakeTimeout_startMax} ? $config{randItemsTakeTimeout_startMax} : 1.5;
	$args->{ai_items_take_start}{timeout} = sortear($timeout{ai_items_take_start}{timeout}) + rand($teto);
	$args->{ai_items_take_delay}{timeout} = sortear($timeout{ai_items_take_delay}{timeout});
	debug "[randItemsTakeTimeout] espera $args->{ai_items_take_start}{timeout} s, intervalo "
		. "$args->{ai_items_take_delay}{timeout} s\n", 'randItemsTakeTimeout';
}

# pegou um item: sorteia o intervalo ate o proximo
sub pegouUm {
	return unless $config{randItemsTakeTimeout} && AI::action() eq 'items_take';
	AI::args()->{ai_items_take_delay}{timeout} = sortear($timeout{ai_items_take_delay}{timeout});
}

1;
