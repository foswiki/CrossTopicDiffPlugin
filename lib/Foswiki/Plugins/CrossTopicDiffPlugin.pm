# See bottom of file for default license and copyright information

=begin TML

---+ package CrossTopicDiffPlugin

TBD

Error messages can be output using the =Foswiki::Func= =writeWarning= and
=writeDebug= functions. You can also =print STDERR=; the output will appear
in the webserver error log. Most handlers can also throw exceptions (e.g.
[[%SCRIPTURL{view}%/%SYSTEMWEB%/PerlDoc?module=Foswiki::OopsException][Foswiki::OopsException]])

For increased performance, all handler functions except =initPlugin= are
commented out below. *To enable a handler* remove the leading =#= from
each line of the function. For efficiency and clarity, you should
only uncomment handlers you actually use.

__NOTE:__ When developing a plugin it is important to remember that

Foswiki is tolerant of plugins that do not compile. In this case,
the failure will be silent but the plugin will not be available.
See %SYSTEMWEB%.InstalledPlugins for error messages.

__NOTE:__ Foswiki:Development.StepByStepRenderingOrder helps you decide which
rendering handler to use. When writing handlers, keep in mind that these may
be invoked

on included topics. For example, if a plugin generates links to the current
topic, these need to be generated before the =afterCommonTagsHandler= is run.
After that point in the rendering loop we have lost the information that
the text had been included from another topic.

=cut

# change the package name!!!
package Foswiki::Plugins::CrossTopicDiffPlugin;

# Always use strict to enforce variable scoping
use strict;

require Foswiki::Func;       # The plugins API
require Foswiki::Plugins;    # For the API version

# $VERSION is referred to by Foswiki, and is the only global variable that
# *must* exist in this package.
# This should always be $Rev: 3193 $ so that Foswiki can determine the checked-in
# status of the plugin. It is used by the build automation tools, so
# you should leave it alone.
our $VERSION = '$Rev: 3193 $';

# This is a free-form string you can use to "name" your own plugin version.
# It is *not* used by the build automation tools, but is reported as part
# of the version number in PLUGINDESCRIPTIONS.
our $RELEASE = '$Date: 2009-03-19 18:32:09 +0200 (Thu, 19 Mar 2009) $';

# Short description of this plugin
# One line description, is shown in the %SYSTEMWEB%.TextFormattingRules topic:
our $SHORTDESCRIPTION = 'Compare different topics';

# You must set $NO_PREFS_IN_TOPIC to 0 if you want your plugin to use
# preferences set in the plugin topic. This is required for compatibility
# with older plugins, but imposes a significant performance penalty, and
# is not recommended. Instead, leave $NO_PREFS_IN_TOPIC at 1 and use
# =$Foswiki::cfg= entries set in =LocalSite.cfg=, or if you want the users
# to be able to change settings, then use standard Foswiki preferences that
# can be defined in your %USERSWEB%.SitePreferences and overridden at the web
# and topic level.
our $NO_PREFS_IN_TOPIC = 1;

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin topic is in
     (usually the same as =$Foswiki::cfg{SystemWebName}=)

*REQUIRED*

Called to initialise the plugin. If everything is OK, should return
a non-zero value. On non-fatal failure, should write a message
using =Foswiki::Func::writeWarning= and return 0. In this case
%<nop>FAILEDPLUGINS% will indicate which plugins failed.

In the case of a catastrophic failure that will prevent the whole
installation from working safely, this handler may use 'die', which
will be trapped and reported in the browser.

__Note:__ Please align macro names with the Plugin name, e.g. if
your Plugin is called !FooBarPlugin, name macros FOOBAR and/or
FOOBARSOMETHING. This avoids namespace issues.

=cut

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    # Example code of how to get a preference value, register a macro
    # handler and register a RESTHandler (remove code you do not need)

    # Set your per-installation plugin configuration in LocalSite.cfg,
    # like this:
    # $Foswiki::cfg{Plugins}{EmptyPlugin}{ExampleSetting} = 1;
    # Optional: See %SYSTEMWEB%.DevelopingPlugins#ConfigSpec for information
    # on integrating your plugin configuration with =configure=.

    # Always provide a default in case the setting is not defined in
    # LocalSite.cfg. See %SYSTEMWEB%.Plugins for help in adding your plugin
    # configuration to the =configure= interface.
    # my $setting = $Foswiki::cfg{Plugins}{EmptyPlugin}{ExampleSetting} || 0;

    # Register the _COMPAREWEBS function to handle %COMPAREWEBS{...}%
    # This will be called whenever %EXAMPLETAG% or %EXAMPLETAG{...}% is
    # seen in the topic text.
    Foswiki::Func::registerTagHandler( 'COMPAREWEBS', \&_COMPAREWEBS );

    # Allow a sub to be called from the REST interface
    # using the provided alias
    Foswiki::Func::registerRESTHandler( 'compareTopics', \&restCompareTopics );

    # Plugin correctly initialized
    return 1;
}

