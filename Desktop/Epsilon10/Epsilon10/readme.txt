Notes on Epsilon 10.00

This file describes changes since beta versions of Epsilon 10.  See
http://www.lugaru.com/rel10.html or the online manual for
descriptions of all new features since Epsilon 9.

Epsilon's complete manual is included in various electronic forms.
Info format can be read from within Epsilon.  The HTML version of the
manual can be read with a web browser.  A WinHelp version is also
included on Windows platforms.  Press F1 followed by F, H, or W,
respectively, to access each version.


Epsilon 10.00 has no significant changes from beta 9c.

Bugs Fixed in Beta 9c
=====================

Epsilon for FreeBSD could deadlock when sending very large blocks of
input to a concurrent process.

The suspend-epsilon command now works under FreeBSD in terminal mode.

Epsilon for Unix, in terminal mode, now looks for the terminfo
database in more places.

When Epsilon for Windows displays a right-click menu, it no longer
positions point to the place you clicked.  (The positioning feature
introduced in beta 9 was removed.)

Epsilon's warning message about older state files that require a
-quickup is now enabled in non-Unix versions too.

A query-replace on a read-only buffer now provides an appropriate
error message.

Pressing { in TeX/LaTeX mode now inserts a matching } before } or $
characters or at the end of the buffer, as well as before whitespace.


Changes in Beta 9
=================

Epsilon for Unix now uses a session file named epsilon.ses (as in
other versions), not .epsilon.ses.  Copy ~/.epsilon/.epsilon.ses to
~/.epsilon/epsilon.ses if you want to keep the session file contents
from previous beta versions.

In Epsilon for Unix, the -w32 flag was removed, and the rules for
interpreting the EPSPATH environment variable have changed.  Formerly
Epsilon acted as if the directory ~/.epsilon was the first element on
an EPSPATH, whether you specified it or not, unless you used the -w32
flag.  Now the ~/.epsilon directory must appear explicitly, if you
have an EPSPATH.  It should normally be the first element on your
EPSPATH.  In a typical installation, no EPSPATH environment variable
is needed, and Epsilon behaves the same as before.

The identifier completion facility has been removed.  A revised
version may appear later.  You can find this facility as a
downloadable extension on our web site.

Editing is no longer slow in large Perl buffers due to automatic
delimiter highlighting and related features.

Typing a curly brace { in TeX or LaTeX modes now omits inserting a
matching } character before a non-whitespace character.

The default for the auto-show-adjacent-delimiter variable is now 3,
not 1.

%f is now permitted in show-when-idle text, so you can make Epsilon
put the current function's name in the echo area instead of the mode
line or window title.

The write-region and insert-file commands provide a default file name
based on the current file's directory, not the previous file name
used with these commands.  Type Alt-e to get the previous file name.

Epsilon interprets <? ?> in HTML files as an indication of Javascript.

When Epsilon displays a right-click menu, it first positions point to
the place you clicked.

Tagging omits some status messages, and is faster as a result.

The want-display-function-name variable was renamed
display-definition.

Various bugs were fixed.


Bugs fixed in Beta 8c
=====================

Epsilon would crash sometimes when an Internet operation completed.

Alt-' and perhaps other commands crashed in Epsilon for Unix under
terminal mode.

Epsilon for Unix could deadlock when sending very large blocks of
input to a concurrent process.

Some problems generate correct key codes under X and in the Win32
console version were fixed.

Changes in Beta 8
=================

New Features in Beta 8:
-----------------------

Epsilon now includes the complete manual in HTML format, readable
with a web browser.  Press F1 H to view it.

The default tab size outside of C mode is now 8.  It remains 4 inside
C mode.

Various commands that prompt for a file now display the current
directory.

