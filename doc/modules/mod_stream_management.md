### Module Description
Enables [XEP-0198: Stream Management](http://xmpp.org/extensions/xep-0198.html). 
It is implemented mostly in `ejabberd_c2s`. 
This module is just a "starter", to supply the configuration values to new client connections.
It also provides a basic session table API and adds a new stream feature.

### Options

* `buffer_max` (default: 100): Buffer size for messages yet to be acknowledged.
* `ack_freq` (default: 1): Frequency of ack requests sent from the server to the client, e.g. 1 means a request after each stanza, 3 means a request after each 3 stanzas.
* `resume_timeout` (default: 600): Timeout for the session resumption. Sessions will be removed after the specified number of seconds.

### Example Configuration

```
  {mod_stream_management, [{buffer_max, 30},
                           {ack_freq, 1},
                           {resume_timeout, 600}
                          ]},
```