# The function used to handle the %COMPAREWEBS{...}% macro
sub _COMPAREWEBS {
    my ( $session, $params, $theTopic, $theWeb ) = @_;

    # $session  - a reference to the Foswiki session object (if you don't know
    #             what this is, just ignore it)
    # $params=  - a reference to a Foswiki::Attrs object containing
    #             parameters.
    #             This can be used as a simple hash that maps parameter names
    #             to values, with _DEFAULT being the name for the default
    #             (unnamed) parameter.
    # $theTopic - name of the topic in the query
    # $theWeb   - name of the web in the query
    # Return: the result of processing the macro. This will replace the
    # macro call in the final text.

    # For example, %EXAMPLETAG{'hamburger' sideorder="onions"}%
    # $params->{_DEFAULT} will be 'hamburger'
    # $params->{sideorder} will be 'onions'
    #
    my $web1;
    my $web2;
    if ( exists $params->{web1} and exists $params->{web2} ) {
        $web1 = $params->{web1};
        $web2 = $params->{web2};
    }
    else {
        $web1 = $theWeb;
        $web2 = $params->{_DEFAULT} || $theWeb;
    }

    my $query = Foswiki::Func::getRequestObject();

    if ( $query->param('comparetopic') ) {
        my $topic = $query->param('comparetopic');
        my $selfLink = Foswiki::Func::getViewUrl( $theWeb, $theTopic );

        return "[[$selfLink#Diff_$topic][ *Return to web comparison* ]]\n\n"
          . _compareTopics( $theWeb, $theTopic, $web1, $topic, undef, $web2,
            $topic, undef );
    }
    elsif ( $params->{comparetopic1} and $params->{comparetopic2} ) {
        return _compareTopics(
            $theWeb,                  $theTopic,
            $web1,                    $params->{comparetopic1},
            $params->{comparerev1},   $web2,
            $params->{comparetopic2}, $params->{comparerev2}
        );
    }
    else {
        return _compareWebs( $theWeb, $theTopic, $web1, $web2 );
    }
}

sub _compareWebs {
    my ( $theWeb, $theTopic, $web1, $web2 ) = @_;

    my $selfLink = Foswiki::Func::getViewUrl( $theWeb, $theTopic );

    my @topics1 = sort { $a cmp $b } Foswiki::Func::getTopicList($web1);
    my @topics2 = sort { $a cmp $b } Foswiki::Func::getTopicList($web2);

    require Algorithm::Diff;

    my $output =
"<style type=\"text/css\" media=\"all\">.ctdpDifferent { background-color:#FFCCCC;} .ctdpSame { background-color:#CCFFCC;} .ctdpError { background-color:#FF8888; color:#444444; font-weight:bold;}</style>\n"
      . "| *Topics in $web1.\%HOMETOPIC\%* | *Topics in $web2.\%HOMETOPIC\%* | *Status* | *Action* |\n";
    my @compareList = ();
    my $diff = Algorithm::Diff->new( \@topics1, \@topics2 );
    while ( $diff->Next() ) {
        my @same = $diff->Same();
        if (@same) {
            foreach my $topic (@same) {
                $output .=
"| <a name=\"Diff_$topic\"></a>[[$web1.$topic][ $topic ]] | [[$web2.$topic][ $topic ]] | <span id=\"Status_$topic\">comparing...</span> | <a href=\"$selfLink?comparetopic=$topic\" target=\"_blank\">compare</a> |\n";
                push @compareList, "$topic";
            }
        }
        else {
            foreach my $topic ( $diff->Items(1) ) {
                $output .=
"| [[$web1.$topic][ $topic ]] | | %BROWN% __Not in $web2.\%HOMETOPIC\%__ %ENDCOLOR% | [[\%SCRIPTURLPATH{save}\%/$web2/$topic?templatetopic=$web1.$topic&redirectto=$theWeb.$theTopic][Copy to $web2]] |\n";
            }

            foreach my $topic ( $diff->Items(2) ) {
                $output .=
"| | [[$web2.$topic][ $topic ]] | %RED% __Not in $web1.\%HOMETOPIC\%__ %ENDCOLOR% | [[\%SCRIPTURLPATH{save}\%/$web1/$topic?templatetopic=$web2.$topic&redirectto=$theWeb.$theTopic][Copy to $web1]] |\n";
            }
        }
    }
    if (@compareList) {

        #TBD - Write a REST handler to compare two topics,
        #      then get some AJAX-style Javascript here,
        #      to replace the text of the "comparing..." spans
        #      based on the comparison result from a REST handler
        $output .=
"<script language=\"javascript\" type=\"text/javascript\" src=\"\%PUBURLPATH\%/\%SYSTEMWEB\%/TinyMCEPlugin/tinymce/jscripts/tiny_mce/tiny_mce.js\"></script>\n"
          . "<script type=\"text/javascript\" src=\"\%PUBURLPATH\%/\%SYSTEMWEB\%/CrossTopicDiffPlugin/update_topic_diff_status.js\"></script>\n"
          . "<script type=\"text/javascript\">\n"
          . "<!--\nctdpRestHandlerUrl = \"\%SCRIPTURLPATH{rest}\%/CrossTopicDiffPlugin/compareTopics\";\nctdpCompareList = [\""
          . join( "\", \"", @compareList )
          . "\"];\n"
          . "ctdpWeb1 = \"$web1\";\n"
          . "ctdpWeb2 = \"$web2\";\n"
          . "ctdpUpdateCompareStatuses();\n"
          . "// -->\n</script>";
    }

    return $output;
}

