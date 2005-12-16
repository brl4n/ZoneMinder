#!/usr/bin/perl -wT
#
# ==========================================================================
#
# ZoneMinder VISCA Control Script, $Date$, $Revision$
# Copyright (C) 2003, 2004, 2005  Philip Coombes
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# ==========================================================================
#
# This script continuously monitors the recorded events for the given
# monitor and applies any filters which would delete and/or upload 
# matching events
#
use strict;

# ==========================================================================
#
# These are the elements you can edit to suit your installation
#
# ==========================================================================

use constant LOG_FILE => ZM_PATH_LOGS.'/zmcontrol-visca.log';

# ==========================================================================

use ZoneMinder;
use Getopt::Long;
use Device::SerialPort;

$| = 1;

$ENV{PATH}  = '/bin:/usr/bin';
$ENV{SHELL} = '/bin/sh' if exists $ENV{SHELL};
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

sub Usage
{
	print( "
Usage: zmcontrol-visca.pl <various options>
");
	exit( -1 );
}

my $arg_string = join( " ", @ARGV );

my $device = "/dev/ttyS0";
my $address = 1;
my $command;
my ( $speed, $step );
my ( $xcoord, $ycoord );
my ( $panspeed, $tiltspeed );
my ( $panstep, $tiltstep );
my $preset;

if ( !GetOptions(
	'device=s'=>\$device,
	'address=i'=>\$address,
	'command=s'=>\$command,
	'speed=i'=>\$speed,
	'step=i'=>\$step,
	'xcoord=i'=>\$xcoord,
	'ycoord=i'=>\$ycoord,
	'panspeed=i'=>\$panspeed,
	'tiltspeed=i'=>\$tiltspeed,
	'panstep=i'=>\$panstep,
	'tiltstep=i'=>\$tiltstep,
	'preset=i'=>\$preset
	)
)
{
	Usage();
}

my $log_file = LOG_FILE;
open( LOG, ">>$log_file" ) or die( "Can't open log file: $!" );
open( STDOUT, ">&LOG" ) || die( "Can't dup stdout: $!" );
select( STDOUT ); $| = 1;
open( STDERR, ">&LOG" ) || die( "Can't dup stderr: $!" );
select( STDERR ); $| = 1;
select( LOG ); $| = 1;

print( $arg_string."\n" );

srand( time() );

my $serial_port = new Device::SerialPort( $device );
$serial_port->baudrate(9600);
$serial_port->databits(8);
$serial_port->parity('none');
$serial_port->stopbits(1);
$serial_port->handshake('rts');
$serial_port->stty_echo(0);
 
#$serial_port->read_const_time(250);
$serial_port->read_char_time(2);

sub printMsg
{
	my $msg = shift;
	my $prefix = shift || "";
	$prefix = $prefix.": " if ( $prefix );

	my $line_length = 16;
	my $msg_len = int(@$msg);

	print( $prefix );
	for ( my $i = 0; $i < $msg_len; $i++ )
	{
		if ( ($i > 0) && ($i%$line_length == 0) && ($i != ($msg_len-1)) )
		{
			printf( "\n%*s", length($prefix), "" );
		}
		printf( "%02x ", $msg->[$i] );
	}
	print( "[".$msg_len."]\n" );
}

sub sendCmd
{
	my $cmd = shift;
	my $ack = shift || 0;
	my $cmp = shift || 0;

	my $result = undef;

	printMsg( $cmd, "Tx" );
	my $id = $cmd->[0] & 0xf;

	my $tx_msg = pack( "C*", @$cmd );

	#print( "Tx: ".length( $tx_msg )." bytes\n" );
	my $n_bytes = $serial_port->write( $tx_msg );
	if ( !$n_bytes )
	{
		print( "Error, write failed: $!" );
	}
	if ( $n_bytes != length($tx_msg) )
	{
		print( "Error, incomplete write, only ".$n_bytes." of ".length($tx_msg)." written: $!" );
	}

	if ( $ack )
	{
		print( "Waiting for ack\n" );
		my $max_wait = 3;
		my $now = time();
		while( 1 )
		{
			my ( $count, $rx_msg ) = $serial_port->read(4);

			if ( $count )
			{
				#print( "Rx1: ".$count." bytes\n" );
				my @resp = unpack( "C*", $rx_msg );
				printMsg( \@resp, "Rx" );

				if ( $resp[0] = 0x80 + ($id<<4) )
				{
					if ( ($resp[1] & 0xf0) == 0x40 )
					{
						my $socket = $resp[1] & 0x0f;
						print( "Got ack for socket $socket\n" );
						$result = !undef;
					}
					else
					{
						printf( "Error, got bogus response\n" );
					}
					last;
				}
				else
				{
					print( "Error, got message for camera ".(($resp[0]-0x80)>>4)."\n" );
				}
			}
			if ( (time() - $now) > $max_wait )
			{
				last;
			}
		}
	}

	if ( $cmp )
	{
		print( "Waiting for command complete\n" );
		my $max_wait = 10;
		my $now = time();
		while( 1 )
		{
			#print( "Waiting\n" );
			my ( $count, $rx_msg ) = $serial_port->read(16);

			if ( $count )
			{
				#print( "Rx1: ".$count." bytes\n" );
				my @resp = unpack( "C*", $rx_msg );
				printMsg( \@resp, "Rx" );

				if ( $resp[0] = 0x80 + ($id<<4) )
				{
					if ( ($resp[1] & 0xf0) == 0x50 )
					{
						printf( "Got command complete\n" );
						$result = !undef;
					}
					else
					{
						printf( "Error, got bogus response\n" );
					}
					last;
				}
				else
				{
					print( "Error, got message for camera ".(($resp[0]-0x80)>>4)."\n" );
				}
			}
			if ( (time() - $now) > $max_wait )
			{
				last;
			}
		}
	}
	return( $result );
}

my $sync = 0xff;

sub cameraOff
{
	print( "Camera Off\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x00, 0x03, $sync );
	sendCmd( \@msg );
}

sub cameraOn
{
	print( "Camera On\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x00, 0x02, $sync );
	sendCmd( \@msg );
}

sub stop
{
	print( "Stop\n" );
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x01, 0x00, 0x00, 0x03, 0x03, $sync );
	sendCmd( \@msg );
}

sub moveUp
{
	print( "Move Up\n" );
	my $speed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x01, 0x00, $speed, 0x03, 0x01, $sync );
	sendCmd( \@msg );
}

sub moveDown
{
	print( "Move Down\n" );
	my $speed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x01, 0x00, $speed, 0x03, 0x02, $sync );
	sendCmd( \@msg );
}

