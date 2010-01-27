package ThatsHot::Link;

use strict;
use warnings;
use MT::App;

@ThatsHot::Link::ISA = qw( MT::App );

use ThatsHot::CMS;

sub init {
    my $app = shift;
    $app->SUPER::init(@_) or return;
    $app->add_methods(
        'return_link'   => \&return_link,
    );
    $app->{default_mode} = 'return_link';
    $app;
}

sub return_link {
    my $app = shift;
    my $q = $app->{query};
    MT->log('here');

    use ThatsHot::Topics;
    my $topic;
    
    if ($q->param('id')) {
        # Lookup by ID, if specified
        $topic = ThatsHot::Topics->load( $q->param('id') );
    }
    else {
        # Or, lookup by basename. Note that the blog ID must also be supplied,
        # because basenames are unique per-blog.
        $topic = ThatsHot::Topics->load({ blog_id  => $q->param('blog_id'),
                                          basename => $q->param('basename'),
                                          class    => ThatsHot::CMS::topic_class_types() });
    }
    
    if ($topic) {
        my $url = ThatsHot::CMS::_create_view_link($topic);
        return $app->redirect( $url );
    }
    else {
        return 'No topic found or specified.';
    }
}

1;

__END__
