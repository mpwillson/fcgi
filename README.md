# FCGI Server implemented in Janet

## Introduction

This is an application server which implements the Fast CGI protocol to
receive requests from a web server. The server is written in Janet and
allows arbitrary Janet programs to be loaded to respond to FCGI
requests.

Based on the specification found at
<https://www.mit.edu/~yandros/doc/specs/fcgi-spec.html>

## Configuration

The FCGI server is configured through an imported Janet script. The
server script first looks for a file in the same directory as
server.janet, called `config-${HOSTNAME}.janet`.

If the file is not found, `config.janet` is imported. Failure to find
a configuration file will cause the server to terminate.

The FCGI server offers the following configuration capabilities. All
configuration elements  must be defined.

### socket-file

The FCGI server communicates with the Web server via a Unix
socket. socket-file defines the pathname of the socket file:

`
(def socket-file "/tmp/fcgi.sock")
`


If chroot is set, the socket-file path must be relative to the chroot.

### chroot


If not nil, the FCGI server will use the UNIX chroot call to set the
defined chroot path as the root of the processes filesystem. Uses
osx/chroot; see [osx](#osx) below, for more details.

`
(def chroot "/var/www")
`

Use of chroot means the FCGI server must be invoked by root.

### user

If not nil, the FCGI server will set the effective user id of the
running process to user.  This can be used to drop privileges when the
FCGI server is invoked by root.

`
(def user "www")
`

### routes

routes is defined as an array of structs. Each struct
defines a url and a Janet script to invoke when that url is
encountered. See [FCGI Scripts](#fcgi-scripts) below.

``` janet
(def routes [{:url "/fcgi/test" :script "/test.fcgi"}
             {:url "/fcgi/list" :script "/fcgi/list.fcgi"}])
```

### route-param

route-param defines which CGI environment parameter the
FCGI server should consult to match route urls.

`
(def route-param "DOCUMENT_URI")
`

### log-file

log-file defines the pathname of the log file. The file must be writable by the
effective user id of the Janet process running the FCGI server.

`
(def log-file "fcgi.log")
`

If chroot is set, the log-file pathname must be relative to the chroot.

### log-level

Defines the logging level required. The default of 0 logs major
actions and errors.  Increasing the value of log-level increases the
verbosity of the log file. NB Not really implemented yet.

`
(def log-level 0)
`

## osx

The osx module implements a number of specialist Unix OS calls. See
<https://github/com/mpwillson/osx>.

To use the module, it must be installed system wide. If the FCGI
server cannot import the osx module, stub functions are defined
to avoid compilation errors.

## FCGI-Scripts

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

Assuming an existing Janet script runs as a CGI program, the following
code will allow the script to run as an FCGI script.

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
