package ThatsHot::CMS;

use strict;
use warnings;

use MT::Util qw( relative_date offset_time offset_time_list epoch2ts ts2epoch format_ts );

# This is an array of the valid ThatsHot::HotTopics class types.
sub hot_class_types {
    return ['scheduled', 'hot', 'cold'];
}
# This is an array of the valid ThatsHot::Topics class types.
sub topic_class_types {
    return ['url', 'keyword', 'tag'];
}

sub settings {
    my ($plugin, $param, $scope) = @_;
    my $app = MT->instance;

    # Grab the ID of the template previously saved.
    my $saved_t = $plugin->get_config_value('th_republish_template', 'blog:'.$app->blog->id);

    # Create a list of index templates in this blog.
    use MT::Template;
    my @templates = MT::Template->load({ type    => 'index',
                                         blog_id => $app->blog->id, },
                                       { sort      => 'name',
                                         direction => 'ascend', },
                                       );
    my ($selected, @template_loop);
    foreach my $t (@templates) {
        $selected = $saved_t eq $t->id ? 1 : 0;
        push @template_loop, { id       => $t->id,
                               name     => $t->name,
                               selected => $selected,
                             };
    }
    $param->{index_templates} = \@template_loop;

    $param->{th_enable}     = $plugin->get_config_value('th_enable', 'blog:'.$app->blog->id);
    $param->{th_hot_length} = $plugin->get_config_value('th_hot_length', 'blog:'.$app->blog->id);
    $param->{th_hot_limit}  = $plugin->get_config_value('th_hot_limit', 'blog:'.$app->blog->id);

    my $blog_ids = $plugin->get_config_value('th_search_blog_ids', 'blog:'.$app->blog->id);
    $blog_ids = ($blog_ids eq '') ? $app->blog->id : $blog_ids;
    $param->{th_search_blog_ids} = $blog_ids;
    
    my $tmpl = $plugin->load_tmpl('settings.mtml', $param);
    return $app->build_page($tmpl);
}

sub init_app {
    # Use this to hide the menu items from any blog that does not have the plugin enabled.
    my ($cb, $app) = @_;
    return if $app->id eq 'wizard'; # MT is being installed.

    # Check to see that we're in the blog context (and not the system context).
    my $blog = $app->blog;
    if ($blog) {
        my $plugin = MT->component('thatshot');
        my $switch = $plugin->get_config_value('th_enable', 'blog:'.$blog->id);
        if (!$switch) { # the switch is disabled. Do not show the menu options.
            delete $plugin->{registry}->{applications}->{cms}->{menus}->{'create:hot_topic'};
            delete $plugin->{registry}->{applications}->{cms}->{menus}->{'manage:hot_topics'};
            return {};
        }
    }
}

sub add_hot_topic {
    my $app    = shift @_;
    my $plugin = MT->component('thatshot');
    # If add_hot_topic was called from somewhere else, it's probably supplying
    # a bunch of parameters to be used. Be sure to grab them!
    my $param  = pop @_ || {};

    return $plugin->translate("Permission denied.")
        unless $app->user->is_superuser() ||
               ($app->blog && $app->user->permissions($app->blog->id)->can_administer_blog());

    my $hot_limit = $plugin->get_config_value('th_hot_limit', 'blog:'.$app->blog->id);
    use ThatsHot::HotTopics;
    my $count = ThatsHot::HotTopics->count({ class => 'hot' });
    $param->{hot_limit} = $hot_limit;
    $param->{hot_count} = ($count >= $hot_limit) ? $count : 0;
    
    # The Class param needs a value. Make it default to 'url' *only* if it's
    # not already defined. (Which could happen if add_hot_topic is being used
    # to show search results or resolve a conflict.)
    if (!$param->{class}) { $param->{class} = 'url'; }

    $param->{date}  = _current_date_stamp(),
    $param->{time}  = _current_time_stamp();
    $param->{empty} = $app->param('empty');
    # Create the generic tag/keyword search URL
    $param->{view_search_url}   = _create_view_link();
    $param->{tag_suggestions}   = $plugin->get_config_value('th_tag_suggestions', 'blog:'.$app->blog->id);
    $param->{specified_blogs}   = $plugin->get_config_value('th_search_blog_ids', 'blog:'.$app->blog->id) || $app->blog->id;
    $param->{search_override}   = $plugin->get_config_value('th_search_blog_ids_override', 'blog:'.$app->blog->id);
    $param->{basename_override} = $plugin->get_config_value('th_basename_override', 'blog:'.$app->blog->id);

    # Build the list of blogs to display if the the search override is enabled.
    # The important piece here is that the default selected blogs are preselected.
    if ($param->{search_override}) {
        my ($selected, $blog_id, @blogs_loop);
        use MT::Blog;
        my $iter = MT::Blog->load_iter();
        while (my $blog = $iter->()) {
            $blog_id = $blog->id;
            $selected = grep(/$blog_id/, $param->{specified_blogs});
            push @blogs_loop, { id       => $blog_id,
                                name     => $blog->name,
                                selected => $selected,
                              };
        }
        $param->{blogs_loop} = \@blogs_loop;
    }
    
    my $tmpl = $plugin->load_tmpl('add.mtml', $param);
    return $app->build_page($tmpl);
}

