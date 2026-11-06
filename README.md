# MessageBee plugin for Koha

This plugin enables Koha to forward message data to Unqiue's MessageBee service for processing and sending.

NOTE: This plugin requires the patches for Koha community bug 29100

# Downloading

From the [release page](https://github.com/bywatersolutions/koha-plugin-message-bee/releases) you can download the latest release in `kpz` format.

# Installation

This plugin requires no special installation, but will require acceptance of the host key for the UniqueMgmt sftp server as the Koha web user (sudo koha-shell <instance>, ssh <unique's sftp address>, accept host key)

# Configuration

## SFTP connection

As of version 4.0 the SFTP connection to MessageBee is configured as a Koha **file transport** (Administration &gt; File transports), not through the plugin itself. Create an SFTP file transport with UMS's host, username, and password, set its upload directory (`cust2unique` unless UMS tells you otherwise), then open the plugin's configuration page and select that transport.

When you upgrade from an older (3.x) version, the plugin automatically migrates the host, username, and password it used to store into a new file transport, with the upload directory set to `cust2unique`. If MessageBee gave you a different directory, change it on the file transport after upgrading.

## Environment variables

There are a number of environment variables that can be set to change the behavior of the MessageBee plugin:
* MESSAGEBEE_ARCHIVE_PATH - If this is set to a directory, a copy of the file uploaded to UMS will be stored here. The directory is best created in /var/lib/koha/<instance>/messagebee_archive
* MESSAGEBEE_TEST_MODE - If MESSAGEBEE_TEST_MODE is set to 1, the JSON file will be generated but messages in the queue will not be updated
* MESSAGEBEE_VERBOSE - If MESSAGEBEE_VERBOSE is set to 1, the plugin will output extra info when process_message_queue.pl is run



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
* `suggestion` - suggestions.suggestionid, auto-imports patron, library, biblio and biblioitem
* `ill_request` - illrequests.illrequest_id, auto-imports patron, library, request attributes, biblio and biblioitem
* `credit` - accountlines.accountlines_id of a payment or writeoff, auto-imports patron, library and the fees it paid off
* `recall` - recalls.recall_id, auto-imports patron, pickup library, item, biblio and biblioitem
* `curbside_pickup` - curbside_pickups.id, auto-imports patron and library
* `article_request` - article_requests.id, auto-imports patron, library, item, biblio and biblioitem
* `booking` - bookings.booking_id, auto-imports patron, pickup library, item, biblio and biblioitem

Example notices:

CHECKOUT:
```
----
---
messagebee: yes
checkout: [% checkout.id %]
library: [% branch.id %]
#Title: [% checkout.item.biblio.title %] [% checkout.item.biblio.subtitle %]
#Barcode: [% checkout.item.barcode %]
----
```

RENEWAL:
```
----
---
messagebee: yes
checkout: [% checkout.id %]
library: [% branch.id %]
#Title: [% checkout.item.biblio.title %] [% checkout.item.biblio.subtitle %]
#Barcode: [% checkout.item.barcode %]
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
#Title: [% old_checkout.item.biblio.title %] [% old_checkout.item.biblio.subtitle %]
#Barcode: [% old_checkout.item.barcode %]
----
```

HOLD:
```
---
messagebee: yes
hold: [% hold.id %]
#Title: [% hold.biblio.title %] [% hold.biblio.subtitle %]
#Barcode: [% hold.item.barcode %]
```

HOLDDGST:
```
----
---
messagebee: yes
hold: [% hold.id %]
#Title: [% hold.biblio.title %] [% hold.biblio.subtitle %]
#Barcode: [% hold.item.barcode %]
----
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
patron: [% borrower.id %]
#Title: [% hold.biblio.title %] [% hold.biblio.subtitle %]
#Barcode: [% hold.item.barcode %]
```

CANCEL_HOLD_ON_LOST:
```
---
messagebee: yes
old_hold: [% hold.id %]
library: [% branch.id %]
patron: [% borrower.id %]
#Title: [% hold.biblio.title %] [% hold.biblio.subtitle %]
#Barcode: [% hold.item.barcode %]
```

NOTE: Predue notices require Koha bug 29100.

PREDUE:
```
---
messagebee: yes
patron: [% borrower.id %]
checkout: [% checkout.issue_id %]
#Title: [% checkout.item.biblio.title %] [% checkout.item.biblio.subtitle %]
#Barcode: [% checkout.item.barcode %]
```

PREDUEDGST:
```
---
messagebee: yes
patron: [% borrower.id %]
checkouts: [% FOREACH c IN checkouts %][% c.issue_id %],[% END %]
```

DUE:
```
---
messagebee: yes
checkout: [% checkout.issue_id %]
#Title: [% checkout.item.biblio.title %] [% checkout.item.biblio.subtitle %]
#Barcode: [% checkout.item.barcode %]
```

DUEDGST:
```
---
messagebee: yes
checkouts: [% FOREACH c IN checkouts %][% c.issue_id %],[% END %]
```

AUTO_RENEWALS:
```
---
messagebee: yes
checkout: [% checkout.id %]
#Title: [% checkout.item.biblio.title %] [% checkout.item.biblio.subtitle %]
#Barcode: [% checkout.item.barcode %]
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
#Expiration date: [% borrower.dateexpiry %]
```

WELCOME:
```
---
messagebee: yes
patron: [% borrower.id %]
library: [% branch.id %]
```

NOTE: The same template works for every purchase suggestion status notice, such as REJECTED, ORDERED and AVAILABLE.

ACCEPTED:
```
---
messagebee: yes
suggestion: [% suggestion.suggestionid %]
library: [% branch.id %]
#Title: [% suggestion.title %]
```

NOTE: The same template works for ILL_REQUEST_UNAVAIL and ILL_REQUEST_UPDATE.

ILL_PICKUP_READY:
```
---
messagebee: yes
ill_request: [% illrequest.illrequest_id %]
library: [% branch.id %]
#Title: [% ill_bib_title %]
```

NOTE: The same template works for ACCOUNT_PAYMENT. The "Email receipt" button on a patron's account sends the notice right away. Add `messagebee_immediate: yes` if it should reach MessageBee right away too, instead of on the next process_message_queue.pl run.

ACCOUNT_WRITEOFF:
```
---
messagebee: yes
credit: [% credit.accountlines_id %]
library: [% branch.id %]
```

PICKUP_RECALLED_ITEM:
```
---
messagebee: yes
recall: [% recall.recall_id %]
library: [% recall.pickup_library_id %]
#Title: [% biblio.title %]
#Barcode: [% item.barcode %]
```

NOTE: RETURN_RECALLED_ITEM goes to the patron who has the item checked out, and Koha gives that notice the checkout rather than the recall, so use the `checkout` key there.

RETURN_RECALLED_ITEM:
```
---
messagebee: yes
checkout: [% checkout.issue_id %]
patron: [% borrower.borrowernumber %]
#Title: [% biblio.title %]
#Barcode: [% item.barcode %]
```

NOTE: The holds line lists the patron's holds waiting at the pickup library, the same ones the default notice shows.

NEW_CURBSIDE_PICKUP:
```
---
messagebee: yes
curbside_pickup: [% curbside_pickup.id %]
library: [% branch.id %]
holds: [% FOREACH h IN curbside_pickup.patron.holds %][% IF h.branchcode == curbside_pickup.branchcode && h.found == 'W' %][% h.id %],[% END %][% END %]
#Pickup time: [% curbside_pickup.scheduled_pickup_datetime %]
```

NOTE: The same template works for AR_REQUESTED, AR_PROCESSING, AR_COMPLETED and AR_CANCELED.

AR_PENDING:
```
---
messagebee: yes
article_request: [% article_request.id %]
library: [% branch.id %]
#Title: [% biblio.title %]
```

NOTE: The same template works for BOOKING_MODIFICATION and BOOKING_CANCELLATION.

BOOKING_CONFIRMATION:
```
---
messagebee: yes
booking: [% booking.booking_id %]
library: [% booking.pickup_library_id %]
#Title: [% booking.biblio.title %]
```
