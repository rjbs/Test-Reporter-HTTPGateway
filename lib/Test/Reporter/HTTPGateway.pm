use strict;
use warnings;

package Test::Reporter::HTTPGateway;

use CGI ();
use Email::Send ();
use Email::Simple;
use Email::Simple::Creator;

my  $NAME    = __PACKAGE__;
our $VERSION = '0.001';

my $MAILER  = $ENV{TEST_REPORTER_HTTPGATEWAY_MAILER}  || 'SMTP';
my $ADDRESS = $ENV{TEST_REPORTER_HTTPGATEWAY_ADDRESS} || 'rjbs@cpan.org';
          #|| 'cpan-testers@perl.org';

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

  # http://rjbs.manxome.org/testy.cgi?from=rjbs@cpan.org&subject=testing-thing&via=manual&report=this%20is%20the%20report&key=1

  eval {
    # This was causing "cgi died ?" under lighttpd.  Eh. -- rjbs, 2008-04-05
    # die [ 405 => undef ] unless $q->request_method eq 'POST';

    for (qw(from subject via)) {
      die [ 500 => "missing $_ field" ]
        unless defined $post{$_} and length $post{$_};

      die [ 500 => "invalid $_ field" ] if $post{$_} =~ /[\r\n]/;
    }

    die [ 403 => "unknown user key" ] unless $self->key_allowed($post{key});

    my $email = Email::Simple->create(
      body   => $post{report},
      header => [
        To      => $ADDRESS,
        From    => $post{from},
        Subject => $post{subject},
        'X-Reported-Via' => "$NAME $VERSION relayed from $post{via}",
      ],
    );

    my $rv = Email::Send->new({ mailer => $MAILER })->send($email);
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

    print "Status: $status\n";
    print "Content-type: text/plain\n\n";
    print "Report not sent: $msg\n";
  } else {
    print "Content-type: text/plain\n\n";
    print "Report sent.\n";
  }
}

1;
