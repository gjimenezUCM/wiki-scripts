#!/usr/bin/perl

use utf8;
use feature 'say';
use warnings;
use strict;

use LWP::UserAgent;
use JSON;
use LWP::ConnCache;
use Data::Dumper;

my $br = LWP::UserAgent->new;
$br->timeout(15);
$br->conn_cache(LWP::ConnCache->new());
$br->agent("Mozilla/5.0");


# Define id max to iterate until.
my $WIKIA_ID_MAX = 10000;

# wikia API
my $wikia_endpoint = 'http://www.wikia.com/api/v1';

# mediawiki API
my $mediawiki_endpoint = 'api.php';
#my $mediawiki_params = '?action=query&list=allusers&aufrom=Y&format=json';
my $mediawiki_params = '?action=query&meta=siteinfo&siprop=statistics&format=json';

# listUsers API
my $listUsers_url;
my $listUsers_post_endpoint = '/index.php?' . 'action=ajax&rs=ListusersAjax::axShowUsers';

# wiki info
my $wiki_name;
my $wiki_url;
my $wiki_hub;
my $wiki_topic;
my $wiki_articles;
my $wiki_pages;
my $wiki_edits;
my $wiki_lang;

my $wiki_users;
my $wiki_admins;
my $wiki_active_users;
my @users_by_contributions;

# csv variables
my $output_file = 'wikia_census.csv';
my $csv_columns = 'id, name, url, articles, pages, active users, admins, users_1, users_5, users_10, users_20, users_50, users_100, edits, lang, hub, topic';

# other variables
my $wikia_id;
my $wiki_info;

# one argument => wiki_info that is a dictionary with all info retrieved from wikia API
sub extract_wiki_info_from_wikia_json {
        $wiki_name = $wiki_info->{'name'};
        $wiki_url = $wiki_info->{'url'};
        $wiki_hub = $wiki_info->{'hub'};
        $wiki_topic = $wiki_info->{'topic'};
        $wiki_lang = $wiki_info->{'lang'};
        
        my $wiki_stats = $wiki_info->{'stats'};
        $wiki_edits = $wiki_stats->{'edits'};
        $wiki_articles = $wiki_stats->{'articles'};
        $wiki_pages = $wiki_stats->{'pages'};

        $wiki_admins = $wiki_stats->{'admins'};
        $wiki_active_users = $wiki_stats->{'activeUsers'};
}

# order of arguments = ($loop, $edits)
sub request_all_users {
        my ($loop, $edits) = @_;
        my @form_data = [
                groups => "all,bot,bureaucrat,rollback,sysop,threadmoderator,authenticated,bot-global,content-reviewer,council,fandom-editor,global-discussions-moderator,helper,restricted-login,restricted-login-exempt,reviewer,staff,util,vanguard,voldev,vstf,",
                username => "",
                edits => $edits,
                limit => "10",
                offset => "0",
                loop => $loop, # simulate user behaviour
                numOrder => "1",
                order => "username:asc"
        ];

        my $res = $br->post($listUsers_url, @form_data);
        if (not $res->is_success) {
                die $res->status_line.' when posting to Special:ListUsers for edits ' . $edits;
        }
        my $raw_users_content = $res->decoded_content();
        my $json_res = decode_json($raw_users_content);
        #~ print Dumper($json_res);
        my $users = $json_res->{'iTotalDisplayRecords'};
        say "Total users with edits equal or higher than $edits is: $users";
        $users;
}

# order of arguments = ($loop, $edits)
sub request_bot_users {
        my ($loop, $edits) = @_;
        my @form_data_for_bots = [
                groups => "bot,bot-global,",
                username => "",
                edits => $edits,
                limit => "10",
                offset => "0",
                loop => $loop, # simulate user behaviour
                numOrder => "1",
                order => "username:asc"
        ];

        my $res = $br->post($listUsers_url, @form_data_for_bots);
        if (not $res->is_success) {
                die $res->status_line.' when posting to Special:ListUsers querying for bot users.';
        }

        my $raw_users_content = $res->decoded_content();
        my $json_res = decode_json($raw_users_content);
        #~ print Dumper($json_res);
        my $bot_users = $json_res->{'iTotalDisplayRecords'};
        say "Bot users with edits equal or higher than $edits is: $bot_users";
        $bot_users;
}

