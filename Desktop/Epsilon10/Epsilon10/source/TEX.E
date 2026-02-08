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
#include "tex.h"

// Functions for coloring TeX.

// Return the start of the biggest specially-colored construct (like
// math mode) that includes point.

int tex_start_construct()
{
	int s;

	save_var point, narrow_end = size() - point;
	re_search(-1, "\n([ \t]*\n|\\def[^a-z0-9])");
	for (; re_search(1, "[%$\\]"); ) {	// Look for %, $, or \\ characters
		s = matchstart;
		switch (character(point - 1)) {
			case '\\':
				if (curchar() == '[') {
					if (!search(1, "\\]"))
						return s;
				} else
					point++;
				break;
			case '$':
				if (curchar() == '$') {
					if (!search(1, "$$"))
						return s;
				} else
					if (!search(1, "$"))
						return s;
				break;
			case '%':
				to_end_line();
				break;
		}
	}
	return point;
}

recolor_tex_from_here(int safe)
{
	safe = safe;			// Suppress compiler warning.
	to_begin_line();		// Get outside math mode.
	return tex_start_construct();
}

color_tex_cmd(int s)
{
	char cmd[200];
	int color = color_class tex_literal;

	cmd[0] = '|';
	if (parse_string(1, "[a-z@]*", cmd + 1)) {
		strcat(cmd, "|");
		if (strstr("|begin|end|", cmd))
			color = color_class tex_begin_end;
		else if (strstr("|chapter|section|subsection|subsubsection"
						"|appendix|bibliography|title|tableofcontents"
						"|input|include|listoffigures|listoftables|part|",
						cmd))
			color = color_class tex_section;
		else
			color = color_class tex_command;
	} else if (curchar() == '[') {
		int orig = point;
		if (re_search(1, "\n[ \t]*\n|\\par![^a-z]|\\]")
			&& character(point - 1) == ']') {
			color_tex_math(orig - 1, point);
			return;
		}
		point = orig + 1;
	} else
		point++;
	set_character_color(s, point, color);
}

color_tex_math(int from, int to)
{
	int s;

	set_character_color(from, to, color_class tex_math);
	save_var narrow_start = from, narrow_end = size() - to, point = from;
	while (re_search(1, "[\\%&]")) {
		s = point - 1;		// Color % and & specially in math mode unless
		switch (character(s)) {	// protected by \ character.
			case '\\':
				point++;
				break;
			case '%':
				to_end_line();
				set_character_color(s, point, color_class tex_comment);
				break;
			case '&':
				set_character_color(s, point, color_class tex_section);
				break;
		}
	}
}

color_tex_dollar(int s)
{
	char pat[30];
	int orig;

	strcpy(pat, "\n[ \t]*\n|\\par![^a-z]|%$");
	if (curchar() == '$') {	// A $$ that signals displayed math?
		point++;			// Get to after $$.
		strcat(pat, "%$");
	}
	orig = point;
	if (re_search(1, pat) && character(point - 1) == '$')
		color_tex_math(s, point);
	else
		point = orig;
}

// Adding/deleting $'s can get math mode coloring out of synch.
// If we just colored a math block and the next character is in
// math color, that's probably happened, so recolor the rest of this
// paragraph.

int fix_tex_math_coloring(int to)
{
	if (get_character_color(point) == color_class tex_math) {
		int s = point;			// Color rest of parag.
		if (!narrowed_search(REGEX, "\n[ \t]*\n", tex_look_back / 2))
			to_end_line();
		set_character_color(s, point, color_class tex_text);
		to = point;
		point = s;
	}
	return to;
}

int color_tex_range(int from, int to) // Recolor just this section.
{						// Last colored region may go past to.
	int s, talk, cnt = 0;

	if (from >= to)
		return to;
	save_var point, matchstart, matchend;
	point = from;
	from = point = tex_start_construct();

	talk = (to - from > tex_look_back + 1000); // Show status during long delays.
	if (point < to)
		set_character_color(point, to, color_class tex_text);
	save_var case_fold = 1;
	for (s = point; point < to && re_search(1, "[][{}%\\$&]"); s = point) {
		if (point > to)
			set_character_color(s, point - 1, color_class tex_text);
		s = point - 1;
		switch (character(s)) {
			case '\\':
				color_tex_cmd(s);
				if (talk)
					if (!(cnt++ % 500))
						note("Coloring TeX: %d%% complete...",
							 muldiv(point - from, 100, to - from));
				break;
			case '$':
				color_tex_dollar(s);
				to = fix_tex_math_coloring(to);
				break;
			case '%':
				to_end_line();
				set_character_color(s, point, color_class tex_comment);
				break;
			case '{': case '}':
				set_character_color(s, point, color_class tex_curly_brace);
				break;
			case '&':
				set_character_color(s, point, color_class tex_section);
				break;
			case '[': case ']':
				set_character_color(s, point,
									color_class tex_square_bracket);
				break;
		}
	}
	if (talk)
		note("");
	return point;
}