sub save_hot_topic {
    my $app = shift;
    my $plugin = MT->component('thatshot');

    my $param = {};
    my $q = $app->{query};
    my $blog_id = $app->blog->id;
    my $submitted_data = $q->param('url') || $q->param('keyword') || $q->param('tag');
    my $submitted_title = $q->param('title');
    use ThatsHot::Topics;
    my @topics;
    
    # If the title *and* data fields are empty, the user just clicked save. Complain!
    if ( ($submitted_title eq '') && ($submitted_data eq '') ) {
        $app->param('empty', 1);
        return add_hot_topic($app);
    }
    
    # If the title or data fields are empty, the user is probably trying to search.
    if ( ($submitted_title eq '') && ($submitted_data ne '') ) {
        # No title, but a piece of data was specified. Search by data.
        @topics = ThatsHot::Topics->load( { blog_id => $blog_id,
                                            data    => { like => "%$submitted_data%" },
                                            class   => topic_class_types(), } );
        # Empty $submitted_title just so that the results screen works.
        $submitted_title = '';

        return _search_results($submitted_title, $submitted_data, @topics);
    }
    elsif ( ($submitted_title ne '') && ($submitted_data eq '') ) {
        # No data, but a title was specified. Search by title.
        @topics = ThatsHot::Topics->load( { blog_id => $blog_id,
                                            title   => { like => "%$submitted_title%" },
                                            class   => topic_class_types(), } );
        # Empty $submitted_data just so that the results screen works.
        $submitted_data = '';

        return _search_results($submitted_title, $submitted_data, @topics);
    }

    # See if this topic already exists, and just needs to be reheated.
    # Search for the supplied data, then search for the supplied title.
    # This will let us ensure that there are no duplicate or mistyped topics.
    my $topic_test_1 = ThatsHot::Topics->load( { blog_id => $blog_id,
                                                 data    => $submitted_data,
                                                 class   => topic_class_types(), } );
    my $topic_test_2 = ThatsHot::Topics->load( { blog_id => $blog_id,
                                                 title   => $submitted_title,
                                                 class   => topic_class_types(), } );

    if ( ($topic_test_1) && ($topic_test_1->title eq $submitted_title) ) {
        # This topic exists, so we just need to heat it up!
        my $result = _heat_this_up($topic_test_1->id);
        my $tmpl = $plugin->load_tmpl('finish.mtml');
        return $app->build_page($tmpl);
    }
    elsif (
        ( ($topic_test_1) && ( $topic_test_1->title ne $submitted_title ) )
        || ( ($topic_test_2) && ( $topic_test_2->data ne $submitted_data ) )
    ) {
        # There is a conflict here--either the topic title or URL have already been used
        my $topic = $topic_test_1 ? $topic_test_1 : $topic_test_2;
        my $param = {
            title           => $topic->title,
            class           => $topic->class,
            data            => $topic->data,
            topic_conflict  => 1,
        };
        # Jump back to add_hot_topic to create the "add" screen with these
        # values in it, and to tell the user there is a conflict.
        return add_hot_topic($app, $param);
    }
    else {
        # There is no conflict--this is a new topic. Save!
        # But first get the valid blog IDs together for a tag or keyword search.
        my $search_blogs;
        if ($q->param('class') ne 'url') {
            if ($q->param('select_blogs')) {
                $search_blogs = join(',', $q->param('select_blogs'));
            }
            else {
                # Either the valid search blogs have not been changed from the
                # default, or they are not allowed to be overridden.
                $search_blogs = $plugin->get_config_value('th_search_blog_ids', 'blog:'.$app->blog->id);
            }
        }
        
        # We need a basename. Grab the basename field, or generate one from the title.
        my $basename = ( $q->param('basename') ) ? $q->param('basename') : MT::Util::dirify($submitted_title);
        # _make_unique_basename will guarantee this basename doesn't conflict with another.
        $basename = _make_unique_basename($basename);

        my $topic = ThatsHot::Topics->new();
        $topic->title(        $submitted_title   );
        $topic->class(        $q->param('class') );
        $topic->data(         $submitted_data    );
        $topic->created_by(   $app->{author}->id );
        $topic->blog_id(      $blog_id           );
        $topic->search_blogs( $search_blogs      );
        $topic->basename(     $basename          );
        $topic->save
            or return $app->error( $topic->errstr );

        # This topic matches a topic already saved. Just reheat it!
        my $result = _heat_this_up($topic->id);
        my $tmpl = $plugin->load_tmpl('finish.mtml');
        return $app->build_page($tmpl);
    }
}

sub save_hot_topic_from_search {
    # The user has selected a topic from the Search Results page. We can just
    # grab that topic and heat it up.
    my $app = shift;
    my $plugin = MT->component('thatshot');
    
    my $result = _heat_this_up( $app->param('id') );

    my $tmpl = $plugin->load_tmpl('finish.mtml');
    return $app->build_page($tmpl);
}

