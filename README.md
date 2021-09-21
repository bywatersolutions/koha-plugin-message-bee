# MessageBee plugin for Koha

This plugin enables Koha to forward message data to Unqiue's MessageBee service for processing and sending.

# Downloading

From the [release page](https://github.com/bywatersolutions/koha-plugin-email-footer/releases) you can download the latest release in `kpz` format.

# Installation

This plugin requires no special installation. Simply download the kpz file from the releases page, then upload it to Koha from Administration / Plugins.

# Configuration

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

CHECKIN:
```
----
---
messagebee: yes
old_checkout: [% old_checkout %]
library: [% branch.id %]
----
```

HOLD:
```
---
messagebee: yes
hold: [% hold.id %]
```

PREDUE:

_advance_notices.pl *must* be run with the option `--itemscontent issue_id`_
```
---
messagebee: yes
checkout: <<items.content>>
```

PREDUEDGST:

_advance_notices.pl *must* be run with the option `--itemscontent issue_id`_
```
---
messagebee: yes
checkouts: [% FILTER replace('\n', ',') %]<<items.content>>[% END %]
```

DUE:

_advance_notices.pl *must* be run with the option `--itemscontent issue_id`_
```
---
messagebee: yes
checkout: <<items.content>>
```

DUEDGST:

_advance_notices.pl *must* be run with the option `--itemscontent issue_id`_
```
---
messagebee: yes
checkouts: [% FILTER replace('\n', ',') %]<<items.content>>[% END %]
```

OVERDUE NOTICES:
```
---
messagebee: yes
checkouts: [% FOREACH o IN overdues %][% o.id %],[% END %]
```