sub _compareTopics {
    my ( $theWeb, $theTopic, $web1, $topic1, $rev1, $web2, $topic2, $rev2 ) =
      @_;

    my $revLink1 = '';
    my $revText1 = '';
    my $revLink2 = '';
    my $revText2 = '';
    if ( defined $rev1 ) {
        $revLink1 = "?rev=$rev1";
        $revText1 = " rev $rev1";
    }
    if ( defined $rev2 ) {
        $revLink2 = "?rev=$rev2";
        $revText2 = " rev $rev2";
    }

    my $output = '';

    my $user = Foswiki::Func::getDefaultUserName();
    my $canView1 =
      Foswiki::Func::checkAccessPermission( 'VIEW', $user, undef, $topic1,
        $web1, undef );
    my $canView2 =
      Foswiki::Func::checkAccessPermission( 'VIEW', $user, undef, $topic2,
        $web2, undef );
    if ( $canView1 and $canView2 ) {
        my ( $meta1, $text1 ) =
          Foswiki::Func::readTopic( $web1, $topic1, $rev1 );
        my ( $meta2, $text2 ) =
          Foswiki::Func::readTopic( $web2, $topic2, $rev2 );
        $output .= "Topics are identical\n\n" if $text1 eq $text2;

        #my $compareMode = "line";
        my $compareMode = "char";
        if ( $compareMode eq 'line' ) {
            my @content1 = split /\n/, $text1;
            my @content2 = split /\n/, $text2;

            $output .=
"| *[[$web1.$topic1$revLink1][ $web1.$topic1$revText1 ]]* | *[[$web2.$topic2$revLink2][ $web2.$topic2$revText2 ]]* |\n";

            require Algorithm::Diff;
            my $diff = Algorithm::Diff->new( \@content1, \@content2 );
            while ( $diff->Next() ) {
                my @same = $diff->Same();
                if (@same) {
                    foreach my $line (@same) {
                        $line =~ s/([^A-Za-z0-9 ])/'&#'.ord($1).';'/ge;
                        $output .= "| $line | $line |\n";
                    }
                }
                else {
                    foreach my $line ( $diff->Items(1) ) {
                        $line =~ s/([^A-Za-z0-9 ])/'&#'.ord($1).';'/ge;
                        $output .= "| %GREEN% $line %ENDCOLOR% | |\n";
                    }
                    foreach my $line ( $diff->Items(2) ) {
                        $line =~ s/([^A-Za-z0-9 ])/'&#'.ord($1).';'/ge;
                        $output .= "| | %RED% $line %ENDCOLOR% |\n";
                    }
                }
            }
        }
        elsif ( $compareMode eq 'char' ) {
            $text1 =~ s/([^A-Za-z0-9 \n])/'&#'.ord($1).';'/ge;
            $text2 =~ s/([^A-Za-z0-9 \n])/'&#'.ord($1).';'/ge;
            my @content1 = split /\b/, $text1;
            my @content2 = split /\b/, $text2;
            $output .=
"<style type=\"text/css\" media=\"all\">.diffItems1 { background-color:#FFCCCC;} .diffItems2 { background-color:#CCFFCC;}</style>"
              . "Colour key:\n"
              . "   * In both [[$web1.$topic1$revLink1][ $web1.$topic1$revText1 ]] and [[$web2.$topic2$revLink2][ $web2.$topic2$revText2 ]]\n"
              . "   * <span class=\"diffItems1\">In [[$web1.$topic1$revLink1][ $web1.$topic1$revText1 ]] but not in [[$web2.$topic2$revLink2][ $web2.$topic2$revText2 ]]</span>\n"
              . "   * <span class=\"diffItems2\">In [[$web2.$topic2$revLink2][ $web2.$topic2$revText2 ]] but not in [[$web1.$topic1$revLink1][ $web1.$topic1$revText1 ]]</span>\n"
              . "<style type=\"text/css\" media=\"all\">.ctdpComparison { border-style:solid; border-width:1px 1px 1px 1px; padding: 5px; border-color:#AAAAAA; background-color:#EEEEEE; }></style><div class=\"ctdpComparison\">\n";

            require Algorithm::Diff;
            my $diff = Algorithm::Diff->new( \@content1, \@content2 );
            while ( $diff->Next() ) {
                my @same = $diff->Same();
                if (@same) {
                    foreach my $symbol (@same) {
                        $output .= $symbol;
                    }
                }
                else {
                    my @symbols1 = $diff->Items(1);
                    if (@symbols1) {
                        $output .= "<span class=\"diffItems1\">";
                        foreach my $symbol (@symbols1) {
                            $output .= $symbol;
                        }
                        $output .= "</span>";
                    }
                    my @symbols2 = $diff->Items(2);
                    if (@symbols2) {
                        $output .= "<span class=\"diffItems2\">";
                        foreach my $symbol (@symbols2) {
                            $output .= $symbol;
                        }
                        $output .= "</span>";
                    }
                }
            }
            $output .= "</div>";
        }
        else {
            $output .= "Topics are different";
        }

    }
    else {
        $output .=
"Cannot compare [[$web1.$topic1][ $web1.$topic1 ]] with [[$web2.$topic2][ $web2.$topic2 ]]\n";
        $output .=
"   * You do not have permission to view [[$web1.$topic1][ $web1.$topic1 ]]\n"
          unless $canView1;
        $output .=
"   * You do not have permission to view [[$web2.$topic2][ $web2.$topic2 ]]\n"
          unless $canView2;
    }

    return $output;
}