sub _search_results {
    my ($submitted_title, $submitted_data, @topics) = @_;
    my $app = MT->instance;
    my $plugin = MT->component('thatshot');
    my $param = {};
    my (@results, $class, $view);
    
    if (@topics) {
        if (scalar(@topics) > 1) {
            foreach my $topic (@topics) {
                # Fix the case for proper grammar.
                $class = ($topic->class eq 'url')     ? 'URL'     : 
                         ($topic->class eq 'keyword') ? 'Keyword' : 'Tag';
                $view = _create_view_link($topic);
                push @results, { id    => $topic->id,
                                 title => $topic->title,
                                 class => $class,
                                 data  => $topic->data,
                                 view  => $view,
                               };
            }
        }
        else {
            # There is only one topic found from this search. No point making
            # the user go through the search results page--just show them the topic.
            my $topic = shift @topics;
            $param = {
                title           => $topic->title,
                class           => $topic->class,
                data            => $topic->data,
                topic_conflict  => 1,
            };
            return add_hot_topic($app, $param);
        }
    }
    else {
        # Being here means the topic searched failed--there were no search results.
        $class = ($app->param('class') eq 'url')     ? 'URL'     : 
                 ($app->param('class') eq 'keyword') ? 'Keyword' : 'Tag';
        $param = { 
            title               => $submitted_title,
            class               => $app->param('class'),
            data                => $submitted_data,
            topic_search_failed => '1',
        };
        return add_hot_topic($app, $param);
    }
    
    $param->{results} = \@results;
    $param->{date}    = _current_date_stamp(),
    $param->{time}    = _current_time_stamp(),

    my $tmpl = $plugin->load_tmpl('search_results.mtml', $param);
    return $app->build_page($tmpl);
}

sub _current_date_stamp {
    # Build a valid and correct date-time stamp to be used for the Hot or
    # Scheduled time on the Add... screen.
    my $app = MT->instance;
    use MT::Blog;
    my $blog = MT::Blog->load($app->blog->id);

    my ($sec, $min, $hours, $day, $month, $year) = (localtime)[0,1,2,3,4,5];
    use Time::Local;
    my $cur_epoch = timelocal($sec,$min,$hours,$day,$month,$year);
    my $datetime = MT::Util::epoch2ts($blog, $cur_epoch);

    return format_ts( "%Y-%m-%d", $datetime, $blog, 
                        $app->user ? $app->user->preferred_language : undef );
}

sub _current_time_stamp {
    # Build a valid and correct time stamp to be used for the Hot or
    # Scheduled time on the Add... screen.
    my $app = MT->instance;
    use MT::Blog;
    my $blog = MT::Blog->load($app->blog->id);

    my ($sec, $min, $hours, $day, $month, $year) = (localtime)[0,1,2,3,4,5];
    use Time::Local;
    my $cur_epoch = timelocal($sec,$min,$hours,$day,$month,$year);
    my $datetime = MT::Util::epoch2ts($blog, $cur_epoch);

    return format_ts( "%H:%M:%S", $datetime, $blog, 
                        $app->user ? $app->user->preferred_language : undef );
}

sub _heat_this_up {
    # Mark this topic as Hot, or schedule it to be Hot.
    my ($topic_id) = @_;
    my $app = MT->instance;
    my $q = $app->{query};

    my $status;
    if ($q->param('status') eq '1') {
        $status = 'hot';
    }
    else {
        $status = 'scheduled';
    }

    # Grab the date & time fields, and verify that they're formatted correctly.
    my $date_format_error;
    my $datetime =  $q->param('date') . ' ' . $q->param('time');
    unless ( $datetime =~ m!^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})(?::(\d{2}))?$! ) {
        $date_format_error = $datetime;
    }

    # Check if the topic is already hot.
    my $hot_topic = ThatsHot::HotTopics->load({ topic_id => $topic_id });
    
    # If the date was formatted incorrectly, stop and complain.
    # For this to be true the hot topic the user is trying to create must be:
    # - marked hot
    # - the topic must have been made hot at least once
    # - the topic must be currently hot
    # - the override must be true. (If true that means we've already asked if
    #   this should be reheated.)
    if ( $date_format_error ||
        (
            ($status eq 'hot') && ($hot_topic) && ($hot_topic->class eq 'hot') && (!$q->param('override')) 
        )
    )
    {
        # Date is formatted incorrectly, or this is currently hot and we
        # need to ask the user how to proceed.
        my $currently_hot = ($hot_topic && ($hot_topic->class eq 'hot')) ? 1 : 0;
        use ThatsHot::Topics;
        my $topic = ThatsHot::Topics->load($topic_id);
        my $param = {
            title           => $topic->title,
            class           => $topic->class,
            data            => $topic->data,
            date_format     => $date_format_error,
            currently_hot   => $currently_hot,
        };
        return add_hot_topic($app, $param);

        # We need to get out of whatever is going on to report this.
#        print "Content-type: text/html\n\n";
#        print $app->build_page($tmpl);
#        exit;
    }
    else {
        # This topic isn't currently hot, so let's reheat it!
        use ThatsHot::HotTopics;
        my $hot_topic = ThatsHot::HotTopics->new();
        $hot_topic->topic_id(   $topic_id          );
        $hot_topic->class(      $status            );
        $hot_topic->created_by( $app->{author}->id );
        # If the topic is scheduled, save it at the correct date/time.
        $hot_topic->created_on( $datetime          );
        $hot_topic->blog_id(    $app->blog->id     );
        $hot_topic->save
            or return $app->error( $hot_topic->errstr );

        # Now, republish a template
        update_topics();
    }
}

