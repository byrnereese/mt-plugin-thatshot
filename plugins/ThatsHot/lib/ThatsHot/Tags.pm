package ThatsHot::Tags;

use strict;

use base qw( MT::App );

sub hot_topics_block {
    my ($ctx, $args, $cond) = @_;
    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');

    # Terms first:
    my $load_terms = {};
    # Only if ID is supplied does it get assigned. Otherwise, load tries (and
    # fails) to find a result.
    if ($args->{'id'}) {
        $load_terms->{topic_id} = $args->{'id'};
    }
    $load_terms->{blog_id} = $ctx->stash('blog_id');
    $load_terms->{class}  = $args->{'status'} || ['hot', 'cold'];
    
    # Then arguments:
    my $load_args = {};
    $load_args->{sort} = $args->{'sort_by'} || 'created_on';
    $load_args->{direction} = $args->{'sort_order'} || 'descend';
    # Allow limit or lastn in case the user can't remember
    $load_args->{limit}  = $args->{'limit'} || $args->{'lastn'};
    $load_args->{offset} = $args->{'offset'};

    use ThatsHot::Topics;
    use ThatsHot::HotTopics;

    # If an ID was specified, only one topic will be returned. That's ok.
    # The user probably wants to display a history of the topic. Later
    # on we will use these same arguments to sort the Hot Topics data.
    my @hot_topics = ThatsHot::HotTopics->load( $load_terms,
                                                $load_args );
    unless (@hot_topics) { return; } # No topics were found. Return quietly.

    my $res = '';
    my $i = 0;
    my $vars = $ctx->{__stash}{vars} ||= {};
    foreach my $hot_topic (@hot_topics) {
        local $vars->{__first__} = !$i;
        local $vars->{__last__} = !defined $hot_topics[$i+1];
        local $vars->{__odd__} = ($i % 2) == 0; # 0-based $i
        local $vars->{__even__} = ($i % 2) == 1;
        local $vars->{__counter__} = $i+1;

        # Craft the load terms for Topics. This is necessary so that we can
        # return only the class type (URL or keyword or tag).
        my $load_terms = {};
        $load_terms->{id}    = $hot_topic->topic_id;
        $load_terms->{class} = $args->{'class'} || ['url', 'keyword', 'tag'];
        my $topic = ThatsHot::Topics->load($load_terms);
        
        # Was a match found? Only fill out the block if we did.
        if ($topic) {
            $ctx->stash('TopicID',           $hot_topic->topic_id    );
            $ctx->stash('TopicTitle',        $topic->title           );
            $ctx->stash('TopicClass',        $topic->class           );
            $ctx->stash('TopicData',         $topic->data            );
            $ctx->stash('TopicIncludeBlogs', $topic->search_blogs    );
            $ctx->stash('TopicBasename',     $topic->basename        );
            $ctx->stash('TopicPermalink',    _create_topic_permalink($topic));
            $ctx->stash('TopicStatus',       $hot_topic->class       );
            $ctx->stash('TopicDate',         $hot_topic->created_on  );
            $ctx->stash('TopicAuthorID',     $hot_topic->created_by  );
            # Necessary for the date handler in MT::Template::Context to do it's thing.
            local $ctx->{current_timestamp} = $hot_topic->created_on;
        
            my $out = $builder->build($ctx, $tokens);
            if (!defined $out) {
                # A error--perhaps a tag used out of context. Report it.
                return $ctx->error( $builder->errstr );
            }
            $res .= $out;

            $i++;
        }
    }
    return $res;
}

