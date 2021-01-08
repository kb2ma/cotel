Cotel is a GUI tool for exploration of CoAP messaging. Cotel focuses on a client sending a request to a server and then displaying the responses.

This guide provides details and tips on how to use Cotel. For installation instructions see the top-level project README. The sections below are organized by the title of menu selections.

# Orientation
Once you start Cotel, it's functionality is available via selections from the menu bar, including:

|Selection                            |Purpose                                                                                   |
|-------------------------------------|------------------------------------------------------------------------------------------|
|[New Request](./snap-request.png)    |Create and send a request, and view response                                              |
|[Local Setup](./snap-setup.png)      |Setup security parameters and Request defaults; optionally setup a CoAP server for testing|
|[View Network Log](./snap-netlog.png)|Show recent network activity; useful to confirm operation                                 |
|Info                                 |Show location of log files, for a full view of activity                                   |

These functions are described in the sections below. The links above are to screenshots for reference. Finally, the *Internals* section identifies the files that comprise a Cotel installation and describes their purpose.

## Messaging and Security
Cotel support CoAP messages sent over UDP transport. A request may be secured with pre-shared key based DTLS.

# New Request

The New Request view allows you to define a request, send it to a server, and view the responses.

## Basic Fields

Protocol, Port, and Host define where to send the request. Use of `coaps` protocol means to use a DTLS pre-shared key to encrypt the request, as defined in the Local Setup view. For Host you may use either an IPv4/IPv6 address or a host name.

URI Path is encoded as one or more options in the CoAP request, but we provide a single field for ease of use. You may percent-encode characters as UTF-8, in a form like `%A7`. The URI Path field does not support inclusion of a query.

If you select Method as PUT or POST, a Payload field appears, as described in the section below.

If you select Confirm, and a response is not received within a couple of seconds, the message will be resent using CoAP's exponential backoff mechanism. Use the Network Log view to follow when a message is resent.

A Token is included automatically in the request based on the token length defined in the Local Setup view.

## Options

This section allows addition of options to the request. Click on the Options bar to show the entry area. Click the New button to enter addition mode. Then select the option type and enter the option value. After pressing OK to save an option, you may reuse the same entry fields for another option. This approach makes it easier to enter repetitive options, like Uri-Query.

For background on available options, see the relevant section of the [IANA CoRE Parameters](https://www.iana.org/assignments/core-parameters/core-parameters.xhtml#option-numbers) page. You may enter options in any order, and they will be sorted by option number in the request message.

An option value is one of three types, which determines its format:

| Type |Description                                                                                           |
|------|------------------------------------------------------------------------------------------------------|
|string|Supports only ASCII text                                                                              |
|  uint|Non-negative integer. The Accept and Content-Format types provide a dropdown for the available values.|
|opaque|Pair of hex digits for each octet, like `40` or `B9`. You may use a space between each pair.          |
|

## Payload

When the Method field is PUT or POST, the Payload multi-line text area appears. You may select either Text or Hex as the mode for entry of the payload, and switch between them. However, you cannot directly enter text if the payload data includes non-ASCII characters. In text mode, non-ASCII characters appear as a Unicode 00B7 middle dot.

The payload entry area does not automatically wrap entry data. However, you can manually start a new line by pressing Enter. Any end of line characters embedded in the text area will be excluded from the actual request payload.

## Send/Reset

Once you have entered all of the request information, press Send. Normally you will see the server's response in the Response section, as described below. However, if there is an error when sending, a message will appear in red below the Send button.

As mentioned above in the Basic Fields section, if the network medium is lossy and you select the Confirm option, a message may be resent a few times. See the View Network Log view to track these retries.

Also, a server response may include a Block2 option, which indicates if there are more blocks in a complete response. Cotel will indicate this situation with text at the top of the Response section below. It also will request the next follow-on block automatically as it receives each response. Finally, the Response section indicates when all blocks have been received.

The Reset button clears some of the basic fields, all options, and any response present on the request view.

## Response

The response to a request appears below the Send and Reset buttons. It shows "complete" when no more responses are expected. (As described above a request may receive multiple responses that include a Block2 option.)

The response area shows the CoAP code for the response, as well as any options and any payload. For more about options and the payload, see the descriptions above. For a response, you may only view the options and response; they are read-only.

# Local Setup

The Local Setup view allows you to configure various kinds of support for messaging.

## Request
Token Length specifies the count in bytes for a request token. The token contents are generated randomly for each request.

## coaps Pre-Shared Key
This section sets up the Pre-Shared Key mode for DTLS security. All requests sent with the `coaps` protocol use the same key regardless of destination server.

Similar to a request payload, you may specify the key as ASCII text or hex digits. In text mode, non-ASCII octets appear as a Unicode 00B7 middle dot. We recommend use of hex mode because it provides a wider range of data for the key. The key may define up to 64 octets.

Client ID may be used by a server to identify the client. This ID must be entered as ASCII text.

See [RFC 7925](https://tools.ietf.org/html/rfc7925) for an informative presentation on the use of DTLS for IoT.

## Server (experimental)
You may run a local CoAP server within Cotel for testing purposes. For example, you can open one instance of Cotel on your workstation as a test server, and a second instance on the same workstation to send CoAP requests to the first.

This section of the Setup view allows you to configure the port and listening address for the server. To listen on all network interfaces, use the IPv6 `::` address or the IPv4 `0.0.0.0` address. For the coaps protocol, the server uses the DTLS key defined above.

### Resources
The server provides a couple of basic resources listed below, which are based on the ETSI CoAP plugtest [specification](https://rawgit.com/cabo/td-coap4/master/base.html). The Test IDs are relative to the "TD_COAP_CORE" identifier, e.g. TD_COAP_CORE_03.

|Resource |Method|Test ID   |Notes                                                                                                                             |
|---------|------|----------|----------------------------------------------------------------------------------------------------------------------------------|
|  /test  |   GET|01, 05, 12|The payload for this resource is arbitrary.                                                                                       |
|  /test  |   PUT|03, 07    |                                                                                                                                  |
|  /test  |  POST|04, 08    |                                                                             Creation response includes a Location-Path option    |
|  /test  |DELETE|02, 06    |After DELETE, the response to a PUT or POST indicates resource creation (2.01)                                                    |
|/validate|  GET |21        |If the request includes a valid ETag, response code is 2.03. Otherwise, response code is 2.05 and the payload is returned as well.|

# View Network Log and Info

The network log view provides a scrolling list of the last 100 entries from the network log. The actual log, `net.log`, is stored in a temporary directory as shown in the Info view.

In addition to the location of the log temporary directory, the Info view shows basic descriptive information about Cotel, like the version number.

# Cotel Internals

Internally Cotel uses the files below to operate.

|Files             |Function                                                                                                                                 |
|------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
|cotel, cimgui.so  |Executable and UI library                                                                                                                |
|cotel.conf        |Application configuration, found in `$HOME/.config/cotel/`. Contains the settings from the Local Setup view.                             |
|cotel.dat, gui.dat|Latest application window positions and sizes, also stored in `$HOME/.config/cotel/`.                                                    |
|net.log, gui.log  |Logs of network and UI events. Stored in a temporary directory for a running instance of Cotel. See the Info view for the directory name.|