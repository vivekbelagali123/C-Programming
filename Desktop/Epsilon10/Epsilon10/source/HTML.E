/************************************************************************
* "Epsilon" is a registered trademark licensed to Lugaru Software, Ltd. *
*		"EEL" and "Lugaru" are trademarks of Lugaru Software, Ltd.		*
*																		*
*  Copyright (C) 1996, 1999 Lugaru Software Ltd.  All rights reserved.  *
*																		*
* Limited permission is hereby granted to reproduce and modify this		*
* copyrighted material provided that the resulting code is used only in *
* conjunction with Lugaru products and that this notice is retained in	*
* any such reproduction or modification.								*
************************************************************************/

#include "eel.h"
#include "proc.h"
#include "colcode.h"
#include "c.h"
#include "html.h"

// HTML syntax highlighting.

html_recolor_from_here(safe)
{
	int start = point;

	safe = safe;			// avoid compiler warning
	if (re_search(-1, "%<%!--|-[ \t\n]*>|%<[%?]|[%?]%>"))
		return point;
	return start;
}

// We've just parsed "<tagname ", now color any attributes before the ">".
// Script is nonzero if tag name was "script".

color_html_attributes(script)
{
	int len, start, java = 0;

	while (len = parse_string(1, "[-_./a-z0-9]*")) {	// An attribute?
		if (script && parse_string(1, "(language|type)[ \t\n]*=[ \t\n]*"
								   "[\"']*(text/)?(javascript|jscript)"))
			java = 1;
		set_character_color(point, point + len, color_class html_attribute);
		point += len;			// Followed by a value?
		if (len = parse_string(1, "[ \t\n]*=[ \t\n]*")) {
			set_character_color(point, point + len, color_class html_punctuation);
							// Color the = and whitespace.
			point += len;		// Value might be quoted.
			start = point;
			if (curchar() == '"') {
				point++;
				search(1, "\"");
			} else if (curchar() == '\'') {
				point++;
				search(1, "'");
			} else	// No quotes, assume it's whitespace-delimited.
				re_search(1, "[^ \t\n<>]*");
			set_character_color(start, point, color_class html_value);
		}
		re_search(1, "[ \t\n]*");	// Parse whitespace.
		set_character_color(matchstart, matchend, color_class html_punctuation);
	}
	if (curchar() == '>') {
		set_character_color(point, point + 1, color_class html_punctuation);
		point++;
	}
	start = point;
	if (script) {
		if (search(1, "</script>"))
			point = matchstart;
		if (java && html_javascript_coloring)
			color_embedded_java(start, point);
		else
			set_character_color(start, point, color_class html_attribute);
	}
}

// Color this region as Java code.

color_embedded_java(from, to)
{
	save_var point;
	save_var narrow_start = from;
	save_var narrow_end = size() - to;
	save_var c_extra_keywords |= JAVA_KEYWORDS;
	save_var recolor_range = color_c_range;
	save_var recolor_from_here = color_c_from_here;
	color_for_narrowed_area(from, to);
}

// An HTML comment starts here.  Color it appropriately.
// HTML comments start with <!.  If there's a - immediately after,
// then this is probably a legal HTML comment like <!-- Comment -->
// so search for -> (this allows commenting out HTML code).
// Otherwise, it's not a "standard" comment (might be a legal DOCTYPE
// spec, or a valid <!>, or an illegal comment).  In any case,
// assume it ends at the next >.

color_html_comment()
{
	int s;

	search(-1, "<");	// Find start of comment.
	s = point;
	if (parse_string(1, "%<[ \t\n]*%![ \t\n]*-"))	// A legal comment?
		re_search(1, "-[ \t\n]*>");	// Search for end of legal comment.
	else	// Some odd flavor of comment; don't be too picky about its end.
		search(1, ">");
	set_character_color(s, point, color_class html_comment);
}

// Color text delimited by <% and %>.

color_html_include()
{
	int s, c = character(point + 1);

	search(-1, "<");	// Find start of include.
	set_character_color(point, point + 2, color_class html_attribute);
	s = point;
	search(1, c == '%' ? "%>" : c == '?' ? "?>" : ">");
	set_character_color(point - 2, point, color_class html_attribute);
	color_embedded_java(s + 2, matchstart);
}

// Don't start coloring from inside <>'s or in script sections, since
// we won't do it right.  Move point back to a good place.  Look back
// for openers <script, <? or <% or closers </script, ?> or %>.  If we
// found an opener, start from there.  Otherwise, move back before the
// nearest good <.

color_html_move_back()
{
	int start = point, p;

	save_var narrow_start = point - color_html_look_back;
	if (re_search(-1, "<Langle>[ \t\n]*/?script")
		&& parse_string(1, "<Langle>[ \t\n]*script"))
		return;				// Found a <script>, not a </script>.
	point = start;
	if (re_search(-1, "<Langle>[%?]|[%?]<Rangle>")
		&& curchar() == '<')
		return;				// Found a <% or <?, not a %> or ?>.
	point = start;
	do {			// start coloring from the previous tag
		if (!search(-1, "<"))
			break;	// but ignore <'s before " or ' characters
		if (get_character_color(point, &p, NULL) == color_class html_comment) {
			point = p + 2;	// If we're in a comment,
			search(-1, "<!");	// go back to its start.
		}
	} while (parse_string(-1, "[\"'].*"));
}