sub _is_hot_now {
    # This is a simple function to check if the selected hot topic is currently hot.
    my ($topic_id) = @_;
    use ThatsHot::HotTopics;
    my $hot_topic = ThatsHot::HotTopics->load({ topic_id => $topic_id});
    if ($hot_topic->class eq 'hot') {
        return 1;
    }
    else {
        return 0;
    }
}


sub hot_topic_listing {
    my $app = shift;
    my %param = @_;
    my $plugin = MT->component('thatshot');

    return $plugin->translate("Permission denied.")
        unless $app->user->is_superuser() ||
            ($app->blog && $app->user->permissions($app->blog->id)->can_administer_blog());

    my $code = sub {
        my ($obj, $row) = @_;
        $row->{'id'} = $obj->id;
        $row->{'topic_id'} = $obj->topic_id;
        $row->{'status'} = $obj->class;

        my $author = MT::Author->load({ id => $obj->created_by });
        $row->{author}  = $author->name;

        use MT::Blog;
        my $blog = MT::Blog->load($obj->blog_id);
        my $ts = $obj->created_on;
        $row->{created_on_formatted} =
            format_ts( MT::App::CMS::LISTING_DATE_FORMAT(), $ts, $blog, 
                        $app->user ? $app->user->preferred_language : undef );
        $row->{created_on_time_formatted} =
            format_ts( MT::App::CMS::LISTING_DATETIME_FORMAT(), $ts, $blog, 
                        $app->user ? $app->user->preferred_language : undef );
        $row->{created_on_relative} =
            relative_date( $ts, time, $blog );

        use ThatsHot::Topics;
        my $topic = ThatsHot::Topics->load($obj->topic_id);
        if ($topic) {
            $row->{'title'} = $topic->title;
            $row->{'view'}  = _create_view_link($topic);
        }
    };

    my %terms = (
        blog_id => $app->blog->id,
        class   => hot_class_types(),
    );

    my %args = (
        sort      => 'created_on',
        direction => 'descend',
    );

    my %params = ();
    %params = map { $_ => $app->param($_) ? 1 : 0 }
        qw( hot cold hot_topic_deleted );

    $app->listing({
        type     => 'hot_topics', # the ID of the object in the registry
        terms    => \%terms,
        args     => \%args,
        listing_screen => 1,
        code     => $code,
        template => $plugin->load_tmpl('hot_listing.mtml'),
        params   => \%params,
    });
}

sub filter_scheduled {
    my ( $terms, $args ) = @_;
    $terms->{class} = 'scheduled';
}

sub filter_hot {
    my ( $terms, $args ) = @_;
    $terms->{class} = 'hot';
}

sub filter_cold {
    my ( $terms, $args ) = @_;
    $terms->{class} = 'cold';
}

sub filter_hot_today {
    my ( $terms, $args ) = @_;
    # Get the current day and assemble it.
    my ($y, $m, $d) = (localtime(time))[5,4,3];
    $y += 1900;
    $m += 1;
    $d = (length($d) == 1) ? '0'.$d : $d;
    my $today = $y . $m . $d;
    # Now use that to grab all results on this day. Range is today and newer.
    $terms->{created_on} = [$today, undef];
    $args->{range} = { created_on => 1 };
}

sub filter_hot_yesterday {
    my ( $terms, $args ) = @_;
    my $app = MT->instance;
    # Get the current day and assemble it.
    my ($y, $m, $d) = (localtime(time))[5,4,3];
    $y += 1900;
    $m += 1;
    $d = (length($d) == 1) ? '0'.$d : $d;
    my $today = $y . $m . $d;

    # Calculate yesterday's date
    use MT::Blog;
    my $blog = MT::Blog->load($app->blog->id);
    my $yesterday = MT::Util::ts2epoch($blog, $y . $m . $d);
    $yesterday -= 86400; # Subtract 86,400 seconds, or 1 day.
    $yesterday = MT::Util::epoch2ts($blog, $yesterday);

    # Now use that to grab all results on this day. Range is between
    # yesterday and today.
    $terms->{created_on} = [$yesterday, $today];
    $args->{range} = { created_on => 1 };
}

sub filter_hot_7_days {
    my ( $terms, $args ) = @_;
    my $app = MT->instance;
    # Get the current day and assemble it.
    my ($y, $m, $d) = (localtime(time))[5,4,3];
    $y += 1900;
    $m += 1;
    $d = (length($d) == 1) ? '0'.$d : $d;

    # Calculate the starting date
    use MT::Blog;
    my $blog = MT::Blog->load($app->blog->id);
    my $previous = MT::Util::ts2epoch($blog, $y . $m . $d);
    $previous -= (86400 * 7); # Subtract 86,400 seconds, or 1 day.
    $previous = MT::Util::epoch2ts($blog, $previous);

    # Now use that to grab all results on this day. Range is between
    # yesterday and today.
    $terms->{created_on} = [$previous, undef];
    $args->{range} = { created_on => 1 };
}

sub filter_hot_this_month {
    my ( $terms, $args ) = @_;
    my $app = MT->instance;
    # Get the current day and assemble it.
    my ($y, $m, $d) = (localtime(time))[5,4,3];
    $y += 1900;
    $m += 1;

    # Calculate the starting date
    my $previous = $y . $m;

    # Now use that to grab all results on this day. Range is between
    # yesterday and today.
    $terms->{created_on} = [$previous, undef];
    $args->{range} = { created_on => 1 };
}

