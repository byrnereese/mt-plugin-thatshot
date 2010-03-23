package ThatsHot::Topics;
 
use strict;
use base qw( MT::Object );
 
__PACKAGE__->install_properties({
    column_defs => {
        'id'           => 'integer not null auto_increment',
        'blog_id'      => 'integer not null',
        'title'        => 'string(999)',
        'data'         => 'string(999)',
        'search_blogs' => 'string(999)',
        'basename'     => 'string(255)'
    },
    audit => 1,
    indexes => {
        blog_id   => 1,
        title     => 1,
        data      => 1,
    },
    datasource  => 'th_topics',
    primary_key => 'id',
    class_type  => 'url',
});

sub class_label {
    MT->translate("Topic");
}

sub class_label_plural {
    MT->translate("Topics");
}
 
1;

__END__