When point is at the very end of the buffer, Epsilon displays End in
the mode line, not Bot (which indicates that the bottom of the buffer
is visible in the window, but point isn't there).

By default, the Make command now runs in the current buffer's directory.

The dired command now uses month names, not numbers.

The grep command records the current directory for each invocation;
this means it no longer becomes confused if you change directories.

New customization variables include tex-auto-fill-mode,
color-html-look-back, push-cmd-unix-interactive,
find-linked-file-ignores-angles, print-long-lines-wrap, and
session-file-name.

Epsilon for Unix uses a different approach for setting up certain
process buffer characteristics, inserting its commands at the front
of each interactive process buffer.

The Alt-x man command now produces a buffer where you can
double-click on links to other man pages, or press m to run Alt-x man
on a different topic.

The fill-paragraph command accepts a numeric argument over 5 as a
temporary margin.  A lower value still means to use an infinite
margin (unfill).

The command print-buffer-no-prompt is new.

The variable cursor-blink-rate was renamed cursor-blink-period.  The
command info-epsilon-manual was renamed epsilon-manual-info, and the
command info-epsilon-look-up was renamed epsilon-info-look-up.

The new variable default-character-set lets you tell Epsilon for
Windows to translate from the DOS/OEM character set for all files.
The new command find-unconverted-file lets you override this for a
particular file.

Epsilon uses new rules for detecting when to automatically enter Conf
mode (designed for generic Unix configuration files).

Epsilon now recognizes the extensions .js, .xsl, .jsp, .sgml, and
.sgm for HTML mode, and .csh for Shell mode.

Epsilon now auto-highlights delimiters only in the current window.

The count-lines command now displays the line count of a highlighted
region, if any.

The write-region command now works with FTP URL's.

The save-all-buffers command saves anonymous buffers (created by the
File/New command) after all named buffers.

The unbind-key command asks if you really wanted to make a key
self-insert, not be unbound.

Killing an empty region now creates a 0-length kill buffer.

If the process-enter-whole-line variable is 2, Epsilon copies old lines to
the end of the buffer to make it easier to repeat commands.

When the Make command reports no errors, it mentions the command it ran.

PostScript coloring detects and skips over some types of embedded
binary data.

The HTML syntax highlighter recognizes <% %> as JavaScript delimiters.

Very large HTML buffers are colored faster.


Bugs Fixed in Beta 8:
---------------------

Tagging searches more thoroughly when a tag is missing.

Tagging doesn't offer to retag a file unless it knows how to do so.

The undo-changes command no longer locks up in certain narrowed buffers.

The Win32 console version now works better with the large console
scrollback buffers found in Windows 2000.

Epsilon for DOS's -ka32 flag no longer has trouble with file patterns.

The Sendeps.exe program works when multiple files are dropped at once.

Identifier completion no longer hangs when it sees certain accented
characters.

Certain Internet-related functions now work when Epsilon for Unix
uses its NSS helper program.

Another bug in find-linked-file was fixed.

Resynchronizing in compare-windows now works when the buffer contains
null characters.

File name completion works better with file names containing spaces.

Process buffer completion on the Tab key was removed; a rewritten
version may appear later.

Perl coloring now works properly with format statements.

The Win32 console version now operates properly when you press Ctrl-C
while pushed.

Internet primitives now work properly in synchronous mode.

Non-passive FTP operations work again.

Composed characters now work under X.

The create-file-associations command now includes Epsilon's path.

Epsilon for X now respects position settings in the -geometry flag.

Very long file names no longer cause Epsilon to crash.


Changes in Beta 5
=================

New Features in Beta 5:
-----------------------

Language Modes:

Epsilon has new modes for PostScript files, Unix shell scripts and
configuration files, and files in the GAMS mathematical modeling
language.

In LaTeX mode, Epsilon now defaults to inserting LaTeX 2e/3 commands,
not LaTeX 2.09 commands.  Set the latex-2e-or-3 variable to change
this.  If you insert a LaTeX environment block and type the name of a
new environment, Epsilon will remember it and offer it for completion
in the future.  The jump-to-dvi command is now bound to Alt-Shift-J
in TeX/LaTeX modes.

Syntax highlighting for Javascript embedded in HTML pages is now much
faster.

Epsilon uses slightly different default colors in HTML and Perl files.

Tagging works better, especially for Perl files.  Perl's indenting
rules were improved too.  The delete-tags-for-file command has been
renamed untag-files.

Concurrent Process:

Epsilon for Unix now supports multiple concurrent processes.  Rename
the concurrent process buffer using Alt-x rename-buffer and the
start-process command on Ctrl-X Ctrl-M will create a second
concurrent process.  Epsilon's compilation commands also use this
feature, and compile in a separate concurrent process buffer.
Various process-related commands have been modified to support this.

In the process buffer, type part of a file name and press <Tab>, and
Epsilon will perform completion on the file name.

Epsilon for Unix modifies the prompt of any shell it runs
concurrently, via some initialization files it installs into the
/etc/profile.d directory.  This lets Epsilon more reliably detect
when a shell prompts for input, and what its current directory is.
(If your shell prompt in a concurrent process buffer changes its
color after you type a command and press <Enter>, then your shell's
initialization script isn't sourcing Epsilon's initialization file as
it should.)

Other Features:

The dired command now displays its results as it goes, whenever it
searches multiple directories or entire hierarchies.  In Unix, dired
now works better when coloring and following symbolic links.

The new locate-file command looks for a file by name, searching all
local drives.  For Unix, this command looks through particular parts
of the directory hierarchy; see the locate-path-unix variable.  The
rename-buffer and suspend-epsilon commands are also new.

Epsilon's searching commands no longer have a 255 character limit on
the search string.

The grep command now colors separator lines for easier visibility.
By default it now skips over files with certain extensions: .o, .b,
.obj, and .exe.  Set the grep-ignore-file-extensions variable to
modify this list.

Epsilon now tags structure members in named structures, recording
them using the C++ notation structname::member.

The <Space> and <Backspace> keys now page forward and backward in all
read-only buffers.  Set the new readonly-pages variable to zero to
disable this.

When Epsilon for Unix runs as an X program, its messages warning
about expiration now appear in an X window, not on its standard
output.

When an X window manager like KDE exits, it tries to record a command
line for each running program so that the command may be restarted.
Epsilon now provides a suitable command line to it.

Epsilon's graphical Windows executable is now named epsilon.exe, not
e32.exe.  Epsilon's console Windows executable is now named
epsilonc.exe, not epsilon.exe.

When printing a buffer in Epsilon for Windows, you can now include
line numbers if you set the print-line-numbers variable nonzero.


Changes to Primitives in Beta 5:
--------------------------------

To support multiple concurrent processes, the primitives
concur_shell(), halt_process(), process_input(), and process_kill()
now take additional optional parameters.  The is_process_buffer()
primitive was added, and the process_exit_status variable.  Also,
process input and output now run EEL code using a different interface
based on the one used for Internet activity.

The EEL syntax for specifying color choices now provides for default
settings for a color class.  You can specify that a color class
should normally be the same as some existing color class, or that it
should normally use blue text, for example.  You can then override
these settings for particular color schemes, as necessary.  Some new
macros ECOLOR_UNKNOWN and ECOLOR_COPY in color definitions represent
the new possibilities.  The primitives get_foreground_color() and
get_background_color() now take an optional second parameter to
retrieve color settings without defaulting rules applied.

The filename_rules() primitive returns new flags that indicate (for
non-Unix environments) whether a drive refers to a CD-ROM, network
drive, removable, or a local hard drive.

The signal_suspend() and set_file_opsys_attribute() primitives are
new.


Other Bugs Fixed in Beta 5:
---------------------------

The Win32 Console version of Epsilon now handles accented characters
properly.  Moving the mouse no longer causes flickering.

EEL's realloc() primitive no longer corrupts memory when asked to
shrink a block.

When Epsilon for Unix used its NSS helper, its Internet commands
couldn't reach any site whose dotted IP address contained a final
component greater than 127.

Timing values for idle-time processing were sometimes interpreted
incorrectly.

Various bugs in the find-linked-file command on Ctrl-X Ctrl-L were
fixed.


Changes in Beta 4
=================

New Features in Beta 4:
-----------------------

The F1 help key has several new options that access Epsilon's
Info-format online manual.  F1 Ctrl-C prompts for a command name,
then displays its documentation.  F1 Ctrl-K prompts for a key, then
displays the documentation for the command it's bound to.  F1 Ctrl-V
displays documentation for a variable.  Also, F1 v now runs the
about-epsilon command, which gives more information that the
show-version command it previously used.

In place of the mode line's percentage, Epsilon will now display the
words Top, Bot, or All, if it should happen that the top, bottom, or
the entire buffer (respectively) is visible in the window.  To get
Epsilon's previous behavior, modify the mode-end variable and replace
%p with %P.

In some buffers Epsilon displays the name of the current function in
the mode line.  You can now reposition this name by setting the
mode-end variable.  %f marks the position of the function name.

The find-linked-file command has many changes: You can now highlight
the file name first, if Epsilon has trouble locating it by itself.
The command now sets a bookmark at your previous location so you can
return with Alt-j.  The command now includes special logic for TeX
and Java files.  Also, some directory-related problems and other bugs
were fixed.

In TeX mode, or whenever the tex-paragraphs variable is nonzero,
Epsilon now uses slightly different rules for determining paragraph
boundaries.  Previously, lines that started with \ at the edge of a
paragraph weren't considered part of the paragraph.  Now such lines
are part of the paragraph, but lines starting with \begin or \end now
delimit the paragraph no matter where they fall.

Epsilon's Visual Studio integration now works when a process is
stopped in the debugger.

C mode's auto-fill feature now works better with its non-C-mode
cousin.  The auto-fill-mode command toggles C mode's variable in a C
mode buffer, Epsilon decides whether to display Fill in the mode line
in a better fashion, and so forth.

Epsilon for Windows now uses heuristics to determine whether its
command line contains a single file name containing spaces, or a
series of file names.

TeX mode now includes a new command on Alt-Shift-C to set text in
small caps, and some improved coloring.

A new variable tag-ask-before-retagging makes Epsilon ask you before
automatically retagging a file when it can't find a tag.


Linux-specific Bugs Fixed in Beta 4:
------------------------------------

In the Linux version, the dired command crashed when it tried to
display a file's group numerically after displaying a file's owner by
name.

In the Linux version, Epsilon is better at locating its executable,
so using Alt-F3 to compile an EEL file now works.

In the Linux version, the shell() primitive now creates the specified
buffer if necessary.

When Epsilon runs as an X program, it no longer crashes in certain
cases when it tries to display characters missing from a font.  Other
minor display problems were also fixed.

When Epsilon runs as a terminal program on the Linux console, shifted
function keys are now translated appropriately with a typical
terminfo definition for the console.

Under X, Alt-tabbing out of Epsilon and back no longer makes Epsilon
interpret mouse drags as if the Alt key were still down.

Under X, clicking Epsilon's close box caused Epsilon to exit without
checking for unsaved files.

Under Linux, Epsilon now checks at startup whether a version code
recorded in the state file matches the version code in the
executable.  If not, Epsilon warns that running Epsilon with its
-quickup flag may be necessary.

Epsilon for Linux uses a different memory management strategy that
improves performance with very large files.

Under Linux, rapid concurrent process output could make Epsilon
unresponsive.  If a process exited at just the right time, Epsilon
could lock up.

Completion in Epsilon's man command (to read manual pages) now works
on manual entries that contain the "." character.


Other Bugs Fixed in Beta 4:
---------------------------

Pressing <Space> when Epsilon is displaying various sorts of pop-up
windows now works correctly again.

Undoing buffer changes no longer inappropriately marks the buffer
unmodified.

When Epsilon does case-folding during searching, or converts the case
of letters on command, it now treats accented characters correctly.

EEL incorrectly rounded structure sizes in certain cases.

In the Win32 console version of Epsilon, after Epsilon auto-quoted a
special character (a character entered via Alt-<NumPad>, for
instance), moving the mouse would insert a series of Ctrl-Q
characters.  Other auto-quoting and keyboard problems in various
versions were also fixed.

When Epsilon failed to read a session file, any -r flags on the
command line operated on the wrong buffer.

Some files needed for the cua-keyboard command were omitted from the
distribution.

Concurrent process output no longer turns off search highlighting.
The concurrent process auto-scrolls less obtrusively.


Changes in Beta 3
=================

The Windows version now preserves font attributes like italic again.

Various accented characters and Ctrl-Alt- keys now work properly in
the Win32 console and DOS versions.

Undoing all changes to a buffer resets its modified flag, the same as
undoing buffer reads or writes that occur later.

The SendEps.exe program now passes flags to Epsilon correctly.

Epsilon does a better job parsing C++ namespaces and Java's try/catch
and other syntax.

Alt-i to list preprocessor conditionals now works in makefiles too.

Commenting commands use a different rule to indent an inserted
comment.

Perl mode no longer changes the indentation of a "here" document.
Also, a Perl coloring bug was fixed, and Perl mode colors comments in
a pattern that uses the x modifier.

Shelling in the Win32 console version no longer creates a new console.

The list-changes command now works when one file looks like a binary
file to Epsilon and the other does not.

Dired's + command to create a directory now ensures that a relative
name is interpreted as expected.

Completion on file names containing spaces works better.

You can now customize the shape of the focus rectangle under Windows
by setting the draw-focus-rectangle variable.  See the online help or
the description below.

Some definitions provide compatibility with old user extensions.

The Win32 console version of Epsilon uses the new
want-gui-help-console variable to determine whether to invoke
WinHelp.

The save-all-files command now puts a log of its actions in the
-messages buffer.

Identifier completion no longer uses the default-word variable to
define the rules for identifiers, and treats <Del> the same as
<Backspace> when auto-completing.

The F1 f command to look something up in the Epsilon online help now
converts between - and _ as needed.

TeX mode now uses different default colors that distinguish additional
constructs.

Some scroll bar problems in the Windows version were fixed.

A bug in identifier completion when typing some international symbols was fixed.


Changes in Beta 2
=================

A regular expression bug could make Epsilon crash.

Write-state's default state file name didn't include the correct path.

Going to a C++/Java tag, then going to the next tag with that name
now goes to functions with the same name but in a different class.
Java tagging is no longer confused by "implements" or "extends"
keywords.

Grep and file-query-replace now interpret your relative file pattern
based on the directory of the current buffer's file.  You can set the
new grep-prompt-with-buffer-directory variable to zero to get
Epsilon's previous behavior.  When you interrupt a file-query-replace
(and not just when you abort it), Epsilon now asks if you want to
continue replacing in the remaining files.

******************************************************************

Lugaru Software, Ltd.
1645 Shady Avenue
Pittsburgh, PA  15217

Tel: (412) 421-5911
Fax: (412) 421-6371
Internet: support@lugaru.com
