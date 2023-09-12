# MessageBee plugin for Koha

This plugin enables Koha to forward message data to Unqiue's MessageBee service for processing and sending.

NOTE: This plugin requires the patches for Koha community bug 29100

# Downloading

From the [release page](https://github.com/bywatersolutions/koha-plugin-message-bee/releases) you can download the latest release in `kpz` format.

# Installation

This plugin requires no special installation. Simply download the kpz file from the releases page, then upload it to Koha from Administration / Plugins.

# Configuration

There are a number of envirnment variables that can be set to change the behavior of the MessageBee plugin:
* MESSAGEBEE_ARCHIVE_PATH - If this is set to a directory, a copy of the file uploaded to UMS will be stored here
* MESSAGEBEE_TEST_MODE - If MESSAGEBEE_TEST_MODE is set to 1, the JSON file will be generated but messages in the queue will not be updated
* MESSAGEBEE_VERBOSE - If MESSAGEBEE_VERBOSE is set to 1, the plugin will output extra info when process_message_queue.pl is run
* MESSAGEBEE_SFTP_DIR - If MESSAGEBEE_SFTP_DIR is set to a path, that path will be used on the remote SFTP server instead of the default `cust2unique`

# Notice templates

To send a message to MessageBee instead of having Koha process and send the notice locally,
the message content must be a YAML blob of key/value pairs. The only one that is required
is `messagebee: yes` which tells the plugin this message is destined for MessageBee.

Other keys you may use are:
* `biblio` - biblio.biblionumber
* `biblioitem` - biblioitems.biblioitemnumber
* `item` - items.itemnumber
* `library` - branches.branchcode
* `patron` - borrowers.borrowernumber
* `checkout` - issues.issue_id, auto-imports patron, library, item, biblio and biblioitem
* `checkouts` - repeating comma delimited issues.issue_id

Example notices:

CHECKOUT:
```
----
---
messagebee: yes
checkout: [% checkout.id %]
library: [% branch.id %]
----
```

RENEWAL:
```
----
---
messagebee: yes
checkout: [% checkout.id %]
library: [% branch.id %]
----
```

CHECKIN:
```
----
---
messagebee: yes
old_checkout: [% old_checkout.issue_id %]
patron: [% borrower.borrowernumber %]
library: [% branch.id %]
----
```

HOLD:
```
---
messagebee: yes
hold: [% hold.id %]
```

HOLD_REMINDER:
```
---
messagebee: yes
holds: [% FOREACH h IN holds %][% h.id %],[% END %]
```

HOLD_CANCELLATION:
```
---
messagebee: yes
old_hold: [% hold.id %]
library: [% branch.id %]
```

CANCEL_HOLD_ON_LOST:
```
---
messagebee: yes
old_hold: [% hold.id %]
library: [% branch.id %]
```

NOTE: Predue notices require Koha bug 29100.

PREDUE:
```
---
messagebee: yes
checkout: [% checkout.issue_id %]
```

PREDUEDGST:
```
---
messagebee: yes
checkouts: [% FOREACH c IN checkouts %][% c.issue_id %],[% END %]
```

DUE:
```
---
messagebee: yes
checkout: [% issue.issue_id %]
```

DUEDGST:
```
---
messagebee: yes
checkouts: [% FOREACH i IN issues %][% i.issue_id %],[% END %]
```

AUTO_RENEWALS:
```
---
messagebee: yes
checkout: [% checkout.id %]
```

AUTO_RENEWALS_DGST:
```
---
messagebee: yes
checkouts: [% FOREACH c IN checkouts %][% c.issue_id %],[% END %]
```

OVERDUE NOTICES:
```
---
messagebee: yes
checkouts: [% FOREACH o IN overdues %][% o.id %],[% END %]
```

MEMBERSHIP_EXPIRY:
```
---
messagebee: yes
patron: [% borrower.borrowernumber %]
```
