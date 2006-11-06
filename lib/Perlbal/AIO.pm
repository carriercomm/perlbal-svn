# AIO abstraction layer
#
# Copyright 2004, Danga Interactice, Inc.
# Copyright 2005-2006, Six Apart, Ltd.

package Perlbal::AIO;

use strict;
use POSIX qw(ENOENT EACCES EBADF);
use Fcntl qw(SEEK_CUR SEEK_SET SEEK_END O_RDWR O_CREAT O_TRUNC);

# Try and use IO::AIO or Linux::AIO, if it's around.
BEGIN {
    $Perlbal::OPTMOD_IO_AIO        = eval "use IO::AIO 1.6 (); 1;";
    $Perlbal::OPTMOD_LINUX_AIO     = eval "use Linux::AIO 1.71 (); 1;";

    # let's test if their Linux::AIO works on their platform.  common for it not to.
    if ($Perlbal::OPTMOD_LINUX_AIO) {
        my $good = 0;
        Linux::AIO::aio_open("/tmp/$$-" . rand() . "-bogusdir/bogusfile-$$", O_RDWR|O_CREAT|O_TRUNC, 0, sub {
            $good = 1 if $_[0] < 0 && $! == ENOENT;
        });
        while (Linux::AIO::nreqs()) {
            my $rfd = "";
            vec ($rfd, Linux::AIO::poll_fileno(), 1) = 1;
            select $rfd, undef, undef, undef;
            Linux::AIO::poll_cb();
        }
        unless ($good) {
            # pretend that they don't have Linux::AIO, but only bitch at them if they don't have IO::AIO ...
            unless ($Perlbal::OPTMOD_IO_AIO) {
                warn("WARNING:  Your installation of Linux::AIO doesn't work.\n".
                     "          You seem to have installed it without 'make test',\n".
                     "          or you ignored the failing tests.  I'm going to ignore\n".
                     "          that you have it and proceed without async IO.  The\n".
                     "          modern replacement to Linux::AIO is IO::AIO.\n");
            }
            $Perlbal::OPTMOD_LINUX_AIO = 0;
        }
    }
}

END {
    Linux::AIO::max_parallel(0)
        if $Perlbal::OPTMOD_LINUX_AIO;
    IO::AIO::max_parallel(0)
        if $Perlbal::OPTMOD_IO_AIO;
}

$Perlbal::AIO_MODE = "none";
$Perlbal::AIO_MODE = "ioaio" if $Perlbal::OPTMOD_IO_AIO;
$Perlbal::AIO_MODE = "linux" if $Perlbal::OPTMOD_LINUX_AIO;

############################################################################
# AIO functions available to callers
############################################################################

sub aio_readahead {
    my ($fh, $offset, $length, $user_cb) = @_;

    aio_channel_push(get_chan(), $user_cb, sub {
        my $cb = shift;
        if ($Perlbal::AIO_MODE eq "linux") {
            Linux::AIO::aio_readahead($fh, $offset, $length, $cb);
        } elsif ($Perlbal::AIO_MODE eq "ioaio") {
            IO::AIO::aio_readahead($fh, $offset, $length, $cb);
        } else {
            $cb->();
        }
    });
}

sub aio_stat {
    my ($file, $user_cb) = @_;

    aio_channel_push(get_chan($file), $user_cb, sub {
        my $cb = shift;
        if ($Perlbal::AIO_MODE eq "linux") {
            Linux::AIO::aio_stat($file, $cb);
        } elsif ($Perlbal::AIO_MODE eq "ioaio") {
            IO::AIO::aio_stat($file, $cb);
        } else {
            stat($file);
            $cb->();
        }
    });
}

sub aio_open {
    my ($file, $flags, $mode, $user_cb) = @_;

    aio_channel_push(get_chan($file), $user_cb, sub {
        my $cb = shift;

        if ($Perlbal::AIO_MODE eq "linux") {
            Linux::AIO::aio_open($file, $flags, $mode, sub {
                my $fd = shift;
                my $fh = _fh_of_fd_mode($fd, $mode);
                $cb->($fh);
            });
        } elsif ($Perlbal::AIO_MODE eq "ioaio") {
            IO::AIO::aio_open($file, $flags, $mode, $cb);
        } else {
            my $fh;
            my $rv = sysopen($fh, $file, $flags, $mode);
            $cb->($rv ? $fh : undef);
        }
    });
}

sub aio_unlink {
    my ($file, $user_cb) = @_;
    aio_channel_push(get_chan($file), $user_cb, sub {
        my $cb = shift;

        if ($Perlbal::AIO_MODE eq "linux") {
            Linux::AIO::aio_unlink($file, $cb);
        } elsif ($Perlbal::AIO_MODE eq "ioaio") {
            IO::AIO::aio_unlink($file, $cb);
        } else {
            my $rv = unlink($file);
            $rv = $rv ? 0 : -1;
            $cb->($rv);
        }
    });
}

sub aio_write {
    #   0    1        2        3(data) 4
    my ($fh, $offset, $length, undef,  $user_cb) = @_;
    return no_fh($user_cb) unless $fh;
    my $alist = \@_;

    aio_channel_push(get_chan(), $user_cb, sub {
        my $cb = shift;
        if ($Perlbal::AIO_MODE eq "linux") {
            Linux::AIO::aio_write($fh, $offset, $length, $alist->[3], 0, $cb);
        } elsif ($Perlbal::AIO_MODE eq "ioaio") {
            IO::AIO::aio_write($fh, $offset, $length, $alist->[3], 0, $cb);
        } else {
            my $old_off = sysseek($fh, 0, SEEK_CUR);
            sysseek($fh, $offset, 0);
            my $rv = syswrite($fh, $alist->[3], $length, 0);
            sysseek($fh, $old_off, SEEK_SET);
            $cb->($rv);
        }
    });
}

