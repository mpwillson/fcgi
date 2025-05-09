# FCGI Server implemented in Janet

## Introduction

This is an application server which implements the Fast CGI protocol to
receive requests from a web server. The server is written in Janet and
allows arbitrary Janet programs to be loaded to respond to FCGI
requests.

Based on the specification found at
<https://www.mit.edu/~yandros/doc/specs/fcgi-spec.html>

## Invocation

The FCGI server script is started by a command line of the form:

`
janet fcgi-server.janet [-c configuration-file] &
`

## Configuration

The FCGI server parameters are set via a configuration file. The
default configuration file locations are `/etc/fcgi-server.cfg` and
`/usr/local/etc/fcgi-server.cfg`. If neither of these files exist, a
default internal configuraton is used.

The default configuration file may be overridden by passing a
configuration file name via the -c command option. Failure to read the
specified configuration file, or syntax errors encountered while
processing the file, will cause the server to terminate.

The FCGI server offers the following configuration capabilities. The
settings shown are the defaults, if no configuration file is
specified.

### socket-file

The FCGI server communicates with the Web server via a Unix
socket. socket-file defines the pathname of the socket file:

`
socket-file: /tmp/fcgi.sock
`

If chroot is set, the socket-file path must be relative to the chroot.

### chroot

If not nil, the FCGI server will use the UNIX chroot call to set the
defined chroot path as the root of the processes filesystem. Uses
osx/chroot; see [osx](#osx) below, for more details.

`
chroot: nil
`

Use of chroot means the FCGI server must be invoked by root.

### user

If not nil, the FCGI server will set the effective user id of the
running janet process to user, using osx/setuid; see [osx](#osx).  The
ownership of the socket-file is also changed to user. This facility
should be used to drop privileges when the FCGI server is invoked by
root.

`
user: nil
`

### routes

The route keyword introduces a route; each route is defined with a url
and a Janet script to invoke when that url is encountered. See [FCGI
Scripts](#fcgi-scripts) below. If chroot is set, script path names
must be relative to the chroot location.

No routes are defined by default.

#### Example:
```
route: /fcgi/test : /fcgi/test.fcgi
route: /fcgi/list : /fcgi/list.janet
```

### route-param

route-param defines which CGI environment parameter the FCGI server
should consult to match route urls.

`
route-param: DOCUMENT_URI
`

### log-file

log-file defines the pathname of the log file. The file must be writable by the
effective user id of the Janet process running the FCGI server.

`
log-file: /tmp/fcgi.log
`

If chroot is set, the log-file pathname must be relative to the chroot.

### log-level

Defines the logging level required. The default of 0 logs major
actions and errors.  Increasing the value of log-level increases the
verbosity of the log file.

`
log-level: 3
`

## osx

The osx module implements a number of specialist Unix OS calls. See
<https://github.com/mpwillson/osx>.

To use the module, it must be installed system wide. Clone or download
the repository. Navigate to the osx directory and install with:

`
sudo jpm install
`

If the FCGI server cannot import the osx module, stub functions are
defined to avoid compilation errors.

## FCGI Scripts

When a url defined in routes is encountered, the script specified is
invoked. A script must provide the function `fcgi-main`, which
takes two arguments. The first is a table containing the CGI names and
values passed by the web server; both keys and values of the table are
strings. The second argument is the string received as stdin.

The `fcgi-main` function returns a string representing an HTML
response to the request received.  Any errors encounted while running
`fcgi-main` are trapped by the FCGI server and will be reported to
the web server.

### Example fcgi-main function

Assuming an existing Janet script runs as a CGI program (via a main
function), the following code will allow the script to run as an FCGI
script.

``` janet
 (defn fcgi-main
   "Enable CGI program to operate as an FCGI route. Set required environment
   variables from params and capture printed output using dynamic var."
   [params in]
   (each name ["DOCUMENT_ROOT" "REMOTE_ADDR" "QUERY_STRING"]
     (os/setenv name (params name)))
   (var output @"")
   (with-dyns [:out output] (main))
   output)
```

## OpenBSD httpd configuration

Add a stanza of the following form to the relevant server section in
the `/etc/httpd.conf` file:

``` conf
location "/fcgi/*" {
    fastcgi {
        socket "/run/fcgi.sock"
    }
}
```

The socket file definition should match that provided to the
fcgi-server via the configuration file.

## Testing

To (minimally) test the FCGI server prior to installation, issue the command:

`
jpm -l install && jpm -l test
`

## Installation

To install system-wide:

`sudo make install
`

This will run `jpm install` and copy the default configuration file to
`/usr/local/etc/`.

## Caveats

The FCGI server is single-threaded.  Not recommended for high traffic
environments (or, indeed, low traffic environments).