color_html_range(from, to) // recolor just this section
{			// last colored region may go past to
	int s, script, t;

	if (from >= to)
		return to;
	save_var point, matchstart, matchend;
	if (from < to)
		set_character_color(from, to, color_class html_text);
	point = from;
	save_var case_fold = 1;
	color_html_move_back();
	if (to > size() - narrow_end)
		to = size() - narrow_end;
	for (s = point; point < to; ) {
		if (curchar() == '&') {
			set_character_color(s, point, color_class html_text);
			s = point++;	 // Color an entity like &amp; or &#251;
			if (parse_string(1, "([a-z]+|#[0-9]+);?"))
				point = matchend;
			set_character_color(s, point, color_class html_entity);
			s = point;
			continue;
		}
		if (curchar() != '<') {
			point++;
			continue;
		}
		set_character_color(s, point, color_class html_text);
		t = point++;
		while (strchr(" \t\n", curchar()))
			point++;	// Parse < followed by whitespace.
		set_character_color(t, point, color_class html_punctuation);
		if (curchar() == '!')
			color_html_comment();
		else if (strchr("%?", curchar()))
			color_html_include();
		else if (s = parse_string(1, "[-_./a-z0-9]*")) { // Parse the tag.
			set_character_color(point, point + s, color_class html_tag);
			script = (s == 6 && parse_string(1, "script"));
			point += s;			// Look for javascript tag.
			for (t = point; strchr(" \t\n", curchar()); )
				point++;	// Parse whitespace.
			set_character_color(t, point, color_class html_punctuation);
			color_html_attributes(script);
		}
		s = point;
	}
	re_search(1, "![<&]");
	if (s < point)
		set_character_color(s, point, color_class html_text);
	return point;
}

// Search forward on line from here for link, set file to its name.
// Abort if none.
html_find_linked_file(char *file)
{
	char buf[FNAMELEN], *p;
	int orig;

	if (!re_search(1, "href[ \t\n]*=[ \t\n]*")) {
		to_begin_line();
		if (!re_search(1, "href[ \t\n]*=[ \t\n]*"))
			error("Can't find any link here.");
	}
	orig = point;
	if (curchar() == '"') {
		point++, orig++;
		search(1, "\"");
	} else if (curchar() == '\'') {
		point++, orig++;
		search(1, "'");
	} else	// No quotes, assume it's whitespace-delimited.
		re_search(1, "[^ \t\n<>]*"), point++;
	grab(orig, point - 1, buf);		// Get link from buffer.
	p = strchr(buf, '#');		// Remove #fragment if any.
	if (p)
		*p = 0;
	if (!*buf)
		error("Can't follow fragment links.");
	point = orig;
	if (!parse_string(1, "[a-z]+:")) {		// A relative URL.
		strcpy(file, filename);
		strcpy(get_tail(file, 1), buf);
	} else						// An absolute URL.
		strcpy(file, buf);
}

/*
Move in direction dir past a matched pair of characters in HTML buffers.
On success, or if the end of the buffer is encountered before the
first character is found, return the new buffer position.
Otherwise return -1.
Maybe this routine should consider <a> and </a> to be delimiters,
instead of < and >.
*/

html_move_level(int dir, int stop_on_key)
{
	char *findch = (dir > 0) ? "<" : ">";
	char *otherch = (dir < 0) ? "<" : ">";

	stop_on_key = stop_on_key;		// Silence EEL's warning.
	return default_move_level(dir, findch, otherch);
}

command html_mode()
{
	mode_keys = html_tab;		/* Use these keys. */
	major_mode = _html_mode_name;

	strcpy(comment_start, "%<%!-- *");
	strcpy(comment_pattern, "%<%!--(.|<newline>)*--%><FirstEnd>");
	strcpy(comment_begin, "<!-- ");
	strcpy(comment_end, " -->");
	mode_move_level = html_move_level;
	if (auto_show_html_delimiters)
		auto_show_matching_characters = html_auto_show_delim_chars;
	recolor_range = color_html_range;	// set up coloring rules
	recolor_from_here = html_recolor_from_here;
	idle_coloring_size = 5000;
	if (want_code_coloring)		// maybe turn on coloring
		when_setting_want_code_coloring();
	try_calling("html-mode-hook");
	drop_all_colored_regions();
	make_mode();
}

// Automatically go into HTML mode on .htm, .html files.

suffix_htm()
{
	html_mode();
}

suffix_html()
{
	html_mode();
}

suffix_shtml()
{
	html_mode();
}

// .cfm and .cfml are HTML variants for Cold Fusion by Allaire.

suffix_cfml()
{
	html_mode();
}

suffix_cfm()
{
	html_mode();
}

// .htx is an HTML variant for Microsoft's Internet Database Connector.

suffix_htx()
{
	html_mode();
}

// .asp and .asa are HTML variants for Microsoft's web server.

suffix_asp()
{
	html_mode();
}

suffix_asa()
{
	html_mode();
}

// Recognize XML and related extensions.

suffix_xml()
{
	html_mode();
}

suffix_cdf()
{
	html_mode();
}

suffix_osd()
{
	html_mode();
}

suffix_htt()
{
	html_mode();
}

suffix_wml()
{
	html_mode();
}

suffix_xsl()		// XML style sheet
{
	html_mode();
}

suffix_jsp()		// Java server page
{
	html_mode();
}

suffix_php()		// PHP server-side page
{
	html_mode();
}

suffix_php3()		// PHP server-side page
{
	html_mode();
}

suffix_sgml()		// Generic SGML file.
{
	html_mode();
}

suffix_sgm()
{
	html_mode();
}