sub filter_hot_last_month {
    my ( $terms, $args ) = @_;
    my $app = MT->instance;
    # Get the current day and assemble it.
    my ($y, $m, $d) = (localtime(time))[5,4,3];
    $y += 1900;
    $m += 1;
    $d = (length($d) == 1) ? '0'.$d : $d;
    my $end = $y . $m;

    # Calculate the starting date
    my $start = $y . ($m - 1);

    # Now use that to grab all results on this day. Range is between
    # yesterday and today.
    $terms->{created_on} = [$start, $end];
    $args->{range} = { created_on => 1 };
}

sub make_hot_now {
    # From the listing or edit screen, make the selected topic(s) Hot now.
    my $app = MT->instance;
    my @hot_topic_ids = $app->param('id');

    use ThatsHot::HotTopics;
    foreach my $hot_topic_id (@hot_topic_ids) {
        # First look up the supplied hot topic ID, so we can get the topic ID.
        my $orig_ht = ThatsHot::HotTopics->load($hot_topic_id);
        if ($orig_ht && ($orig_ht->class eq 'scheduled')) {
            # This is a scheduled topic. Just change the status to hot and be done.
            $orig_ht->class('hot');
            $orig_ht->save;
        }
        else {
            # If a result was found, grab the topic ID. If no result was found,
            # that meas we're on the Edit Topic screen, so just grab the topic ID.
            my $topic_id = $app->param('edit_topic') ? $hot_topic_id : $orig_ht->topic_id;

            my $hot_topic = ThatsHot::HotTopics->new();
            $hot_topic->topic_id(   $topic_id          );
            $hot_topic->class(      'hot'              );
            $hot_topic->created_by( $app->{author}->id );
            $hot_topic->blog_id(    $app->blog->id     );
            $hot_topic->save;
        }
    }

    # Lastly, need to republish the template!
    update_topics();
    #_republish_template($app->blog->id);

    # If we came from the Edit Topic screen, the return URL needs to be crafted.
    my $return_args;
    if ( $app->param('edit_topic') ) {
        $return_args = "__mode=edit_topic&topic_id=".$app->param('id')."&blog_id=".$app->blog->id;
    }
    $app->return_args($return_args);
    $app->add_return_arg( hot => 1 );
    $app->call_return;
}

sub make_cold_now {
    # From the listing or edit screen, make the selected topic(s) Cold now.
    my $app = MT->instance;
    my @hot_topic_ids = $app->param('id');

    use ThatsHot::HotTopics;
    if ( $app->param('edit_topic') ) {
        # We're on the Edit Topic screen. Use the topic ID to make all Hot Topics cold.
        # Redefine @hot_topic_ids and move along.
        my @hot_topics = ThatsHot::HotTopics->load({ topic_id => $hot_topic_ids[-1], });
        # Empty the array, removing the topic ID.
        undef(@hot_topic_ids);
        # Now rebuild the array with the hot topic IDs.
        foreach my $hot_topic (@hot_topics) {
            push @hot_topic_ids, $hot_topic->id;
        }
    }

    foreach my $hot_topic_id (@hot_topic_ids) {
        my $hot_topic = ThatsHot::HotTopics->load($hot_topic_id);
        $hot_topic->class('cold');
        $hot_topic->save;
    }

    # Lastly, need to republish the template!
    update_topics();

    my $return_args;
    if ( $app->param('edit_topic') ) {
        $return_args = "__mode=edit_topic&topic_id=".$app->param('id')."&blog_id=".$app->blog->id;
    }
    $app->return_args($return_args);
    $app->add_return_arg( cold => 1 );
    $app->call_return;
}

sub delete_hot_topic {
    my ($app) = @_;
    $app->validate_magic or return;

    my @hot_topic_ids = $app->param('id');
    use ThatsHot::HotTopics;
    foreach my $hot_topic_id (@hot_topic_ids) {
        my $hot_topic = ThatsHot::HotTopics->load($hot_topic_id);
        $hot_topic->remove;
    }
    
    # Lastly, need to republish the template!
    update_topics();

    $app->add_return_arg( hot_topic_deleted => 1 );
    $app->call_return;
}

