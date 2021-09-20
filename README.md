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
* `message` - message_queue.message_id - Sends the message queue data, this should always be transmitted as well
* `biblio` - biblio.biblionumber
* `item` - items.itemnumber