sub aio_read {
    #   0    1        2        3(data) 4
    my ($fh, $offset, $length, undef,  $user_cb) = @_;
    return no_fh($user_cb) unless $fh;
    my $alist = \@_;

    aio_channel_push(get_chan(), $user_cb, sub {
        my $cb = shift;
        if ($Perlbal::AIO_MODE eq "linux") {
            Linux::AIO::aio_read($fh, $offset, $length, $alist->[3], 0, $cb);
        } elsif ($Perlbal::AIO_MODE eq "ioaio") {
            IO::AIO::aio_read($fh, $offset, $length, $alist->[3], 0, $cb);
        } else {
            my $old_off = sysseek($fh, 0, SEEK_CUR);
            sysseek($fh, $offset, 0);
            my $rv = sysread($fh, $alist->[3], $length, 0);
            sysseek($fh, $old_off, SEEK_SET);
            $cb->($rv);
        }
    });
}

############################################################################
# AIO channel stuff
#    prevents all AIO threads from being consumed by requests for same
#    failing/overloaded disk by isolating them into separate 'channels' in
#    parent process and not dispatching more than the max in-flight count
#    allows.  think of a channel as a named queue.  or in reality, a disk.
############################################################################

my %chan_outstanding;  # $channel_name -> $num_in_flight
my %chan_pending;      # $channel_name -> [ [$subref, $cb], .... ]
my %chan_hitmaxdepth;  # $channel_name -> $times_enqueued
my $use_aio_chans = 0; # keep them off for now, until mogstored code is ready to use them
my $file_to_chan_hook; # coderef that returns $chan_name given a $filename

sub get_aio_stats {
    my $ret = {};
    foreach my $c (keys %chan_outstanding) {
        $ret->{$c} = {
            in_flight    => $chan_outstanding{$c},
            ctr_too_deep => $chan_hitmaxdepth{$c} || 0,
        };
    }

    foreach my $c (keys %chan_pending) {
        my $rec = $ret->{$c} ||= {};
        $rec->{delayed} = scalar @{$chan_pending{$c}};
    }

    return $ret;
}

# (external API).  set trans hook, but also enables AIO channels.
sub set_file_to_chan_hook {
    $file_to_chan_hook = shift;   # coderef that returns $chan_name given a $filename
    $use_aio_chans     = 1;
}

# internal API:
sub aio_channel_push {
    my ($chan, $user_cb, $action) = @_;

    # if we were to do it immediately, bypassing AIO channels (future option?)
    unless ($use_aio_chans) {
        $action->($user_cb);
        return;
    }

    # IO::AIO/etc only take one callback.  so we wrap the user
    # (caller) function with our own that first calls theirs, then
    # does our bookkeeping and queue management afterwards.
    my $wrapped_cb = sub {
        $user_cb->(@_);
        $chan_outstanding{$chan}--;
        aio_channel_cond_run($chan);
    };

    # in case this is the first time this queue has been used, init stuff:
    my $chanlist = ($chan_pending{$chan} ||= []);
    $chan_outstanding{$chan} ||= 0;

    my $max_out  = aio_chan_max_concurrent($chan);

    if ($chan_outstanding{$chan} < $max_out) {
        $chan_outstanding{$chan}++;
        $action->($wrapped_cb);
        return;
    } else {
        # too deep.  enqueue.
        $chan_hitmaxdepth{$chan}++;
        push @$chanlist, [$action, $wrapped_cb];
    }
}

sub aio_chan_max_concurrent {
    my ($chan) = @_;
    return 100 if $chan eq '[default]';
    return 10;
}

sub aio_channel_cond_run {
    my ($chan) = @_;

    my $chanlist = $chan_pending{$chan} or return;
    my $max_out  = aio_chan_max_concurrent($chan);

    my $job;
    while ($chan_outstanding{$chan} < $max_out && ($job = shift @$chanlist)) {
        $chan_outstanding{$chan}++;
        $job->[0]->($job->[1]);
    }
}

my $next_chan;
sub set_channel {
    $next_chan = shift;
}

sub set_file_for_channel {
    my ($file) = @_;
    if ($file_to_chan_hook) {
        $next_chan = $file_to_chan_hook->($file);
    } else {
        $next_chan = undef;
    }
}

# gets currently-set channel, then clears it.  or if none set,
# lets registered hook set the channel name from the optional
# $file parameter.  the default channel, '[default]' has no limits
sub get_chan {
    return undef unless $use_aio_chans;
    my ($file) = @_;
    set_file_for_channel($file) if $file;

    if (my $chan = $next_chan) {
        $next_chan = undef;
        return $chan;
    }

    return "[default]";
}

############################################################################
# misc util functions
############################################################################

sub _fh_of_fd_mode {
    my ($fd, $mode) = @_;
    return undef unless defined $fd && $fd >= 0;

    #TODO: use the write MODE for the given $mode;
    my $fh = IO::Handle->new_from_fd($fd, 'r+');
    my $num = fileno($fh);
    return $fh;
}

sub no_fh {
    my $cb = shift;

    my $i = 1;
    my $stack_trace = "";
    while (my ($pkg, $filename, $line, $subroutine, $hasargs,
               $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($i++)) {
        $stack_trace .= " at $filename:$line $subroutine\n";
    }

    Perlbal::log("crit", "Undef \$fh: $stack_trace");
    $cb->(undef);
    return undef;
}

1;