sub extract_users_by_contributions {
        my $no_bot_users;
        my $edits_query;
        my $loop_query;
        for (my $i = 0; $i < 6; ++$i) {
                if ($i == 0) {$edits_query = 1;}
                elsif ($i == 1) {$edits_query = 5;}
                elsif ($i == 2) {$edits_query = 10;}
                elsif ($i == 3) {$edits_query = 20;}
                elsif ($i == 4) {$edits_query = 50;}
                else {$edits_query = 100;} # ($i == 5)
                
                $loop_query = $i * 2 + 1;
                $no_bot_users = request_all_users($loop_query, $edits_query) - request_bot_users($loop_query + 1, $edits_query);
                say "Non-bot users with edits equal or higher than $edits_query is: $no_bot_users";
                $users_by_contributions[$i] = $no_bot_users;
        }        
}


# To fill $csv_columns => 'id, name, url, articles, pages, active users, admins, users_1, users_5, users_10, users_20, users_50, users_100, edits, lang, hub, topic';
sub print_wiki_to_csv {
        say "Printing info for wiki $wikia_id .....";
        print CSV "$wikia_id, $wiki_name, $wiki_url, $wiki_pages, $wiki_active_users, $wiki_admins, $users_by_contributions[0], $users_by_contributions[1], $users_by_contributions[2], $users_by_contributions[3], $users_by_contributions[4], $users_by_contributions[5], $wiki_edits, $wiki_lang, $wiki_hub, $wiki_topic \n";
}


#### Starts main(): #####

# creating CSV file handler for writing
open CSV, " >$output_file" or die "Error trying to write on $output_file: $!\n";
print CSV $csv_columns . "\n";


# Iterating over ids
for ($wikia_id = 1; $wikia_id <= $WIKIA_ID_MAX; $wikia_id++) {
        
        say ("Retrieving data for wiki with id: $wikia_id");
        
        # Getting wiki's canonical url from wikia general API
        my $wikia_params = '/Wikis/Details?ids=' . $wikia_id; # params targetting wikia api to get wiki info
        my $api_request = $wikia_endpoint . $wikia_params;
        my $res = $br->get($api_request);
        if (not $res->is_success) {
                die $res->status_line.' when getting wikias from ' . $api_request;
        }
        my $json_res = decode_json($res->decoded_content);
        #~ print Dumper($json_res);
        if ( not($json_res->{'items'}->{$wikia_id} )) {
                say "--- No wiki found with id $wikia_id ---";
                next;
        }
        
        # Getting general info using wikia API:
        $wiki_info = $json_res->{'items'}->{$wikia_id};
        extract_wiki_info_from_wikia_json();
        
        # Getting users using Special:ListUsers page
        $listUsers_url = $wiki_url . $listUsers_post_endpoint;
        extract_users_by_contributions();
        
        
        # Info retrieved, printing:
        print_wiki_to_csv();
        
        say ("Non bot users per contribution: ");
        print "$_, " foreach (@users_by_contributions);
        print "\n\n";        
        say('#' x 20);
        print "\n\n";
        
        sleep 2;
}



###############################################

#### Additional info / resources: #####
# Other possible queries targetting wikia api with useful info:
#my $wikia_params = '/Wikis/List?limit=25&batch=1'; # top wikis by pageviews
#my $wikia_params = '/WikiaHubs/getHubsV3List?lang=en'; # wiki hubs list
#my $wikia_params = '/Wikis/ByString?expand=1&string=mountain&hub=Lifestyle&limit=25&batch=1&includeDomain=true'; # search wiki by name

# If we wanted to get wiki info from wikimedia API instead of from wikia API:
#$api_request = $wiki_url . $mediawiki_endpoint . $mediawiki_params;
#my $res = $br->get($api_request);
#if (not $res->is_success) {
        #die $res->status_line." when getting wikias from " . $api_request;
#}
#my $json_res = decode_json($res->decoded_content);
#print Dumper($json_res);
#my $wiki_stats = $json_res->{'query'}->{'statistics'};
#say $wiki_stats->{'users'};
#say $wiki_stats->{'activeusers'};
#say $wiki_stats->{'admins'};