sub edit_topic {
    my $app = shift;
    my $q = $app->{query};
    my $plugin = MT->component('thatshot');

    return $plugin->translate("Permission denied.")
        unless $app->user->is_superuser() ||
            ($app->blog && $app->user->permissions($app->blog->id)->can_administer_blog());

    use ThatsHot::Topics;
    use MT::Blog;
    use MT::Author;

    my $topic  = ThatsHot::Topics->load( $q->param('topic_id') );
    my $blog   = MT::Blog->load( $topic->blog_id );

    my $created_author  = MT::Author->load( $topic->created_by );
    my $created_ts      = $topic->created_on;
    my $created_date    = format_ts( '%b %e, %Y %l:%M:%S %p', $created_ts, 
                          $blog, $app->user ? $app->user->preferred_language : undef );
    
    my $param = {
        id               => $topic->id,
        title            => $topic->title,
        class            => $topic->class,
        data             => $topic->data,
        basename         => $topic->basename,
        topic_created_by => $created_author->name,
        topic_created_on => $created_date,
        view_search_url  => _create_view_link(),
    };
    $param->{tag_suggestions} = $plugin->get_config_value('th_tag_suggestions', 'blog:'.$app->blog->id);
    $param->{specified_blogs} = $topic->search_blogs || $plugin->get_config_value('th_search_blog_ids', 'blog:'.$app->blog->id) || $app->blog->id;
    $param->{search_override} = $plugin->get_config_value('th_search_blog_ids_override', 'blog:'.$app->blog->id);
    # The basename field should always be shown on the Edit screen.
    $param->{basename_override} = 1;

    # Build the list of blogs to display if the the search override is enabled.
    # The important piece here is that the default selected blogs are preselected.
    if ($param->{search_override}) {
        my ($selected, $blog_id, @blogs_loop);
        use MT::Blog;
        my $iter = MT::Blog->load_iter();
        while (my $blog = $iter->()) {
            $blog_id = $blog->id;
            $selected = grep(/$blog_id/, $param->{specified_blogs});
            push @blogs_loop, { id       => $blog_id,
                                name     => $blog->name,
                                selected => $selected,
                              };
        }
        $param->{blogs_loop} = \@blogs_loop;
    }
    
    
    if ($topic->modified_by) {
        my $modified_author = MT::Author->load( $topic->modified_by );
        my $modified_ts     = $topic->modified_on;
        my $modified_date   = format_ts( '%b %e, %Y %l:%M:%S %p', $modified_ts, 
                              $blog, $app->user ? $app->user->preferred_language : undef );
        $param->{topic_modified_by} = $modified_author->name;
        $param->{topic_modified_on} = $modified_date;
    }

    $param->{view} = _create_view_link($topic);
    
    # Build the history of this topic, showing its current and previous status
    use ThatsHot::HotTopics;
    my @hot = ThatsHot::HotTopics->load({ topic_id => $topic->id,
                                          class    => hot_class_types(), },
                                        { sort      => 'created_on',
                                          direction => 'descend', }
                                       );
    my (@history);
    foreach my $hot (@hot) {
        my $blog = MT::Blog->load($hot->blog_id);
        my $author = MT::Author->load( $hot->created_by );
        my $ts = $hot->created_on;
        my $date = format_ts( MT::App::CMS::LISTING_DATE_FORMAT(), $ts, $blog, $app->user ? $app->user->preferred_language : undef );
        my $time = format_ts( '%I:%M:%S %p', $ts, $blog, $app->user ? $app->user->preferred_language : undef );
        
        # Build a row of Hot data
        push @history, { id => $hot->id,
                         status => $hot->class,
                         author => $author->name,
                         date   => $date,
                         time   => $time, };
    }
    $param->{history} = \@history;

    # Messaging variables.
    $param->{saved}        = $q->param('saved');
    $param->{incomplete}   = $q->param('incomplete');
    $param->{exists_id}    = $q->param('exists_id');
    $param->{exists_title} = $q->param('exists_title');
    $param->{hot}          = $q->param('hot');
    $param->{cold}         = $q->param('cold');
    
    my $tmpl = $plugin->load_tmpl('edit.mtml', $param);
    return $app->build_page($tmpl);
}

sub save_topic {
    my $app = shift;
    my $plugin = MT->component('thatshot');

    my $q = $app->{query};
    my $blog_id = $app->blog->id;
    my $submitted_data = $q->param('url') || $q->param('keyword') || $q->param('tag');
    my $submitted_title = $q->param('title');
    
    # If the title or data field is empty, complain! At this point the
    # topic has been Hot at least once, so *needs* to be functional.
    if (!$submitted_title || !$submitted_data) {
        my $param = {
            id         => $q->param('id'),
            title      => $submitted_title,
            class       => $q->param('class'),
            data       => $submitted_data,
            incomplete => 1,
        };
        return $app->redirect( MT->config('CGIPath') . MT->config('AdminScript') . '?__mode=edit_topic'
                    . '&blog_id='.$blog_id.'&topic_id='.$q->param('id') . '&incomplete=1' );
    }

    use ThatsHot::Topics;
    my $topic = ThatsHot::Topics->load( $q->param('id') );

    # If the topic is being changed (new title, URL, keyword), check that the
    # new info is still unique.
    my $topic_test_1 = ThatsHot::Topics->load( { blog_id => $blog_id,
                                                 data    => $submitted_data, } );
    my $topic_test_2 = ThatsHot::Topics->load( { blog_id => $blog_id,
                                                 title   => $submitted_title, } );
    # Compare the topic being edited with the two topic tests just done.
    if (
        ( ($topic_test_1) && ( $topic_test_1->id ne $topic->id ) )
        || ( ($topic_test_2) && ( $topic_test_2->id ne $topic->id ) )
    ) {
        # There is a conflict here--either the topic title or data field
        # have already been used.
        my $topic = $topic_test_1 ? $topic_test_1 : $topic_test_2;

        return $app->redirect( MT->config('CGIPath') . MT->config('AdminScript') . '?__mode=edit_topic'
                    . '&blog_id=' . $blog_id . '&topic_id=' . $q->param('id') . '&exists_title=' 
                    . MT::Util::encode_url($topic->title) . '&exists_id=' . $topic->id );
    }
    else {
        # There is no conflict--this topic is just being updated.
        # But first get the valid blog IDs together for a tag or keyword search.
        my $search_blogs;
        if ($q->param('class') ne 'url') {
            if ($q->param('select_blogs')) {
                $search_blogs = join(',', $q->param('select_blogs'));
            }
            else {
                # Either the valid search blogs have not been changed from the
                # default, or they are not allowed to be overridden.
                $search_blogs = $plugin->get_config_value('th_search_blog_ids', 'blog:'.$app->blog->id);
            }
        }
        # We need a basename. Grab the basename field.
        my $basename = $q->param('basename');
        # Or generate one from the title.
        if (!$basename) {
            $basename = MT::Util::dirify($submitted_title);
            # _make_unique_basename will guarantee this basename doesn't conflict with another.
            $basename = _make_unique_basename($basename);
        }
        
        $topic->title(        $submitted_title   );
        $topic->class(        $q->param('class') );
        $topic->data(         $submitted_data    );
        $topic->search_blogs( $search_blogs      );
        $topic->basename(     $basename          );
        $topic->modified_by(  $app->{author}->id );
        $topic->save
            or return $app->error( $topic->errstr );
        
        # Republish the specified template. If the user has renamed the title
        # or changed a link, we want to be sure the latest is published.
        _republish_template($blog_id);

        return $app->redirect( MT->config('CGIPath') . MT->config('AdminScript') . '?__mode=edit_topic'
                    . '&blog_id=' . $blog_id . '&topic_id=' . $topic->id . '&saved=1');
    }
}

