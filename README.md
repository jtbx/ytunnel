ytunnel downloads YouTube content, whether it be audio or video, in large
quantities. It takes as its input a file containing a list of URLs, and
then downloads each YouTube video specified in this list, and converts it
to your desired format.

For documentation run `man ytunnel` or view the manual page online:
    https://jtbx.codeberg.page/man/ytunnel.1

## Building

First run the configure script which will generate a portable Makefile
tailored for your system. Supported D compilers are dmd and ldc.

(If you're trying to build in debug mode, pass configure the `-d` flag)

    ./configure

Now simply running make will compile the project.

    make

After this you will have an executable created in the current directory
named `ytunnel`. Use `make install` to copy this and the man page to
/usr/local, or copy it to a place in PATH yourself (this won't install
the man page).