=begin TML

---++ restCompareTopics($session) -> $text

This is an example of a sub to be called by the =rest= script. The parameter is:
   * =$session= - The Foswiki object associated to this session.

Additional parameters can be recovered via de query object in the $session.

For more information, check %SYSTEMWEB%.CommandAndCGIScripts#rest

For information about handling error returns from REST handlers, see
Foswiki::Support.Faq1

*Since:* Foswiki::Plugins::VERSION 2.0

=cut

sub restCompareTopics {
    my ($session) = @_;
    my $request = Foswiki::Func::getRequestObject();

    my $web1 = $request->param("web1")
      or return
      "<span class=\"ctdpError\">Cannot compare: no web1 parameter</span>";
    my $web2 = $request->param("web2")
      or return
      "<span class=\"ctdpError\">Cannot compare: no web2 parameter</span>";
    my $topic1 = $request->param("topic1")
      or return
      "<span class=\"ctdpError\">Cannot compare: no topic1 parameter</span>";
    my $topic2 = $request->param("topic2")
      or return
      "<span class=\"ctdpError\">Cannot compare: no topic2 parameter</span>";

    # If revisions are not defined, then the latest revisions are compared
    my $rev1 = $request->param("rev1");
    my $rev2 = $request->param("rev2");

    my $output = '';

    my $user = Foswiki::Func::getDefaultUserName();
    my $canView1 =
      Foswiki::Func::checkAccessPermission( 'VIEW', $user, undef, $topic1,
        $web1, undef );
    my $canView2 =
      Foswiki::Func::checkAccessPermission( 'VIEW', $user, undef, $topic2,
        $web2, undef );
    if ( $canView1 and $canView2 ) {
        my ( $meta1, $text1 ) =
          Foswiki::Func::readTopic( $web1, $topic1, $rev1 );
        my ( $meta2, $text2 ) =
          Foswiki::Func::readTopic( $web2, $topic2, $rev2 );
        if ( $text1 eq $text2 ) {
            $output .= "<span class=\"ctdpSame\">Same</span>";
        }
        else {
            $output .= "<span class=\"ctdpDifferent\">Different</span>";
        }
    }
    else {
        $output .=
"<span class=\"ctdpError\">Cannot compare [[$web1.$topic1][ $web1.$topic1 ]] with [[$web2.$topic2][ $web2.$topic2 ]]\n";
        $output .=
"   * You do not have permission to view [[$web1.$topic1][ $web1.$topic1 ]]\n"
          unless $canView1;
        $output .=
"   * You do not have permission to view [[$web2.$topic2][ $web2.$topic2 ]]\n"
          unless $canView2;
        $output .= "</span>";
    }

    return Foswiki::Func::renderText($output);
}

=begin TML

---++ earlyInitPlugin()