sub moveLeft
{
	print( "Move Left\n" );
	my $speed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x01, $speed, 0x00, 0x01, 0x03, $sync );
	sendCmd( \@msg );
}

sub moveRight
{
	print( "Move Right\n" );
	my $speed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x01, $speed, 0x00, 0x02, 0x03, $sync );
	sendCmd( \@msg );
}

sub moveUpLeft
{
	print( "Move Up/Left\n" );
	my $panspeed = shift || 0x40;
	my $tiltspeed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x01, $panspeed, $tiltspeed, 0x01, 0x01, $sync );
	sendCmd( \@msg );
}

sub moveUpRight
{
	print( "Move Up/Right\n" );
	my $panspeed = shift || 0x40;
	my $tiltspeed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x01, $panspeed, $tiltspeed, 0x02, 0x01, $sync );
	sendCmd( \@msg );
}

sub moveDownLeft
{
	print( "Move Down/Left\n" );
	my $panspeed = shift || 0x40;
	my $tiltspeed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x01, $panspeed, $tiltspeed, 0x01, 0x02, $sync );
	sendCmd( \@msg );
}

sub moveDownRight
{
	print( "Move Down/Right\n" );
	my $panspeed = shift || 0x40;
	my $tiltspeed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x01, $panspeed, $tiltspeed, 0x02, 0x02, $sync );
	sendCmd( \@msg );
}

sub stepUp
{
	print( "Step Up\n" );
	my $step = shift;
	my $speed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x03, 0x00, $speed, 0x00, 0x00, 0x00, 0x00, ($step&0xf000)>>12, ($step&0x0f00)>>8, ($step&0x00f0)>>4, ($step&0x000f)>>0, $sync );

	sendCmd( \@msg );
}

