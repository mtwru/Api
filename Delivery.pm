package MTW::Delivery;

use 5.008008;
use strict;
use warnings;

=head1

MTW::Delivery - ready to go lib for sending email messages with locale, base64 encoding and DKIM signature

=head1 SYNOPSIS

Using example:

	use MTW::Delivery;
	my $r = mail (
		'to@a.com',
		'Subject',
		'My message here',
		{encode_from => 'koi8-r'}
	);
	$r = (!$r) ? "OK" : "FALSE";
	print "Sending message: $r\n";

Mandatory args:
	To - recipient address,
	Subject - message subject,
	Message - message content

Optional args:
Hash data with keys (and default values):
	verbose		=> verbose mode (default: 0)
	via			=> sending method, supported 'sendmail' or smtp address, such as 'smtp1.mtw.ru' (default: smtp4.mtw.rum with no-auth)
	username		=> smtp login
	password		=> smtp password
	encode_from	=> source encoding (default: utf-8)
	encode_to	=> destination encoding (default: utf-8)
	from			=> sender address (default: noreply@delivery.mtw.ru), can't be changed for sending via SMTP smtp1.mtw.ru, supported named notation: Petrovich S Konstantin <kp@mtw.ru>
	reply			=> Reply-To header, supported named notation: Network Operation Center <noc@mtw.ru>
	x-mailer		=> X-Mailer header (default: MTW Delivery System [http://mtw.ru] $VERSION)
	dkim			=> use DKIM signature (default: 1)
	dkim_key		=> path to private dkim key (default: /usr/local/apache/conf/dkim/mtwpriv.key)
	storemy		=> try to add message into client account at my.mtw.ru (id loaded via email address) < DOES NOT WORK NOW!!!!!!!!!!!!!

=head1 DESCRIPTION
MTW::Delivery - perl extension for email deliveries. Provides PHP-like mail () function. But extended with param $h.
Default syntax:

	mail (
		TO,
		SUBJECT,
		MESSAGE,
		{ EXT_KEYS }
	);

1. By default, header 'Subject' and message body encoded Base64. Quoted-printable does not support now.
2. Default locale for all outgoing messages is UTF-8, favorite for Google/Yandex/Mail.ru.
3. DKIM signature used by default for delivery.mtw.ru. When used auth-based SMTP, like smtp1.mtw.ru, we need to set header 'From' as noreply@delivery.mtw.ru. Or unset them.

=head1 AUTHOR
Petrovich S Konstantin, kp@mtw.ru

=head1 EXAMPLES
=head2 Create a simple message containing just text using default sending options

	use MTW::Delivery;
	mail ('to@a.com', 'Subject', 'Message');

=head2 Custom sending options

	use MTW::Delivery;
	mail (
		'to@a.com',
		'Subject',
		'Message',
		{
			from	=> 'MTW.RU Information Center <info@mtw.ru>',
			reply	=> 'MTW.RU Network Operation Center <noc@mtw.ru>',
			via	=> 'smtp1.mtw.ru',
			username	=> 'securelogin',
			password	=> 'securepassword',
			dkim	=> 0,
			'x-mailer'	=> 'Microsoft Outlook 14.0'
		}
	);

=head2 END
=cut

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(mail);
our $VERSION = '2.1';

use MIME::Lite;
use MIME::Base64 qw(encode_base64);
use Mail::DKIM::Signer;
use Mail::DKIM::TextWrap;
use Authen::SASL;
use Text::Iconv;
use Data::Dumper;

# for my.mtw.ru reporting
#use MTW::DbConn;

sub mail {
	my (
		$to,
		$subject,
		$message,
		$d
	) = @_;
	my $USE_ENCODE_LOCALE = 0;

	return 0 if !defined $to || !defined $subject || !defined $message;

	# header From
	$d->{from} = 'MTW.RU <noc@mtw.ru>' if !exists $d->{from};

	# header Reply-To
	$d->{reply} = $d->{from} if !exists $d->{reply};

	# header X-Mailer
	$d->{'x-mailer'} = "MTW.RU Delivery System [http://mtw.ru] $VERSION" if !exists $d->{'x-mailer'};

	# use encoding
	$d->{encode_from} = 'utf-8' if !exists $d->{encode_from};
	$d->{encode_to} = 'utf-8' if !exists $d->{encode_to};
	#$USE_ENCODE_LOCALE = (exists $d->{encode_from} && $d->{encode_from} ne $d->{encode_to}) ? 1 : 0;
	$USE_ENCODE_LOCALE = (exists $d->{encode_from}) ? 1 : 0;
	$d->{encode_to} =~ tr/a-z/A-Z/;

	# use DKIM
	$d->{dkim} = 1 if !exists $d->{dkim};

	# default via 
	$d->{via} = "smtp4.mtw.ru" if !exists $d->{via}; # HARDCODE: default SMTP

	# copy email message into my.mtw.ru
	$d->{storemy} = 0 if !exists $d->{storemy};

	if ($USE_ENCODE_LOCALE) {
		my $conv	= Text::Iconv->new ($d->{encode_from}, $d->{encode_to});
		$subject		= $conv->convert ($subject);
		$message		= $conv->convert ($message);
		$d->{from}	= $conv->convert ($d->{from});
		$d->{reply}	= $conv->convert ($d->{reply});
	}

	return sendmail ($to, $subject, $message, $d);
}

sub sendmail {
	my ($to, $subject, $message, $d) = @_;
	print Dumper (@_) if exists $d->{verbose};

	chomp ($subject = encode_base64 ($subject));
	$subject = "=?$d->{encode_to}?B?$subject?=";

	foreach ('from', 'reply') {
		my ($a, $b) = split /[\<\>]/, $d->{$_};
		if (defined $b) {
			chomp ($a = encode_base64 ($a));
			$d->{$_} = "=?$d->{encode_to}?B?$a?= <$b>";
		}
	}

	my @recipients = split /[\,+\;+\s+\|]/, $to;
	foreach $to (@recipients) {
		my $relay = MIME::Lite->new (
			From			=> $d->{from},
			To				=> $to,
			'Reply-To'	=> $d->{reply},
			Subject		=> $subject,
			Type			=> "text/plain; charset=". $d->{encode_to},
			Encoding		=> 'base64',
			Data			=> $message
 		);
		$relay->replace ('X-Mailer'	=> $d->{'x-mailer'});
		$relay = setDKIM ($relay, $d->{dkim_key}) if $d->{dkim} == 1;

		eval { viaSmtp ($relay, $d) } if $d->{via} ne 'sendmail';
		eval { viaSendmail ($relay, $d) } if $@ or $d->{via} eq 'sendmail';
	}

	return 0;
}

sub setDKIM {
	my ($relay, $dkim_key) = @_;
	my $dkim = Mail::DKIM::Signer->new (
		Algorithm	=> 'rsa-sha1',
		Method		=> 'relaxed',
		Domain		=> 'delivery.mtw.ru',
		Selector		=> 'dkim1',
		KeyFile		=> (defined $dkim_key) ? $dkim_key : '/usr/local/apache/conf/dkim/mtwpriv.key'
	);

	my $raw = $relay->as_string;
	$raw =~ s/\n/\015\012/gs;
	$dkim->PRINT ($raw);
	$dkim->CLOSE;

	my $sig = $dkim->signature;
	my ($dkim_header_name, $dkim_header_value) = split /:\s*/, $sig->as_string, 2;
	unshift @{$relay->{Header}}, [$dkim_header_name, $dkim_header_value];

	return $relay;
}

sub viaSmtp {
	my ($relay, $d) = @_;
	if (exists $d->{username} && exists $d->{password}) {
		print "Using SMTP (auth)\n" if $d->{verbose};
	} else {
		print "Using SMTP (no-auth)\n" if $d->{verbose};
	}

	$relay->send (
		'smtp',
		$d->{via},
		Timeout	=> 60,
		AuthUser	=> $d->{username},
		AuthPass	=> $d->{password},
		Debug		=> ($d->{verbose}) ? 1 : 0
	);
}

sub viaSendmail {
	my ($relay, $d) = @_;
	my $verbose = '-v' if defined $d->{verbose};
	$d->{from} =~ m/([a-z\_\-\.0-9]+\@[a-z0-9\-\.]{2,}\.[a-z]{2,})/i;
	my $from = $1;

	print "Using Sendmail\n" if $d->{verbose};
	$relay->send ('sendmail', "/usr/sbin/sendmail -t -oi $verbose -oem -f$from");
}

# Does not work now!
sub storeMy {
	my ($to, $subject, $message, $d) = @_;
	my $conv	= Text::Iconv->new ($d->{encode_from}, 'windows-1251');
	$subject = $conv->convert ($subject);
	$message = $conv->message ($message);

	my $sql = "
		INSERT INTO mailtoabon
			(login, mail, subj, message, f_mail, date, time)
		VALUES
			(?, ?, ?, ?, 1, CURDATE(), CURTIME())";
	
	return 1;
}

1;
