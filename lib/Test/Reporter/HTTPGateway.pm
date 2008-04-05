use strict;
use warnings;

package Test::Reporter::HTTPGateway;

use CGI ();
use Email::Send ();
use Email::Simple;
use Email::Simple::Creator;

our $VERSION = '0.001';

sub via {
  my ($self) = @_;
  return ref $self ? ref $self : $self;
}

sub default_mailer { 'SMTP' }
sub mailer { $ENV{TEST_REPORTER_HTTPGATEWAY_MAILER} || $_[0]->default_mailer }

sub default_destination {
  'rjbs@cpan.org';
  # 'cpan-testers@perl.org';
}

sub destination {
  $ENV{TEST_REPORTER_HTTPGATEWAY_ADDRESS} || $_[0]->default_destination;
}

sub key_allowed { 1 };

sub handle {
  my ($self, $q) = @_;
  $q ||= CGI->new;

  my %post = (
    from    => scalar $q->param('from'),
    subject => scalar $q->param('subject'),
    via     => scalar $q->param('via'),
    report  => scalar $q->param('report'),
    key     => scalar $q->param('key'),
  );

  eval {
    # This was causing "cgi died ?" under lighttpd.  Eh. -- rjbs, 2008-04-05
    # die [ 405 => undef ] unless $q->request_method eq 'POST';

    for (qw(from subject via)) {
      die [ 500 => "missing $_ field" ]
        unless defined $post{$_} and length $post{$_};

      die [ 500 => "invalid $_ field" ] if $post{$_} =~ /[\r\n]/;
    }

    die [ 403 => "unknown user key" ] unless $self->key_allowed($post{key});

    my $via = $self->via;

    my $email = Email::Simple->create(
      body   => $post{report},
      header => [
        To      => $self->destination,
        From    => $post{from},
        Subject => $post{subject},
        'X-Reported-Via' => "$via $VERSION relayed from $post{via}",
      ],
    );

    my $rv = Email::Send->new({ mailer => $self->mailer })->send($email);
    die "$rv" unless $rv; # I hate you, Return::Value -- rjbs, 2008-04-05
  };

  if (my $error = $@) {
    my ($status, $msg);

    if (ref $error eq 'ARRAY') {
      ($status, $msg) = @$error;
    } else {
      warn $error;
    }

    $status = 500 unless $status and $status =~ /\A\d{3}\z/;
    $msg  ||= 'internal error';

    $self->_respond($status, "Report not sent: $msg");
    return;
  } else {
    $self->_respond(200, 'Report sent.');
    return;
  }
}

sub _respond {
  my ($self, $code, $msg) = @_;

  print "Status: $code\n";
  print "Content-type: text/plain\n\n";
  print "$msg\n";
}

1;