sub stepDown
{
	print( "Step Down\n" );
	my $step = shift;
	$step = -$step;
	my $speed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x03, 0x00, $speed, 0x00, 0x00, 0x00, 0x00, ($step&0xf000)>>12, ($step&0x0f00)>>8, ($step&0x00f0)>>4, ($step&0x000f)>>0, $sync );
	sendCmd( \@msg );
}

sub stepLeft
{
	print( "Step Left\n" );
	my $step = shift;
	$step = -$step;
	my $speed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x03, $speed, 0x00, ($step&0xf000)>>12, ($step&0x0f00)>>8, ($step&0x00f0)>>4, ($step&0x000f)>>0, 0x00, 0x00, 0x00, 0x00, $sync );
	sendCmd( \@msg );
}

sub stepRight
{
	print( "Step Right\n" );
	my $step = shift;
	my $speed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x03, $speed, 0x00, ($step&0xf000)>>12, ($step&0x0f00)>>8, ($step&0x00f0)>>4, ($step&0x000f)>>0, 0x00, 0x00, 0x00, 0x00, $sync );
	sendCmd( \@msg );
}

sub stepUpLeft
{
	print( "Step Up/Left\n" );
	my $panstep = shift;
	$panstep = -$panstep;
	my $tiltstep = shift;
	my $panspeed = shift || 0x40;
	my $tiltspeed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x03, $panspeed, $tiltspeed, ($panstep&0xf000)>>12, ($panstep&0x0f00)>>8, ($panstep&0x00f0)>>4, ($panstep&0x000f)>>0, ($tiltstep&0xf000)>>12, ($tiltstep&0x0f00)>>8, ($tiltstep&0x00f0)>>4, ($tiltstep&0x000f)>>0, $sync );
	sendCmd( \@msg );
}

sub stepUpRight
{
	print( "Step Up/Right\n" );
	my $panstep = shift;
	my $tiltstep = shift;
	my $panspeed = shift || 0x40;
	my $tiltspeed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x03, $panspeed, $tiltspeed, ($panstep&0xf000)>>12, ($panstep&0x0f00)>>8, ($panstep&0x00f0)>>4, ($panstep&0x000f)>>0, ($tiltstep&0xf000)>>12, ($tiltstep&0x0f00)>>8, ($tiltstep&0x00f0)>>4, ($tiltstep&0x000f)>>0, $sync );
	sendCmd( \@msg );
}

sub stepDownLeft
{
	print( "Step Down/Left\n" );
	my $panstep = shift;
	$panstep = -$panstep;
	my $tiltstep = shift;
	$tiltstep = -$tiltstep;
	my $panspeed = shift || 0x40;
	my $tiltspeed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x03, $panspeed, $tiltspeed, ($panstep&0xf000)>>12, ($panstep&0x0f00)>>8, ($panstep&0x00f0)>>4, ($panstep&0x000f)>>0, ($tiltstep&0xf000)>>12, ($tiltstep&0x0f00)>>8, ($tiltstep&0x00f0)>>4, ($tiltstep&0x000f)>>0, $sync );
	sendCmd( \@msg );
}

sub stepDownRight
{
	print( "Step Down/Right\n" );
	my $panstep = shift;
	my $tiltstep = shift;
	$tiltstep = -$tiltstep;
	my $panspeed = shift || 0x40;
	my $tiltspeed = shift || 0x40;
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x03, $panspeed, $tiltspeed, ($panstep&0xf000)>>12, ($panstep&0x0f00)>>8, ($panstep&0x00f0)>>4, ($panstep&0x000f)>>0, ($tiltstep&0xf000)>>12, ($tiltstep&0x0f00)>>8, ($tiltstep&0x00f0)>>4, ($tiltstep&0x000f)>>0, $sync );
	sendCmd( \@msg );
}

sub zoomTele
{
	print( "Zoom Tele\n" );
	my $speed = shift || 0x06;
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x07, 0x20|$speed, $sync );
	sendCmd( \@msg );
}

sub zoomWide
{
	print( "Zoom Wide\n" );
	my $speed = shift || 0x06;
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x07, 0x30|$speed, $sync );
	sendCmd( \@msg );
}

sub zoomStop
{
	print( "Zoom Stop\n" );
	my $speed = shift || 0x06;
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x07, 0x00, $sync );
	sendCmd( \@msg );
}