This handler is called before any other handler, and before it has been
determined if the plugin is enabled or not. Use it with great care!

If it returns a non-null error string, the plugin will be disabled.

=cut

#sub earlyInitPlugin {
#    return undef;
#}

=begin TML

---++ initializeUserHandler( $loginName, $url, $pathInfo )
   * =$loginName= - login name recovered from $ENV{REMOTE_USER}
   * =$url= - request url
   * =$pathInfo= - pathinfo from the CGI query
Allows a plugin to set the username. Normally Foswiki gets the username
from the login manager. This handler gives you a chance to override the
login manager.

Return the *login* name.

This handler is called very early, immediately after =earlyInitPlugin=.

*Since:* Foswiki::Plugins::VERSION = '2.0'

=cut

#sub initializeUserHandler {
#    my ( $loginName, $url, $pathInfo ) = @_;
#}

=begin TML

---++ finishPlugin()

Called when Foswiki is shutting down, this handler can be used by the plugin
to release resources - for example, shut down open database connections,
release allocated memory etc.

Note that it's important to break any cycles in memory allocated by plugins,
or that memory will be lost when Foswiki is run in a persistent context
e.g. mod_perl.

=cut

#sub finishPlugin {
#}

=begin TML

---++ registrationHandler($web, $wikiName, $loginName )
   * =$web= - the name of the web in the current CGI query
   * =$wikiName= - users wiki name
   * =$loginName= - users login name

Called when a new user registers with this Foswiki.

*Since:* Foswiki::Plugins::VERSION = '2.0'

=cut

#sub registrationHandler {
#    my ( $web, $wikiName, $loginName ) = @_;
#}

=begin TML

---++ commonTagsHandler($text, $topic, $web, $included, $meta )
   * =$text= - text to be processed
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$included= - Boolean flag indicating whether the handler is
     invoked on an included topic
   * =$meta= - meta-data object for the topic MAY BE =undef=
This handler is called by the code that expands %<nop>MACROS% syntax in
the topic body and in form fields. It may be called many times while
a topic is being rendered.

Only plugins that have to parse the entire topic content should implement
this function. For expanding macros with trivial syntax it is *far* more
efficient to use =Foswiki::Func::registerTagHandler= (see =initPlugin=).

Internal Foswiki macros, (and any macros declared using
=Foswiki::Func::registerTagHandler=) are expanded _before_, and then again
_after_, this function is called to ensure all %<nop>MACROS% are expanded.

*NOTE:* when this handler is called, &lt;verbatim> blocks have been
removed from the text (though all other blocks such as &lt;pre> and
&lt;noautolink> are still present).

*NOTE:* meta-data is _not_ embedded in the text passed to this
handler. Use the =$meta= object.

*Since:* $Foswiki::Plugins::VERSION 2.0

=cut

#sub commonTagsHandler {
#    my ( $text, $topic, $web, $included, $meta ) = @_;
#
#    # If you don't want to be called from nested includes...
#    #   if( $included ) {
#    #         # bail out, handler called from an %INCLUDE{}%
#    #         return;
#    #   }
#
#    # You can work on $text in place by using the special perl
#    # variable $_[0]. These allow you to operate on $text
#    # as if it was passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

=begin TML

---++ beforeCommonTagsHandler($text, $topic, $web, $meta )
   * =$text= - text to be processed
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - meta-data object for the topic MAY BE =undef=
This handler is called before Foswiki does any expansion of its own
internal variables. It is designed for use by cache plugins. Note that
when this handler is called, &lt;verbatim> blocks are still present
in the text.

*NOTE*: This handler is called once for each call to
=commonTagsHandler= i.e. it may be called many times during the
rendering of a topic.

*NOTE:* meta-data is _not_ embedded in the text passed to this
handler.

*NOTE:* This handler is not separately called on included topics.

=cut

#sub beforeCommonTagsHandler {
#    my ( $text, $topic, $web, $meta ) = @_;
#
#    # You can work on $text in place by using the special perl
#    # variable $_[0]. These allow you to operate on $text
#    # as if it was passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

=begin TML

---++ afterCommonTagsHandler($text, $topic, $web, $meta )
   * =$text= - text to be processed
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - meta-data object for the topic MAY BE =undef=
This handler is called after Foswiki has completed expansion of %MACROS%.
It is designed for use by cache plugins. Note that when this handler
is called, &lt;verbatim> blocks are present in the text.

*NOTE*: This handler is called once for each call to
=commonTagsHandler= i.e. it may be called many times during the
rendering of a topic.

*NOTE:* meta-data is _not_ embedded in the text passed to this
handler.

=cut

#sub afterCommonTagsHandler {
#    my ( $text, $topic, $web, $meta ) = @_;
#
#    # You can work on $text in place by using the special perl
#    # variable $_[0]. These allow you to operate on $text
#    # as if it was passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

