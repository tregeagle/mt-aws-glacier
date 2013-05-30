# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

package App::MtAws::HttpWriter;

use strict;
use warnings;
use utf8;
use Carp;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->initialize();
    return $self;
}

sub initialize
{
	my ($self) = @_;
    $self->{write_threshold} = 2*1024*1024;
    
    # when to append string to existing, or when to use new buffer
    # this actually affects both string concatenation performance and file write performance
    # (data flushed right after writing single append_threshold chunk); 
    $self->{append_threshold} = 64*1024; # 1024*1024;
    $self->{size} or confess;
}

sub reinit
{
	my ($self) = @_;
	$self->{totalsize}=0;
	$self->{total_commited_length} = $self->{pending_length} = $self->{total_length} = $self->{incr_position} = 0;
	$self->{buffers} = [];
}

sub add_data
{
	my $self = $_[0];
	return unless length($_[1]);
	my $len = length($_[1]);
	if (scalar @{$self->{buffers}} && length(${$self->{buffers}->[-1]}) <= $self->{append_threshold}) {
		${$self->{buffers}->[-1]} .= $_[1];
	} else {
		push @{$self->{buffers}}, \$_[1];
	}
	$self->{pending_length} += $len;
	$self->{total_length} += $len;
	
	if ($self->{pending_length} > $self->{write_threshold}) {
		$self->_flush();
	}
	
	1;
}

sub _flush
{
	confess "not implemented";
}

sub _flush_buffers
{
	my ($self, @files) = @_;
	for (@{$self->{buffers}}) {
		for my $fh (@files) {
			print $fh $$_ or confess "cant write to file $!";
		}
		my $len = length($$_);
		$self->{total_commited_length} += $len;
		$self->{incr_position} += $len;
	}
	$self->{buffers} = [];
	$self->{pending_length} = 0;
}

sub finish
{
	my ($self) = @_;
	$self->_flush();
	$self->{total_commited_length} == $self->{total_length} or confess; 
	return $self->{total_length} == $self->{size} ? ('ok') : ('retry', 'Unexpected end of data');
}

package App::MtAws::HttpSegmentWriter;

use strict;
use warnings;
use utf8;
use App::MtAws::Utils;
use Fcntl qw/SEEK_SET LOCK_EX LOCK_UN/;
use Carp;
use base qw/App::MtAws::HttpWriter/;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->SUPER::initialize(%args);
    $self->initialize();
    return $self;
}

sub initialize
{
	my ($self) = @_;
    defined($self->{filename}) or confess;
    defined($self->{tempfile}) or confess;
    defined($self->{position}) or confess;
}

sub reinit
{
	my ($self) = @_;
	open $self->{T}, ">", "$self->{filename}_part_$self->{position}_$self->{size}" or confess;
	binmode $self->{T};
	$self->SUPER::reinit();
}


sub _flush
{
	my ($self) = @_;
	if ($self->{pending_length}) {
		open_file(my $fh, $self->{tempfile}, mode => '+<', binary => 1) or confess "cant open file $self->{tempfile} $!";
		flock $fh, LOCK_EX or confess;
		$fh->flush();
		$fh->autoflush(1);
		seek $fh, $self->{position}+$self->{incr_position}, SEEK_SET or confess "cannot seek() $!";
		my $T = $self->{T};
		$self->_flush_buffers($fh, $T);
		flock $fh, LOCK_UN or confess;
		close $fh or confess;
	}
}

sub finish
{
	my ($self) = @_;
	my @r = $self->SUPER::finish();
	close $self->{T} or confess;
	return @r;
}


package App::MtAws::HttpFileWriter;

use strict;
use warnings;
use utf8;
use App::MtAws::Utils;
use Fcntl qw/SEEK_SET LOCK_EX LOCK_UN/;
use Carp;
use base qw/App::MtAws::HttpWriter/;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->SUPER::initialize(%args);
    $self->initialize();
    return $self;
}

sub initialize
{
	my ($self) = @_;
    defined($self->{tempfile}) or confess;
}

sub reinit
{
	my ($self) = @_;
	undef $self->{fh};
	open_file($self->{fh}, $self->{tempfile}, mode => '+<', binary => 1) or confess "cant open file $self->{tempfile} $!";
	binmode $self->{fh};
	$self->SUPER::reinit();
}

sub _flush
{
	my ($self) = @_;
	if ($self->{pending_length}) {
		$self->_flush_buffers($self->{fh});
	}
}

sub finish
{
	my ($self) = @_;
	my @r = $self->SUPER::finish();
	close $self->{fh} or confess;
	return @r;
}

1;