sub topic_listing {
    my $app = shift;
    my %param = @_;
    my $plugin = MT->component('thatshot');

    return $plugin->translate("Permission denied.")
        unless $app->user->is_superuser() ||
            ($app->blog && $app->user->permissions($app->blog->id)->can_administer_blog());

    my $code = sub {
        my ($obj, $row) = @_;
        $row->{'id'} = $obj->id;

        my $author = MT::Author->load({ id => $obj->created_by });
        $row->{author} = $author->name;
        
        use MT::Blog;
        my $blog = MT::Blog->load($obj->blog_id);
        my $ts = $obj->created_on;
        $row->{created_on_formatted} =
            format_ts( MT::App::CMS::LISTING_DATE_FORMAT(), $ts, $blog, 
                        $app->user ? $app->user->preferred_language : undef );
        $row->{created_on_time_formatted} =
            format_ts( MT::App::CMS::LISTING_DATETIME_FORMAT(), $ts, $blog, 
                        $app->user ? $app->user->preferred_language : undef );
        $row->{created_on_relative} =
            relative_date( $ts, time, $blog );
        
        $row->{'title'} = $obj->title;
        $row->{'view'}  = _create_view_link($obj);
        
        use ThatsHot::HotTopics;
        $row->{reheated_count} = ThatsHot::HotTopics->count({ topic_id => $obj->id,
                                                              class    => hot_class_types(), });
        my $recent_hot = ThatsHot::HotTopics->load( { topic_id => $obj->id,
                                                      class    => hot_class_types(), }, 
                                                    { sort      => 'created_on',
                                                      direction => 'descend',
                                                      limit     => 1, } );
        if ($recent_hot) {
            $ts = $recent_hot->created_on;
            $row->{reheated_formatted} =
                format_ts( MT::App::CMS::LISTING_DATE_FORMAT(), $ts, $blog, 
                            $app->user ? $app->user->preferred_language : undef );
            $row->{reheated_time_formatted} =
                format_ts( MT::App::CMS::LISTING_DATETIME_FORMAT(), $ts, $blog, 
                            $app->user ? $app->user->preferred_language : undef );
            $row->{reheated_relative} =
                relative_date( $ts, time, $blog );
        }
    };

    my %terms = (
        blog_id => $app->blog->id,
        class   => topic_class_types(),
    );

    my %args = (
        sort      => 'created_on',
        direction => 'descend',
    );

    my %params = ();
    %params = map { $_ => $app->param($_) ? 1 : 0 }
        qw( hot cold hot_topic_deleted );

    $app->listing({
        type     => 'topics', # the ID of the object in the registry
        terms    => \%terms,
        args     => \%args,
        listing_screen => 1,
        code     => $code,
        template => $plugin->load_tmpl('topic_listing.mtml'),
        params   => \%params,
    });
}