=begin TML

---++ preRenderingHandler( $text, \%map )
   * =$text= - text, with the head, verbatim and pre blocks replaced
     with placeholders
   * =\%removed= - reference to a hash that maps the placeholders to
     the removed blocks.

Handler called immediately before Foswiki syntax structures (such as lists) are
processed, but after all variables have been expanded. Use this handler to
process special syntax only recognised by your plugin.

Placeholders are text strings constructed using the tag name and a
sequence number e.g. 'pre1', "verbatim6", "head1" etc. Placeholders are
inserted into the text inside &lt;!--!marker!--&gt; characters so the
text will contain &lt;!--!pre1!--&gt; for placeholder pre1.

Each removed block is represented by the block text and the parameters
passed to the tag (usually empty) e.g. for
<verbatim>
<pre class='slobadob'>
XYZ
</pre>
</verbatim>
the map will contain:
<pre>
$removed->{'pre1'}{text}:   XYZ
$removed->{'pre1'}{params}: class="slobadob"
</pre>
Iterating over blocks for a single tag is easy. For example, to prepend a
line number to every line of every pre block you might use this code:
<verbatim>
foreach my $placeholder ( keys %$map ) {
    if( $placeholder =~ /^pre/i ) {
        my $n = 1;
        $map->{$placeholder}{text} =~ s/^/$n++/gem;
    }
}
</verbatim>

__NOTE__: This handler is called once for each rendered block of text i.e.
it may be called several times during the rendering of a topic.

*NOTE:* meta-data is _not_ embedded in the text passed to this
handler.

Since Foswiki::Plugins::VERSION = '2.0'

=cut

#sub preRenderingHandler {
#    my( $text, $pMap ) = @_;
#
#    # You can work on $text in place by using the special perl
#    # variable $_[0]. These allow you to operate on $text
#    # as if it was passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

=begin TML

---++ postRenderingHandler( $text )
   * =$text= - the text that has just been rendered. May be modified in place.

*NOTE*: This handler is called once for each rendered block of text i.e. 
it may be called several times during the rendering of a topic.

*NOTE:* meta-data is _not_ embedded in the text passed to this
handler.

Since Foswiki::Plugins::VERSION = '2.0'

=cut

#sub postRenderingHandler {
#    my $text = shift;
#    # You can work on $text in place by using the special perl
#    # variable $_[0]. These allow you to operate on $text
#    # as if it was passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

=begin TML

---++ beforeEditHandler($text, $topic, $web )
   * =$text= - text that will be edited
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
This handler is called by the edit script just before presenting the edit text
in the edit box. It is called once when the =edit= script is run.

*NOTE*: meta-data may be embedded in the text passed to this handler 
(using %META: tags)

*Since:* Foswiki::Plugins::VERSION = '2.0'

=cut

#sub beforeEditHandler {
#    my ( $text, $topic, $web ) = @_;
#
#    # You can work on $text in place by using the special perl
#    # variable $_[0]. These allow you to operate on $text
#    # as if it was passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

=begin TML

---++ afterEditHandler($text, $topic, $web, $meta )
   * =$text= - text that is being previewed
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - meta-data for the topic.
This handler is called by the preview script just before presenting the text.
It is called once when the =preview= script is run.

*NOTE:* this handler is _not_ called unless the text is previewed.

*NOTE:* meta-data is _not_ embedded in the text passed to this
handler. Use the =$meta= object.

*Since:* $Foswiki::Plugins::VERSION 2.0

=cut

#sub afterEditHandler {
#    my ( $text, $topic, $web ) = @_;
#
#    # You can work on $text in place by using the special perl
#    # variable $_[0]. These allow you to operate on $text
#    # as if it was passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

=begin TML

---++ beforeSaveHandler($text, $topic, $web, $meta )
   * =$text= - text _with embedded meta-data tags_
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - the metadata of the topic being saved, represented by a Foswiki::Meta object.

This handler is called each time a topic is saved.

*NOTE:* meta-data is embedded in =$text= (using %META: tags). If you modify
the =$meta= object, then it will override any changes to the meta-data
embedded in the text. Modify *either* the META in the text *or* the =$meta=
object, never both. You are recommended to modify the =$meta= object rather
than the text, as this approach is proof against changes in the embedded
text format.

*Since:* Foswiki::Plugins::VERSION = 2.0

=cut

#sub beforeSaveHandler {
#    my ( $text, $topic, $web ) = @_;
#
#    # You can work on $text in place by using the special perl
#    # variable $_[0]. These allow you to operate on $text
#    # as if it was passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

=begin TML

