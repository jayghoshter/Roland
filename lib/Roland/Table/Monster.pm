package Roland::Table::Monster;
use Moose;
with 'Roland::Table';

use Data::Bucketeer;
use Roland::Result::Monster;

use namespace::autoclean;

has _guts => (
  is => 'ro',
);

sub from_data {
  my ($class, $data, $hub) = @_;

  return $class->new({
    _guts => $data,
    hub   => $hub,
  });
}

sub roll_table {
  my ($self) = @_;

  # TODO: barf about extra table entries?
  my $main = $self->_guts->[0];
  my $name = $main->{Name} // "(unknown)";
  my $num_dice = $main->{stats}{'No. Appearing'} // '?';
  $num_dice = $num_dice->{wandering} if ref $num_dice;
  my $num = $num_dice =~ /d/
          ? $self->hub->roll_dice($num_dice, "number of $name")
          : $num_dice;

  my $HD = $main->{stats}{'Hit Dice'} // '?';
  my @hd = split /\s+/, $HD;
  my $hd = do {
    local $" = '';
    my $d = $hd[0] !~ /d/ ? 'd8' : '';
    "$hd[0]$d@hd[ 1 .. $#hd]"
  };

  my @units = $num eq '?'
    ? ()
    : map {; { hp => $self->hub->roll_dice($hd, "$name \#$_ hp") } } 1 .. $num;

  my %extra;
  for my $extra (@{ $main->{extras} || [] }) {
    my $desc = $extra->{label};

    my $result = $self->hub->roll_table([$extra], "$name/$desc");
    # TODO reinstate encounter redirects
    $extra{ $desc } = $result;
  }

  for my $unit_extra (@{ $main->{'per-unit'} || [] }) {
    my $desc = $unit_extra->{label};

    UNIT: for my $unit (@units) {
      my $result = $self->hub->roll_table([$unit_extra], "$name/$desc");
      # TODO reinstate unit redirects

      $unit->{ $desc } = $result;
    }
  }

  my $ac  = $main->{stats}{'Armor Class'} // '?';
  my $mv  = $main->{stats}{Movement}      // '?';
  my $dmg = $main->{stats}{Damage}        // '?';

  my $xp   = $self->xp_for_monster($main) || '?';
  my $xp_t = $xp eq '?' ? '?' : $num * $xp;

  return Roland::Result::Monster->new(
    name  => $name,
    hit_dice => $HD,
    damage   => $dmg,
    armor_class => $ac,
    movement    => $mv,
    xp_per_unit => $xp,

    extras => \%extra,
    units  => \@units,
  );
}

my $XP_LOOKUP = Data::Bucketeer->new('>=' => {
  0.9 => sub { [    5,    1 ] },
  1.0 => sub { [   10,    1 ] },
  1.1 => sub { [   15,    1 ] },
  2.0 => sub { [   20,    5 ] },
  2.1 => sub { [   25,   10 ] },
  3.0 => sub { [   50,   15 ] },
  3.1 => sub { [   50,   25 ] },
  4.0 => sub { [   75,   50 ] },
  4.1 => sub { [  125,   75 ] },
  5.0 => sub { [  175,  125 ] },
  5.1 => sub { [  225,  175 ] },
  6.0 => sub { [  350,  225 ] },
  6.1 => sub { [  350,  300 ] },
  7.0 => sub { [  450,  400 ] },
  8.0 => sub { [  650,  550 ] },
  9.0 => sub { [  900,  700 ] },
  11  => sub { [ 1100,  800 ] },
  13  => sub { [ 1350,  950 ] },
  17  => sub { [ 2000, 1150 ] },
  21  => sub {
    my $hd   = int $_;
    my $over = $hd - 21;
    return [
      2500 + 250 * $over,
      2000,
    ];
  },
});

sub xp_for_monster {
  my ($self, $monster) = @_;
  my $bonuses = @{ $monster->{'XP Bonuses'} // [] };

  return 0 unless my $hd = $monster->{stats}{'Hit Dice'};
  my ($dice, $sign, $bonus) = split /\s+/, $hd, 3;
  $bonus = ($sign || $bonus) ? "$sign$bonus" : 0;

  if ($dice =~ /d/) {
    my ($num, $type) = split /d/, $dice, 2;
    die "confused about hit dice: $hd" if $type != 8 and $num != 1;
    if ($type > 8) { $bonus = 1  };
    if ($type < 8) { $bonus = -1 }
    $dice = $num;
  }

  my $d8 = $dice;
  $d8 += $bonus > 0 ? .1 : $bonus < 0 ? -.1 : 0;

  my $pair = $XP_LOOKUP->result_for($d8);
  return($pair->[0] + $pair->[1] * $bonuses);
}

1;