sub _create_view_link {
    my ($topic) = @_;

    my $app    = MT->instance;
    my $plugin = MT->component('thatshot');
    
    my $blog_id = ( defined($app->blog) ) ? $app->blog->id : $topic->blog_id;

    # If an alternate search template was specified, use it.
    my $search_alt_tmpl = $plugin->get_config_value('th_search_alt_tmpl', 'blog:'.$blog_id);
    if ($search_alt_tmpl) {
        $search_alt_tmpl = "&Template=$search_alt_tmpl";
    }
    # If IncludeBlogs blog IDs were set, use them. First try to get
    # topic-specific blog IDs, then go for the blog defaults.
    my $include_blogs = ($topic && $topic->search_blogs) ? $topic->search_blogs :
                        $plugin->get_config_value('th_search_blog_ids', 'blog:'.$blog_id);
    if ($include_blogs) {
        $include_blogs = "&IncludeBlogs=$include_blogs";
    }
    
    my $result;
    if ($topic && $topic->class eq 'url') {
        $result = $topic->data;
    }
    elsif ($topic && $topic->class eq 'keyword') {
        # If this is a keyword search, craft a search URL.
        $result = MT->config('CGIPath') . MT->config('SearchScript')
                     . '?blog_id=' . $blog_id . '&limit=20' . $search_alt_tmpl . $include_blogs
                     . '&search=' . MT::Util::encode_url($topic->data);
    }
    elsif ($topic && $topic->class eq 'tag') {
        # This is a tag search, so we need a tag search URL.
        $result = MT->config('CGIPath') . MT->config('SearchScript')
                     . '?blog_id=' . $blog_id . '&limit=20' . $search_alt_tmpl . $include_blogs
                     . '&tag=' . MT::Util::encode_url($topic->data);
    }
    else { # No topic was supplied, so we just need to craft a generic
           # tag/keyword search URL to be used on the "add" screen.
           # IncludeBlogs are specified on the "add" screen because the
           # search_blog_ids_override gives the user the ability to change them.
       $result = MT->config('CGIPath') . MT->config('SearchScript')
                    . '?blog_id=' . $blog_id . '&limit=20' . $search_alt_tmpl;
    }
    
    return $result;
}

sub _make_unique_basename {
    my ($basename) = @_;
    $basename = 'topic' if $basename eq '';
    
    my $app = MT->instance;
    my $i = 1;
    use ThatsHot::Topics;
    while (
        ThatsHot::Topics->exist({ blog_id  => $app->blog->id,
                                  basename => $basename, })
    ) {
        $basename = $basename . '_' .$i++;
    }
    return $basename;
}



sub update_topics {
    # This is run by MT's tasks framework:
    # - make scheduled topics Hot.
    # - make expired Hot topics Cold.
    # - make scheduled topics Hot.
    # - republish the selected template.
    # Run this as a background task. That'll let large templates or big "hot"
    # lists do their work without making the user wait.
    MT::Util::start_background_task(
        sub {
            my $app = MT->instance;
            my $plugin = MT->component('thatshot');

            use MT::Blog;
            use ThatsHot::HotTopics;

            # Load all of the Hot topics. Decide if any should be made Cold.
            my @hot = ThatsHot::HotTopics->load({ class => 'hot', });
            my ($expire_time, $cur_time, $blog, $topic_time);
            foreach my $topic (@hot) {
                $blog = MT::Blog->load($topic->blog_id);
                $topic_time = MT::Util::ts2epoch($blog, $topic->created_on);

                $expire_time = $plugin->get_config_value('th_hot_length', 'blog:'.$topic->blog_id);
                $expire_time = $expire_time * 3600; # 3600 seconds/hour
                $cur_time = time();
                $expire_time = $cur_time - $expire_time;

                # Compare times: if older than the specified hot_length, make the topic Cold.
                if ( $expire_time > $topic_time) {
                    $topic->class('cold');
                    $topic->save;
                }
                # Republish the template if this is the last item in the array.
                _republish_template($topic->blog_id)
                    if ($topic == $hot[-1]);
            }

            # Load all of the Scheduled topics. Decide if any should be made Hot.
            my @scheduled = ThatsHot::HotTopics->load({ class => 'scheduled', });
            foreach my $topic (@scheduled) {
                $blog = MT::Blog->load($topic->blog_id);
                $topic_time = MT::Util::ts2epoch($blog, $topic->created_on);
                $cur_time = time();
                # If the current time is newer than the topic time, this
                # should be made hot!
                if ($cur_time > $topic_time ) {
                    # It's possible someone messed up and scheduled a topic to
                    # be hot *before* the current time, in which case the topic
                    # should go from being scheduled to being cold. Compare
                    # against the Keep Hot For... setting.
                    $expire_time = $plugin->get_config_value('th_hot_length', 'blog:'.$topic->blog_id);
                    $expire_time = $expire_time * 3600; # 3600 seconds/hour
                    $cur_time = time();
                    $expire_time = $cur_time - $expire_time;
                    # Compare times: if older than the specified hot_length,
                    # make the topic Cold. Otherwise, it must be hot.
                    if ( $expire_time > $topic_time) {
                        $topic->class('cold');
                    } 
                    else {
                        $topic->class('hot');
                    }
                    $topic->save;
                }
                # Republish the template if this is the last item in the array.
                _republish_template($topic->blog_id)
                    if ($topic == $hot[-1]);
            }
        }
    );
}

sub _republish_template {
    # After making things hot or cold, we might need to republish a template.
    my ($blog_id) = @_;
    my $app       = MT->instance;
    my $plugin    = MT->component('thatshot');

    my $template = $plugin->get_config_value('th_republish_template', 'blog:'.$blog_id);

    # Was a template ID saved? If so, we want to republish it!
    if ($template) {
        use MT::Template;
        my $t = MT::Template->load({id => $template});

        if ($t) { # Found the template!
            use MT::WeblogPublisher;
            my $pub = MT::WeblogPublisher->new;
            $pub->rebuild_indexes( Template => $t,
                                   Force    => 1, )
                or MT::log( $pub->publish_error() );
        }
        else { # Did not find the specified template!
            MT::log({
                message => "That's Hot did not find the template specified (ID: $template). "
                           . "Was it deleted or renamed?",
                level   => 4, # Error!
            });
        }
    }
}

1;

__END__