// Insert a command, position inside its braces, and optionally
// add an italic correction after.  If a region's highlighted,
// put it inside the command and move after it.

tex_insert_cmd(char *before, char *after, int italic_correction)
{
	iter = 0;
	if (is_highlight_on()) {
		fix_region();
		stuff(before);
		exchange_point_and_mark();
	} else {
		stuff(before);
		save_var point;		// Stay here after.
	}
	if (italic_correction && !index(",.", curchar()))	// Add italic
		stuff("\\/");		// correction except before punctuation.
	stuff(after);
}

command tex_italic() on tex_tab[ALT('i')]
{
	tex_insert_cmd(latex_2e_or_3 ? "\\textit{" : "{\\it ", "}",
				   !latex_2e_or_3);
}

command tex_slant() on tex_tab[ALT('I')]
{
	tex_insert_cmd(latex_2e_or_3 ? "\\textsl{" : "{\\sl ", "}",
				   !latex_2e_or_3);
}

command tex_typewriter() on tex_tab[ALT('T')]
{
	tex_insert_cmd(latex_2e_or_3 ? "\\texttt{" : "{\\tt ", "}", 0);
}

command tex_boldface() on tex_tab[ALT('B')]
{
	tex_insert_cmd(latex_2e_or_3 ? "\\textbf{" : "{\\bf ", "}", 0);
}

command tex_small_caps() on tex_tab[ALT('C')]
{
	tex_insert_cmd(latex_2e_or_3 ? "\\textsc{" : "{\\sc ", "}", 0);
}


// Insert a pair of characters, position between them.
// But if quoted or repeated, just insert normally.
tex_insert_pair(char *pair)
{
	if (character(point - 1) == '\\' || has_arg)
		normal_character();
	else {
		stuff(pair);
		point--;
	}
}

command tex_left_brace() on tex_tab['{']
{
	iter = 0;
	if (point < size() - narrow_end && !strchr(" \t\n$}", curchar()))
		insert('{');
	else if (character(point - 1) == '\\' && !has_arg) {
		stuff("{\\}");
		point -= 2;
	} else
		tex_insert_pair("{}");
}

command tex_math_escape() on tex_tab['$']
{
	iter = 0;
	tex_insert_pair("$$");
}

// Maybe delete an italic correction \/.

command tex_rm_correction() on tex_tab[','], tex_tab['.']
{
	if (parse_string(-1, "\\/}"))
		delete(matchend, matchstart - 1);
	normal_character();
}

// Convert " to TeX's quote sequences of `` or '' as appropriate.

command tex_quote() on tex_tab['"']
{
	if (character(point - 1) == '\\' || has_arg)
		normal_character();		// quoted (\" is an umlaut)
	else if (point <= narrow_start || index(" \t\n([{",
											character(point - 1)))
		stuff("``");	// use opening quote
	else
		stuff("''");	// closing quote
}

// An alternative to typing Ctrl-Q ".
command tex_force_quote() on tex_tab[ALT('"')], tex_tab[ALT('\'')]
{
	insert('"');
}

// Insert appropriate footnote cmd (TeX's takes two parameters).

command tex_footnote() on tex_tab[ALT('F')]
{
	tex_insert_cmd("\\footnote{",
				   tex_force_latex ? "}" : "}{}", 0);
}

// Make sure there's a \n before and after point.
tex_open_new_line()
{
	if (point > 0 && character(point - 1) != '\n')
		insert('\n');			// Make new lines before or after?
	if (curchar() != '\n')
		insert('\n'), point--;
}

command tex_center_line() on tex_tab[ALT('s')]
{
	iter = 0;
	tex_open_new_line();
	if (tex_force_latex && latex_2e_or_3)
		tex_insert_cmd("\\begin{center}", "\\end{center}", 0);
	else
		tex_insert_cmd("\\centerline{", "}", 0);
}

