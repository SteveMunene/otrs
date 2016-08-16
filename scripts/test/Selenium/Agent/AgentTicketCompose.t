# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

use Kernel::Language;

# get selenium object
my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        # get needed objects

        my $ConfigObject    = $Kernel::OM->Get('Kernel::Config');
        my $Helper          = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
        my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

        # disable check email addresses
        $ConfigObject->Set(
            Key   => 'CheckEmailAddresses',
            Value => 0,
        );

        # do not check RichText
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Frontend::RichText',
            Value => 0
        );

        # do not check service and type
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Ticket::Service',
            Value => 0
        );
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Ticket::Type',
            Value => 0
        );

        # disable RequiredLock for AgentTicketCompose
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Ticket::Frontend::AgentTicketCompose###RequiredLock',
            Value => 0
        );

        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Ticket::Frontend::AgentTicketCompose###DefaultArticleType',
            Value => 'email-internal'
        );

        # use test email backend
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'SendmailModule',
            Value => 'Kernel::System::Email::Test',
        );

        # get standard template object
        my $StandardTemplateObject = $Kernel::OM->Get('Kernel::System::StandardTemplate');

        # create a new template
        my $TemplateID = $StandardTemplateObject->StandardTemplateAdd(
            Name     => 'New Standard Template' . $Helper->GetRandomID(),
            Template => "Thank you for your email.
                             Ticket state: <OTRS_TICKET_State>.\n
                             Ticket lock: <OTRS_TICKET_Lock>.\n
                             Ticket priority: <OTRS_TICKET_Priority>.\n
                            ",
            ContentType  => 'text/plain; charset=utf-8',
            TemplateType => 'Answer',
            ValidID      => 1,
            UserID       => 1,
        );
        $Self->True(
            $TemplateID,
            "Standard template is created - ID $TemplateID",
        );

        # assign template to the queue
        my $Success = $Kernel::OM->Get('Kernel::System::Queue')->QueueStandardTemplateMemberAdd(
            QueueID            => 1,
            StandardTemplateID => $TemplateID,
            Active             => 1,
            UserID             => 1,
        );
        $Self->True(
            $Success,
            "$TemplateID is assigned to the queue.",
        );

        # get customer user object
        my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

        # add test customer for testing
        my $TestCustomer       = 'Customer' . $Helper->GetRandomID();
        my $CustomerEmail      = "$TestCustomer\@localhost.com";
        my $TestCustomerUserID = $CustomerUserObject->CustomerUserAdd(
            Source         => 'CustomerUser',
            UserFirstname  => $TestCustomer,
            UserLastname   => $TestCustomer,
            UserCustomerID => $TestCustomer,
            UserLogin      => $TestCustomer,
            UserEmail      => $CustomerEmail,
            ValidID        => 1,
            UserID         => 1
        );
        $Self->True(
            $TestCustomerUserID,
            "CustomerUserAdd - ID $TestCustomerUserID",
        );

        # set customer user language
        my $Language = 'es';
        $Success = $CustomerUserObject->SetPreferences(
            Key    => 'UserLanguage',
            Value  => $Language,
            UserID => $TestCustomer,
        );
        $Self->True(
            $Success,
            "Customer user language is set.",
        );

        # get ticket object
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # create test ticket
        my %TicketData = (
            State    => 'new',
            Priority => '4 high',
            Lock     => 'unlock',
        );
        my $TicketID = $TicketObject->TicketCreate(
            Title        => 'Selenium ticket',
            QueueID      => 1,
            Lock         => $TicketData{Lock},
            Priority     => $TicketData{Priority},
            State        => $TicketData{State},
            CustomerID   => 'SeleniumCustomer',
            CustomerUser => $TestCustomer,
            OwnerID      => 1,
            UserID       => 1,
        );
        $Self->True(
            $TicketID,
            "Ticket is created - ID $TicketID",
        );

        # create test email article
        my $ArticleID = $TicketObject->ArticleCreate(
            TicketID       => $TicketID,
            ArticleType    => 'email-external',
            SenderType     => 'customer',
            Subject        => 'some short description',
            Body           => 'the message text',
            Charset        => 'ISO-8859-15',
            MimeType       => 'text/plain',
            HistoryType    => 'EmailCustomer',
            HistoryComment => 'Some free text!',
            UserID         => 1,
        );
        $Self->True(
            $ArticleID,
            "Article is created - ID $ArticleID",
        );

        # create test user and login
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users' ],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # get script alias
        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');

        # navigate to created test ticket in AgentTicketZoom page
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AgentTicketZoom;TicketID=$TicketID");

        # click on reply
        $Selenium->execute_script(
            "\$('#ResponseID').val('$TemplateID').trigger('redraw.InputField').trigger('change');"
        );

        # switch to compose window
        $Selenium->WaitFor( WindowCount => 2 );
        my $Handles = $Selenium->get_window_handles();
        $Selenium->switch_to_window( $Handles->[1] );

        # wait without jQuery because it might not be loaded yet
        $Selenium->WaitFor( JavaScript => 'return document.getElementById("ToCustomer");' );

        # check AgentTicketCompose page
        for my $ID (
            qw(ToCustomer CcCustomer BccCustomer Subject RichText
            FileUpload StateID ArticleTypeID submitRichText)
            )
        {
            my $Element = $Selenium->find_element( "#$ID", 'css' );
            $Element->is_enabled();
        }

        $Self->Is(
            $Selenium->execute_script('return $("#ArticleTypeID option:selected").val()'),
            2,
            "Default article type is honored",
        );

        # test bug #11810 - http://bugs.otrs.org/show_bug.cgi?id=11810
        # translate ticket data tags (e.g. <OTRS_TICKET_State> ) in standard template
        $Kernel::OM->ObjectParamAdd(
            'Kernel::Language' => {
                UserLanguage => $Language,
            },
        );
        my $LanguageObject = $Kernel::OM->Get('Kernel::Language');

        for my $Item ( sort keys %TicketData ) {
            my $TransletedStateValue = $LanguageObject->Translate( $TicketData{$Item} );

            # check translated value
            $Self->True(
                index( $Selenium->get_page_source(), $TransletedStateValue ) > -1,
                "Translated \'$Item\' value is found - $TicketData{$Item} .",
            );
        }

        # input required fields and submit compose
        my $AutoCompleteString = "\"$TestCustomer $TestCustomer\" <$TestCustomer\@localhost.com> ($TestCustomer)";
        $Selenium->find_element( "#ToCustomer", 'css' )->send_keys($TestCustomer);

        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $("li.ui-menu-item:visible").length' );

        $Selenium->find_element("//*[text()='$AutoCompleteString']")->VerifiedClick();
        $Selenium->find_element( "#RichText",       'css' )->send_keys('Selenium Compose Text');
        $Selenium->find_element( "#submitRichText", 'css' )->click();

        $Selenium->WaitFor( WindowCount => 1 );
        $Selenium->switch_to_window( $Handles->[0] );

        # force sub menus to be visible in order to be able to click one of the links
        $Selenium->execute_script("\$('.Cluster ul ul').addClass('ForceVisible');");

        $Selenium->find_element("//*[text()='History']")->VerifiedClick();

        $Selenium->WaitFor( WindowCount => 2 );
        $Handles = $Selenium->get_window_handles();
        $Selenium->switch_to_window( $Handles->[1] );

        # wait until page has loaded, if necessary
        $Selenium->WaitFor( JavaScript => 'return typeof($) === "function" && $(".CancelClosePopup").length' );

        # verify that compose worked as expected
        my $HistoryText = "Email sent to \"\"$TestCustomer $TestCustomer\"";

        $Self->True(
            index( $Selenium->get_page_source(), $HistoryText ) > -1,
            "Compose executed correctly",
        );

        # delete created test ticket
        $Success = $TicketObject->TicketDelete(
            TicketID => $TicketID,
            UserID   => 1,
        );
        $Self->True(
            $Success,
            "Ticket with ticket ID $TicketID is deleted"
        );

        # delete standard template
        $Success = $StandardTemplateObject->StandardTemplateDelete(
            ID => $TemplateID,
        );
        $Self->True(
            $Success,
            "Standard template is deleted - ID $TemplateID"
        );

        # delete created test customer user
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        $TestCustomer = $DBObject->Quote($TestCustomer);
        $Success      = $DBObject->Do(
            SQL  => "DELETE FROM customer_user WHERE login = ?",
            Bind => [ \$TestCustomer ],
        );
        $Self->True(
            $Success,
            "Delete customer user - $TestCustomer",
        );

        # make sure the cache is correct
        for my $Cache (
            qw (Ticket CustomerUser )
            )
        {
            $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
                Type => $Cache,
            );
        }

    }
);

1;