sub topics_block {
    my ($ctx, $args, $cond) = @_;
    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');

    # Terms first:
    my $load_terms = {};
    $load_terms->{blog_id} = $ctx->stash('blog_id');
    $load_terms->{class} = $args->{'class'} || ['url', 'keyword', 'tag'];

    # Then arguments:
    my $load_args = {};
    $load_args->{sort} = $args->{'sort_by'} || 'created_on';
    $load_args->{direction} = $args->{'sort_order'} || 'descend';
    # Allow limit or lastn in case the user can't remember
    $load_args->{limit} = $args->{'limit'} || $args->{'lastn'};
    $load_args->{offset} = $args->{'offset'};

    use ThatsHot::Topics;

    # If an ID was specified, only one topic will be returned. That's ok.
    # The user probably wants to display a history of the topic. Later
    # on we will use these same arguments to sort the Hot Topics data.
    my @topics = ThatsHot::Topics->load( $load_terms,
                                         $load_args );
    unless (@topics) { return; } # No topics were found. Return quietly.

    my $res = '';
    my $i = 0;
    my $vars = $ctx->{__stash}{vars} ||= {};
    foreach my $topic (@topics) {
        local $vars->{__first__} = !$i;
        local $vars->{__last__} = !defined $topics[$i+1];
        local $vars->{__odd__} = ($i % 2) == 0; # 0-based $i
        local $vars->{__even__} = ($i % 2) == 1;
        local $vars->{__counter__} = $i+1;

        $ctx->stash('TopicID',           $topic->id              );
        $ctx->stash('TopicTitle',        $topic->title           );
        $ctx->stash('TopicClass',        $topic->class           );
        $ctx->stash('TopicData',         $topic->data            );
        $ctx->stash('TopicIncludeBlogs', $topic->search_blogs    );
        $ctx->stash('TopicBasename',     $topic->basename        );
        $ctx->stash('TopicPermalink',    _create_topic_permalink($topic));
        $ctx->stash('TopicStatus',   '' ); # Topics have no status, so just be empty.
        $ctx->stash('TopicDate',         $topic->created_on      );
        $ctx->stash('TopicAuthorID',     $topic->created_by      );
        # Necessary for the date handler in MT::Template::Context to do it's thing.
        local $ctx->{current_timestamp} = $topic->created_on;
        
        my $out = $builder->build($ctx, $tokens);
        if (!defined $out) {
            # A error--perhaps a tag used out of context. Report it.
            return $ctx->error( $builder->errstr );
        }
        $res .= $out;

        $i++;
    }
    return $res;
}

sub topic_id {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicID');
    if (!defined $a) {
        return $ctx->error('The TopicID tag must be used within the Topics or HotTopics block tags.');
    }
    return $a
}

sub topic_basename {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicBasename');
    if (!defined $a) {
        return $ctx->error('The TopicBasename tag must be used within the Topics or HotTopics block tags.');
    }
    if (my $sep = $args->{separator}) {
        if ($sep eq '-') {
            $a =~ s/_/-/g;
        } elsif ($sep eq '_') {
            $a =~ s/-/_/g;
        }
    }
    return $a
}

sub topic_title {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicTitle');
    if (!defined $a) {
        return $ctx->error('The TopicTitle tag must be used within the Topics or HotTopics block tags.');
    }
    return $a
}

sub topic_class {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicClass');
    if (!defined $a) {
        return $ctx->error('The TopicClass tag must be used within the Topics or HotTopics block tags.');
    }
    return $a
}

sub topic_data {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicData');
    if (!defined $a) {
        return $ctx->error('The TopicData tag must be used within the Topics or HotTopics block tags.');
    }
    return $a
}

sub topic_include_blogs {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicIncludeBlogs');
    if (!defined $a) {
        return $ctx->error('The TopicIncludeBlogs tag must be used within the Topics or HotTopics block tags.');
    }
    return $a
}

sub topic_status {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicStatus');
    if (!defined $a) {
        return $ctx->error('The TopicStatus tag must be used within the Topics or HotTopics block tags.');
    }
    return $a
}

sub topic_date {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicDate');
    if (!defined $a) {
        return $ctx->error('The TopicDate tag must be used within the Topics or HotTopics block tags.');
    }
    # The following lets the user specify the normal date format modifiers.
    use MT::Template::Context;
    return MT::Template::Context::_hdlr_date($ctx, $args);
}

sub topic_author_id {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicAuthorID');
    if (!defined $a) {
        return $ctx->error('The TopicAuthorID tag must be used within the Topics or HotTopics block tags.');
    }
    return $a
}

sub topic_permalink {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('TopicPermalink');
    if (!defined $a) {
        return $ctx->error('The TopicPermalink tag must be used within the Topics or HotTopics block tags.');
    }
    return $a;
}

sub _create_topic_permalink {
    my ($topic) = @_;
    my $permalink = MT->config('CGIPath') . 'plugins/ThatsHot/topic.cgi?id=' . $topic->id;
    return $permalink;
}

1;

__END__