---++ afterSaveHandler($text, $topic, $web, $error, $meta )
   * =$text= - the text of the topic _excluding meta-data tags_
     (see beforeSaveHandler)
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$error= - any error string returned by the save.
   * =$meta= - the metadata of the saved topic, represented by a Foswiki::Meta object 

This handler is called each time a topic is saved.

*NOTE:* meta-data is embedded in $text (using %META: tags)

*Since:* Foswiki::Plugins::VERSION 2.0

=cut

#sub afterSaveHandler {
#    my ( $text, $topic, $web, $error, $meta ) = @_;
#
#    # You can work on $text in place by using the special perl
#    # variable $_[0]. These allow you to operate on $text
#    # as if it was passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

=begin TML

---++ afterRenameHandler( $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment )

   * =$oldWeb= - name of old web
   * =$oldTopic= - name of old topic (empty string if web rename)
   * =$oldAttachment= - name of old attachment (empty string if web or topic rename)
   * =$newWeb= - name of new web
   * =$newTopic= - name of new topic (empty string if web rename)
   * =$newAttachment= - name of new attachment (empty string if web or topic rename)

This handler is called just after the rename/move/delete action of a web, topic or attachment.

*Since:* Foswiki::Plugins::VERSION = '2.0'

=cut

#sub afterRenameHandler {
#    my ( $oldWeb, $oldTopic, $oldAttachment,
#         $newWeb, $newTopic, $newAttachment ) = @_;
#}

=begin TML

---++ beforeAttachmentSaveHandler(\%attrHash, $topic, $web )
   * =\%attrHash= - reference to hash of attachment attribute values
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
This handler is called once when an attachment is uploaded. When this
handler is called, the attachment has *not* been recorded in the database.

The attributes hash will include at least the following attributes:
   * =attachment= => the attachment name
   * =comment= - the comment
   * =user= - the user id
   * =tmpFilename= - name of a temporary file containing the attachment data

*Since:* Foswiki::Plugins::VERSION = 2.0

=cut

#sub beforeAttachmentSaveHandler {
#    my( $attrHashRef, $topic, $web ) = @_;
#}

=begin TML

---++ afterAttachmentSaveHandler(\%attrHash, $topic, $web, $error )
   * =\%attrHash= - reference to hash of attachment attribute values
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$error= - any error string generated during the save process
This handler is called just after the save action. The attributes hash
will include at least the following attributes:
   * =attachment= => the attachment name
   * =comment= - the comment
   * =user= - the user id

*Since:* Foswiki::Plugins::VERSION = 2.0

=cut

#sub afterAttachmentSaveHandler {
#    my( $attrHashRef, $topic, $web ) = @_;
#}

=begin TML

---++ mergeHandler( $diff, $old, $new, \%info ) -> $text
Try to resolve a difference encountered during merge. The =differences= 
array is an array of hash references, where each hash contains the 
following fields:
   * =$diff= => one of the characters '+', '-', 'c' or ' '.
      * '+' - =new= contains text inserted in the new version
      * '-' - =old= contains text deleted from the old version
      * 'c' - =old= contains text from the old version, and =new= text
        from the version being saved
      * ' ' - =new= contains text common to both versions, or the change
        only involved whitespace
   * =$old= => text from version currently saved
   * =$new= => text from version being saved
   * =\%info= is a reference to the form field description { name, title,
     type, size, value, tooltip, attributes, referenced }. It must _not_
     be wrtten to. This parameter will be undef when merging the body
     text of the topic.

Plugins should try to resolve differences and return the merged text. 
For example, a radio button field where we have 
={ diff=>'c', old=>'Leafy', new=>'Barky' }= might be resolved as 
='Treelike'=. If the plugin cannot resolve a difference it should return 
undef.

The merge handler will be called several times during a save; once for 
each difference that needs resolution.

If any merges are left unresolved after all plugins have been given a 
chance to intercede, the following algorithm is used to decide how to 
merge the data:
   1 =new= is taken for all =radio=, =checkbox= and =select= fields to 
     resolve 'c' conflicts
   1 '+' and '-' text is always included in the the body text and text
     fields
   1 =&lt;del>conflict&lt;/del> &lt;ins>markers&lt;/ins>= are used to 
     mark 'c' merges in text fields

The merge handler is called whenever a topic is saved, and a merge is 
required to resolve concurrent edits on a topic.

*Since:* Foswiki::Plugins::VERSION = 2.0

=cut

#sub mergeHandler {
#    my ( $diff, $old, $new, $info ) = @_;
#}

=begin TML

---++ modifyHeaderHandler( \%headers, $query )
   * =\%headers= - reference to a hash of existing header values
   * =$query= - reference to CGI query object