sub focusNear
{
	print( "Focus Near\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x08, 0x03, $sync );
	sendCmd( \@msg );
}

sub focusFar
{
	print( "Focus Far\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x08, 0x02, $sync );
	sendCmd( \@msg );
}

sub focusStop
{
	print( "Focus Far\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x08, 0x00, $sync );
	sendCmd( \@msg );
}

sub focusAuto
{
	print( "Focus Auto\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x38, 0x02, $sync );
	sendCmd( \@msg );
}

sub focusMan
{
	print( "Focus Man\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x38, 0x03, $sync );
	sendCmd( \@msg );
}

sub presetClear
{
	my $preset = shift || 1;
	print( "Clear Preset $preset\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x3f, 0x00, $preset, $sync );
	sendCmd( \@msg );
}

sub presetSet
{
	my $preset = shift || 1;
	print( "Set Preset $preset\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x3f, 0x01, $preset, $sync );
	sendCmd( \@msg );
}

sub presetGoto
{
	my $preset = shift || 1;
	print( "Goto Preset $preset\n" );
	my @msg = ( 0x80|$address, 0x01, 0x04, 0x3f, 0x02, $preset, $sync );
	sendCmd( \@msg );
}

sub presetHome
{
	print( "Home Preset\n" );
	my @msg = ( 0x80|$address, 0x01, 0x06, 0x04, $sync );
	sendCmd( \@msg );
}

if ( $command eq "move_con_up" )
{
	moveUp( $tiltspeed );
}
elsif ( $command eq "move_con_down" )
{
	moveDown( $tiltspeed );
}
elsif ( $command eq "move_con_left" )
{
	moveLeft( $panspeed );
}
elsif ( $command eq "move_con_right" )
{
	moveRight( $panspeed );
}
elsif ( $command eq "move_con_upleft" )
{
	moveUpLeft( $panspeed, $tiltspeed );
}
elsif ( $command eq "move_con_upright" )
{
	moveUpRight( $panspeed, $tiltspeed );
}
elsif ( $command eq "move_con_downleft" )
{
	moveDownLeft( $panspeed, $tiltspeed );
}
elsif ( $command eq "move_con_downright" )
{
	moveDownLeft( $panspeed, $tiltspeed );
}
elsif ( $command eq "move_stop" )
{
	stop();
}
elsif ( $command eq "move_rel_up" )
{
	stepUp( $tiltstep, $tiltspeed );
}
elsif ( $command eq "move_rel_down" )
{
	stepDown( $tiltstep, $tiltspeed );
}
elsif ( $command eq "move_rel_left" )
{
	stepLeft( $panstep, $panspeed );
}
elsif ( $command eq "move_rel_right" )
{
	stepRight( $panstep, $panspeed );
}
elsif ( $command eq "move_rel_upleft" )
{
	stepUpLeft( $panstep, $tiltstep, $panspeed, $tiltspeed );
}
elsif ( $command eq "move_rel_upright" )
{
	stepUpRight( $panstep, $tiltstep, $panspeed, $tiltspeed );
}
elsif ( $command eq "move_rel_downleft" )
{
	stepDownLeft( $panstep, $tiltstep, $panspeed, $tiltspeed );
}
elsif ( $command eq "move_rel_downright" )
{
	stepDownRight( $panstep, $tiltstep, $panspeed, $tiltspeed );
}
elsif ( $command eq "zoom_con_tele" )
{
	zoomTele( $speed );
}
elsif ( $command eq "zoom_con_wide" )
{
	zoomWide( $speed );
}
elsif ( $command eq "zoom_stop" )
{
	zoomStop();
}
elsif ( $command eq "focus_con_near" )
{
	focusNear();
}
elsif ( $command eq "focus_con_far" )
{
	focusFar();
}
elsif ( $command eq "focus_stop" )
{
	focusStop();
}
elsif ( $command eq "focus_auto" )
{
	focusAuto();
}
elsif ( $command eq "focus_man" )
{
	focusMan();
}
elsif ( $command eq "preset_home" )
{
	presetHome();
}
elsif ( $command eq "preset_set" )
{
	presetSet( $preset );
}
elsif ( $command eq "preset_goto" )
{
	presetGoto( $preset );
}
else
{
	print( "Error, can't handle command $command\n" );
}

$serial_port->close();