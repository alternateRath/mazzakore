# IdletimeSelfCond - condicao "_whenIdleFor <segundos>" em qualquer bloco que usa checkSelfCondition
#
# Origem: https://github.com/Henrybk/Plugins/tree/master/IdletimeSelfCond (idleTimeCondition.pl, commit 473f544,
# 2022-09-29), de Henrybk. O repositorio nao declara licenca; o autor mantem o core do OpenKore (GPL) e o plugin
# roda dentro dele.
# mazzakore (2026-11-03): reescrito pequeno.
#   - o original guardava a hora do ultimo "ocupado" so quando alguma condicao era checada, num relogio unico,
#     e comecava valendo (relogio vazio = ocioso desde 1970); aqui o relogio anda a cada AI_pre;
#   - o original devolvia return=1 e podia desfazer a reprovacao de outro plugin; aqui so reprova;
#   - _whenNotIdleFor <s>: o contrario (ocupado ha pelo menos <s> segundos).
#
# Ocioso = fila da IA vazia (AI::isIdle: sem andar, atacar, pegar item, rota...).
#
# config.txt (exemplos):
#   doCommand e ... {            # emote depois de 20 s parado
#       whenIdleFor 20
#   }
#   useSelf_skill ... {
#       whenIdleFor 5
#   }
package IdletimeSelfCond;

use strict;
use Plugins;
use Globals qw(%config $char);
use AI;
use Time::HiRes qw(time);

Plugins::register('IdletimeSelfCond', 'condicao whenIdleFor em checkSelfCondition', \&Unload, \&Unload);
my $hooks = Plugins::addHooks(
	['AI_pre',             \&tick,  undef],
	['checkSelfCondition', \&check, undef],
);

my ($ociosoDesde, $ocupadoDesde);

sub Unload { Plugins::delHooks($hooks); }

sub tick {
	if (AI::isIdle()) {
		$ociosoDesde = time unless defined $ociosoDesde;
		undef $ocupadoDesde;
	} else {
		$ocupadoDesde = time unless defined $ocupadoDesde;
		undef $ociosoDesde;
	}
}

sub check {
	my (undef, $args) = @_;
	my $p = $args->{prefix};
	if (my $s = $config{"${p}_whenIdleFor"}) {
		$args->{return} = 0 unless defined $ociosoDesde && time - $ociosoDesde >= $s;
	}
	if (my $s = $config{"${p}_whenNotIdleFor"}) {
		$args->{return} = 0 unless defined $ocupadoDesde && time - $ocupadoDesde >= $s;
	}
}

1;