Lets the plugin modify the HTTP headers that will be emitted when a
page is written to the browser. \%headers= will contain the headers
proposed by the core, plus any modifications made by other plugins that also
implement this method that come earlier in the plugins list.
<verbatim>
$headers->{expires} = '+1h';
</verbatim>

Note that this is the HTTP header which is _not_ the same as the HTML
&lt;HEAD&gt; tag. The contents of the &lt;HEAD&gt; tag may be manipulated
using the =Foswiki::Func::addToHEAD= method.

*Since:* Foswiki::Plugins::VERSION 2.0

=cut

#sub modifyHeaderHandler {
#    my ( $headers, $query ) = @_;
#}

=begin TML

---++ redirectCgiQueryHandler($query, $url )
   * =$query= - the CGI query
   * =$url= - the URL to redirect to

This handler can be used to replace Foswiki's internal redirect function.

If this handler is defined in more than one plugin, only the handler
in the earliest plugin in the INSTALLEDPLUGINS list will be called. All
the others will be ignored.

*Since:* Foswiki::Plugins::VERSION 2.0

=cut

#sub redirectCgiQueryHandler {
#    my ( $query, $url ) = @_;
#}

=begin TML

---++ renderFormFieldForEditHandler($name, $type, $size, $value, $attributes, $possibleValues) -> $html

This handler is called before built-in types are considered. It generates 
the HTML text rendering this form field, or false, if the rendering 
should be done by the built-in type handlers.
   * =$name= - name of form field
   * =$type= - type of form field (checkbox, radio etc)
   * =$size= - size of form field
   * =$value= - value held in the form field
   * =$attributes= - attributes of form field 
   * =$possibleValues= - the values defined as options for form field, if
     any. May be a scalar (one legal value) or a ref to an array
     (several legal values)

Return HTML text that renders this field. If false, form rendering
continues by considering the built-in types.

*Since:* Foswiki::Plugins::VERSION 2.0

Note that you can also extend the range of available
types by providing a subclass of =Foswiki::Form::FieldDefinition= to implement
the new type (see =Foswiki::Extensions.JSCalendarContrib= and
=Foswiki::Extensions.RatingContrib= for examples). This is the preferred way to
extend the form field types.

=cut

#sub renderFormFieldForEditHandler {
#    my ( $name, $type, $size, $value, $attributes, $possibleValues) = @_;
#}

=begin TML

---++ renderWikiWordHandler($linkText, $hasExplicitLinkLabel, $web, $topic) -> $linkText
   * =$linkText= - the text for the link i.e. for =[<nop>[Link][blah blah]]=
     it's =blah blah=, for =BlahBlah= it's =BlahBlah=, and for [[Blah Blah]] it's =Blah Blah=.
   * =$hasExplicitLinkLabel= - true if the link is of the form =[<nop>[Link][blah blah]]= (false if it's ==<nop>[Blah]] or =BlahBlah=)
   * =$web=, =$topic= - specify the topic being rendered

Called during rendering, this handler allows the plugin a chance to change
the rendering of labels used for links.

Return the new link text.

*Since:* Foswiki::Plugins::VERSION 2.0

=cut

#sub renderWikiWordHandler {
#    my( $linkText, $hasExplicitLinkLabel, $web, $topic ) = @_;
#    return $linkText;
#}

=begin TML

---++ completePageHandler($html, $httpHeaders)

This handler is called on the ingredients of every page that is
output by the standard CGI scripts. It is designed primarily for use by
cache and security plugins.
   * =$html= - the body of the page (normally &lt;html>..$lt;/html>)
   * =$httpHeaders= - the HTTP headers. Note that the headers do not contain
     a =Content-length=. That will be computed and added immediately before
     the page is actually written. This is a string, which must end in \n\n.

*Since:* Foswiki::Plugins::VERSION 2.0

=cut

#sub completePageHandler {
#    my( $html, $httpHeaders ) = @_;
#    # modify $_[0] or $_[1] if you must change the HTML or headers
#    # You can work on $html and $httpHeaders in place by using the
#    # special perl variables $_[0] and $_[1]. These allow you to operate
#    # on parameters as if they were passed by reference; for example:
#    # $_[0] =~ s/SpecialString/my alternative/ge;
#}

1;
__END__
This copyright information applies to the EmptyPlugin:

# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# EmptyPlugin is Copyright (C) 2008 Foswiki Contributors. Foswiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
# Additional copyrights apply to some or all of the code as follows:
# Copyright (C) 2000-2003 Andrea Sterbini, a.sterbini@flashnet.it
# Copyright (C) 2001-2006 Peter Thoeny, peter@thoeny.org
# and TWiki Contributors. All Rights Reserved. Foswiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
#
# This license applies to EmptyPlugin *and also to any derivatives*
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the Foswiki root.
