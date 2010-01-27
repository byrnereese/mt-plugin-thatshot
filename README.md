# That's Hot Overview

That's Hot is a plugin for Movable Type that helps you manage and publish links and search keywords. The twist That's Hot offers is that your link or search (a "Topic") starts life "hot" and becomes "cold" after a specified amount of time passes. Topics can be reheated over and over to appear at the top of the hot list again. A history of each topic's life is also maintained so that you can see how frequently it's been hot. Topics can also be scheduled to be hot.


# Prerequisites

* Movable Type 4.x
* That's Hot makes use of Movable Type's tasks framework, which requires that run-periodic-tasks be running or an Activity Feed be subscribed to.


# Installation

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install


# Configuration

That's Hot can be configured at the Blog level. Visit Preferences > Plugins to find That's Hot, then click Settings.

By default, That's Hot is *disabled* for each blog. **Enable** it for the blog(s) you want to use it with. This little step is an easy way to be sure that hot topics are created only in the master blog.

Topics can be kept "hot" for a specified amount of time. After that time has elapsed, topics become "cold." Use the **Keep Hot For...** setting to specify how long a topic should be kept hot.

It's quite possible the designated area on your site where you want to publish your hot topics to has a limited amount of space, or you want to keep track of how many topics you're publishing there. Use the **Hot Topic Soft Limit** setting to help manage this by specifying an acceptable maximum number of hot topics. When this number is hit users will see a notification when adding a new hot topic, informing them that this limit has been hit. This is a soft limit, and does *not* prevent additional topics from being added.

After a topic has been heated or cooled, you probably want to see a template be republished with this updated data. Use the **Republish this Template** option to do that. Select an index template to be republished.


# Use

## Add Hot Topic

Create a hot topic with this screen, found in Create > Hot Topic. Specify a topic title and a URL or search keyword, then make the topic hot now or schedule it for future hotness. Save.

Enter only partial details--part of a title or URL, for example--to search for an existing topic to reheat. If only one search result is found, That's Hot offers to reheat the existing topic--make it hot now or schedule hotness and save. If many search results are found, they are all returned so you can select which topic to make or schedule hot and save.

Upon successful save, the specified template is republished.

## Manage Hot Topics

The Manage screen lets you work with all topics and is found in Manage > Hot Topics. This listing screen displays all scheduled hot, currently hot, and previously hot topics. These three statuses are indicated by different colored status icons. This screen can display the same topic several times, indicating that it is currently hot and was previously hot.

Reheat a topic by selecting it and clicking the "Reheat" page action. Pull a topic from the hot list by selecting it an clicking "Make Cold"--notice that the topic is not removed, but the status is simply changed to "Cold." Use the Quickfilters to see a history of hot topics.

## Edit Topic

Edit a topic by going to the Manage Hot Topics or List Topics screen and clicking the topic title. The Edit Topic screen is most useful to see the history of a specific topic: when it was hot or when it will be hot again. Also use the this screen to edit the topic title or url/keywords. This will update *all* instances of the topic with this new information.

## List Topics

The List Topics screen can be accessed by going to the Manage Hot Topics screen, and selecting "List topics" from the Quickfilters list. The List Topics screen displays all of the unique topics that have been entered, irrespective of the topic's past and present hotness (in other words: its history).


# Template tags

A handful of template tags will expose the plugin's functionality to templates.

## Block tags:

**HotTopics**: returns all hot topics, and their history. This is most likely the block tag you want to use. This block has the meta loop variables available (\_\_first\_\_, \_\_last\_\_, \_\_odd\_\_, \_\_even\_\_, \_\_counter\_\_). This block has several valid arguments:
* id: specify the ID of a topic to create a complete history of only that topic.
* status valid options: 'hot' *or* 'cold'; the default is to return both 'hot' and 'cold.'
* class valid options: 'url' *or* 'keyword'; the default is to return both url and 'keyword.'
* sort\_by valid options: created\_on, created\_by. Default: created_on
* sort\_order: valid options: descend, ascend. Default: descend
* limit: an integer used to limit the number of results.
* offset: start the results "n" topics from the start of the list.

**Topics**: returns all topics. Topics are unique. This block has the meta loop variables available (\_\_first\_\_, \_\_last\_\_, \_\_odd\_\_, \_\_even\_\_, \_\_counter\_\_). This block tag has several valid arguments:
* class valid options: 'url' *or* 'keyword'; the default is to return both 'url' and 'keyword.'
* sort\_by valid options: created\_on, modified\_on, title, data (which refers to the URL or keyword). Default: created_on
* sort\_order: valid options: descend, ascend. Default: descend
* limit: an integer used to limit the number of results.
* offset: start the results "n" topics from the start of the list.

## Function tags:

Most of these function tags act just as you'd expect:

* TopicID: returns the ID of this topic.
* TopicTitle: returns the topic title.
* TopicClass: returns either "url" or "keyword".
* TopicData: returns the URL or search keyword data.
* TopicStatus: returns "hot" or "cold" when used in the HotTopics block. Since Topics don't have a status, this tag is not useful in the Topics block and will simply return empty.
* TopicAuthorID: returns the ID of the author associated with the topic or reheat. Feed this to an Authors block to access the author context.
* TopicDate: returns the date of the topic or reheat. Use any of MT's date formatting modifiers when publishing.

## Template Recipes

One of the most popular uses is to display a list of all hot topics:

    <mt:HotTopics status="hot">
        <mt:If name="__first__">
            <h2>Hot Topics</h2>
            <ul>
        </mt:If>
                <li>
                <mt:If tag="TopicClass" eq="url">
                    <a href="<mt:TopicData>"><mt:TopicTitle></a>
                <mt:Else tag="TopicClass" eq="keyword">
                    <a href="<mt:CGIPath><mt:SearchScript>?search=<mt:TopicData encode_url="1">"><mt:TopicTitle></a>
                </mt:If>
                </li>
        <mt:If name="__last__">
            </ul>
        </mt:If>
    </mt:HotTopics>

Of course, that will display *only* hot topics. If you're not diligent about keeping topics hot, displaying the hot and recently-hot topics might be preferred:

    <mt:HotTopics limit="5">
        <mt:If name="__first__">
            <h2>Hot Topics</h2>
            <ul>
        </mt:If>
                <li>
                    <mt:TopicDate format="%x %X">:
                <mt:If tag="TopicClass" eq="url">
                    <a href="<mt:TopicData>"><mt:TopicTitle></a>
                <mt:Else tag="TopicClass" eq="keyword">
                    <a href="<mt:CGIPath><mt:SearchScript>?search=<mt:TopicData encode_url="1">"><mt:TopicTitle></a>
                </mt:If>
                is <mt:TopicStatus>!
                </li>
        <mt:If name="__last__">
            </ul>
        </mt:If>
    </mt:HotTopics>

# Acknowledgements

This plugin was commissioned by Endevver to Dan Wolfgang of uiNNOVATIONS. Endevver is proud to be partners with uiNNOVATIONS.
http://uinnovations.com/

# License

This plugin is licensed under the same terms as Perl itself.

#Copyright

Copyright 2009, Endevver LLC. All rights reserved.
