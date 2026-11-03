# ====================
# reactOnActor v2.1
# ====================
# This plugin is licensed under the GNU GPL
# original code by hakore (hakore@users.sourceforge.net)
# ported to 2.1 by Kissa2k
#
# mazzakore: copiado de plugins/needs-review/reactOnActor/trunk (openkore/openkore, GPL) em 2026-11-03.
# Mudancas: o ator e achado pelo ID nas listas atuais ($playersList etc.); o teste de versao antigo
# (substr($Settings::VERSION, 4)) caia nos hashes %players/%monsters, que o core nao preenche mais, e o plugin
# nunca reagia. checkSelfCondition vem do Misc. Alem dos pacotes, olha os atores uma vez por segundo (o pacote
# de andar chega quando o ator comeca a andar, entao "actor_dist" quase nunca casava).
#

package reactOnActor;

use strict;
use Plugins;
use Globals;
use Utils;
use Commands;
use Misc;
use Log qw(message debug);

my @timers;

Plugins::register('reactOnActor', 'automatically react on certain actors', \&Unload, \&Unload);

my $hooks = Plugins::addHooks(
				['packet/actor_display', \&onActorDisplay, undef],
				['packet/actor_exists', \&onActorDisplay, undef],
				['packet/actor_connected', \&onActorDisplay, undef],
				['packet/actor_moved', \&onActorDisplay, undef],
				['packet/actor_spawned', \&onActorDisplay, undef],
				['AI_pre', \&onTick, undef]);

sub Unload {
	Plugins::delHooks($hooks);
};

sub onActorDisplay {
	my ($self, $args) = @_;

	# o handler do core ja rodou (packet/<nome> vem depois dele): o ator esta numa das listas
	foreach my $l (listas()) {
		if (my $actor = $l->[1]->getByID($args->{ID})) {
			$actor->{lv} = $args->{lv} if (!$actor->{lv} && $args->{lv});
			reagir($l->[0], $actor);
			return;
		}
	}
}

sub listas {
	return grep { $_->[1] } (['player', $playersList], ['monster', $monstersList], ['npc', $npcsList],
		['portal', $portalsList], ['pet', $petsList], ['pet', $slavesList]);
}

# mazzakore: o pacote de andar chega quando o ator COMECA a andar (ainda longe); ninguem manda pacote quando ele
# para do nosso lado. Uma vez por segundo olha os atores visiveis, para "actor_dist" valer. Use actor_timeout
# para nao repetir a reacao.
my $ultimoTick = 0;
sub onTick {
	return unless exists $config{reactOnActor_0};
	return if time - $ultimoTick < 1;
	$ultimoTick = time;
	foreach my $l (listas()) {
		reagir($l->[0], $_) foreach @{$l->[1]->getItems};
	}
}

sub reagir {
	my ($type, $actor) = @_;
	my $ID = unpack("V1", $actor->{ID});

	my $i = 0;
	while ((exists $config{"reactOnActor_$i"}) && $actor) {
		debug "[reactOnActor] > Checking reactOnActor_$i block...\n", "reactOnActor";
		if (
			(my $cmd = $config{"reactOnActor_$i"})
			&& Misc::checkSelfCondition("reactOnActor_$i")
			&& checkActorCondition("reactOnActor_${i}_actor", $actor, $type, $i)
			&& checkTimeout("reactOnActor_${i}_actor", $i)
		) {
			debug "[reactOnActor] > Check successful.\n", "reactOnActor";
			my %replace;
			$replace{ID} = $actor->{ID};
			$replace{binID} = $actor->{binID};
			$replace{name} = $actor->{name};
			$replace{type} = $type;
			my $pos = $actor->position();
			$replace{x} = $pos->{x};
			$replace{y} = $pos->{y};
			$replace{'$'} = '$';
			$cmd =~ s/\$(?:(\$)|actor->{(ID|binID|name|type|x|y)})/$replace{$1}$replace{$2}/g;
			message "[reactOnActor] Reacting to Actor ($ID) using command \"$cmd\".\n", "success";
			Commands::run($cmd);
			last;
		} else {
			debug "[reactOnActor] > Check failed.\n", "reactOnActor";
		}
		$i++;
	}
}

