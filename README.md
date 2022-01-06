# MessageBee plugin for Koha

This plugin enables Koha to forward message data to Unqiue's MessageBee service for processing and sending.

NOTE: This plugin requires the patches for Koha community bug 29100

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

HOLD_CANCELLATION:
```
---
messagebee: yes
hold: [% hold.id %]
library: [% branch.id %]
biblio: [% biblio.id %]
item: [% item.id %]
patron: [% borrower.id %]
```

CANCEL_HOLD_ON_LOST:
```
---
messagebee: yes
hold: [% hold.id %]
library: [% branch.id %]
biblio: [% biblio.id %]
item: [% item.id %]
patron: [% borrower.id %]
```

PREDUE:
```
---
messagebee: yes
checkout: [% issue.issue_id %]
```

PREDUEDGST:
```
---
messagebee: yes
checkouts: [% FOREACH i IN issues %][% i.issue_id %],[% END %]
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
checkouts: [% FOREACH i IN issues %][% i.issue_id %],[% END %]
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
