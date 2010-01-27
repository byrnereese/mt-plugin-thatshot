package ThatsHot::HotTopics;
 
use strict;
use base qw( MT::Object );
 
__PACKAGE__->install_properties({
    column_defs => {
        'id'       => 'integer not null auto_increment',
        'blog_id'  => 'integer not null',
        'topic_id' => 'integer not null',
    },
    audit => 1,
    indexes => {
        id       => 1,
        blog_id  => 1,
        topic_id => 1,
    },
    datasource  => 'th_hot_topics',
    primary_key => 'id',
    class_type  => 'hot',
});
 
1;

__END__