sub checkTimeout {
	my ($prefix, $i) = @_;
	
	return 1 unless $config{$prefix . "_timeout"};
	
	if(!$timers[$i]){
		$timers[$i] = time;
		return 1;
	}
	if(!timeOut($timers[$i], $config{$prefix . "_timeout"})){
		return 0;
	}else{
		$timers[$i] = time;
		return 1;
	}
}

sub checkActorCondition {
	my ($prefix, $actor, $type, $i) = @_;

	my $ID = unpack("V1", $actor->{ID});
	
	if ($config{$prefix . "_id"}) {
		debug "[reactOnActor] > _id " . $config{$prefix . "_id"} . " [$ID].\n", "reactOnActor";
		return 0 unless (existsInList($config{$prefix . "_id"}, $ID));
	}

	if ($config{$prefix . "_type"}) {
		debug "[reactOnActor] > _type " . $config{$prefix . "_type"} . " [$type].\n", "reactOnActor";
		return 0 unless (existsInList($config{$prefix . "_type"}, $type));
	}

	if ($actor->{walk_speed} && $config{$prefix . "_walkSpeed"}) {
		debug "[reactOnActor] > _walkSpeed " . $config{$prefix . "_walkSpeed"} . " [$actor->{walk_speed}].\n", "reactOnActor";
		return 0 unless (inRange($actor->{walk_speed}, $config{$prefix . "_walkSpeed"}));
	}

	if ($config{$prefix . "_whenStatusActive"}) {
		debug "[reactOnActor] > _whenStatusActive " . $config{$prefix . "_whenStatusActive"} . " [??].\n", "reactOnActor";
		return 0 unless (whenStatusActiveActor($actor, $config{$prefix . "_whenStatusActive"}));
	}
	
	if ($config{$prefix . "_whenStatusInactive"}) {
		debug "[reactOnActor] > _whenStatusInactive " . $config{$prefix . "_whenStatusInactive"} . " [??].\n", "reactOnActor";
		return 0 if (whenStatusActiveActor($actor, $config{$prefix . "_whenStatusInactive"}));
	}

	if ($type ne 'portal') {
		if ($config{$prefix . "_name"}) {
			debug "[reactOnActor] > _name " . $config{$prefix . "_name"} . " [$actor->{name}].\n", "reactOnActor";
			return 0 unless (existsInList($config{$prefix . "_name"}, $actor->{name}));
		}
		if ($config{$prefix . "_notName"}) {
			debug "[reactOnActor] > _notName " . $config{$prefix . "_notName"} . " [$actor->{name}].\n", "reactOnActor";
			return 0 if (existsInList($config{$prefix . "_notName"}, $actor->{name}));
		}
	}

	if ($type eq 'player') {
		if ($config{$prefix . "_isJob"}) {
			debug "[reactOnActor] > _isJob " . $config{$prefix . "_isJob"} . " [$jobs_lut{$actor->{jobID}}].\n", "reactOnActor";
			return 0 unless (existsInList($config{$prefix . "_isJob"}, $jobs_lut{$actor->{jobID}}));
		}
		if ($config{$prefix . "_isNotJob"}) {
			debug "[reactOnActor] > _isNotJob " . $config{$prefix . "_isNotJob"} . " [$jobs_lut{$actor->{jobID}}].\n", "reactOnActor";
			return 0 if (existsInList($config{$prefix . "_isNotJob"}, $jobs_lut{$actor->{jobID}}));
		}

		if ($config{$prefix."_isGuild"}) {
			debug "[reactOnActor] > _isGuild " . $config{$prefix . "_isGuild"} . " [$actor->{guild}{name}].\n", "reactOnActor";
			return 0 unless ($actor->{guild} && existsInList($config{$prefix . "_isGuild"}, $actor->{guild}{name}));
		}
		if ($config{$prefix."_isNotGuild"}) {
			debug "[reactOnActor] > _isNotGuild " . $config{$prefix . "_isNotGuild"} . " [$actor->{guild}{name}].\n", "reactOnActor";
			return 0 if ($actor->{guild} && existsInList($config{$prefix . "_isNotGuild"}, $actor->{guild}{name}));
		}

		if ($config{$prefix."_isParty"}) {
			debug "[reactOnActor] > _isParty " . $config{$prefix . "_isParty"} . " [$actor->{party}{name}].\n", "reactOnActor";
			return 0 unless ($actor->{party} && existsInList($config{$prefix . "_isParty"}, $actor->{party}{name}));
		}
		if ($config{$prefix."_isNotParty"}){
			debug "[reactOnActor] > _isNotParty " . $config{$prefix . "_isNotParty"} . " [$actor->{party}{name}].\n", "reactOnActor";
			return 0 if ($actor->{party} && existsInList($config{$prefix . "_isNotParty"}, $actor->{party}{name}));
		}

		if ($config{$prefix."_topHead"}) {
			my $item = itemNameSimple($actor->{headgear}{top});
			debug "[reactOnActor] > _topHead " . $config{$prefix . "_topHead"} . " [$item].\n", "reactOnActor";
			return 0 unless (existsInList($config{$prefix . "_topHead"}, $item));
		}
		if ($config{$prefix."_midHead"}) {
			my $item = itemNameSimple($actor->{headgear}{mid});
			debug "[reactOnActor] > _midHead " . $config{$prefix . "_midHead"} . " [$item].\n", "reactOnActor";
			return 0 unless (existsInList($config{$prefix . "_midHead"}, $item));
		}
		if ($config{$prefix."_lowHead"}) {
			my $item = itemNameSimple($actor->{headgear}{low});
			debug "[reactOnActor] > _lowHead " . $config{$prefix . "_lowHead"} . " [$item].\n", "reactOnActor";
			return 0 unless (existsInList($config{$prefix . "_lowHead"}, $item));
		}
		if ($config{$prefix."_weapon"}) {
			my $item = itemNameSimple($actor->{weapon});
			debug "[reactOnActor] > _weapon " . $config{$prefix . "_weapon"} . " [$item].\n", "reactOnActor";
			return 0 unless (existsInList($config{$prefix . "_weapon"}, $item));
		}
		if ($config{$prefix."_shield"}) {
			my $item = itemNameSimple($actor->{shield});
			debug "[reactOnActor] > _shield " . $config{$prefix . "_shield"} . " [$item].\n", "reactOnActor";
			return 0 unless (existsInList($config{$prefix . "_shield"}, $item));
		}

		if ($config{$prefix."_sex"}) {
			debug "[reactOnActor] > _sex " . $config{$prefix . "_sex"} . " [$actor->{sex}].\n", "reactOnActor";
			return 0 unless ($config{$prefix."_sex"} eq $actor->{sex});
		}

		if ($config{$prefix."_isDead"}) {
			debug "[reactOnActor] > _isDead " . $config{$prefix . "_isDead"} . " [$actor->{dead}].\n", "reactOnActor";
			return 0 unless ($actor->{dead});
		}elsif ($config{$prefix."_isSitting"}) {
			debug "[reactOnActor] > _isSitting " . $config{$prefix . "_isSitting"} . " [$actor->{sitting}].\n", "reactOnActor";
			return 0 unless ($actor->{sitting});
		}
	}

	if ($config{$prefix . "_lvl"}) {
		debug "[reactOnActor] > _lvl " . $config{$prefix . "_lvl"} . " [$actor->{lv}].\n", "reactOnActor";
		return 0 unless (inRange($actor->{lv}, $config{$prefix . "_lvl"}));
	}

	my $pos = $actor->position();
	if ($config{$prefix . "_x"}) {
		debug "[reactOnActor] > _x " . $config{$prefix . "_x"} . " [$pos->{x}].\n", "reactOnActor";
		return 0 unless (inRange($pos->{x}, $config{$prefix . "_x"}));
	}
	if ($config{$prefix . "_y"}) {
		debug "[reactOnActor] > _y " . $config{$prefix . "_y"} . " [$pos->{y}].\n", "reactOnActor";
		return 0 unless (inRange($pos->{y}, $config{$prefix . "_y"}));
	}
	if ($config{$prefix . "_dist"}) {
		my $dist = $actor->distance();
		debug "[reactOnActor] > _dist " . $config{$prefix . "_dist"} . " [$dist].\n", "reactOnActor";
		return 0 unless (inRange($dist, $config{$prefix . "_dist"}));
	}

	return $actor;
}

sub whenStatusActiveActor {
	my ($actor, $statuses) = @_;
	my @arr = split /[, ]*,[, ]*/, $statuses;
	foreach (@arr) {
		return 1 if $actor->{statuses}{$_};
	}
	return 0;
}

return 1;