tex_insert_open(int close)
{
	normal_character();
	if (tex_force_latex && character(point - 2) == '\\') {
		save_var point;
		bprintf("\\%c", close);
	}
}

command tex_inline_math() on tex_tab['(']
{
	tex_insert_open(')');
}

command tex_display_math() on tex_tab['[']
{
	tex_insert_open(']');
}

tex_init_env()		// Load the list of environments.
{					// Return 0 if we couldn't.
	char *s;

	if (exist(TEX_ENV_BUF))
		return 1;
	save_var bufnum = create(TEX_ENV_BUF);
	s = lookpath("latex.env");
	if (!s)
		return 0;
	err_file_read(s, FILETYPE_AUTO);
	save_var sort_status = 0;
	do_sort_region(0, size(), 0, 0);
	delete_final_newlines();
	return 1;
}

// Add this environment to the list.
tex_add_to_env_list(char *env)
{
	char *s = lookpath("latex.env");

	if (!tex_init_env())
		return;
	save_var bufname = TEX_ENV_BUF;
	point = 0;
	bprintf("%s\n", env);
	save_var sort_status = 0;
	do_sort_region(0, size(), 0, 0);
	point = 0;
	do_uniq(1, 1, 0);
	delete_final_newlines();
	if (s && tex_save_new_environments)
		file_write(s, translation_type);
}

char *tex_env_match(char *partial, int start)
{
	if (!tex_init_env())
		error("Can't find latex.env");
	save_var bufname = TEX_ENV_BUF;
	case_fold = 0;
	if (start & STARTMATCH)
		point = 0;
	if (*partial ? !col_search(partial, 0) : (point >= size()))
		return NULL;
	to_begin_line();
	if (!grab_line(bufnum, _this_match))
		return NULL;
	return _this_match;
}

command tex_environment() on tex_tab[ALT('E')]
{
	char res[FNAMELEN];

	iter = 0;				// Ask which environment to use.
	comp_read(res, "Environment name: ", tex_env_match, 0,
			  tex_environment_name);
	strcpy(tex_environment_name, res);
	if (*res && tex_init_env())
		tex_add_to_env_list(res);
	if (is_highlight_on()) {	// Surround highlighted region.
		fix_region();
		if (point > 0 && character(point - 1) != '\n')
			insert('\n');			// Make new line before?
		bprintf("\\begin{%s}\n", tex_environment_name);
		exchange_point_and_mark();
		if (point > 0 && character(point - 1) != '\n')
			insert('\n');			// Make new line before?
		bprintf("\\end{%s}\n", tex_environment_name);
	} else {
		tex_open_new_line();
		bprintf("\\begin{%s}\n", tex_environment_name);
		save_var point;		// Stay here afterwards.
		bprintf("\n\\end{%s}", tex_environment_name);
	}
}

// Search on line for link, set file to its name.
// Abort if none.
tex_find_linked_file(char *file)
{
	char rel[FNAMELEN], curdir[FNAMELEN], *p, *include;

	to_begin_line();
	if (parse_string(1, ".*\\(include|input)[ \t{]*([^{} \t\n]+)"))
		grab(find_group(2, 1), find_group(2, 0), rel);
	else
		error("Can't find any link here.");
	if (!*get_extension(rel))
		strcpy(get_extension(rel), ".tex");
	strcpy(file, rel);
	get_buffer_directory(curdir);
	absolute(file, curdir);
	if (check_file(file))
		return;
	include = getenv("TEXINPUTS");
	p = 0;
	if (!p && include)
		p = look_on_path(rel, 0, include);
	if (!p && *include_directories)
		p = look_on_path(rel, 0, include_directories);
	if (!p)
		error("%s not found in include-directories path", rel);
	strcpy(file, p);
}

// We're inserting the character in key; maybe break this line first
// (or instead).  Return 1 if we still want to insert the character, or
// 0 to ignore it.  But if mode is 0,1,2, then we're only setting (0,1) or
// retrieving (2) the value of tex-auto-fill-mode.

int tex_maybe_break_line(int mode)
{
	switch (mode) {
		case 0:
		case 1:
			tex_auto_fill_mode = (mode != 0);
			return 0;
		case 2:
			return tex_auto_fill_mode;
	}
	if (!tex_auto_fill_mode)		// We're not in auto-fill mode.
		return 1;
	if                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      