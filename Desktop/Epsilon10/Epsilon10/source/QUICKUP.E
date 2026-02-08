/************************************************************************
* "Epsilon" is a registered trademark licensed to Lugaru Software, Ltd. *
*		"EEL" and "Lugaru" are trademarks of Lugaru Software, Ltd.		*
*																		*
*  Copyright (C) 1984, 2000 Lugaru Software Ltd.  All rights reserved.	*
*																		*
* Limited permission is hereby granted to reproduce and modify this		*
* copyrighted material provided that the resulting code is used only in *
* conjunction with Lugaru products and that this notice is retained in	*
* any such reproduction or modification.								*
************************************************************************/

#include "eel.h"
#include "proc.h"
#include "colcode.h"
#include "bufed.h"
#include "c.h"
#include "grep.h"
#include "kill.h"
#include "tags.h"
#include "tex.h"
#include "info.h"
#include "diff.h"
#include "epsnet.h"
#include "filter.h"
#include "dired.h"
#include "makemode.h"
#include "html.h"
#include "perl.h"
#include "video.h"

int inp_next_page();

command quoted_insert()
{
	mention("Quote: ");
	do {
		getkey();
		if (IS_WIN_KEY(key)) {
			iter = 0;
			say("");
			return;
		}
	} while (key >= 512);
	if (key == CTRL('Q') && ungot_key != -1) {	// auto-quoted
		key = ungot_key;	// Strip extra auto-quoting.
		ungot_key = -1;
	}
	say("");
	if (user_abort == 2)
		check_abort();
	user_abort = 0;
	if (IS_ALT_KEY(key))
		key = key | 128;			// turn on meta bit
	delete_if_highlighted();
	while (iter-- > 0)
		insert(key);
}

command normal_character()
{
	int i;

	check_abort();
	delete_if_highlighted();
	if (!call_maybe_break_line(3))
		return;
	if (key >= 512) return;
	if (IS_ALT_KEY(key))
		key = key | 128;			// turn on meta bit
	if (key == '\n') {
		if (over_mode) {
			if (!nl_forward())
				insert('\n');
		} else if (auto_indent && indenter) {
			delete(point, point - parse_string(-1, "[ \t]*"));
			insert('\n');		/* delete trailing whitesp */
			(*indenter)();
		} else
			insert('\n');
	} else if (over_mode && point < size() && curchar() != '\n') {
		if (curchar() == '\t')
			i = display_width('\t', current_column());
		else
			i = 0;
		replace(point++, key);
		while (--i > 0)		/* insert i-1 spaces after pt */
			insert(' '), point--;
	} else
		insert(key);
}

bufed_kill()
{
	char bname[FNAMELEN];
	int buf, win, prev, newbuf = 0;

	if (!bufed_getname(bname) || !strcmp(bname, BUFED_BUF))
		return;
	buf = name_to_bufnum(bname);
	if (!buf || !check_drop_buffer(bname))
		return;
	bufed_restore_orig();
	while ((win = buf_in_window(buf)) >= 0) {
		window_handle = win;
		if (prev = give_prev_buf())
			to_buffer_num(prev);
		else if (newbuf)			// Make a new buffer, switch all
			to_buffer_num(newbuf);	// windows to it if we can't find
		else {						// a better buffer for them to show.
			make_newfile_buf();
			newbuf = bufnum;
		}
		check_abort();
	}
	window_handle = _bufed_window;
	delete_user_buffer(bname);
	set_read_only(0);
	save_var modified;	// leave modify bit alone
	to_begin_line();	// but delete line
	delete(point, give_end_line() + 1);
	if (point >= size() && character(point - 1) == '\n')
		delete(point - 1, point);
	set_read_only(1);
	to_bufed_column();
}

list_line(inbuffer)	/* insert a line into the buffer list */
char *inbuffer;
{
	char file[FNAMELEN], msg[FNAMELEN * 2], bname[FNAMELEN];
	int width;

	strcpy(bname, bufname);
	quote_bufname(bname);
	relative(filename, file);
	if (force_save_as == FSA_NEWFILE)
		*file = 0;

	width = sprintf(msg, "%10d%9d %c%c %-18s %s\n",
					buf_accessed, size(), _buf_readonly ? 'R' : ' ',
					modified ? '*' : ' ', bname, file);
	bufname = inbuffer;
	stuff(msg);
	width = width - ACCESS_WIDTH + 2;
	if (width > bufed_width)
		bufed_width = width;
}

normal_on_modify()
{
	int paging = (_buf_readonly == 3 || _buf_readonly && readonly_pages);

	if (_doing_input != DI_SEARCH)
		highlight_off();
	if (paging && key == ' ') {
		next_page();
		quick_abort();
	} else if (paging && (key == '\b' || key == GREYBACK)) {
		previous_page();
		quick_abort();
	} else if (_buf_readonly)
		error("Buffer is read-only.");
	call_on_modify = 0;	/* don't call us next time */
	if (virtual_space && bufnum == window_bufnum)
		virtual_to_real_column();
}

command count_lines()
{
	int count, here, disksize;

	noteput("Counting...");
	here = lines_between(0, point, 1);
	check_abort();
	noteput("Counting... point on line %d...", here + 1);
	count = here + lines_between(point, size(), 1);
	check_abort();
	disksize = size();
	if (translation_type == FILETYPE_MSDOS)
		disksize += count;
	save_var point, mark;
	fix_region();
	if (is_highlight_on())
		say("%d lines, %d in region, point on line %d.  %d bytes on disk.",
			  count + 1, lines_between(point, mark, 1), here + 1, disksize);
	else
		say("%d lines, point on line %d.  %d bytes on disk.",
			  count + 1, here + 1, disksize);
	expire_message = 1;
	iter = 0;
}

int grab_string_expanding(int b, char **s, char *endmark, int minlen)
{
	int opt, res, len;
	save_var bufnum = b;

	opt = point;
	res = search(1, endmark);
	len = MAX(point - opt + 1, minlen);
	*s = realloc(*s, len);
	if (res)
		grab(opt, matchstart, *s);
	else
		**s = 0;
	return res;
}

grab_expanding(int from, int to, char **str, int minlen)
{
	int len = MAX(ABS(to - from) + 1, minlen);

	*str = realloc(*str, len);
	grab(from, to, *str);
}

command rename_buffer()
{
	char bfname[FNAMELEN];

	get_buf(bfname, "Rename buffer to", "");
	if (*bfname)
		change_buffer_name(bfname);
}

command kill_all_buffers()	// kill all user-visible buffers
{
	int count = 0;
	char *oldbuf;

	tiled_only();
	buffer_list(1);         // Count the buffers.
	do {
		count++;
	} while (buffer_list(0));

	while (count-- >= 0) {
		if (is_process_buffer(bufnum)) {
			next_buffer();
			continue;
		}
		oldbuf = bufname;
		if (modified && *filename && size() && !is_dired_buf()
			  && !discardable_buffer) {
			if (!check_drop_buffer(bufname))	// Ask user if ok to drop.
				return;
		} else
			to_another_buffer(bufname);
		delete_user_buffer(oldbuf);
	}
}

check_drop_buffer(bname) /* check if buffer can be deleted safely */
char *bname;		/* ask user if questionable */
{			/* return 1 if done, 0 if user said don't */
	char msg[80], *origbuf = bufname;
	int mod;

	if (!exist(bname))
		error("No buffer %s.", bname);
	if (another_process() && !strcmp(bname, PROCBUF))
		error("A process is running in buffer %s.", bname);
	bufname = bname;
	mod = modified && size() > 0 && !discardable_buffer;
	if (ftp_job && ftp_job->buf == bufnum
		  && ftp_job->operation == FTP_SEND)
		mod = 1;
	bufname = origbuf;
	if (!another_process() && !strcmp(bname, PROCBUF))
		mod = 0;
	if (mod) {
		sprintf(msg, "Buffer %.40s not saved.  Delete it? ", bname);
		if (!ask_yn("Delete buffer", msg, "Delete", "Cancel", 2))
			return 0;
	}
	to_another_buffer(bname);
	return 1;
}

c_indenter()		/* replace surrounding indentation with new */
{
	if (in_shell_buffer)
		prev_indenter();
	else if (!(in_c_comment(c_look_back) & IN_COMMENT))
		indent_to_column(c_compute_indent());
	else if (reindent_c_comments && !in_perl_buffer)
		indent_c_comment();
}

int c_smart_move_level(int dir, int comm, int stop_on_key)
{
	char delims[100], *pat = (dir > 0) ? "])}[({*/" : "[({])}*/";
	int c, i, depth = 0, cnt = 0;
	int in_block_comment = (comm == IN_OLD_COMMENT) ? comm : 0;

	while (re_search(dir, "[])}[({]|/%*|%*/")) {
		if (stop_on_key && (cnt++ % 20 == 0)
			  && (char_avail() || is_key_repeating()))
			return -2;		// Give up search now?
		c = character(point - (dir > 0));
		if (c == '/' && !in_c_comment(c_look_back))
			in_block_comment = 0;	// Leaving a block comment.
		else if (c == '*' && in_c_comment(c_look_back) == IN_OLD_COMMENT)
			in_block_comment = IN_OLD_COMMENT;	// Entering block comment.
		i = strchr(pat, c) - pat;
		if (i >= 6)	// Block comment chars, not delimiters.
			continue;
		if ((in_block_comment ? in_block_comment : in_c_comment(0)) != comm)
			if (comm)			// If we started in comment/string,
				return -1;		// stop if we ever search outside it.
			else				// We didn't start in comment/string, so
				continue;		// skip over delims in comments/strings.
		if (i < 3) {		// Closing delim.
			if (depth < 1 || c != delims[--depth])
				return -1;	// This didn't match what we expected.
			if (!depth)		// We found a match, success.
				return point;
		} else			// Opening delim, record it.
			delims[depth++] = pat[i - 3];
	}
	return -1;
}

c_move_level(int dir, int stop_on_key)
{
	int cnow, cstart = in_c_comment(c_look_back);	// in comment/string at start?

	save_var point;			// if aborted, don't move anywhere
	do {				/* find the first char of pair */
		if (!re_search(dir, (dir > 0) ? "[[({]" : "[])}]"))
			return point;	/* at end of buffer */
		cnow = in_c_comment(c_look_back);	// ignore if it's in a comment/string
	} while (cnow && cnow != cstart);	// (unless we started in one)
	point -= dir;			/* move back over first char */
	return c_smart_move_level(dir, cnow, stop_on_key);
}

int find_c_class_info(int start, char *type, char *class, char *func)
{
	char this[FNAMELEN], last[FNAMELEN];
	int class_start = point, i;

	point--;	// See if "class foo" is before this.
	strcpy(last, "");
	for (i = 20; i-- > 0; ) {	// Look through some words before the {.
		if (cind_try_space() || give_begin_line() > start)
			return 0;
		if (strchr("<>:", character(point - 1)))
			point--;
		else {
			if (!parse_string(-1, "[a-zA-Z0-9_]+", this))
				return 0;
			if (!strcmp(this, "class") || !strcmp(this, "struct")
				  || !strcmp(this, "union") || !strcmp(this, "namespace")) {
				if (type)
					strcpy(type, this);		// Word to the right of type is class.
				if (class)
					strcpy(class, last);	// Is place where we started within func?
				if (find_inner_func_name(start, class_start, func))
					return CF_INFO_TYPE | CF_INFO_CLASS | CF_INFO_FUNC;
				return CF_INFO_TYPE | CF_INFO_CLASS;
			}
			strcpy(last, this);		// Go on to the next word.
		}
	}
	return 0;		// Couldn't recognize anything here.
}

command c_mode()
{
	mode_keys = c_tab;		/* use these keys */
	indenter = c_indenter;
	auto_indent = 1;
	major_mode = _c_mode_name;
	strcpy(comment_start, "(/</|*>)[ \t\f]*");
	strcpy(comment_pattern, "//.*$|/<*>(.|<newline>)*<*>/<FirstEnd>");
	when_setting_new_c_comments();
	mode_move_level = c_move_level;
	recolor_range = color_c_range;	// set up coloring rules
	recolor_from_here = color_c_from_here;
	if (want_code_coloring)		// maybe turn on coloring
		when_setting_want_code_coloring();
	if (auto_show_c_delimiters)
		auto_show_matching_characters = c_auto_show_delim_chars;
	if (c_mode_mouse_to_tag)
		mouse_goes_to_tag = 1;
	if (c_tab_override > 0)
		tab_size = c_tab_override;
	buffer_maybe_break_line = c_maybe_break_line;
	if (c_fill_column > 0)
		margin_right = c_fill_column;
	try_calling("c-mode-hook");
	drop_all_colored_regions();
	make_mode();
}

suffix_c()
{
	c_mode();
	compile_buffer_cmd = compile_c_cmd;	// can compile this
	if (is_unix)			// special definition
		compile_buffer_cmd = compile_c_cmd_unix;
	c_extra_keywords = 0;	// don't recognize C++ or EEL keywords in .c
}

suffix_cpp()
{
	c_mode();
	compile_buffer_cmd = compile_cpp_cmd;	// can compile this
	if (is_unix)			// special definition
		compile_buffer_cmd = compile_c_cmd_unix;
	c_extra_keywords = CPP_KEYWORDS;	// recognize only C++, not EEL
}

suffix_js()
{
	suffix_java();
}

c_compute_indent()
{
	int ind = 0;		/* indentation to use */
	int orig = point;
	int first_char = curchar(); /* cur line's first char */
	int pstart;		/* start position of prev line */
	int pafter;		/* after label on prev line */
	int pend;		/* end position of prev line */
	int prev_end = ';';	/* last char on previous line */
	int norm_narrow;	/* narrowing setting for most parsing */

	save_var point;
	if (setjmp(&c_indent_giveup))	/* if we hit end & gave up, */
		return ind;		/* use best guess so far */
	if (in_perl_buffer)
		return perl_compute_indent();
	norm_narrow = fix_narrowing(point - c_look_back);
	save_var narrow_start = norm_narrow;
	if (!reindent_c_comments && parse_string(1, "[ \t\f]*/<*>"))
		return get_indentation(point);
	if (!reindent_one_line_c_comments && parse_string(1, "[ \t\f]*//"))
		return get_indentation(point);
	if (first_char == '#' || first_char == '\f')
		return 0;
	else if (first_char == '}')
		return cind_close();

	to_begin_line();
	if (character(point - 2) == '\\')
		return indent_after_backslash();
	if (parse_string(1, "[ \t]*\n") && after_many_comments()) {
		re_search(-1, "[^ \t\n]");	/* find previous non-blank line */
		return get_indentation(point);
	}
	cind_space();			/* skip whitespace and comments */
	if (character(point - 1) == ':')
		move_before_labels();
	prev_end = character(point - 1); /* get last relevant char */
	pend = point;

	to_statement_start();		/* if contin line, back up */
	pstart = point;			/* now at start of biggest statement */
	past_labels();			/* containing original point */
	pafter = point;			/* just after label */
	ind = current_column();
	narrow_start = norm_narrow;	/* ok to look far back again */

	if (is_case(orig)) {
		ind = indent_case(orig);
	} else if (parse_string(1, "ON_")) {
		// Found MFC dispatch table, leave alone.
	} else if (have_label(orig)) {
		char type[FNAMELEN];		// Could it be a bitfield, not a label?
		find_c_func_info(type, NULL, NULL, 0);
		if (!strcmp(type, "struct") || !strcmp(type, "union"))	// Yes, a bitfield.
			ind += get_c_indent();
		else					// It's a label.
			ind = c_label_indent;
	} else if (prev_end == ':' && is_label(pstart)) {
		ind = get_column(pstart);
		if (!(Closeback && just_open(orig)))
			ind += get_c_indent();
		if (just_open(orig))
			ind += c_brace_offset;
	} else if (is_else(orig)) {
		point = orig;
		ind = indent_else(ind);
	} else if (prev_end == ';') {
		if (just_open(orig) && func_start_block(pstart))
			ind = c_top_braces;
		else
			ind = indent_after_statement(orig);
	} else if (prev_end == '}') {
		point = pend;
		ind = indent_after_block(orig);
	} else if (prev_end == '{') {
		if (ind <= c_top_braces	// special case if no previous indent
			  || get_column(pend - 1) <= c_top_braces) {
			ind += top_indent(prev_end) ? get_c_indent() : c_top_braces;
			if (just_open(orig))
				ind += c_brace_offset;
			if (ind < c_top_braces)
				ind = c_top_braces;
		} else if (Closeback || curchar() != '{')
			ind += get_c_indent();
		if (just_open(pafter))
			ind -= c_brace_offset;
	} else if (just_open(orig))
		return indent_just_open(ind);
	else if (is_contin_statement(pend, 1, orig)) {
		return indent_c_contin(ind, orig, pend);
	} else if (!index(":);{}", c_line_before()) && !c_statement_start()
			   && !(Closeback && just_open(point)))
		return ind;
	else
		ind += get_c_indent();
	return ind;
}

command do_c_indent()
{
	int orig = point, ind = get_c_indent();
	int orig_column = current_column();

	if (maybe_indent_rigidly(0))
		return;
	to_indentation();
	if (!c_tab_always_indents && orig_column > current_column() || in_shell_buffer) {
					/* if not in indentation */
		point = orig;
		to_column(orig_column + tab_size - orig_column % tab_size);
	} else if (prev_cmd == C_INDENT)	/* repeated, make bigger */
		to_column(orig_column + ind);
	else {
		c_indenter();
		if (in_perl_buffer && !get_indentation(point) && !orig_column
			  && this_cmd != CMD_INDENT_REG)
			to_column(ind);	// 0 indent=>0 indent, but indent anyway
	}
	if (this_cmd != CMD_INDENT_REG)
		this_cmd = C_INDENT;
}

c_statement_start()
{
	return parse_string(1, "[{} \t\f]*(if|else|while|do|for|switch|try|"
						"catch|finally)[^a-zA-Z0-9]");
}

is_switch(p)	/* is there a switch-like statement at position p? */
{
	if (!index("scu", character(p)))
		return 0;
	save_var point = p;
	return parse_string(1, "(switch|struct|union|class|namespace)[^a-zA-Z0-9_]");
}

after_many_comments()
{
	char pat[FNAMELEN];
	int cnt = 0;

	if (comment_repeat_indentation_lines < 0)
		return 0;
	save_var point;
	sprintf(pat, "[ \t]*%s", comment_start);
	while (nl_reverse()) {
		to_begin_line();
		if (!parse_string(1, pat))
			break;
		if (++cnt >= comment_repeat_indentation_lines)
			return 1;
	}
	return 0;
}

indent_after_statement(orig) // orig is place needing indentation, for toplevel
{
	int lastcont, i, c, atparen = -1;

	for (;;) { /* was only the end of a larger statement, find start */
		do {	/* look back for line that ends with ;{}: */
			lastcont = point;
			to_begin_line();
			if (cind_try_space())
				break;
			if ((c = character(point - 1)) == ')') {
				atparen = lastcont;
				if (!c_rev_skip_level('(', ')'))
					break;
				to_begin_line();
			}
		} while (!index(";{}:", c));
		point = lastcont;	/* use indentation of line */
		to_c_indentation();	/* just after it */
		if (parse_string(RE_FORWARD, "(}[ \t\f]*)?e!lse[^a-zA-Z0-9_]")) {
			point = matchend;
			if (!to_matching_if())
				break;
		} else if (parse_string(RE_FORWARD,
								"(}[ \t\f]*)?!(catch|finally)[^a-zA-Z0-9_]")) {
			point = matchend;
			if (!to_matching_try())
				break;
		} else
			break;
	}
	i = current_column();
	if (!i && atparen != -1 && (Topindent || !c_statement_start()))
		i = get_indentation(atparen);	// 2nd func param decl
	if ((atparen = parse_string(1, "for[ \t\f]*%([ \t\f]*"))
		  && for_unclosed(point, orig))
		i = get_column(point + atparen); // part of "for" statement
	if (i <= c_top_braces)
		return 0;	// 1st line of new func
	return i;
}

c_default_indent(ind, orig, defmult)
{
	if (ind)
		return ind + defmult * get_c_indent() + c_contin_offset;
	if (parse_string(1, "[ \t\f]*(struct|union|class|namespace)[ \t\f\n]+"
					 "[a-zA-Z0-9_]*[ \t\f\n]*{[ \t\f\n]*[\n/]"))
		return ind + c_top_struct;
	if (just_open(orig))
		return c_top_braces;
	point = orig;
	cind_space();
	return is_contin_statement(point, 0, orig)
			? c_top_contin : c_param_decl;
}

to_matching_try()	/* go to matching try statement, assuming we're */
{			/* just before a catch or finally keyword */
	int extra_elses = 0;	/* ret 0 if couldn't find it, 1 if ok */

	while (cind_search("<min>(([^#a-zA-Z0-9]|^)(try|catch|finally)[^a-zA-Z0-9]|})")) {
		if (!in_c_comment(c_look_back) && !parse_string(-1, "[ \t]*#[ \t]*")) {
			if (curchar() == '}') {
				point++;	/* find matching { */
				c_rev_skip_level('{', '}');
			} else if (character(point + 1) == 'e')
				extra_elses++;
			else if (--extra_elses < 0)
				return 1;
		}
	}
	return 0;
}

to_matching_if()	/* go to matching if statement, assuming we're */
{			/* just before an else keyword */
	int extra_elses = 0;	/* ret 0 if couldn't find it, 1 if ok */

	while (cind_search("<min>(([^#a-zA-Z0-9]|^)(else|if)[^a-zA-Z0-9]|})")) {
		if (!in_c_comment(c_look_back) && !parse_string(-1, "[ \t]*#[ \t]*")) {
			if (curchar() == '}') {
				point++;	/* find matching { */
				c_rev_skip_level('{', '}');
			} else if (character(point + 1) == 'e')
				extra_elses++;
			else if (--extra_elses < 0)
				return 1;
		}
	}
	return 0;
}

unmatched_rparen(from, to)	// is there an unmatched ")" in range?
{
	save_var narrow_start = from;
	save_var point = to;
	do {
		if (!search(-1, ")"))
			return 0;	// find last ")" in range
	} while (in_c_comment(c_look_back));
	point++;		// return 1 if unmatched
	return !c_rev_skip_level('(', ')');
}

is_contin_statement(p, fd, orig) // would line after p be a continuation line?
{			// assumes p is just after last interesting char
	// if fd, pretend func param decls are a "continuation" of func decl
	// orig is later position in buffer, for unclosed "for" scan
	switch (character(p - 1)) {
		case ';':		// check for multi-line "for" statemnt
			if (unmatched_rparen(p, orig))
				return 1;
		case '{':
		case '}':
			return 0;
		case ')':
			save_var point = p;
			save_var narrow_start = p - 500;
			if (!c_rev_skip_level('(', ')'))
				return 1;
			return !parse_string(-1, "[^a-z0-9_](if|while|for"
								 "|switch)[ \t\f]*") && (fd
				|| !Topindent || get_indentation(point)) || in_perl_buffer;
		case 'e':
			return !is_else(p - 4);
		case 'o':
			save_var point = p;
			return !parse_string(-1, "[^a-z0-9_]do");
		case ':':
			save_var point = p;
			to_indentation();
			return !is_label(point);
		default:
			return 1;
	}
}

do_list_preprocessor_conditionals(char *line, char *if_line, char *end_line, char *msg)
{
	int b = zap("-list-preprocessor-conditionals"), level = 0;

	iter = 0;
	save_var point = give_begin_line();
	while (re_search(-1, line)) {
		if (parse_string(1, end_line))
			level--;
		else if (!level) {
			buf_xfer(b, give_begin_line(), give_end_line() + 1);
			set_buf_point(b, 0);
		} else if (parse_string(1, if_line))
			level++;
	}
	restore_vars();
	save_var _view_title = "Preprocessor conditionals";
	if (buffer_size("-list-preprocessor-conditionals"))
		view_buffer("-list-preprocessor-conditionals", 1);
	else
		say("Not in any %s conditional.", msg);
}

command list_preprocessor_conditionals()
{
	do_list_preprocessor_conditionals(PREPROC_LINE, PREPROC_IF,
									  PREPROC_ENDIF, "#if");
}

c_find_linked_file(char *file)
{
	char rel[FNAMELEN], curdir[FNAMELEN], *p, *classpath, *include;
	int add_cd = PATH_ADD_CUR_DIR, is_abs = 0;

	to_begin_line();
	if (parse_string(1, "[ \t]*#[ \t]*include[ \t]*[<\"](.*)([>\"])[ \t]*$")) {
		grab(find_group(1, 1), find_group(1, 0), rel);
		is_abs = character(find_group(2, 1)) == '>'
				 && !find_linked_file_ignores_angles;
		// Using #include "" or <> syntax?
	} else if (is_java_buffer() &&  parse_string(1, "[ \t]*(package|import)"
		"[ \t]*(<word>+(%.<word>+)*)(%.%*)?[ \t]*;")) {
		grab(find_group(2, 1), find_group(2, 0), rel);
		while (p = strchr(rel, '.'))	// Transform java.lang to 
			*p = path_sep;				// java/lang filename.
		if (character(find_group(2, 0)) != '.')
			strcat(rel, ".java");
	} else
		error("Can't find any link here.");
	strcpy(file, rel);
	get_buffer_directory(curdir);
	if (is_abs)				// Don't look for relative names at all.
		add_cd = 0;
	else {
		absolute(file, curdir);
		if (check_file(file))
			return;
	}
	include = getenv("INCLUDE");
	classpath = getenv("CLASSPATH");
	p = 0;
	if (!p && is_java_buffer() && classpath)
		p = look_on_path(rel, add_cd, classpath);
	if (!p && include)
		p = look_on_path(rel, add_cd, include);
	if (!p && *include_directories)
		p = look_on_path(rel, add_cd, include_directories);
	if (!p)
		p = look_on_path(rel, add_cd, (opsys == OS_UNIX)
						 ? INCL_PATH_UNIX : INCL_PATH_WIN);
	if (!p)
		error("%s not found in include-directories path", rel);
	strcpy(file, p);
}

fix_c_indentation()		/* recompute this line's indentation */
{				/* without moving point */
	if (in_shell_buffer)
		return;
	save_spot point;
	to_indentation();
	c_indenter();
}

user short clipboard_format = CF_DEFAULT;

command copy_to_clipboard()	// copy region to clipboard
{
	int err = 0, tmp = zap("-clipboard-");
	save_spot point, mark;
	fix_region();
	if (region_type() == REGRECT)
		extract_rectangle(tmp, 0);
	else
		buf_xfer(tmp, point, mark);
	if (!buffer_to_clipboard(tmp, clipboard_convert_newlines(), clipboard_format))
		err = errno;
	clipboard_to_buffer(zap("-clipboard-"), clipboard_convert_newlines(),
						clipboard_format);
	if (err)
		file_error(err, "", "Couldn't copy to clipboard.");
	else {
		say("Selection copied to clipboard.");
		highlight_off();
	}
}

when_restoring()
{
	int tflag = 0, i, j, splitmode = HORIZONTAL;
	char fname[FNAMELEN];
	char *s;

	after_loading(); /* call early, so we can display errors, etc. */
	putenv("EPSRUNS=Y");	/* for catching nested Epsilons */
	if (opsys == OS_DOS)
		putenv("PKNOFASTCHAR=Y"); //make PKZIP, UNZIP output capturable
	root_keys = reg_tab;
		/* now set buffer-specific variables */
	if (has_feature & FEAT_ANSI_CHARS) {
		word_pattern.default = default_word;
		_char_class.default = _def_ansi_char_class;
		_case_map.default = _def_ansi_case_map;
		_srch_case_map.default = _def_ansi_srch_case_map;
	} else {
		word_pattern.default = default_oem_word;
		_char_class.default = _def_char_class;
		_case_map.default = _def_case_map;
		_srch_case_map.default = _def_srch_case_map;
	}
	_display_class.default = _std_disp_class;
	_echo_display_class = _echo_disp_class;
	i = *get_color_scheme_variable();
	if (name_type(i) == NT_COLSCHEME)
		selected_color_scheme = i;
	else
		get_standard_color_scheme();
	use_default = 1;		/* default is fundamental mode */
	mode_default_settings();
	use_default = 0;
	apply_defaults();	/* apply defaults to init buffer & window */

	force_save_as = FSA_NEWFILE;	// make startup buffer prompt
	strcpy(fname, "startup.txt");	// for filename
	absolute(fname);
	filename = fname;
	strcpy(_docname, "edoc");
	early_init();

	for (i = 1; i < argc && argv[i][0] == '-'; i++)
		switch (argv[i][1]) {
			case 'f':
				switch (argv[i][2]) {
					case 's':
						set_swapname(argv[i] + 3);
						break;
					case 'h':
						set_shrinkname(argv[i] + 3);
						break;
					case 'd':
						strcpy(_docname, argv[i] + 3);
						break;
					default:
						bad_flag(argv[i]);
				}
				break;
			case 't':
				tflag = 1;
				break;
			case 'r':
			case 'l': break;
			case 'h': case '?': usage();
			case 'p':
				if (!argv[i][2])
					preserve_session = preserve_session ? 0 : 1;
				else if (isdigit(argv[i][2]))
					preserve_session = numtoi(argv[i] + 2);
				else
					cmd_line_session_file = argv[i] + 2;
				break;
			case 'v':
				switch (argv[i][2]) {
					case 'v':
						splitmode = VERTICAL;
						break;
					default:
						bad_flag(argv[i]);
				}
				break;
			case 'd':
				s = index(argv[i] + 2, '=');
				if (!s)		// accept either VAR=VAL or VAR!VAL
					s = index(argv[i] + 2, '!');
				if (s) {
					*s = 0;
					if (j = find_index(argv[i] + 2)) {
						set_var_val(j, s + 1, 1);
						break;
					}
					bprintf("No such variable %s.\n", argv[i] + 2);
					init_help_abort();
				}		/* fall through on error */
			default:
				bad_flag(argv[i]);
		}			/* i is 1st file argument */
	term_init();
#include "keyext.h"
	try_calling("key-setup");
	middle_init();
	init_menu();
	term_cmd_line();
	if (tflag) {
		preserve_session = 0;
		tutorial();
	} else {
		if (load_from_state && (i >= argc || session_always_restore)) {
			if (session_restore_files == 2 && i < argc)	// Have cmdline files,
				save_var session_restore_files = 0;	// skip session files.
			load_session();
		}
		if (i < argc)
			load_cmd_line_files(i, splitmode);
		delete_dull_buffer("startup");
	}
	switching_to_buffer();
	set_toolbar();
	if (load_from_state && (strcmp(eel_version, versioned_file_string) < 0
							|| (strchr(eel_version, 'b')
								&& !strchr(versioned_file_string, 'b')))
		  && !strchr(versioned_file_string, 'a')) {
		// Each user has a private state file, so we can't update them
		// all automatically.
		save_var bufnum = zap(HELPBUF);
		bprintf("Your version %s state file requires updating.\n"
				"You need to start Epsilon with its -quickup flag.\n", 
				eel_version);
		bprintf("Until you do this, Epsilon will not work correctly.\n");
		view_help(" Update Needed! ", 0);
		restore_vars();
	}
	note("Epsilon Programmer's Editor %s", version);
//	note("Post Process Editor B1.1 version.");
	try_calling("start-up");
	for (i = 1; i < argc && argv[i][0] == '-'; i++)
		switch (argv[i][1]) {
			case 'l': load_commands(argv[i] + 2); break;
			case 'r': try_calling(argv[i] + 2); break;
		}
}

load_cmd_line_files(i, splitmode)	/* start at argv[i] */
{
	int wins = 0, tot_size = window_height, line, column, j;
	char fname[FNAMELEN], fixed[FNAMELEN], *s, first = 1;

	one_window();			// Don't use windows specified by session
	if (is_gui && i + 1 < argc && argv[i][0] != '+') {	// multiple args
		for (j = i, *fixed = 0; j < argc; j++) {
			if (strlen(fixed) + strlen(argv[j]) >= FNAMELEN - 1) {
				*fixed = 0;
				break;		// See if perhaps a stray association is
			}				// passing us a file name w/o the quotes.
			if (*fixed)
				strcat(fixed, " ");
			strcat(fixed, argv[j]);
		}
		if (check_file(fixed) == 1 && !check_file(argv[i])) {
			argv[i] = strsave(fixed);
			argc = i + 1;
		}
	}
	line = column = -1;
	for (; i < argc; i++) {
		if (argv[i][0] == '+') {
			line = strtoi(argv[i] + 1, 10);
			s = strchr(argv[i], ':');
			if (s)
				column = strtoi(s + 1, 10);
		} else {
			strcpy(fname, argv[i]);
			absolute(fname);
			if ((directory_flags & DIR_CWD_FROM_FILE) && first) {
				char dir[FNAMELEN];
				strcpy(dir, fname);
				*get_tail(dir, 1) = 0;
				chdir(dir);
				first = 0;
			}
			s = expand_wildcards ? do_file_match(fname, STARTMATCH | EXACTONLY)
								 : fname;
			if (!s)		/* new file */
				s = fname;
			do {
				if (wins < max_initial_windows && wins++ > 0) {
					window_split(splitmode);
					window_height = 1000;
				}
				if (!(is_pattern(s) & 2) && !is_directory(s)
					  && !is_remote_file(s))	// Has quotable wildcards.
					find_it(s, default_translation_type);
				else
					do_find(s, default_translation_type);
				if (line > 0)
					go_line(line);
				if (column >= 0)
					move_to_column(column);
			} while (expand_wildcards
					 && (s = do_file_match(fname, EXACTONLY)));
			line = column = -1;
		}
	}
	for (; window_number > 0; window_number--)
		window_height = tot_size / number_of_user_windows();
}

init_help_abort()
{
	bprintf("For help, type \"epsilon -help\".\n\n");
	init_abort();
}

color_for_area(from, to)	// we need to color region in this range
{
	save_var point, abort_searching = 0;
	init_color_code();
	color_for_narrowed_area(from, to);
}

// Like above, but don't disturb narrowing.
color_for_narrowed_area(from, to)
{
	int i, j, give_up = 0;

	save_var point, abort_searching = 0;
	init_color_code();
	to = MIN(to, size() - narrow_end);
	for (;;) {
		if (get_tagged_region("needs-color", from, &i, &j)) {
			if (i < from) {
				point = from;		// From isn't colored, so start before it.
				nl_reverse();	// Color a few extra lines before
				nl_reverse();	// to speed up scrolling.
				nl_reverse();		// Next, find starting place guaranteed to be
				if (point > i)		// on the edge of a colored region.
					i = recolor_from_here(i);
			}						// (Or use known safe place if it's closer.)
		} else {
			if (j >= to) {		// From is colored, see if good region extends
				return;			// far enough.  If not, get following bad reg.
			} else if (!get_tagged_region("needs-color", j, &i, &j)) {
				int a, b, res;

				say("Coloring internal error 1");
				buffer_printf("debug-color", "Coloring internal error 1:\n");
				buffer_printf("debug-color", "bad color 0 from %d to %d in %s, size %d\n",
							  i, j, bufname, size());
				res = get_tagged_region("needs-color", from, &a, &b);
				buffer_printf("debug-color", "color %d at %d (from %d to %d) in %s, size %d\n",
							  res, from, a, b, bufname, size());
				res = get_tagged_region("needs-color", j - 1, &a, &b);
				buffer_printf("debug-color", "color %d at %d (from %d to %d) in %s, size %d\n",
							  res, j - 1, a, b, bufname, size());
				return;
			}
		}
		j = MIN(j, to);		// Color only some of it.
		if (i >= j)
			return;
		j = recolor_range(i, j);
		set_tagged_region("needs-color", i, j, 0);
		if (give_up++ > 100) {
			say("Coloring internal error 2");
			return;
		}
	}
}

is_c_keyword(p)		// is text in p (must be surrounded by |'s) a keyword?
char *p;
{
	if (strstr("|if|else|for|do|while|return|break|continue|switch|"
			   "case|default|goto|char|short|int|static|volatile|const|"
			   "float|double|long|void|", p))
		return 1;
	if (p[1] == '_' &&
		  strstr("|_asm|_based|_cdecl|_emit|_except|_export|_far|_fastcall|"
				 "_fortran|_huge|_interrupt|_loadds|_near|_pascal|_saveregs|"
				 "_segment|_segname|_stdcall|_syscall|_try|__int64|", p))
		return 1;
	if ((c_extra_keywords & EEL_KEYWORDS) &&
		  strstr("|keytable|buffer|window|command|on|color_class|"
				 "spot|save_spot|save_var|on_exit|user|zeroed|", p))
		return 1;
	if ((c_extra_keywords & CPP_KEYWORDS) &&
		  strstr("|asm|catch|class|delete|friend|inline|new|operator|"
				 "private|protected|public|template|try|this|virtual|"
				 "throw|_self|and|and_eq|bitand|bitor|bool|compl|const_cast|"
				 "dynamic_cast|explicit|false|mutable|namespace|not|not_eq|"
				 "or|or_eq|reinterpret_cast|static_cast|true|typeid|typename|"
				 "using|wchar_t|xor|xor_eq|", p))
		return 1;
	if ((c_extra_keywords & JAVA_KEYWORDS) &&
		  strstr("|abstract|boolean|byte|catch|class|extends|false|final|"
				 "finally|function|implements|import|in|instanceof|"
				 "interface|native|new|null|package|private|protected|"
				 "public|super|synchronized|this|throw|throws|transient|"
				 "true|try|var|with|", p))
		return 1;
	if (!(c_extra_keywords & JAVA_KEYWORDS) &&
		  strstr("|auto|enum|extern|register|unsigned|signed|sizeof|"
				 "struct|union|typedef|", p))
		return 1;		// C keywords not in Java.
	if ((c_extra_keywords & IDL_KEYWORDS) &&
		  strstr("|appobject|auto_handle|bindable|boolean|broadcast|byte|"
				 "callback|coclass|code|comm_status|context_handle|"
				 "control|decode|defaultbind|dispinterface|displaybind|"
				 "dual|enable_allocate|encode|error_status_t|"
				 "explicit_handle|fault_status|handle|handle_t|hidden|"
				 "hyper|idempotent|ignore|immediatebind|import|in|"
				 "include|interface|library|licensed|local|maybe|module|", p))
		return 1;
	if ((c_extra_keywords & IDL_KEYWORDS) &&
		  strstr("|ms_union|nocode|nonextensible|notify|object|odl|"
				 "oleautomation|optional|out|pipe|propget|propput|"
				 "propputref|public|ptr|readonly|ref|requestedit|"
				 "restricted|retval|small|source|string|unique|"
				 "usesgetlasterror|v1_enum|vararg|", p))
		return 1;
	return 0;
}

#define MAXREACH		2000
#define MATCHES(off1, off2)	(off1 < max1 - resynch_match_chars && \
							off2 < max2 - resynch_match_chars && \
							!memcmp(buf1 + off1, buf2 + off2, \
							resynch_match_chars))

resynch_by_chars()	/* move fwd to next match of resynch_match_chars */
{	/* in this & next window, assuming it's within MAXREACH chars */
	int max1, max2, max, i, reach, t;
	char buf1[MAXREACH], buf2[MAXREACH];

	grab(point, point + MAXREACH - 1, buf1);
	max1 = size() - narrow_end - point;
	next_user_window(1);
	grab(point, point + MAXREACH - 1, buf2);
	max2 = size() - narrow_end - point;
	next_user_window(-1);
	max = max1;
	if (max2 > max)
		max = max2;
	if (max > MAXREACH)		/* highest limit less than MAXREACH */
		max = MAXREACH;
	for (reach = 0; reach < max - resynch_match_chars; reach++) {
		for (i = 0; i <= reach; i++) {
			if (MATCHES(reach, i))
				t = reach, reach = i, i = t;	/* swap */
			else if (!MATCHES(i, reach))
				continue;
			point += i;
			next_user_window(1);
			point += reach;
			next_user_window(-1);
			say("Found a match, skipping %d and %d", i, reach);
			return;
		}
		if (reach > 10) {
			note("Trying to resynchronize...%d", reach);
			check_abort();
		}
	}
	say("Couldn't resynchronize.");
}

comp_read(trystr, prmpt, finder, flags, def)
char *trystr, *prmpt;
char *(*finder)();
char *def;		/* default value */
{
	int oldbuf, editbuf, ocmd_len = cmd_len, olen_def_mac = _len_def_mac;
	int skipped_redisp = char_avail();

	save_var postpone_asynchronous_notify = 1;
	error_if_input(1);
	*trystr = 0;
	if (run_by_mouse && ungot_key == -1 && finder
		  && ((flags & MUST_MATCH) || show_mouse_choices))
		ungot_key = '?';
	else if (insert_default_response)
		strcpy(trystr, def);
	save_var iter, has_arg, this_cmd, prev_cmd;
	save_var return_raw_buttons = 0;
	save_var permit_window_keys |= PERMIT_WHEEL_KEY;
	if ((flags & COMP_FILE) && !completion_literal_char)
		save_var completion_literal_char = literal_if_quoted;
	_grab_word_loc = point;
	_grab_word_start = 0;
	oldbuf = bufnum;
	editbuf = bufnum = tmp_buf();
	stuff(trystr);
	full_comp_read(trystr, prmpt, finder, flags, editbuf, def);
	bufnum = oldbuf;
	buf_delete(editbuf);
	if (_len_def_mac >= 0)	// now treat as one big cmd
		cmd_len = ocmd_len + _len_def_mac - olen_def_mac;
	check_abort();
	if (!skipped_redisp)		// skipped before, so skip now
		maybe_refresh();
	if (!(flags & PASSWORD_PROMPT))
		save_completion(trystr, finder);
	if (flags & COMP_FILE)
		drop_quotes(trystr);
	say("");
}

full_comp_read(trystr, prmpt, finder, flags, edit, def)
char *trystr, *prmpt, *def;
char *(*finder)();
{
	int i, j, num_match = 0, maxlen = ptrlen(trystr) - 1, pbuf, res;
	int pwin, editwin, owin = window_handle;
	int olen = 0, in_menu = 0, menu = -1, mbuf = 0;
	jmp_buf this_level;
	int *(*lister)();
	char password_display_class[256];

	save_var last_index;
	save_var _help_on_cmd = last_index;
	save_var _doing_input = DI_LINEINPUT;
	save_var _doing_completion = (finder != 0);
	save_var top_level = &this_level;

	while (!in_macro() && !char_avail() && unseen_msgs())
		check_abort();	// Wait for unseen msgs to display so we don't cover them.
	pwin = add_popup(0, echo_line, screen_cols - 1, 1, 0,
		pbuf = tmp_buf());	/* make system window with prompt */
	stuff(prmpt);
	i = current_column();
	system_window = 1;	/* don't let user switch to it */
	point = display_column = 0;
	text_color = color_class echo_area;
	_display_class = _echo_disp_class;

	editwin = add_popup(i, echo_line, screen_cols - i, 1,
							0, edit);
	display_column = 0;	/* horizontally scroll this window */
	text_color = color_class echo_area;
	_display_class = _echo_disp_class;
	if (flags & PASSWORD_PROMPT) {
		memset(password_display_class, '*', 256);
		_display_class = password_display_class;
		build_first = 1;
	}
	mouse_handler = allow_mouse_switching;
	if (insert_default_response == 1) {
		highlight_on();
		shift_selecting = 2;
	}
	if ((flags & POP_UP_PROMPT) && (has_feature & FEAT_GUI_DIALOGS)) {
		remove_window(pwin);
		do_display_dialog_box("OneLineBox", prmpt, editwin, 0, 0,
							  "OK", "Cancel", "Help");
	}
	maybe_refresh();
	if (setjmp(top_level)) {
		if (in_menu == 2) {	/* menu is half-created */
			remove_window(menu);
			buf_delete(mbuf);
			in_menu = mbuf = 0;
			if (is_gui && want_gui_prompts) {
				res = INP_ABORT;
				goto done;
			}
		}
	}
	for (;;) {
		window_handle = in_menu ? menu : editwin;
		mode_keys = in_menu ? menu_tab : comp_tab;
		_doing_input = (response_tracks_list && mbuf)
					   ? DI_LISTBOX : DI_LINEINPUT;
		if (_doing_input == DI_LISTBOX) {
			maybe_refresh();
			getkey();
			cmd_result = 0;
			run_topkey();
			res = cmd_result;
		} else
			res = do_recursion();	/* let user edit input */
		if (!is_window(editwin) || in_menu && !is_window(menu)) {
			res = INP_ABORT;
			break;
		} else if (window_handle == (in_menu ? editwin : menu))
			in_menu = !in_menu;
		window_handle = editwin;
		if (res == INP_ADD) {
			window_handle = editwin;
			run_topkey();
			if (search_in_menu) {
				window_handle = editwin;
				grab(0, maxlen, trystr);
				if (strlen(trystr) >= olen) {
					window_handle = menu;
					point = 0;
					if (!col_search(trystr, 0))
						in_menu = 0;
				}
			} else
				in_menu = 0;
		} else if (res == INP_SEEN)
			in_menu = 0;
		else if (res == INP_TO_LIST && mbuf) {
			window_handle = menu;
			in_menu = 1;
		} else if (res == INP_GET || res == INP_GET_EXIT) {
			window_handle = menu;
			get_menu_line(edit);
			window_handle = editwin;
			in_menu = 0;
		} else if (!res) {
			if (_doing_input == DI_LISTBOX)
				if (in_menu) {
					window_handle = menu;
					get_menu_line(edit);
				} else {
					window_handle = editwin;
					grab(0, maxlen, trystr);
					window_handle = menu;
					point = 0;
					col_search(trystr, 0);
				}
			continue;
		}
		restart_file_paths();
		if (res == INP_ABORT || res == INP_GET_EXIT || res == INP_EXIT)
			break;
		else if (res == INP_GRAB_WORD) {
			grab_buffer_word(owin, 0);
			continue;
		} else if (res == INP_GRAB_LINE) {
			grab_buffer_word(owin, 1);
			continue;
		} else if (res == INP_DEFAULT) {
			if (!size())	/* type in default text */
				stuff(def);
			in_menu = 0;
			continue;
		} else if (res == INP_LAST_RECALL) {
			get_last_recall(finder, trystr);
			if (*trystr && !mbuf) {
				delete(0, size());
				stuff(trystr);
			}
			in_menu = 0;
		} else if (res == INP_SHOW_MATCHES || res == INP_RECALL) {
show_matches:		grab(0, maxlen, trystr);	/* typed '?' */
			if (is_highlight_on() || res == INP_RECALL) {
				if (flags & COMP_FILE)
					*get_tail(trystr, 0) = 0;
				else
					*trystr = 0;
				highlight_off();
			}
			olen = strlen(trystr);
			if (!mbuf) {
				menu = new_menu(mbuf = tmp_buf());
				if (is_gui && want_gui_prompts) {
					remove_window(pwin);
					say("");
					make_prompt_box(res == INP_RECALL, prmpt, editwin, menu);
				}
			}
			in_menu = 2;		/* initializing */
			if (res == INP_RECALL)
				lister = list_recalls;
			else if (completion_lister)
				lister = completion_lister;
			else
				lister = list_matches;
			make_menu(menu, trystr, finder, flags, editwin, mbuf, lister);
			in_menu = 1;
			mode_keys = menu_tab;
			cursor_to_column = -1;
		} else if (res == INP_TRY || res == INP_COMPLETE) {
			if (res == INP_TRY && cursor_to_column
						== current_column() + 1)
				break;	/* exactly 1 match last time */
			grab(0, maxlen, trystr);
			i = strlen(trystr);
			num_match = complete(trystr, finder, flags);
			j = strlen(trystr);
			if ((flags & SPACE_VALID) && key == ' ' && trystr[i] == ' '
				  && could_add_space(trystr, finder, flags) == 1)
				i++, num_match++;
			else if (num_match && i != j)
				i = j;
			else if (num_match != 1) {
				if ((flags & SPACE_VALID) && key == ' ' && is_window(menu)
//					  && trystr[i] == ' ' 
// Given dirs c:\program files and c:\programs, this commented-out code
// made selecting the former fail.
				   && could_add_space(trystr, finder, flags)) {
					trystr[i++] = ' ';
				} else {
					maybe_ding(bell_on_completion);
					if (completion_pops_up)
						ungot_key = '?';
				}
			}
			if ((flags & COMP_FILE) && num_match == 1 && i > 0
			    && is_path_separator(trystr[i - 1]))
				num_match++;	/* might be directory */
			trystr[i] = 0;
			buf_zap(edit);
			stuff(trystr);
			if (num_match == 1) {
				if (res == INP_COMPLETE)
					break;	/* <Esc> worked */
				maybe_refresh();
				cursor_to_column = current_column() + 1;
			}
		}
	}
done:
	if (res != INP_ABORT)
		grab(0, maxlen, trystr);
	else if (!user_abort)		/* user deleted edit window */
		user_abort = 1;
	if (res == INP_EXIT && must_match(trystr, finder, flags))
		goto show_matches;
	if (is_window(owin))
		window_handle = owin;
	remove_window(editwin);
	remove_window(pwin);
	buf_delete(pbuf);
	if (mbuf) {
		remove_window(menu);
		buf_delete(mbuf);
	}
}

literal_if_quoted()
{
	return buffer_has_pattern("\"");
}

literal_always()
{
	return 1;
}

inp_try() on comp_tab[' ']
{
	if (completion_literal_char && (*completion_literal_char)())
		insert(' ');
	else
		pass_if_complete(INP_TRY);
}

inp_previous_page() on menu_tab['\b'], view_tab['\b'],
					   menu_tab[GREYBACK], view_tab[GREYBACK]
{
	if (_doing_input) {
		if (search_in_menu)
			pass_back(INP_ADD);
		else if (previous_page() && !paging_retains_view)
			if (_doing_input == DI_VIEWLAST)
				remove_final_view();
			else
				leave_recursion(INP_SEEN);
	} else
		do_command(root_keys[key]);
}

inp_remove_file_path()
{
	normal_character();
	undo_mainloop();
	if (point == size())
		restart_file_paths();
}

char *f_only_match();

get_file(res, pr, def)
char *res, *pr, *def;
{
	char rel[FNAMELEN];

//	relative(def, rel);
	strcpy(rel, def);
	if (!*rel) {
		get_buffer_directory(rel);
		save_var insert_default_response = 3;
	}
	if (*rel && is_directory(rel))
		save_var insert_default_response = 3;
	save_var completion_lister = list_file_matches;
	save_var abort_file_matching = ABORT_JUMP;
	save_var resize_menu_list = 1;
	if (only_file_extensions)  {
		prompt_comp_read(res, pr, f_only_match, COMP_FILE | FOLDFILE, rel);
	} else {
		save_var list_finder = do_file_match;
		prompt_comp_read(res, pr, f_match, COMP_FILE | FOLDFILE, rel);
	}
	if (*res && !wild_pattern(res))
		absolute(res);
}

get_file_dir(res, pr)
char *res, *pr;
{
	jmp_buf *old_level = top_level, this_level;
	char def[FNAMELEN], old[FNAMELEN];
	int ret = 0, ok;

	ok = get_buffer_directory(def);
	save_var completion_lister = list_file_matches;
	save_var list_finder = do_file_match;
	save_var abort_file_matching = ABORT_JUMP;
	save_var resize_menu_list = 1;
	save_var insert_default_response = 0;

	if (prompt_with_buffer_directory == PBD_INSERT)
		insert_default_response = 3;
	if (prompt_with_buffer_directory == PBD_TEMPCD) {
		top_level = &this_level;
		getcd(old);
		if (ok)
			chdir(def);
		ret = setjmp(top_level);
	}
	if (!ret)
		comp_read(res, pr, f_match, COMP_FILE | FOLDFILE, def);
	if (prompt_with_buffer_directory == PBD_TEMPCD)
		chdir(old);
	if (prompt_with_buffer_directory == PBD_INSERT && !strcmp(res, def))
		*res = 0;
	top_level = old_level;
	if (*res && !is_remote_file(res) && ok
		  && prompt_with_buffer_directory == PBD_TEMPCD)
		absolute(res, def);
	else if (*res && !wild_pattern(res))
		absolute(res);
	if (ret)
		longjmp(top_level, ret);
}

getkey()
{
	if (ungot_key != -1) {		/* check before calling */
		wait_for_key();
		return key;
	} else {
		if (want_auto_save && !cmd_len && !in_macro() && norm_binding()
			  && !_doing_input && _auto_save_counter++ > auto_save_count) {
			_auto_save_counter = 0;
			auto_save_buffers();
		}
		wait_for_key();
		if (key_type == KT_ACCENT_SEQ || key_type == KT_ACCENT) {
			if (!in_macro()) {	// For auto-quoting control and Alt-digit keys.
				_recent_keys[_recent_place++] = key;
				_recent_place %= MAXRECENT;
			}			// Record in macro that we got both.
			if (_len_def_mac > 0) {
				add_key_to_macro(CTRL('Q'));
				add_key_to_macro(key);
			}
			ungot_key = key;	// Now pretend we got Ctrl-Q then this char.
			key = CTRL('Q');
			user_abort = 0;
			return key;
		}
	}
	if (!in_macro() && IS_TRUE_KEY(key)) {
		_recent_keys[_recent_place++] = key;
		_recent_place %= MAXRECENT;
	}
	if (_len_def_mac > 0 && IS_TRUE_KEY(key))
		add_key_to_macro(key);
	return key;
}

command suspend_epsilon()
{
	signal_suspend();
}

command unbind_key()
{
	char keyname[80];
	short *binding, val = -1;

	binding = ask_key("Unbind key: ", keyname);
	sayput("Make \"%s\" Unbound, or make it Self-insert [U, S]? ", keyname);
	while (!user_abort && val == -1) {
		getkey();
		switch (toupper(key)) {
			case 'U':	val = 0; break;
			case 'S':	val = normal_character; break;
		}
	}
	say("");
	check_abort();
	if (val != -1)
		*binding = val;
	rebuild_menu();
}

char _fundamental_mode_name[] = "Fundamental";

mode_default_settings()
{
	indenter = indenter.default;
	if (!indenter)
		indenter = prev_indenter;
	auto_indent = auto_indent.default;
	strcpy(comment_start, comment_start.default);
	strcpy(comment_pattern, comment_pattern.default);
	strcpy(comment_begin, comment_begin.default);
	strcpy(comment_end, comment_end.default);
	mode_keys = buf_tab;		/* use these keys */
	major_mode = _fundamental_mode_name;
	when_displaying = 0;
	recolor_range = recolor_from_here = 0;
	drop_coloring(bufnum);
	make_mode();
}

command fundamental_mode()
{
	mode_default_settings();
}

zeroed TIMER idle_display_time;
int auto_show_delimiter_delay;	// time before next check (.01 sec units)

when_idle(cnt)
{
	int delay, disp;

	if (!cnt || time_done(&idle_display_time)) {
		show_idle_text();
		time_begin(&idle_display_time, 10);	// wait .1 seconds next time
	}
	if (auto_show_matching_characters && cnt == 1) {
		auto_show_delimiter_delay = 5;
		if (maybe_auto_show_delimiter() == 2)	// No match, wait .5 sec
			auto_show_delimiter_delay = 50;	 // before looking on next key.
		refresh();
	}
	if (!leave_blank && cnt == 2 && set_display_func_name())
		maybe_refresh();
	delay = when_idle_coloring(cnt);
	if (*show_when_idle) {		// Wait for .1 seconds.
		disp = time_remaining(&idle_display_time);
		if (delay < 0 || disp < delay)
			delay = disp;
	}
	if (cnt < 2 && (delay < 0 || auto_show_delimiter_delay < delay))
		delay = auto_show_delimiter_delay;
	return (cnt < 2) ? 0 : delay;
}

show_idle_text()
{
	char text[FNAMELEN], tmp[FNAMELEN];
	int col;

	if (*show_when_idle && !_doing_input && !_doing_completion
		  && !cmd_len) {
		strcpy(tmp, show_when_idle);
		substitute_func_name(tmp);
		make_title(text, tmp, 199);
		col = show_when_idle_column;
		if (col < 0)
			col = screen_cols + col;
		show_text(col, 0, "%s", text);
	}
}

char *get_dired_buffer_pattern()
{
	return dired_buffer_pattern ? dired_buffer_pattern : bufname;
}

do_dired_examine(fname, isdir)
char *fname;
{
	char file[FNAMELEN], *p;

	strcpy(file, fname);
	absolute(file);
	if (isdir == 3 && !is_remote_file(file))
		isdir = 0;	// symbolic link to a local file; get directly
	if (isdir) {
		if (is_remote_file(file) && isdir == 1
			  && is_path_separator(file[strlen(file) - 1]) != 1)
			strcat(file, "/");	// If dir, not link, add /.
		if (dired_one(file) || is_remote_file(file))
			return;
		strcpy(file, fname);
		p = get_tail(file, 0);	/* for .., go to right place */
		if (p > file && strcmp(p, "..") == 0) {
			p[-(opsys != OS_UNIX)] = 0;	// Remove / too unless Unix.
			p = get_tail(file, 0);
			strcat(p, "\n");
			col_search(p, goal_column);
			move_to_column(goal_column);
			build_first = 1;
		}
	} else			/* regular file */
		find_it(file, ask_line_translate());
}

dired_refresh()
{
	char msg[FNAMELEN];
	int yes, remote;

	if (modified) {
		sprintf(msg, "Relist %s, discarding markings? ", bufname);
		yes = ask_yn("Discard markings", msg, "Yes", "No", 1);
		check_abort();
		if (!yes)
			return;
	}
	remote = is_remote_file(get_dired_buffer_pattern());
	if (remote)
		point = 0;
	else
		save_var point, window_start;
	create_dired_listing(get_dired_buffer_pattern());
	restore_vars();
	if (!remote)
		move_to_column(goal_column);
	dired_orig_position = point;
	fix_window_start();
}

do_create_directory(int in_dired)
{
	char dir[FNAMELEN], cmd[FNAMELEN], url[FNAMELEN];

	if (!prompt_with_buffer_directory)
		save_var prompt_with_buffer_directory = 2;
	get_file_dir(dir, "Create directory: ");
	if (is_remote_file(dir)) {
		if (in_dired)
			dired_getdir(url);
		else
			strcpy(url, dir);
		sprintf(cmd, "MKD %s", get_url_file_part(dir, 0));
		ftp_misc_operation(url, cmd);
		say("Operation queued.");
	} else {
		mkdir(dir);
		if (is_dired_buf())
			dired_refresh();
	}
}

dired_mark_for_copy()
{
	if (is_remote_file(get_dired_buffer_pattern()))
		error("Copy operation not implemented for remote files.");
	dired_repl('C');
}

dired_do_delete(name, to, in_dired)	/* return 1 if error */
char *name, *to;
{
	int isdir = in_dired ? dired_isdir() : 0;

	to = to;
	if (is_remote_file(name)) {
		buffer_printf(REMOTE_FTP_OP_BUFFER,
					  isdir ? "RMD %s\n" : "DELE %s\n",
					  get_url_file_part(name, 0));
	} else {
		if (in_dired)
			noteput("Deleting %s.", name);
		if (isdir ? rmdir(name) : delete_file(name))
			return 1;
	}
	if (in_dired) {
		save_var modified;	// leave modify bit alone
		to_begin_line();	// but delete line
		delete(point - 1, give_end_line());
	}
	return 0;
}

/* Return 1 if error, 2 if we didn't do it but already showed error. */
dired_do_copy(name, to, in_dired)
char *name, *to;
{
	char dest[FNAMELEN];

	make_copy_name(name, to, dest);
	if (is_remote_file(name)) {
		if (!in_dired)
			noteput("Copy operation not implemented for remote files.");
		return 2;
	}
	if (in_dired)
		noteput("Copying %s to %s.", name, dest);

	if (!strcmp(name, dest) || warn_existing_file(dest))
		return 2;
	if (copyfile(name, dest))
		return 1;	// disallow copying file to itself
	if (in_dired) {
		save_var modified;	// leave modify bit alone
		dired_unmark();
		nl_reverse();
	}
	return 0;
}

make_copy_name(src, dest, res)	// if dest is a dir, append src to it
char *src, *dest, *res;		// else copy dest
{
	int remote = is_remote_file(dest);

	strcpy(res, dest);
	if (remote ? is_path_separator(res[strlen(res) - 1])
			   : is_directory(res)) {
		dest = res + strlen(res);
		if (*res && !is_path_separator(dest[-1]))
			*dest++ = remote ? '/' : path_sep;
		strcpy(dest, get_tail(src, 0));
	}
}

char *dired_prompt_regex_replace()
{
	if (!dired_regex_rename_data)		/* Get space for it. */
		dired_regex_rename_data = (struct dired_regex_rename_data *)
								  malloc(sizeof(struct dired_regex_rename_data));
	dired_regex_rename_data->whole_name = has_arg;
	dired_regex_rename_data->prompt = 1;
	dired_regex_rename_data->flags = get_replace_text(REGEX,
		dired_regex_rename_data->with);
	strncpy(dired_regex_rename_data->str,
			default_search_string(dired_regex_rename_data->flags), FNAMELEN - 1);
	return NULL;
}

int dired_do_delete(), dired_do_copy(), dired_do_move();
int dired_do_uppercase(), dired_do_lowercase(), dired_do_regex_rename();

dired_execute()
{
	char url[FNAMELEN];
	int del, copy, move, uc, lc, rr;

	if (is_remote_file(get_dired_buffer_pattern()) && exist(REMOTE_FTP_OP_BUFFER))
		zap(REMOTE_FTP_OP_BUFFER);
	del = dired_do_no_param("Delete", "\nD ", "deleted", dired_do_delete, 0);
	copy = dired_do_param("Copy", "\nC ", "copied", dired_do_copy);
	move = dired_do_param("Move", "\nM ", "moved", dired_do_move);
	uc = dired_do_no_param("Uppercase", "\nU ", "uppercased",
						   dired_do_uppercase, 0);
	lc = dired_do_no_param("Lowercase", "\nL ", "lowercased",
						   dired_do_lowercase, 0);
	rr = dired_do_no_param("Regex-rename", "\nR ", "regex-renamed",
						   dired_do_regex_rename, dired_prompt_regex_replace);
	if (del + copy + move + uc + lc + rr == 0)
		error("No files marked");
	modified = 0;
	if (!is_remote_file(get_dired_buffer_pattern()) && (move + copy + uc + lc + rr))
		dired_refresh();	// could be rename or similar, make new listing
	if (is_remote_file(get_dired_buffer_pattern())) {
		dired_getdir(url);
		send_remote_ftp_op(url);
	}
	fix_window_start();
	iter = 0;
}

command quick_dired_command()
{
	char file[FNAMELEN], rel[FNAMELEN], msg[FNAMELEN], dest[FNAMELEN];
	char dir[FNAMELEN];

	strcpy(file, filename);
	strcpy(dir, filename);
	*get_tail(dir, 0) = 0;
	if (!*file)
		error("This buffer has no associated file.");
	strcpy(rel, get_tail(file, 0));
	do {
		sayput("%s: D=Delete, Move, Copy, View, T=Props, .=Dired, "
			   "F=Folder, G=Go dir: ", rel);
		getkey();
		check_abort();
	} while (!isalpha(key) && (!IS_ASCII_KEY(key) || !strchr(".+!?", key)));
	say("");
	if (is_remote_file(file) && exist(REMOTE_FTP_OP_BUFFER))
		zap(REMOTE_FTP_OP_BUFFER);
	switch (toupper(key)) {
		case '.':
			dired_one(file);
			break;
		case 'D':
			sprintf(msg, "Delete %s? ", rel);
			if (!ask_yn("Delete file", msg, "Delete", "Cancel", 1))
				break;
			if (dired_do_delete(file, NULL, 0))
				file_error(errno, file, "Could not delete");
			else if (!is_remote_file(file))
				say("%s deleted.", file);
			break;
		case 'C':
			if (is_remote_file(file))
				error("Copy operation not implemented for remote files.");
			sprintf(msg, "Copy %s to: ", rel);
			get_file_dir(dest, msg);
			if (*dest) {
				switch (dired_do_copy(file, dest, 0)) {
					case 1:
						file_error(errno, dest, "Could not copy");
						break;
					case 0:
						say("%s copied.", file);
						break;
				}
			}
			break;
		case 'M':
			sprintf(msg, "Move %s to: ", rel);
			get_file_dir(dest, msg);
			if (*dest) {
				if (dired_do_move(file, dest, 0))
					file_error(errno, dest, "Could not move");
				else if (!is_remote_file(file))
					say("%s moved.", file);
			}
			break;
		case 'V':
			do_shell_execute(file, "Open", "run viewer");
			break;
		case 'T':
			do_shell_execute(file,  "Properties", "show properties");
			break;
		case 'F':
			do_shell_execute(dir, "Open", "run viewer");
			break;
		case 'G':
			if (chdir(dir))
				file_error(errno, dir, "unknown error");
			else {
				getcd(dir);
				say("Current directory: %s", dir);
			}
			break;
		case '+':
			do_create_directory(0);
			break;
		case '!':
			do_shell_command(file, dir);
			break;
		default:
			if (key == '?' || key == HELPKEY)
				help_on_command("quick-dired-command");
			else
				error("Invalid key.");
	}
	if (is_remote_file(file))
		send_remote_ftp_op(file);
}

dired_isdir_unix()
{
	save_var point;
	to_begin_line();
	save_var case_fold = 1;
	if (!parse_string(1, dired_dirsearch_unix))
		return 0;
	switch (character(matchend - 1)) {
		case 'l':	return 3;
		case 'L':	return 2;
	}
	return 1;
}

dired_isdir()
{
	char buf[FNAMELEN];
	int i;

	i = get_dired_item("dired-isdir-", 1);
	if (i)
		return (*(int (*)())i)();
	i = get_dired_item("dired-dirsearch-", 0);
	if (i) {
		save_var point;
		to_begin_line();
		return parse_string(1, get_str_var(i)) != 0;
	}
	dired_getindex(buf, ISDIR_START);
	return !strncmp(buf, DIRMARK, strlen(DIRMARK));
}

color_dired_range(from, to)
{
	int color, namecolor, old, namestart, nameend, isdir;
	char buf[FNAMELEN];

	if (from >= to)
		return to;
	detect_dired_format();
	save_var point, matchstart, matchend;
	point = from;
	save_var narrow_start = give_begin_line();
	point = to;
	nl_forward();
	save_var narrow_end = size() - point;
	point = 0;
	while (point < size() - narrow_end) {
		switch (curchar()) {
			case 'D': color = color_class dired_deleted; break;
			case 'U': case 'L': case 'R':
			case 'M': color = color_class dired_moved; break;
			case 'C': color = color_class dired_copied; break;
			default: color = color_class dired_normal; break;
		}
		old = point;
		if (parse_string(1, SKIPLINEPAT) != 0) {
			color = color_class dired_header;
			namestart = matchend;
			nameend = give_end_line();
			namecolor = color_class dired_dir_name;
		} else {
			dired_getindex(buf, goal_column);
			namestart = matchstart;
			nameend = matchend;
			namecolor = color_class dired_file_name;
			if (dired_format == DF_VMS)
				nameend = point + parse_string(1, "[^\n;]*;?[0-9]*");
			isdir = dired_isdir();
			if (isdir) {
				namecolor = color_class dired_dir_name;
				if (!dired_format)
					namestart = column_to_pos(ISDIR_START);
				if (isdir == 3)
					nameend = point + parse_string(1, ".* -> ");
			}
			if (!is_remote_file(get_dired_buffer_pattern())
				  && character(namestart - 1) == ' ')
				namestart--;
		}
		nl_forward();
		set_character_color(old, point - 1, color);
		set_character_color(namestart, nameend, namecolor);
	}
	return point;
}

detect_dired_format()
{
	int old = dired_format;

	dired_format = 0;
	goal_column = NAME_START;
	save_var point = 0, case_fold = 1;
	while (parse_string(1, SKIPLINEPAT))
		nl_forward();
	if (point >= size())
		return;
	if (parse_string(1, ".*" UNIX_DATE)) {
		dired_format = DF_UNIX;
		goal_column = get_column(matchend);
	} else if (parse_string(1, ".*" OLDNT_DATE)) {
		dired_format = DF_OLDNT;
		goal_column = 41;
	} else if (parse_string(1, ".*" VMS_DATE)) {
		dired_format = DF_VMS;
		goal_column = 2;
	} else if (!parse_string(1, ". [ 0-9][0-9]-[a-z][a-z][a-z]-[0-9][0-9]")) {
		dired_format = DF_SIMPLE;
		goal_column = 2;
	}
	if (dired_format != old)
		drop_all_colored_regions();
}

make_dired(dir)
char *dir;
{
	char tmp[FNAMELEN];

	modified = 0;
	save_var abort_file_matching = ABORT_JUMP;
	strcpy(tmp, dir);		// Our arg might be a dired_buffer_pattern that we're
	if (dired_buffer_pattern)	// about to delete.
		free(dired_buffer_pattern);
	dired_buffer_pattern = strsave(tmp);
	dir = tmp;
	if (is_remote_file(dir))
		do_remote_dired(dir);
	else if (do_dired(dir))
		return 1;
	detect_dired_format();
	switching_to_buffer();
	modified = 0;
	if (!is_remote_file(dir))
		sort_for_dired();
	else {
		to_end_line();
		type_point = size();
	}
	dired_orig_position = point;
	return 0;
}

dired_group_sorter(start, end)
{
	int on_col = goal_column, stripwid = 0, i;

	if (!dired_sorts_files || user_abort)
		return;
	save_var narrow_start = start;
	save_var narrow_end = size() - end;
	save_var point;
	save_var abort_searching = ABORT_ERROR;
	switch (toupper(dired_sorts_files)) {
		case 'D': stripwid = dired_sort_by_date(); break;
		case 'E': stripwid = dired_sort_by_exten(); break;
		case 'S': i = get_dired_item("dired-sort-by-size-", 1);
				  if (i)		// Call style-specific function.
					  stripwid = (*(int (*)())i)();
				  else
					  on_col = SIZE_COL;
					  break;
	}
	do_sort_region(0, size(), on_col, isupper(dired_sorts_files));
	if (stripwid)
		strip_columns(goal_column, goal_column + stripwid);
}

dired_sort_by_date()	/* insert stuff in each line, return length */
{
	char line[FNAMELEN], *p, *months;
	int end, hour, i, month;

	months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec ";
	if (size() - narrow_end - narrow_start > 10000)
		noteput("Sorting by date...");
	point = 0;
	i = get_dired_item("dired-sort-by-date-", 1);
	if (i)		// Call style-specific function.
		return (*(int (*)())i)();
	do {
		end = give_end_line();
		if (point == end)
			break;
		grab(point, end, line);
		hour = numtoi(line + 15);
		if (hour == 12)
			hour = 0;
		if (line[23] == 'p')
			hour += 12;
		line[8] = 0;
		p = strstr(months, line + 5);
		if (!p) {
			say("Unrecognized month %s, can't sort.", line + 5);
			p = months;
		}
		month = 1 + (p - months) / 4;	// Compute month 1..12.

		move_to_column(goal_column);
		bprintf("%.4s%2d%.2s%2d%.5s",
				line + 9, month, line + 2, hour, line + 18);
		point = end;
	} while (nl_forward());
	return 15;
}

command find_oem_file()
{
	save_var default_character_set = 2;
	find_file();
}

set_display_func_name()
{
	char subr[80];
	int i;

	if (!display_definition || is_window(window_handle) != ISTILED)
		return 0;
	display_func_name_buf = bufnum;	// Only show it in this buffer
	display_func_name_win = window_handle;	// or window.
	sprintf(subr, "%s_func_name_finder", major_mode);
	i = find_index(subr);
	switch (name_type(i)) {		// i has name table index of subr/var
		case NT_SUBR: case NT_COMMAND:
		case NT_AUTOSUBR: case NT_AUTOLOAD:
			(*(int (*)())i)();		// Cast i to a func ptr, then call it.
			break;
		default:					// No func names for this buffer.
			*display_func_name = 0;
	}
	if (display_func_name_method() == 1)
		make_mode();
	return 1;
}

// Should we display the name of the function we're currently editing.
// Returns 1: Display in window title; 2: Display in mode line; 0: Don't.
display_func_name_method()
{
	if (bufnum != display_func_name_buf
		  || display_func_name_win != window_handle)
		return 0;
	if ((has_feature & FEAT_SET_WIN_CAPTION) && (display_definition & 2))
		return 2;
	if ((display_definition & 1))
		return 1;
	return 0;
}

assemble_mode_line(m)	/* construct mode line in m */
char *m;
{
	int i, left;
	char *p, *q, file[FNAMELEN];

	strcpy(m, mode_start);
	if (mode_extra)
		strcat(m, mode_extra);
	p = m + strlen(m);
	left = ptrlen(p) - 30;
	if (!*filename || fnamecmp(get_tail(filename, 0), bufname)) {
		q = p;
		if (!is_dired_buf())
			*q++ = '(';
		strncpy_double_percents(q, bufname, left);
		q += strlen(q);
		if (!is_dired_buf())
			*q++ = ')';
		*q++ = ' ';
		*q = 0;
		left = ptrlen(p) - 30;
	}
	if (*filename && force_save_as != FSA_NEWFILE) {
		relative(filename, file);		/* if file, put name */
		strncpy_double_percents(p, file, left);
		strcat(p, " ");
	}
	if (mode_line_shows_mode) {
		for (i = _recursion_level; i-- >= 0;)
			strcat(p, "[");
		set_mode(p + strlen(p)); /* build part inside []'s in mode */
		for (i = _recursion_level; i-- >= 0;)
			strcat(p, "]");
	}
	strcat(p, mode_end);
	substitute_func_name(m);
}

// If m contains a %f sequence, replace it by the function name if any,
// doubling any %'s within.

substitute_func_name(char *m)
{
	char *p, *s, tmp[FNAMELEN];

	for (p = m; p = strchr(p, '%'); ) {	// look for %f in string.
		if (p[1] == 'f') {
			strcpy(tmp, p + 2);
			if (display_func_name_method() == 1 && *display_func_name) {
				for (s = display_func_name; *s; ) {
					if (*s == '%')
						*p++ = '%';
					*p++ = *s++;
				}
				*p++ = ' ';
			}
			strcpy(p, tmp);
		} else		// Skip past %% sequences.
			p += p[1] ? 2 : 1;
	}
}

char *name_of_filetype();

set_mode(mode)	/* add major and minor modes to mode line */
char *mode;
{
	strcpy(mode, major_mode);
	if (call_maybe_break_line(2))
		strcat(mode, " Fill");
	if (over_mode)
		strcat(mode, " Over");

	strcat(mode, name_of_filetype(translation_type));
	if (file_io_converter)
		strcat(mode, (*file_io_converter)(0));
	if (_len_def_mac)
		strcat(mode, " Def");
	if (ignore_kbd_macro || final_macro_pause || recording_suspended)
		strcat(mode, " Susp");
	if (narrow_start > 0 || narrow_end > 0)
		strcat(mode, " Narrow");
	if (_buf_readonly == 3)
		strcat(mode, " Pager");
	else if (_buf_readonly)
		strcat(mode, " RO");
}

compare_dates(a, b)
struct file_info *a, *b;
{
	int diff;

	if (a->fsize != b->fsize)
		return 1;
	// We test raw times to avoid an NT problem with daylight savings
	// time.  (Files on some file systems change their timestamps when
	// daylight savings time starts or ends, while files on other file
	// systems do not.)  Also we can easily ignore small time differences
	// which can occur over networks or in various other situations.
	diff = b->raw_file_date_low - a->raw_file_date_low;
	if (diff < 0)
		diff = -diff;
	if (a->raw_file_date_high || a->raw_file_date_low)	// Good, we have raw times.
		if (a->raw_file_date_high == b->raw_file_date_high)
			if (diff < file_date_tolerance)		// Raw times are available,
				return 0;					// and close, so they're equal.

	return a->year != b->year || a->month != b->month
			|| a->day != b->day || a->hour != b->hour || a->minute != b->minute
			|| a->second != b->second;
}

command write_file()
{
	char tmp[FNAMELEN], tmp2[FNAMELEN];
	int flags = OFN_NOREADONLYRETURN | OFN_HIDEREADONLY;

	iter = 0;
	if (use_common_file_dialog()) {
		strcpy(tmp, force_save_as == FSA_NEWFILE ? "" : filename);
		if (!use_common_open_file_dlg(tmp, "Save file as", &flags, 1))
			return 0;
	} else
		get_file_dir(tmp, "Write file: ");
	if (*tmp && is_directory(tmp) && *filename) {
		make_copy_name(filename, tmp, tmp2);
		strcpy(tmp, tmp2);
	}
	if (*tmp) {
		if (get_file_read_only(tmp) == 1)
			error("File %s is read-only.", get_tail(tmp, 0));
		if (warn_existing_file(tmp))
			return 0;
		if (has_arg)
			translation_type = ask_line_translate();
		set_buffer_filename(tmp);
		already_made_backup = 0;
		modified = 1;
		return do_save_file(1, 0, 1);
	}
	return 0;
}

send_printed_pages(fname)
char *fname;
{
	int total_pages, page = 1, printed = 0;
	char date[FNAMELEN];
	struct time_info t;

	// Collect info we need for the page header.
	time_and_day(&t);
	format_date(date, t.year, t.month, t.day, t.hour, t.minute, t.second);
	save_var display_column = print_long_lines_wrap ? -1 : 0;
	total_pages = count_printed_pages();

	window_start = point = 0;
	while (point < size() - narrow_end) {
		if (print_this_page(page)) {
			note("Printing page %d of %d...", page, total_pages);
			print_headings(fname, page, total_pages, date);
			show_printed_page();
			if (!print_eject())
				break;
			printed++;
		}
		point = window_start = next_printed_page(window_start);
		page++;
		if (user_abort)
			break;
	}
	return printed;
}

command print_buffer_no_prompt()
{
	do_print_region(window_bufnum, !is_highlight_on(), 1);
}

do_print_region(b, all, silent)
{
	int buf, err, transl, tabs, skipped_lines, cnt, cols;
	char to[FNAMELEN], title[FNAMELEN], *fname, *dest;
	int (*buf_recolor_range)();
	int (*buf_recolor_from_here)();
	char buf_want_code_coloring;
	char buf_c_extra_keywords;

	iter = 0;
	dest = is_unix ? print_destination_unix : print_destination;
	if ((has_feature & FEAT_OS_PRINTING) && want_gui_printing) {
		print_options.flags = all ? 0 : PD_SELECTION;
		if (silent)
			print_options.flags |= PD_RETURNDEFAULT;
		if (!select_printer(&print_options))
			return -1;		// User canceled.
		all = !(print_options.flags & PD_SELECTION);
		if (*filename)
			strcpy(title, get_tail(filename, 1));
		else
			strcpy(title, bufname);
		fname = filename;
	} else if (!silent) {
		get_strdef(to, "Print to device (or !command)", dest);
		strcpy(dest, to);
	}
	save_var bufnum = b;
	transl = translation_type, tabs = tab_size;
	buf_recolor_range = recolor_range;
	buf_recolor_from_here = recolor_from_here;
	buf_want_code_coloring = want_code_coloring;
	buf_c_extra_keywords = c_extra_keywords;
	buf = tmp_buf();
	save_spot point, mark;
	fix_region();		// handle other types of regions
	skipped_lines = all ? 0 : lines_between(0, point, 0);
	if (all)
		buf_xfer(buf, 0, size());
	else if (region_type() == REGRECT)
		extract_rectangle(buf, 0);
	else
		buf_xfer(buf, point, mark);
	bufnum = buf;
	translation_type = transl;		/* use orig buffer's vals */
	tab_size = tabs;
	recolor_range = buf_recolor_range;
	recolor_from_here = buf_recolor_from_here;
	want_code_coloring = buf_want_code_coloring;
	c_extra_keywords = buf_c_extra_keywords;
	if (want_code_coloring)		// maybe turn on coloring
		when_setting_want_code_coloring();

	point = 0;
	if (!print_tabs || print_line_numbers)
		tab_convert(0, size(), 0);
	if (print_line_numbers) {
		cnt = lines_between(0, size(), 0) + 1 + skipped_lines;
		for (cols = 0; cnt > 0; cols++)
			cnt /= 10;		// Compute maximum width of line numbers.
		cnt = 1;
		do {
			if (point >= size())
				break;
			bprintf("%*d  ", cols, skipped_lines + cnt++);
			set_character_color(give_begin_line(), point, -1);
		} while (nl_forward());
		point = 0;
	}
	if ((has_feature & FEAT_OS_PRINTING) && want_gui_printing) {
		gui_print(title, fname);
		err = 0;
	} else
		err = send_to_file_or_cmd(buf, dest);
	bufnum = b;
	buf_delete(buf);
	if (!err && !all)
		highlight_off();
	if (!err && !((has_feature & FEAT_OS_PRINTING) && want_gui_printing))
		say("%s printed.", all ? "Buffer" : "Region");
	return err;
}

send_to_file_or_cmd(b, file)	// copy buffer b to file, or send to cmd
char *file;
{
	int err;
	char *thisfile = file, cmdline[FNAMELEN], tempfile[FNAMELEN];

	if (!size()) {
		say("Nothing to print.");
		return -1;
	}
	save_var bufnum = b;
	if (*file == '!')
		make_temp_file(thisfile = tempfile, size());
	if (err = file_write(thisfile, translation_type)) {
		file_error(err, thisfile, "write error");
		maybe_ding(bell_on_write_error);
	}
	if (!err && *file == '!') {
		convert_to_8_3_filename(tempfile);
		build_filename(cmdline, file + 1, tempfile);
		err = do_push(cmdline, 0, -1);
		delete_file(tempfile);
	}
	return err;
}

command insert_file()
{
	char file[FNAMELEN];
	int flags = OFN_HIDEREADONLY;

	save_var show_mouse_choices = 1;
	if (use_common_file_dialog()) {
		strcpy(file, _region_file);
		if (!use_common_open_file_dlg(file, "Insert file", &flags, 0))
			return;
	} else {
		get_buffer_directory(_region_file);
		get_file(file, "Insert file", _region_file);
	}
	if (!*file)
		return;
	strcpy(_region_file, file);
	mark = point;			/* put mark before it */
	set_region_type(REGNORM);
	build_first = 1;
	do_insert_file(file, ask_line_translate());
	iter = 0;
}

command write_region()
{
	char file[FNAMELEN];
	int b = -1;
	int flags = OFN_NOREADONLYRETURN | OFN_HIDEREADONLY;

	if (use_common_file_dialog()) {
		strcpy(file, _region_file);
		if (!use_common_open_file_dlg(file, "Write region to file", &flags, 1))
			return;
	} else {
		get_buffer_directory(_region_file);
		get_file(file, "Write region to file", _region_file);
	}
	if (!*file)
		return;
	if (warn_existing_file(file))
		return;
	if (has_arg)
		save_var translation_type = ask_line_translate();
	strcpy(_region_file, file);
	save_spot point, mark;
	fix_region();		// handle other types of regions
	highlight_off();
	if (region_type() == REGRECT) {
		b = tmp_buf();
		extract_rectangle(b, 0);
		save_var bufnum = b;
		mark = 0;
	}
	if (!write_part(file, translation_type, point, mark))
		note_written(file);
	if (b != -1)
		buf_delete(b);
}

write_part(file, strip, start, end)
char *file;
{
	int orig = bufnum, buf, err;

	buf = tmp_buf();
	buf_xfer(buf, start, end);
	bufnum = buf;
	if (is_remote_file(file)) {
		filename = file;
		err = save_remote_file(file, strip, NULL);
	} else
		err = file_write(file, strip);
	bufnum = orig;
	if (!is_remote_file(file))
		buf_delete(buf);
	if (err) {
		file_error(err, file, "write error");
		maybe_ding(bell_on_write_error);
	}
	return err;
}

do_save_file(backup, checkdate, getdate) /* 0=ok, 1=err, 2=user canceled */
{				/* always prints status in echo area */
	struct file_info *finfo;
	char othername[FNAMELEN], msg[FNAMELEN];
	int err;

	iter = 0;
	if (!*filename || force_save_as)
		return write_file();
	if (checkdate)
		if (check_dates(1))
			return 2;
	if (_read_aborted) {
		relative(filename, othername);
		sprintf(msg, "Only part of %s was read from disk.  "
				"Save anyway? ", othername);
		if (!ask_yn("Confirm save", msg, "Save", "Cancel", 0))
			return 2;
	}
	build_filename(othername, backup_name, filename);
	if (backup && (want_backups && !already_made_backup
				   || want_backups == 2) && fnamecmp(filename, othername)) {
		make_backup(filename, othername);
		already_made_backup = 1;
	}
	finfo = getdate ? &file_info : 0;
	if (err = file_convert_write(filename, translation_type, finfo)) {
		auto_read_changed_file = 0;
		file_error(err, filename, "write error");
		maybe_ding(bell_on_write_error);
	} else {
		note_written(filename);
		undo_set_flag(UNDO_WRITE_FILE);
		if (finfo)
			update_readonly_warning(finfo);
	}
	return (err != 0);
}

buffer_to_end(char *buf, int limit)
{
	if (exist(buf)) {
		save_var bufname = buf;
		if (limit > 0) {
			point = size() - limit;
			to_begin_line();
			delete(0, point);
		}
		point = size();
	}
}

do_save_all_buffers(int newfile_bufs, int *count, int *failed)
{
	int i;

	save_var bufnum, window_bufnum;
	i = buf_list(0, 0);
	do {
		bufnum = i;
		if (!*filename || !modified || buffer_not_saveable)
			continue;
		if (newfile_bufs ? (force_save_as != FSA_NEWFILE)
						 : (force_save_as == FSA_NEWFILE))
			continue;	// Only do one group.
		if (newfile_bufs)	// Show the buffer we'll be prompting for.
			to_buffer_num(i);
		switch (do_save_file(1, 1, 1)) {
			case 1:
				buffer_printf("-messages", "save-all-buffers: Could not save %s\n",
							  filename);
				(*failed)++;
				break;
			case 0:
				buffer_printf("-messages", "save-all-buffers: Saved %s\n",
							  filename);
				(*count)++;
				break;
		}
	} while (i = buf_list(1, 1));
}

command save_all_buffers()
{
	int count = 0, failed = 0;

	buffer_to_end("-messages", 40000);
	do_save_all_buffers(0, &count, &failed);
	do_save_all_buffers(1, &count, &failed);
	if (failed) {
		if (in_bufed())
			do_bufed(0);
		error("%d file%s saved, %d file%s could not be saved.",
			  count, (count > 1) ? "s" : "",
			  failed, (failed > 1) ? "s" : "");
	}
	if (count) {
		say("%d file%s saved.", count, (count > 1) ? "s" : "");
		if (in_bufed())
			do_bufed(0);
	} else
		say("No files needed saving.");
	return count;
}

command find_unconverted_file()
{
	save_var default_character_set = 1;
	find_file();
}

find_linked_file_here(char *file)
{
	char subr[FNAMELEN], curdir[FNAMELEN], *s, *pat;
	int i = 0;

	save_var narrow_end = size() - give_end_line();
	if (opsys == OS_UNIX)
		pat = "[+-9A-z~]+[/.][+-9A-z]*[--9+A-z]";
	else
		pat = "([a-z]:)?[+-9A-z~]+<.>[+-9A-z]*[--9+A-z]";
	if (*filename) {
		s = get_extension(filename);
		sprintf(subr, "%s_find_linked_file", *s ? (s + 1) : "none");
		i = find_index(subr);		// Any special method for this file extension?
	}
	if (!i) {
		sprintf(subr, "%s_find_linked_file", major_mode);
		i = find_index(subr);		// Any special method for this buffer?
	}
	switch (name_type(i)) {		// i has name table index of subr/var
		case NT_SUBR: case NT_COMMAND:
		case NT_AUTOSUBR: case NT_AUTOLOAD:
			(*(int (*)())i)(file);		// Cast i to a func ptr, then call it.
			break;
		default:		// Look in file for something like a file name.
			point -= parse_string(-1, "[^ \t\n]*");
			if (!re_search(1, pat)) {
				to_begin_line();
				if (!re_search(1, pat))
					error("Can't find any file name on this line.");
			}
			if (strchr("\"'`", character(matchstart)))
				matchstart++;
			if (strchr("\"'`", character(matchend - 1)))
				matchend--;
			grab(matchstart, matchend, file);
			break;
	}
	get_buffer_directory(curdir);
	absolute(file, curdir);
}

command find_linked_file()
{
	char file[FNAMELEN], curdir[FNAMELEN];

	*file = 0;
	if (is_highlight_on()) {
		save_var point, mark;
		fix_region();
		if (mark - point < FNAMELEN - 1 && !lines_between(point, mark, 0))
			grab(point, mark, file);
	}
	if (!*file)
		find_linked_file_here(file);
	get_buffer_directory(curdir);
	absolute(file, curdir);
	quiet_set_bookmark();
	tiled_only();
	locate_window("", file);
	do_find(file, ask_line_translate());
}

find_in_other_buf(fname, transl)
char *fname;
{
	char bname[FNAMELEN+10];
	int err;

	make_bname(fname, bname);
	to_buffer(bname);
	if (default_character_set == 2)
		file_io_converter = oem_file_converter;
	else
		file_io_converter = 0;
	err = read_file(fname, transl);
	call_mode(filename);
	make_mode();
	return err;
}

call_by_suffix(file, pattern)	// construct a subr name from extension
char *file, *pattern;		// of file name, try to call it
{				// return 1 if we found something to call
	char *s, subr[FNAMELEN], def[FNAMELEN];

	s = get_extension(file);
	sprintf(subr, pattern, *s ? (s + 1) : "none");
	sprintf(def, pattern, "default");
	return try_calling(subr) || try_calling(def);
}

guess_mode_without_extension(char *res, char *pat)
{
	if (!strfcmp(get_tail(filename), "makefile")) {
		sprintf(res, pat, "mak");	// Recognize special file name
		return 1;					// w/o .mak extension.
	}
	save_var point = 0;
	if (parse_string(1, "#%!.*/perl")) {
		sprintf(res, pat, "perl");
		return 1;
	}
	if (parse_string(1, "(:.*\n)?#%!.*/(sh|csh|bash)</word>|:\n")) {
		sprintf(res, pat, "sh");
		return 1;
	}
	if (size() > 1000)		// Look in 1st 1000 chars only.
		save_var narrow_end = size() - 1000;
	if (parse_string(1, "[ \t\n]*(//|/%*|#)")
		  && re_search(1, "^[ \t]*(#define|#include)[ \t]+")) {
		// It starts with a comment or preprocessor line, and it's
		// got a #define or #include, so assume it's a C++ header
		// file.
		sprintf(res, pat, "hpp");
		return 1;
	}
	point = 0;
	if (translation_type == FILETYPE_UNIX && parse_string(1, "([ \t]*\n)*#")) {
		sprintf(res, pat, "conf");
		return 1;
	}
	return 0;
}

suffix_none()		// Try to detect the file type from its contents.
{
	char mode[FNAMELEN];

	if (guess_mode_without_extension(mode, "suffix-%s"))
		if (try_calling(mode))
			return;
	suffix_default();
}

suffix_default()
{
	char mode[FNAMELEN];

	if (guess_mode_without_extension(mode, "suffix-%s"))
		if (try_calling(mode))
			return;
	fundamental_mode();
}

command locate_file()
{
	char file[FNAMELEN], pat[FNAMELEN], tmp[FNAMELEN];
	int d;

	get_string(file, "Locate files matching the pattern: ");
	if (is_unix) {
		sprintf(pat, "%s%s", locate_path_unix, file);
	} else {
		strcpy(pat, "{");
		for (d = 'C'; d < 'Z'; d++) {
			sprintf(tmp, "%c:\\", d);
			if (filename_rules(tmp) & FSYS_LOCAL)
				sprintf(pat + strlen(pat), "%c,", d);
		}
		if (strlen(pat) < 2)
			error("Can't determine local drive list.");
		pat[strlen(pat) - 1] = '}';
		sprintf(pat + strlen(pat) - 1, "}:\\**\\%s", file);
	}
	sayput("Listing files matching %s...", pat);
	dired_one(pat);
}

get_buffer_directory(dir)
char *dir;
{
	int ok = 1;

	*dir = 0;
	if (is_dired_buf())		/* get directory name from dired */
		dired_getdir(dir);
	else if (!strcmp(bufname, PROCBUF))	// process buffer?
		strcpy(dir, process_current_directory);
	else if (!strcmp(bufname, INFO_BUF))
		ok = 0;
	else {
		strcpy(dir, filename);
		if (!*filename || (force_save_as & FSA_NEWFILE)) {
			ok = 0;			// No file name, so use Epsilon's cur dir
			*dir = 0;		// but say we couldn't find anything specific.
		}
		absolute(dir);
		if (ok)			/* want only directory part */
			*get_tail(dir, 1) = 0;
	}
	if (!*dir) {
		ok = 0;
		getcd(dir);
	}
	if (*dir) {
		dir += strlen(dir);	/* ptr to end of string */
		if (!is_path_separator(dir[-1])) {
			*dir++ = path_sep; /* make sure it ends with slash */
			*dir = 0;
		}
	}
	return ok;
}

switching_to_buffer()
{		// put "timestamp" on this buffer showing last access
	hide_auto_show_delimiter();
	buf_accessed = ++buf_accessed_clock;
}

command forward_paragraph()
{
	char pat[100];

	do_shift_selects();
	re_search(1, ".");
	sprintf(pat, "\n%s|\f",
			indents_separate_paragraphs ? "[ \t\n]" : "[ \t]*\n");
	if (tex_paragraphs) {	/* skip formatter lines */
		to_begin_line();
		re_search(1, "(([@.]|^\\(begin|end)|^[ \t]*%%).*\n)*");
		re_search(1, "[^ \t\n@.\\]");
		strcat(pat, "|^\\(begin|end)|^[ \t]*%%");
	}
	if (re_search(1, pat)) {
		point--;
		if (curchar() != '\f') {
			if (!indents_separate_paragraphs)
				re_search(-1, "[ \t]*");
			if (tex_paragraphs)
				re_search(-1, "^(([@.]|^\\(begin|end)|^[ \t]*%%).*\n)*");
		}
	} else
		point = size();
}

command backward_paragraph()
{
	do_shift_selects();
	if (tex_paragraphs) {
		if (character(point - 1) == '\n')
			re_search(-1, "^(([@.]|^\\(begin|end)|^[ \t]*%%).*\n)*");
		re_search(-1, "[^ \t\n]");
		if (matches_at(give_begin_line(), 1, "^\\(begin|end)|^[ \t]*%%"))
			to_begin_line();
		if (indents_separate_paragraphs) {
			if (re_search(-1, "\n[ \t\n]|\f|^\\(begin|end|^[ \t]*%%)"))
				re_search(1, "\n*");
		} else
			re_search(-1, "(\n[ \t]*\n|\f|^\\(begin|end)|^[ \t]*%%)!");
		if (curchar() != '\f')
			re_search(1, "^(([@.\f]|^\\(begin|end)|^[ \t]*%%).*\n)*");
	} else {
		re_search(-1, "[^ \t\n]");
		if (indents_separate_paragraphs) {
			if (re_search(-1, "\n[ \t\n]|\f|\n\\(begin|end|\n[ \t]*%%)"))
				re_search(1, "\n*");
		} else
			re_search(-1, "(\n[ \t]*\n|\f)!");
	}
}

command auto_fill_mode()
{
	call_maybe_break_line(has_arg? (iter != 0) : !call_maybe_break_line(2));
	make_mode();
	iter = 1;
}

call_maybe_break_line(int mode)
{
	if (buffer_maybe_break_line)
		return (*buffer_maybe_break_line)(mode);
	switch (mode) {
		case 0:
		case 1:		fill_mode = (mode != 0);
					return 0;
		case 2:		return fill_mode != 0;
	}
	return fill_mode ? maybe_break_this_line() : 1;
}

command fill_region()
{
	save_var point;
	if (has_arg)
		save_var margin_right = (iter > 5) ? iter : 32000;
	if (region_type() == REGRECT)
		fill_rectangle(0);
	else {
		fix_region();
		do_fill_region();
	}
}

command fill_paragraph()
{
	int end;

	if (has_arg)
		save_var margin_right = (iter > 5) ? iter : 32000;
	if (is_highlight_on()) {
		fill_region();
		return;
	}
	save_var point;
	iter = 0;
	point--;
	forward_paragraph();
	end = point - 1;
	backward_paragraph(); 
	re_search(1, "[ \t\n]*");	/* leave leading whitespace intact */
	if (point < end)
		region_fill(point, end);
	if (display_column > 0)
		display_column = 0;
	fix_window_start();	/* win shouldn't start in middle of line */
}

grep_prompt(flags, inbufs)
{
	char filepat[FNAMELEN];

	_last_was_grep = 1;
	tiled_only();
	iter = 0;
	error_if_input(1);	/* error if we're in the middle of input */
	flags = get_search_string("List lines with: ",
							  flags | (inbufs ? BUFGREP : FILEGREP));
	flags &= ~(INCR | FAILING | BAD | REVERSE);
	if (!get_grep_file(inbufs, filepat))
		return;
	do_grep("grep", default_search_string(flags), flags, filepat, inbufs);
}

get_grep_file(inbufs, filepat)
char *filepat;
{
	char pr[FNAMELEN];

	if (!inbufs) {
		if (*_grep_files)
			sprintf(pr, "In file(s) [%r]: ", _grep_files);
		else
			sprintf(pr, "In file(s): ");
		save_var prompt_with_buffer_directory = grep_prompt_with_buffer_directory;
		get_file_dir(filepat, pr);
		if (*filepat)
			strcpy(_grep_files, filepat);
		relative(_grep_files, filepat);
		if (!*filepat)
			return 0;
	} else
		comp_read(filepat, "In buffers [pattern]: ", b_match, 0, bufname);
	return 1;
}

ok_grep_file_match(char *s)
{
	char pat[FNAMELEN];

	save_var case_fold = (FOLDFILE != 0);
	sprintf(pat, "|%s|", get_extension(s));
	return strstr(grep_ignore_file_extensions, pat) == NULL;
}

do_grep(buf, pat, flags, filepat, inbufs)
char *buf, *pat, *filepat;
{
	int res = 0, aborted = 0, cnt = 0, tempbuf = 0, i;
	int orig, before_head, this_err;
	char *s, rel[FNAMELEN], abs[FNAMELEN], search_type[80], *(*finder)();
	spot start;

	create(buf);
	if (grep_empties_buffer)
		zap(buf);
	locate_window(buf, "");
	point = size();
	if (size())
		bprintf("\n");	/* separate from previous query */
	make_search_prompt(search_type, flags & SMODES);
	before_head = point;
	getcd(abs);
	bprintf("Found 0 lines with %s\"%s\" in %s (cur dir \"%s\")\n",
			search_type, pat, filepat, abs);
	set_character_color(before_head, point, color_class grep_header);
	start = alloc_spot(0);
	if (display_column.default != -1)
		display_column = 0;	/* horizontally scroll this window */
	grep_mode();
	finder = give_grep_finder(inbufs, filepat, &s);	// get 1st match
	save_var readonly_warning |= ROWARN_GREP;
	readonly_warning &= ~(ROWARN_MSG | ROWARN_BELL);
	orig = bufnum;
	for (; s; s = (*finder)(filepat, 0)) {
		if (!inbufs && !ok_grep_file_match(s))
			continue;
		grep_make_names(rel, abs, s, inbufs);
		noteput("%d matches, searching %s...", cnt, rel);
		if (inbufs)	// skip over grep results buffer
			this_err = !strcmp(s, buf);
		else if (!look_file(abs)) {
			this_err = find_it(abs, default_translation_type);
			if (!grep_keeps_files)
				tempbuf = bufnum;
		} else {
			this_err = 0;
			check_dates(0);
		}
		if (this_err == EREADABORT || user_abort) {
			aborted = 1;
			break;
		} else if (this_err) {
			window_bufnum = orig;
			if (tempbuf)
				buf_delete(tempbuf);
			tempbuf = 0;
			continue;
		}
		res = copy_matches(name_to_bufnum(buf), flags, pat, rel);
		window_bufnum = orig;
		if (res < 0)	/* error occurred during search */
			break;
		else if (res > 0) {
			cnt += res;
			build_first = 1;
			point = before_head;
			delete(point, point + parse_string(1, "Found [0-9]+ "));
			bprintf("Found %d ", cnt);
			set_character_color(before_head, point, color_class grep_header);
			point = size();
			refresh();
		}
		if (tempbuf)
			buf_delete(tempbuf);
		tempbuf = 0;
	}
	window_bufnum = orig;
	point = i = *start;
	free_spot(start);
	build_first = 1;
	if (tempbuf)
		buf_delete(tempbuf);
	say("");
	if (aborted)
		quick_abort();
	if (res == -DSBAD)
		error("Illegal search pattern: %s", pat);
	else if (res != -DSABORT) {
		locate_window(buf, "");
		modified = 0;
		point = i;
	}
}

grep_examine() on grep_tab[' '], grep_tab['\n'],
				  grep_tab['e'], grep_tab['\r'], grep_tab[GREYENTER]
{
	int start, end, colon, old, instance, i, toolong = 0;
	char file[FNAMELEN], string[FNAMELEN], line[FNAMELEN], curdir[FNAMELEN], *p;

	_last_was_grep = 1;
	to_begin_line();
	save_var case_fold = 0;		/* turn off for grep buffer */
	if (!search(1, ": "))
		error("Can't read file name");
	colon = point;
	to_begin_line();
	start = point;
	to_end_line();
	end = point;
	point = start;
	grab(start, colon - 2, file);
	if (start + FNAMELEN - 3 < end)
		end = toolong = start + FNAMELEN - 3;
	grab(colon, end, string);
	line[0] = '\n';		// Put \n at start and end of line.
	grab(start, end + 1, line + 1);
	instance = count_instances(line) + 1;
	if (strstr(file, BUFPREFIX) != file) {
		grep_get_curdir(curdir);
		absolute(file, curdir);
		locate_window("", file);
		if (find_it(file, ask_line_translate()))
			return;
	} else if (exist(p = file + sizeof(BUFPREFIX) - 1))
		to_buffer(p);
	else
		error("Can't find buffer %s.", p);
	if (strlen(line) != end - start + 2)
		error("Can't find matching lines with null characters.");
	old = point;
	save_var case_fold = 0;		/* turn off for user buffer */
	point = 0;
	for (i = 0; i < instance; i++)
		if (toolong ? !search(1, string) : !line_search(1, string)) {
			point = old;
			if (i == 0 || instance == 1)
				error("Can't find \"%s\"", string);
			else
				error("Can't find this copy of "
					  "repeated line");
		} else {
			old = point;
			if (i + 1 < instance)
				nl_forward();
		}
	to_begin_line();
	if (toolong)
		say("Line too long; this may not be the correct match.");
}

grep_get_curdir(char *dir)
{
	save_var point;
	search(-1, "\nFound ");
	point += parse_string(1, "\nFound .* lines with \"");
	search(1, "\"");
	if (parse_string(1, ".*%(cur dir \"(.*)\"%)\n"))
		grab(find_group(1, 1), find_group(1, 0), dir);
	else
		getcd(dir);
}

drop_matching_lines(drop, pr)
char *pr;
{
	int flags;

	tiled_only();
	iter = 0;
	error_if_input(1);	/* error if we're in the middle of input */
	save_var point;
	flags = get_search_string(pr, UNKNOWN | REGEX | BUFGREP);
	restore_vars();
	flags &= ~(INCR | FAILING | BAD | REVERSE);
	do_drop_matching_lines(flags, default_search_string(flags), drop);
}

prompt_file_replace(flags, inbufs)
{		// prompt for replacing in files/buffers, then do it
	char *str, with[FNAMELEN], filepat[FNAMELEN];

	flags = get_replace_text(flags | (inbufs ? BUFGREP : FILEGREP),
							 with);
	if (flags == -1 || !get_grep_file(inbufs, filepat))
		return;
	str = default_search_string(flags);
	do_file_replace(str, with, flags, filepat, inbufs);
}
			
do_file_replace(str, with, flags, filepat, inbufs)
char *str, *with, *filepat;	// (query-) replace across files/buffers
{
	int res, oldbuf = 1, prevbuf = 0, total = 0, cnt = 0;
	char rel[FNAMELEN], abs[FNAMELEN], *s, *(*finder)();
	int total_found = 0, total_changed = 0, old_readonly;

	old_readonly = readonly_warning;
	save_var readonly_warning;			// Don't show msg or ring bell
	readonly_warning &= ~(ROWARN_MSG | ROWARN_BELL); // unless matches.
	finder = give_grep_finder(inbufs, filepat, &s);	// Get 1st match
	save_var window_bufnum;
	for (; s; s = (*finder)(filepat, 0)) {
		if (!inbufs && !ok_grep_file_match(s))
			continue;
		grep_make_names(rel, abs, s, inbufs);
		noteput("Searching %s...", rel);
		if (!inbufs) {
			oldbuf = look_file(abs);
			find_it(abs, default_translation_type);
		} else
			to_buffer(s);
		undo_mainloop();
		res = one_file_replace(str, with, flags, oldbuf, old_readonly);
		total_found += replace_num_found;
		total_changed += replace_num_changed;
		total++;
		if (res >= 0)
			cnt++;
		if (prevbuf && buf_in_window(prevbuf) == -1) {
			buf_delete(prevbuf);	// delete untouched new bufs
			prev_forget(_prev_num - 1); // fix default
		}
		prevbuf = (oldbuf || modified) ? 0 : bufnum;
		if (res == 0 && (flags & QUERY) && key == '!'
			&& ask_continue_replace("Replace without asking"))
			flags &= ~QUERY;	// no more querying
		else if (res == DSABORT || res == 1 && ungot_key != -1) {
			if (!ask_continue_replace("Continue replacing"))
				break;
		} else if (res > 0) {	// User said to stop, or bad pattern.
			if (res == DSBAD)
				show_replace(str, with, flags | BAD);
			user_abort = 0;
			return;
		}
		ungot_key = -1;
		if (user_abort)
			break;
	}
	ungot_key = -1;
	user_abort = 0;
	say("Replaced %d of %d matches in %d of %d %s.",
	    total_changed, total_found, cnt, total,
	    inbufs ? "buffers" : "files");
}

prompt_for_help()
{
	for (;;) {
		mention("Help on (? for choices): ");
		do {
			getkey();
		} while (!IS_TRUE_KEY(key));
		check_abort();
		say("");
		if (root_keys[key] == (short) help || key == '?')
			dodesc("help", "help", 0);
		else if (key < 128)
			switch (tolower(key)) {
				case 'k': describe_key(); return;
				case 'c': describe_command(); return;
				case 'a': apropos(); return;
				case 'b': show_bindings(); return;
				case 'q': what_is(); return;
				case 'l': show_last_keys(); return;
				case 'v': about_epsilon(); return;
				case 'r': describe_variable(); return;
				case 'm': help_on_mode(); return;
				case 'i': info(); return;
				case 'f': epsilon_info_look_up(); return;
				case 'w': win_help_contents(""); return;
				case 'h': epsilon_html_look_up(); return;
				case CTRL('C'): info_goto_epsilon_command(); return;
				case CTRL('K'): info_goto_epsilon_key(); return;
				case CTRL('V'):
				case CTRL('R'): info_goto_epsilon_variable(); return;
			}
	}
}

use_winhelp()
{
	if (has_feature & FEAT_WINHELP)
		if (is_win32 == IS_WIN32_GUI)
			return want_gui_help;
		else
			return want_gui_help_console;
	return 0;
}


command epsilon_manual()
{
	if (!(has_feature & FEAT_WINHELP))
		epsilon_manual_html();
	else
		win_help_string("", "Epsilon Manual Contents");
}

html_help_check_ok()
{
	if (is_unix != IS_UNIX_XWIN && !is_gui && !is_win32)
		error("Don't know how to run a web browser in this environment, sorry.");
}

// Cause this URL to be displayed by a browser.
show_url(char *url)
{
	char cmd[300], prog[300];

	if (is_win32) {
		get_executable_directory(prog);
		strcat(prog, "lhelp.exe");
		sprintf(cmd, "lhelp -u \"%s\"", url);
		winexec(prog, cmd, SW_SHOWMINNOACTIVE, 0);
		return;
	} else if (is_unix == IS_UNIX_XWIN) {
		get_executable_directory(cmd);
		sprintf(cmd + strlen(cmd), "goto_url \"%s\"", url);
		if (!shell("", cmd, ""))
			return;
	}
	error("Can't start a browser, please access %s manually.", url);
}

html_help_string(char *topic)
{
	char url[FNAMELEN], prog[FNAMELEN], *p, *q, cmdline[100], dir[FNAMELEN];

	if (epsilon_manual_port > 0)
		sprintf(url, "http://127.0.0.1:%d/man/", epsilon_manual_port);
	else
		strcpy(url, "http://www.lugaru.com/cgi-bin/lhelp/man/");
	for (p = topic, q = url + strlen(url); *p; p++, q++)
		if (*p == ' ') {
			strcpy(q, "%20");
			q += 2;
		} else
			*q = *p;
	*q = 0;
	if (!*topic)
		strcat(url, "0");
	get_executable_directory(prog);
	p = lookpath("lhelp/epsilon.lhl");
	if (p) {		// Find name of directory containing our lhelp files.
		strcpy(dir, p);
		*get_tail(dir, 0) = 0;
	} else
		get_executable_directory(dir);
	convert_to_8_3_filename(dir);
	if (opsys == OS_UNIX) {
		sayput("Running a browser...");
		sprintf(prog + strlen(prog), "lhelpd -p %d -d %s &",
				epsilon_manual_port, dir);
		if (epsilon_manual_port > 0)
			shell("", prog, "");
	} else if (is_gui || is_win32) {
		sayput("Starting a browser, please wait...");
		strcat(prog, "lhelp.exe");
		sprintf(cmdline, "lhelp -p %d -d %s", epsilon_manual_port, dir);
		if (epsilon_manual_port > 0)
			winexec(prog, cmdline, SW_SHOWMINNOACTIVE, 0);
	} else
		error("Don't know how to run a web browser in this environment, sorry.");
	show_url(url);
	note("");
}

command epsilon_html_look_up()
{
	char topic[FNAMELEN], def[FNAMELEN], file[FNAMELEN], *p;

	html_help_check_ok();
	*def = 0;
	if (!strcmp(bufname, INFO_BUF)) {
		info_get_file(file);
		if (strstr(file, "epsilon")) {
			p = strchr(filename, ')');
			strcpy(def, p ? (p + 1) : filename);
		}
	}
	get_strnone(topic, "Show browser-hosted Epsilon documentation "
				"on topic [show title page]: ", def);
	html_help_string(topic);
}

command epsilon_manual_html()
{
	html_help_check_ok();
	html_help_string("");
}

command view_lugaru_web_site()	// point browser to Lugaru's web site
{
	if (is_unix == IS_UNIX_XWIN) {
		show_url("www.lugaru.com");
	} else {
		char *s = lookpath("lugaru.url");

		if (!s)			// Can't find URL file, so try this other method.
			s = "http://www.lugaru.com";
		run_viewer(s, "Open", "");
	}
}

add_help_line(s)
char *s;
{
	one_help_line(s, "api32.hlp", "Windows API (32-bit)"); // VC2
	one_help_line(s, "win32.hlp", "Windows API (32-bit)");	// Old name
	one_help_line(s, "win31wh.hlp", "Windows API (16-bit)"); // VC1
	one_help_line(s, "tcwhelp.hlp", "Windows API (16-bit)"); // BC3.1
	one_help_line(s, "mfc.hlp", "MFC v1.0"); // VC1
	one_help_line(s, "mfc20.hlp", "MFC v2.0"); // VC2
	one_help_line(s, "mfc30.hlp", "MFC v3.0"); // VC2
	one_help_line(s, "cxx20.hlp", "C/C++ Language"); // VC2
	one_help_line(s, "mscxx.hlp", "C/C++ Language (VC 1.X)"); // VC1
	one_help_line(s, "crt20.hlp", "MSVC 2.X Run Time"); // VC2
	one_help_line(s, "msvc20.hlp", "MSVC 2.X Tools"); // VC2
	one_help_line(s, "mscopts.hlp", "MSVC 1.X Build Tools"); // VC1
	one_help_line(s, "classlib.hlp", "Borland Class Library"); // BC5
	one_help_line(s, "bcpp.hlp", "Borland C/C++ Library"); // BC5
	one_help_line(s, "bcb4.hlp", "Borland C++ Builder v4"); // Borland C++...
	one_help_line(s, "bcb5.hlp", "Borland C++ Builder v5"); // ...Builder
	one_help_line(s, "obpascal.hlp", "Borland Object Pascal Reference");
	one_help_line(s, "vcl.hlp", "Borland Visual Component Library");
	one_help_line(s, "cwg.hlp", "Borland Component Writers Guide");

		// MSDL interface (not actually help files)
	one_help_line(s, "msdntool.exe", "Find in MSDL");
	one_help_line(s, "msdntool.exe", "Look Up Keyword in MSDL");
		// MSDL interface (not actually help files)
	one_help_line(s, "iv2tool.exe", "Find in MSDL");
	one_help_line(s, "iv2tool.exe", "Look Up Keyword in MSDL");
}

tell_key(full, pr)
char *pr;
{
	char msg[80],tmp[80], *flavor;
	int index;

	index = *ask_key(pr, tmp);
	user_abort = 0;
	say("");
	if (index <= 0)
		sprintf(msg, "The key %s is not bound to any command.", tmp);
	else {
		switch (name_type(index)) {
			case NT_MACRO:	flavor = "macro"; break;
			case NT_SUBR:	flavor = "subroutine"; break;
			default:	flavor = "command"; break;
		}
		sprintf(msg, "%s runs the %s %s.",
				tmp, flavor, name_name(index));
		if (full == 2)
			info_to_epsilon_node(name_name(index), 1);
		else if (full) {
			if (use_winhelp())
				show_help_for(name_name(index));
			else
				dodesc(name_name(index), msg, 1);
			return;
		}
	}
	say("%s", msg);
}

command describe_command()
{
	char cmd[80];

	if (use_winhelp() && run_by_mouse) {
		win_help_string("", "commands, list of");
		return;
	}
	iter = 0;
	save_var show_mouse_choices = 1;
	get_cmd(cmd, "Describe command", "");
	show_cmd_help(cmd);
}

show_cmd_help(cmd)
char *cmd;
{
	char msg[160];

	if (use_winhelp()) {
		sprintf(msg, "%s command", cmd);
		win_help_string("", msg);
	} else {
		descr_bindings(cmd, msg);
		dodesc(cmd, msg, 1);
	}
}

command describe_variable()
{
	char var[80];

	if (use_winhelp() && run_by_mouse) {
		win_help_string("", "all variables, list of");
		return;
	}
	iter = 0;
	save_var show_mouse_choices = 1, show_all_variables = 1;
	get_var(var, "Describe variable", "", MUST_MATCH);
	restore_vars();
	show_var_help(var);
}

show_var_help(var)
char *var;
{
	char msg[80];

	if (use_winhelp()) {
		sprintf(msg, "%s variable", var);
		win_help_string("", msg);
	} else {
		make_var_help(var, bufnum, window_handle, 0);
		sprintf(msg, " Help on %s ", var);
		view_help(msg, 1);
	}
}

dodesc(str, also, last)
char *str, *also;
{
	char *old = bufname, msg[80];
	int start, i;

	if (use_winhelp()) {
		show_help_for(str);
		return;
	}
	if (!get_doc(0))
		return;
	i = find_index(str);
	if (!i || name_help(i) < 0) {
		gripe("No information on %s", str, last);
		bufname = old;
		return;
	}
	point = name_help(i);
	while (isspace(curchar()))
		point++;
	start = point;
	re_search(1, "^!~");
	xfer(HELPBUF, start, point);
	bufname = HELPBUF;
	if (also && *also)
		point = 0, stuff(also);
	insert('\n');
	point = 0;
	bufname = old;
	sprintf(msg, " Help on %s ", str);
	view_help(msg, last);
}

grab_man_word_from_buffer(int b, int pos, char *word, char *pat)
{
	*word = 0;
	save_var bufnum = b, point = pos;
	point--;		// Get to start of word nearest point.
	re_search(1, pat);
	re_search(-1, pat);
	re_search(1, pat);
	if (point - matchstart + 1 < ptrlen(word))
		grab(matchstart, point, word);
}

literal_if_args()
{
	save_var point = 0;
	return !isalpha(curchar()) || search(1, " ");
}

// Matches path lines from man.conf or manpath.conf.
#define MANCONF_PATH	"^(MANDATORY_|OPTIONAL_)?MANPATH" \
						"(_MAP[ \t]+[^ \t\n]+)?[ \t]+([^ \t\n]+)$"

// Compute a list of directories where man pages might be, and put in
// dest.

build_man_path(char *dest)
{
	int tmp = tmp_buf();

	save_var bufnum = tmp;
	if (!file_read("/etc/manpath.config", FILETYPE_AUTO)
		  || !file_read("/etc/man.config", FILETYPE_AUTO)) {
		do_drop_matching_lines(REGEX, MANCONF_PATH, 0);
		string_replace(MANCONF_PATH, "#3", REGEX);
	}
	stuff("/usr/man\n/usr/share/man\n");
	do_sort_region(0, size(), 0, 0);
	do_uniq(1, 1, 0);
	simple_re_replace(0, "\n", ":");
	simple_re_replace(REGEX, ":<eof>", "");
	grab(0, size(), dest);
	restore_vars();
	buf_delete(tmp);
}

char *man_match(s, flags)
char *s;
{
	char pat[FNAMELEN], match[FNAMELEN], *path, *t, *f, *q;
	char man_path[FNAMELEN * 2];

	if ((flags & STARTMATCH) && *s && (!isalpha(*s) || s[1] == ' ')) {
		zap(_MATCH_BUF);	// Something like "-k foo" or "2 bar".
		buffer_printf(_MATCH_BUF, "%s%s\n", s, (flags & LISTMATCH) ? "" : " ");
		// Just return text itself as the match.
	} else if (flags & STARTMATCH) {
		sayput("Listing matches...");
		zap(_MATCH_BUF);
		path = getenv("MANPATH");
		if (!path)
			build_man_path(path = man_path);
		while (!user_abort) {
			t = strchr(path, path_list_char);
			if (t)
				strncpy(pat, path, t - path);
			else
				strcpy(pat, path);
			if (*pat && pat[strlen(pat) - 1] != '/')
				strcat(pat, "/");
			sprintf(pat + strlen(pat), "man*/%s*", s);
			f = do_file_match(pat, STARTMATCH);
			for (; f && !user_abort; f = do_file_match(pat, 0)) {
				strcpy(match, get_tail(f, 0));
				q = get_extension(match);
				if (q && !strcmp(q, ".gz"))
					*q = 0;
				q = get_extension(match);
				if (!q || !*q)
					continue;
				*q = 0;
				buffer_printf(_MATCH_BUF, "%s\n", match);
			}
			if (!t)
				break;
			path = t + 1;
			drop_pending_says();
		}
		save_var bufname = _MATCH_BUF;
		point = 0;
		do_sort_region(0, size(), 0, 0);
		do_uniq(1, 1, 0);
		restore_vars();
	}
	return general_matcher(s, flags);
}

man_find_linked_file(char *file)
{
	c_find_linked_file(file);
}

keytable man_tab;
char _man_mode_name[] = "Man";

man_mode()
{
	mode_keys = man_tab;
	major_mode = _man_mode_name;
	mouse_dbl_selects = 1;
	make_mode();
}

man_follow_link() on man_tab['\n'], man_tab['e'], man_tab['\r'],
					 man_tab[GREYENTER]
{
	char buf[FNAMELEN];

	save_var sort_status = 0, abort_searching = 0;
	grab_man_word_from_buffer(bufnum, point, buf,
							  "[-+_0-9a-z:]+(%(..?%))?");
	if (man_rewrite(buf))
		make_man_page(buf);
	else
		error("Not a manual page cross-reference; must use open(2) format.");
}

// Rewrite "open(2)" into "2 open"; return nonzero if we did.
man_rewrite(char *buf)
{
	char p1[FNAMELEN], p2[FNAMELEN], *p;

	if (*buf && (p = strchr(buf, '('))) {
		strcpy(p1, p + 1);
		*p = 0;
		p = strchr(p1, ')');
		if (p)
			*p = 0;
		strcpy(p2, buf);
		for (p = p1; *p; p++)
			*p = tolower(*p);
		sprintf(buf, "%s %s", p1, p2);
		return 1;
	}
	return 0;
}

command man() on man_tab['m']
{
	char topic[FNAMELEN], buf[FNAMELEN];

	save_var sort_status = 0, abort_searching = 0;
	grab_man_word_from_buffer(bufnum, point, buf,
							  "[-+_0-9a-z:]+(%(..?%))?");
	man_rewrite(buf);
	save_var completion_literal_char = literal_if_args;
	prompt_comp_read(topic, "Show manual entry for", man_match,
					 COMP_FOLD | SPACE_VALID | CAUTIOUS, buf);
	if (!*topic)
		return;
	make_man_page(topic);
}

make_man_page(char *topic)
{
	char cmdline[FNAMELEN], buf[FNAMELEN];
	int color;

	sprintf(cmdline, "man %s", topic);
	sprintf(buf, "man-%s", topic);
	to_buffer(buf);
	man_mode();
	if (!size()) {
		set_read_only(0);
		pipe_text(NULL, buf, cmdline, NULL,
				  PIPE_SYNCH | PIPE_CLEAR_BUF | PIPE_NOREFRESH, 0);
		point = 0;
		if (parse_string(1, "Reformatting.*please wait.*\n"))
			delete(0, matchend);
		simple_re_replace(1, "\n\n\n+", "\n\n");
		set_character_color(0, size(), -1);
		point = 0;
		while (re_search(1, ".\b.")) {
			if (character(point - 3) == '_')
				color = color_class man_underlined;
			else
				color = color_class man_bold;
			delete(point - 3, point - 1);
			set_character_color(point - 1, point, color);
			point--;
		}
		filename = "fake-man-file.man";	// So find-linked-files works.
		force_save_as = FSA_NEWFILE;
		discardable_buffer = buffer_not_saveable = 1;
	}
	modified = point = 0;
	set_read_only(3);
}

command show_last_keys()
{
	char line[200];
	int i, c, len;

	len = MIN(screen_cols - _view_left - _view_right - 15, sizeof(line));
	if (use_winhelp())
		len = 48;
	bufnum = zap(HELPBUF);
	bprintf("The last %d keys pressed were:\n", MAXRECENT);
	*line = 0;
	for (i = 0; i < MAXRECENT; i++) {
		c = _recent_keys[(i + _recent_place) % MAXRECENT];
		if (c == ' ')
			strcat(line, "<Sp>");
		else
			show_char(line, c, 1);
		if (strlen(line) >= len)
			bprintf("%s\n", line), *line = 0;
		else
			strcat(line, " ");
	}
	bprintf("%s", line);
	view_help(" Last Keys Pressed ", 1);
}

command about_epsilon()
{
	if (is_gui)
		about_box();
	else {
		save_var bufnum = zap(HELPBUF), window_start;
		about_box();
		save_var indents_separate_paragraphs = 1;
		save_var margin_right = screen_cols - _view_left - _view_right - 10;
		fill_paragraph();
		margin_right = screen_cols - _view_left - _view_right;
		point = 0;
		do {
			center_line();
		} while (nl_forward());
		point = 0;
		restore_vars();
		view_help(" About Epsilon ", 1);
	}
}

html_recolor_from_here(safe)
{
	int start = point;

	safe = safe;			// avoid compiler warning
	if (re_search(-1, "%<%!--|-[ \t\n]*>|%<[%?]|[%?]%>"))
		return point;
	return start;
}

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

html_move_level(int dir, int stop_on_key)
{
	char *findch = (dir > 0) ? "<" : ">";
	char *otherch = (dir < 0) ? "<" : ">";

	stop_on_key = stop_on_key;		// Silence EEL's warning.
	return default_move_level(dir, findch, otherch);
}

int color_html_range(), html_recolor_from_here();

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

command indent_region()
{
	int temp;
	int (*func)() = (int (*)()) (mode_keys['\t'] ? mode_keys['\t']
		: root_keys['\t']);
	int progress, cnt = 0;

	fix_region();
	highlight_off();
	if (nl_reverse())
		point++;
	temp = point;
	progress = (mark - point > 4000);
	this_cmd = CMD_INDENT_REG;
	while (point < mark) {
		(*func)();
		if (curchar() == '\n')
			delete_horizontal_space();
		nl_forward();
		if (!(cnt % 25) && progress && temp - mark != 0)
			note("Indenting region: %d%%...",
				 100 * (point - temp ) / (mark - temp));
		cnt++;
		check_abort();
	}
	if (progress)
		say("");
	mark = temp;
	this_cmd = iter = 0;
}

do_save_kill(near, far)		/* near is end adjacent to old text */
{
	do_save_only(near, far);
	delete(near, far);
}

do_save_only(near, far)		/* near is end adjacent to old text */
{
	char *thisbuf = bufname;

	check_num_kill_buffers();
	if (prev_cmd != APPENDKILL || !NORM_REGION(_kill_width[_num_kill])) {
		push_kill();		/* start on a new killbuffer */
		_kill_width[_num_kill] = (region_type() == REGLINE)
								 ? REGION_LINE : REGION;
	} else { /* get to proper end of same kill buffer as last time */
		bufname = _cur_kill_buf;
		point = (near < far) ? size() : 0;
		bufname = thisbuf;
	}
	xfer(_cur_kill_buf, near, far);
	this_cmd = APPENDKILL;
	save_to_clipboard();
}

int set_font_for_unix()
{
	char buf[200];

	pipe_text(NULL, _MATCH_BUF, "xlsfonts", NULL,
			  PIPE_SYNCH | PIPE_CLEAR_BUF | PIPE_NOREFRESH, 0);
	save_var bufname = _MATCH_BUF;
	if (lines_between(0, size(), 0) < 5) {
		say("Couldn't run xlsfonts to list the fonts.");
		return 0;
	}
	point = 0;			// Discard obviously proportional fonts.
	save_var sort_status = 0;
	do_drop_matching_lines(REGEX, "-p-[^-\n]*-[^-\n]*-[^-\n]*$", 1);
	drop_pending_says();
	do_uniq(1, 1, 0);
	restore_vars();
	save_var resize_menu_list = 1;
	prompt_comp_read(buf, "Select a font", general_matcher,
					 COMP_FOLD | MUST_MATCH | NONE_OK, font_fixed);
	if (!user_abort)
		font_fixed = buf;
	if (strcmp(font_fixed, buf))
		say("Sorry, can't use that font.");
	else
		say("Edit your ~/.Xdefaults file (or similar) to use this font in future sessions.");
	return 1;			// User picked one, even if it was bad.
}

command change_font_size()
{
	char *s, name[50], buf[50], old[50];
	int h, w, dir;

	if (is_unix)
		error("Please use the set-font command to select a font.");
	strcpy(old, font_fixed);
	strcpy(name, font_fixed);
	s = index(name, ',');
	*s = 0;
	h = numtoi(s + 1);
	s = index(s + 1, ',');
	w = numtoi(s + 1);
	s = index(s + 1, ',') + 1;		// rest of spec
	for (;;) {
		note("Using font %s %dx%d, screen is %dx%d. "
			 "(Press an arrow key to change.)",
			 name, h, w, screen_cols, screen_lines);
		getkey();
		if (user_abort || key == BELL || key == ESC) {
			font_fixed = old;
			break;
		}
		dir = get_direction();
		switch (dir) {
			case BTOP:		if (h > 0) h--; break;
			case BBOTTOM:	h++; break;
			case BLEFT:		if (w > 0) w--; break;
			case BRIGHT:	w++; break;
		}
		if (dir != -1) {
			sprintf(buf, "%s,%d,%d,%s", name, h, w, s);
			font_fixed = buf;
			refresh();
		} else if (IS_ENTER_KEY(key) || key == ' ')
			break;
		else if (IS_TRUE_KEY(key))
			say("Press <Esc> to abort, <Enter> to keep these settings.");
	}
	say("");
}

command mouse_to_tag()
{
	int k = key;

	if (has_feature & FEAT_OS_MENUS) {
		context_menu();
	} else if (mouse_other_handler())
		return;
	else if (!in_text_area(mouse_x, mouse_y)) // clicked in border
		mouse_move_border(1);
	else if (IS_MOUSE_DOUBLE(key) && mouse_dbl_selects)
		run_enter_key();
	else {
		if (mouse_goes_to_tag && IS_MOUSE_DOUBLE(key) &&
			  !(mouse_shift & (KB_SHIFT_DN | KB_CTRL_DN | KB_ALT_DN))) {
			mouse_display = 0;
			point_to_pos(mouse_x, mouse_y, mouse_screen);
			pluck_tag();
		} else
			mouse_selecting();
		mouse_call_hook(k);	// call correct hook for this key
	}
}

int _orig_thumb = -1, _orig_pos;

scroll_thumb_track(thumb, maxval)
int thumb, maxval;
{
	int s = size();

	if (thumb == 0){
		point = 0;
		return;
	} else if (thumb == maxval){
		point = s;
		return;
	}

	if (scroll_bar_type == 1 && is_win32 == IS_WIN32_GUI) {
		if (_orig_thumb == -1){		// line-based scroll bar
			_orig_thumb = thumb;
			_orig_pos = lines_between(0, window_start, 0) + 1;
			return;
		}

		go_line(_orig_pos + muldiv(lines_between(0, size(), 0)
								   - text_height() / 2,
								   thumb - _orig_thumb, maxval));
		window_start = point;
		point = next_screen_line(text_height() / 2);
		move_to_column((point > 0 && goal_column >= 0) ? goal_column : 0);
		return;
	}

	if (_orig_thumb == -1){
		_orig_thumb = thumb;
		_orig_pos = point;
		return;
	}

// Compute the amount to move;
	point = _orig_pos + muldiv(s, thumb - _orig_thumb, maxval);
	if (point > 0 && goal_column >= 0)
		move_to_column(goal_column);
	else
		to_begin_line();
	window_start = prev_screen_line(text_height() / 2);
}

no_running()			/* make sure no process is running */
{
	if (!is_process_buffer(name_to_bufnum(PROCBUF)))
		return 0;
	say("A process is already running in buffer %s.", PROCBUF);
	if (strcmp(bufname, PROCBUF)) {
		tiled_only();
		locate_window(PROCBUF, "");
		maybe_refresh();
	}
	point = size();
	return 1;
}

do_push(cmdline, cap, show)
char *cmdline;	// cap nonzero means capture output, show means show it to user
{		// but show -1 means don't wait for keystroke
	char *s, dir[FNAMELEN], old[FNAMELEN];
	int result, tbuf;

	if (!(has_feature & FEAT_MULT_CONCUR) && !another_process())
		save_var restart_concurrent = 0;
	if (opsys == OS_DOS && !is_gui && !is_win32)
		try_exit_concurrent();
	if (is_unix == IS_UNIX_XWIN && !*cmdline)
		cmdline = push_cmd_unix_interactive;
	iter = 1;
	before_push();
	if (start_process_in_buffer_directory) {
		getcd(old);
		get_buffer_directory(dir);
		chdir(dir);
	}
	result = shell("", cmdline, cap ? bufnum_to_name(tbuf = tmp_buf())
					: "");
	if (start_process_in_buffer_directory == 2)
		chdir(old);
	if (cap) {
		process_captured(tbuf, cmdline);
		buf_delete(tbuf);
	} else if (cmdline[0] && show != -1 && !is_gui && !is_win32 && !is_unix) {
		if (!char_avail()) {
			s = "Press any key to return to Epsilon";
			term_write(0, screen_lines - 1, s, strlen(s),
				color_class after_exiting, 1);
			term_position(strlen(s), screen_lines - 1);
		}
		getkey();
	}
	after_push();
	if (cmdline[0] && cap && show) {
		locate_window(PROCBUF, "");
		point = size();
	}
	if (result == -1 && errno) {
		file_error(errno, "During exec", "Couldn't exec");
		quick_abort();
	}
	maybe_restart_concurrent();
	if (cmdline[0] && result)
		say("Process returned %d", result);
	else
		check_dates(0);
	return result;
}

process_captured(b, cmdline)	/* move captured output to process buffer */
char *cmdline;
{
	save_var bufnum;
	create(PROCBUF);
	bufname = PROCBUF;
	if (clear_process_buffer)
		zap(PROCBUF);
	point = is_process_buffer(bufnum) ? type_point : size();
	set_error_spot();
	_had_errors = 0;
	if (point > 0 && character(point - 1) != '\n')
		insert('\n');
	if (cmdline[0])
		bprintf("%s\n", cmdline);
	grab_buffer(b);
	if (point > type_point)
		type_point = point;
}

command start_process()
{
	char cmd[FNAMELEN], *cmdline, *sh, fixup[FNAMELEN], *p;
	char cust1[FNAMELEN], cust2[FNAMELEN];

	_last_was_grep = 0;
	tiled_only();
	if (no_running())
		return;
	error_if_input(1);
	cmdline = get_cmdline("Start Process With Command", cmd);
	create_concur(cmdline);
	iter = 1;
	locate_window(PROCBUF, "");
	if (opsys == OS_UNIX && (sh = getenv("SHELL"))) {
		*cust1 = *cust2 = *fixup = 0;
		if (p = lookpath("epsilon.sh", 0))
			strcpy(cust1, p);
		if (p = lookpath("epsilon.csh", 0))
			strcpy(cust2, p);
		if (!*cust1 || !*cust2)
			sprintf(fixup, "echo \"Customization file not found, "
					"no customizations performed.\">/dev/null");
		else if (strstr(sh, "/sh") || strstr(sh, "/bash") || strstr(sh, "/ksh"))
			sprintf(fixup, ". %s; set +o emacs", cust1);
		else if (strstr(sh, "/csh") || strstr(sh, "/tcsh"))
			sprintf(fixup, "source %s", cust2);
		else
			sprintf(fixup, "echo \"Unrecognized shell, no customizations "
					"performed.\">/dev/null");
		delay(40, 0);	// Let's first get a prompt if we can.
		point = type_point;
		bprintf("%s\n", fixup);
	}
	point = size();
	process_mode();
}

create_concur(cmdline)
char *cmdline;
{
	char dir[FNAMELEN], old[FNAMELEN];
	int err = 0;

	create(PROCBUF);
	if (clear_process_buffer)
		zap(PROCBUF);
	if (start_process_in_buffer_directory) {
		getcd(old);	// Don't switch to proc buffer before
		get_buffer_directory(dir);	// doing this.
		chdir(dir);
	}
	bufname = PROCBUF;
	point = size();
	if (!is_process_buffer(bufnum))
		err = do_concur_shell("", cmdline);
	if (start_process_in_buffer_directory == 2)
		chdir(old);
	if (err) {
		file_error(errno, "During exec", "Couldn't exec");
		quick_abort();
	}
}

command stop_process()
{
	halt_process(has_arg ? iter : 0, is_process_buffer(bufnum) ? bufnum : 0);
	iter = 1;
}

command exit_process()
{
	tiled_only();
	if (!exist(PROCBUF) || !is_process_buffer(name_to_bufnum(PROCBUF)))
		error("No process to exit");
	bufname = PROCBUF;
	type_point = point = size();
	stuff("exit\n");
	delay(500, COND_PROC);
	if (is_process_buffer(bufnum) && !char_avail()) {
		locate_window(PROCBUF, "");
		error("Couldn't exit from concurrent process.");
	}
}

command kill_process()
{
	if (!process_kill(is_process_buffer(bufnum) ? bufnum : 0))
		say("Unable to kill the process.");
}

command compile_buffer()
{		// compile the current buffer (mode-specific)
	int res;
	char cmd[FNAMELEN], oscmd[FNAMELEN], full[FNAMELEN], *ext;

	tiled_only();
	if (!compile_buffer_cmd) {
		ext = get_extension(filename);
		sprintf(cmd, "compile-%s-cmd", *ext ? (ext + 1) : "none");
		sprintf(oscmd, "%s-%s", cmd, is_unix ? "unix" :
				is_win32 ? "win32" : "other");
		if ((ext = get_str_var(find_index(oscmd)))
			  || (ext = get_str_var(find_index(cmd))))
			save_var compile_buffer_cmd = ext;
	}
	if (!compile_buffer_cmd) {
		get_string(cmd, "Command to compile this buffer: ");
		compile_buffer_cmd = strsave(cmd);
	}
	save_var concurrent_make, shell_shrinks;
	if (pre_compile_hook)	// hook can change above vars
		if ((*pre_compile_hook)())
			return;		// hook says don't do compile
	if (concurrent_compile < 3)
		concurrent_make = concurrent_compile;
	if (concurrent_compile == 0 && (is_gui || is_win32))	// Run in the 
		concurrent_make = 4;		// concur proc if any, but keep control.
	if (start_process_in_buffer_directory) {
		char dir[FNAMELEN], old[FNAMELEN];

		getcd(old);
		get_buffer_directory(dir);
		chdir(dir);
		build_filename(full, compile_buffer_cmd, filename);
		chdir(old);
		if (start_process_in_buffer_directory == 2)	// For error msgs.
			save_var start_process_in_buffer_directory = 1;
	} else
		build_filename(full, compile_buffer_cmd, filename);
	res = do_compile(full);
	if ((!res || res == 4) && post_compile_hook)
		(*post_compile_hook)(res);
}

compile_via_dll()	// Try to compile .e file using a DLL, return 1 if ok.
{
	if (!is_win32)
		return 0;			// Only supported in 32-bit Windows.
	_had_errors = 0;
	save_var point;
	switch (eel_compile(bufname, 0, compile_eel_dll_flags, "eel-errors")) {
		case 2:		// Couldn't access DLL.
			say("Unable to compile using eel_lib.dll, running process.");
			return 0;
		case 0:
			say("%s compiled and loaded.%s",
				filename ? filename : "Buffer",
				buffer_size("eel-errors") ? "  (There were warnings.)" : "");
	}
	restore_vars();
	save_var bufname = "eel-errors";
	if (size()) {
		point = 0;			// Starting at the beginning,
		set_error_spot();	//    scan in this buffer.
		do_next_error(1, NULL);	// Scan for error messages.
	} else {
		restore_vars();
		delete_buffer("eel-errors");
	}
	return 1;
}

compile_handler(int activity, int buf, int from, int to)
{
	to = to;			// Prevent compiler warning.
	if (activity == NET_DONE) {
		save_var bufnum = buf;
		point = size();
		if (size() && character(point - 1) != '\n')
			bprintf("\n");
		bprintf("Process exited with status %d\n", from);
	}
}

do_compile(cmd)
char *cmd;
{
	int err = 0, nerr, sep_buf_ok = 0;
	int obuf = bufnum;
	char *procbuf = PROCBUF, curdir[FNAMELEN];

	_last_was_grep = 0;
	if (maybe_save_all())
		return 3;
	if (start_process_in_buffer_directory)
		get_buffer_directory(curdir);
	else
		getcd(curdir);
	drop_final_slash(curdir);
	if (!(has_feature & FEAT_MULT_CONCUR) && !another_process())
		save_var restart_concurrent = 0;

	// If we're allowed to run non-concur, then use separate buffer.
	if (concurrent_make < 2 && (has_feature & FEAT_MULT_CONCUR)
		  && compile_in_separate_buffer)
		sep_buf_ok = 1;
	if (concurrent_make == 2)
		create_concur("");
	else if (!sep_buf_ok && concurrent_make == 0)
		try_exit_concurrent();
	if (sep_buf_ok) {
		bufnum = create(procbuf = "compilation-output");
		tab_size = process_tab_size;
		discardable_buffer = 1;
		point = size();
		set_error_spot();
		_had_errors = 0;
		bprintf("Running `%s' in directory `%s'\n", cmd, curdir);
		type_point = size();
		if (!concur_shell("", cmd, curdir, procbuf)) {
			while (process_exit_status == PROC_STATUS_RUNNING) {
				if (char_avail() && getkey() != MOUSE_MOVE) {
					ungot_key = key;	// Wait until user presses a key
					return 2;			// or process finishes.
				}
				delay(10, COND_KEY);	// Delay 0.1 secs
			}
			err = process_exit_status;
		} else
			err = -1;
	} else if (concurrent_make == 4 && is_process_buffer(name_to_bufnum(PROCBUF))) {
		save_var bufname = PROCBUF;	// Run the program in the concur
		set_error_spot();			// proc buffer, but don't process
		_had_errors = 0;			// the user's keys until it finishes.
		if (*cmd) {
			point = size();
			bprintf("%s\n", cmd);
		}
		maybe_refresh();
		iter = 1;
		delay(-1, COND_PROC);
		if (!is_process_buffer(name_to_bufnum(PROCBUF)) || !process_input())
			return 2;	/* else assume it's compiled */
	} else if (no_running()) {	/* goes to end of proc buffer */
		set_error_spot();
		_had_errors = 0;
		if (*cmd)
			bprintf("%s\n", cmd);
		maybe_refresh();
		iter = 1;
		if (opsys != OS_UNIX)
			delay(-1, COND_PROC | COND_KEY);
		if (!is_process_buffer(name_to_bufnum(PROCBUF)) || !process_input())
			return 2;	/* else assume it's compiled */
		if (!(has_feature & FEAT_DETECT_CONCUR_WAIT))
			return 5;
	} else
		err = do_push(cmd, 1, 0);
	maybe_restart_concurrent();
	nerr = do_next_error(1, cmd);	// scan for error messages
	if (!nerr && err) {	// no message recognized, but error code
		say("Process returned %d", err);
		locate_window(procbuf, "");
		point = size();		/* show end of process buffer */
		return err;
	} else
		bufnum = obuf;
	if (err)
		return 1;
	else if (nerr)
		return 4;
	return 0;
}

// The following functions save & restore a concurrent process.  To use,
// you must first execute:
// 	if (!another_process()) save_var restart_concurrent = 0;
// Then call try_exit_concurrent(), run the process, and then call
// maybe_restart_concurrent().
// These functions are disabled in versions that support multiple
// concurrent processes, as they're not useful there.

try_exit_concurrent()
{
	if (!(has_feature & FEAT_MULT_CONCUR) && another_process()) {
		exit_process();
		if (another_process())
			error("Couldn't exit from concurrent process.");
	}
}

maybe_restart_concurrent()
{
	if (!(has_feature & FEAT_MULT_CONCUR) && restart_concurrent && !another_process())
		do_concur_shell("", "");
}

// Epsilon calls this function whenever something happens with the
// process.

concur_handler(int activity, int buf, int from, int to)
{
	switch (activity) {
		case NET_SEND:	do_when_process_input(buf, from, to); break;
		case NET_RECV:	do_when_process_output(buf, from, to); break;
	}
}

do_concur_shell(char *prog, char *cmd)
{
	save_var bufnum = create(PROCBUF);
	when_activity = concur_handler;
	restore_vars();
	return concur_shell(prog, cmd);
}

command next_error()
{
	do_next_error(iter, NULL);
	iter = 1;
}

command previous_error()
{
	do_next_error(-iter, NULL);
	iter = 1;
}

// A reference to this file was found in compiler output in the
// specified buffer.  Determine the directory it's in and make it an
// absolute pathname.  We recognize the "Running" message we insert,
// and the Entering and Leaving messages created by Gnu Make that
// indicate it's changing directories.

process_find_directory(char *file, int buf, int pos)
{
	char dir[FNAMELEN];
	int level = 0, got = 0;

	save_var bufnum = buf, point = pos;
	*dir = 0;
	if (is_process_buffer(bufnum) && *process_current_directory)
		strcpy(dir, process_current_directory);
	while (!got && re_search(-1, "(Entering|Leaving|Running `.*' in)"
							 " directory `(.*)'$")) {
		switch (character(find_group(1, 1))) {
			case 'L':	level++; break;
			case 'E':	if (--level > 0)
							break;
			case 'R':	got = 1;
						grab(find_group(2, 1), find_group(2, 0), dir);
						break;
		}
	}
	if (*dir)
		absolute(file, dir);
	else
		absolute(file);
}

/* if you change ERROR_PATTERN, change the next 3 macros as well */
#define ERROR_PATTERN	"^(e \"|w \"|<*>*(error|warning|fatal|Buffer )" \
			"( [a-z][0-9]+)?<*>*:?|[\"(]?) *" \
			"(([a-z]:)?[+-9A-z~][+-9A-z~ ]*<.>[+-9A-z]+[0-9<>]*)\"?" \
			"([ (:,]( line|L)?) *" \
			"([0-9]+)(<rparen|:>|[^0-9\n].*[:;]).*"
#define FILE_PAREN	4	/* filename is in 3rd () pair above */
#define LINE_PAREN	8	/* line# is in 7th pair of parens above */
#define SIMP_PATTERN	"[:;)]| line "	/* search with simple pattern first */

#define ERROR_PATTERN2	".* at (.*) line (.*)%."
#define FILE_PAREN2	1	/* filename in () pair above */
#define LINE_PAREN2	2	/* line# in pair of parens above */

// You can define ERROR_PATTERN3 with an alternate pattern.  Epsilon
// will look for either one, on lines that contain SIMP_PATTERN.
// Define FILE_PAREN3 and LINE_PAREN3 to match.  (Also ERROR_PATTERN4
// etc.)

do_next_error(int count, char *cmd)	// return 0 if no errors, else 1
{
	char file[FNAMELEN], number[30], line[130], *p;
	int lineno, origpt, dir, from, to, is_bufname, file_paren, line_paren;
	int orig = bufnum, procbuf;

	tiled_only();
	_last_was_grep = 0;
	if (spot_to_buffer(error_spot) <= 0 && !exist(PROCBUF))
		error("No process buffer to read errors from.");
	tiled_only();
	if (spot_to_buffer(error_spot) > 0)
		bufnum = spot_to_buffer(error_spot);
	else
		bufname = PROCBUF;
	procbuf = bufnum;
	origpt = point;
	case_fold = 1;
	if (spot_to_buffer(error_spot) > 0)
		point = *error_spot;
	else {
		error_spot = alloc_spot();
		point = 0;
	}

	noteput("Searching...");
	if (!count)
		find_error(-1, &file_paren, &line_paren), count = 1;
	dir = (count > 0) ? 1 : -1;
	for (; count; count -= dir) {
		if (!find_error(dir, &file_paren, &line_paren)) {
			point = origpt;
			bufnum = orig;
			if (_had_errors)
				say("No more errors.");
			else if (cmd)
				say("No errors running \"%s\".", cmd);
			else
				say("No errors.");
			return 0;
		}
	}
	_had_errors = 1;
	grab(find_group(file_paren, 1), find_group(file_paren, 0), file);
	grab(find_group(line_paren, 1), find_group(line_paren, 0), number);
	from = find_group(line_paren, 0);
	to = find_group(0, 0);
	if (to - from < 5)	// error message at end is too short
		from = find_group(0, 1);	// so try including whole line
	if (to > from + sizeof(line) - 1)
		to = from + sizeof(line) - 1;
	grab(from, to, line);
	is_bufname = (parse_string(1, "Buffer ") != 0);
	if (dir > 0)
		to_end_line();
	*error_spot = point;
	point = origpt;
	lineno = strtoi(number, 10);
	bufnum = orig;
	if (is_bufname)
		locate_window(file, "");
	else {
		process_find_directory(file, procbuf, from);
		locate_window("", file);
		find_it(file, default_translation_type);
	}
	go_line(lineno);
	for (p = line; *p && index("() :;\t", *p); p++)
		;			// skip over these chars at start of msg
	say("=> %s", p);
	return 1;
}

/* Find next error in direction, return 1 and set vars to find_group() paren count */
find_error(int dir, int *file_paren, int *line_paren)
{
	int old = point;

	if (point > 0 && dir > 0)
		to_end_line();
	else
		to_begin_line();
	while (re_search(dir, SIMP_PATTERN)) {
		to_begin_line();
		if ((!*ignore_error || !parse_string(1, ignore_error, NULL))) {
			if (parse_string(1, ERROR_PATTERN, (char *)0)) {
				*file_paren = FILE_PAREN;
				*line_paren = LINE_PAREN;
				return 1;
			}
#ifdef ERROR_PATTERN2
			if (parse_string(1, ERROR_PATTERN2, (char *)0)) {
				*file_paren = FILE_PAREN2;
				*line_paren = LINE_PAREN2;
				return 1;
			}
#endif
#ifdef ERROR_PATTERN3
			if (parse_string(1, ERROR_PATTERN3, (char *)0)) {
				*file_paren = FILE_PAREN3;
				*line_paren = LINE_PAREN3;
				return 1;
			}
#endif
#ifdef ERROR_PATTERN4
			if (parse_string(1, ERROR_PATTERN4, (char *)0)) {
				*file_paren = FILE_PAREN4;
				*line_paren = LINE_PAREN4;
				return 1;
			}
#endif
		}
		if (dir > 0)
			nl_forward();
	}
	*error_spot = old;
	return 0;
}

command view_process()
{					//  let user select one, and go there
	int w = window_handle, win, buf, pos, proc;

	tiled_only();
	if (buf_exist(spot_to_buffer(error_spot)))
		proc = spot_to_buffer(error_spot);
	else if (exist(PROCBUF))
		proc = name_to_bufnum(PROCBUF);
	else
		error("No process buffer to read errors from.");
	save_var menu_width = screen_cols - _view_left - _view_right;
	save_var _doing_input = DI_LINEINPUT;

	save_var bufnum = proc;
	if (spot_to_buffer(error_spot) != bufnum) {
		pos = 0;
		set_error_spot();
	} else
		pos = *error_spot;
	win = new_menu(buf = tmp_buf());
	grab_buffer(proc);
	point = pos;
	to_begin_line();
	window_title(win, BTOP, TITLECENTER, " Compiler Errors ");
	window_to_fit(screen_lines - 7);
	save_var _window_flags |= HIGHLIGHT_LINE;
	save_var search_in_menu = 0;
	save_var display_column = -1;	// ensure all of msg is visible
	if (is_gui && want_gui_prompts) {
		one_window_to_dialog("Select an error message", win,
							 "To Error", "Cancel", "");
	} else
		say("Select an error message and press <Enter>.");
	set_read_only(1);
	select_menu_item(0, win, w, 0);
	bufnum = buf;
	pos = point;
	bufnum = proc;
	buf_delete(buf);
	check_abort();
	point = pos;
	set_error_spot();
	ungot_key = -1;
	restore_vars();
	do_next_error(0, NULL);
}

try_grab_directory_name(int from, int to)
{
	char dir[FNAMELEN];

	if (is_gui != IS_NT || !use_process_current_directory
		|| to - from > 200)
		return;					// Too long for a likely dir name.
	if (character(--to) != '>')
		return;
	grab(from, to, dir);
	if (is_directory(dir)) {
		chdir(dir);
		can_get_process_directory = 1;
	}
}

// Called in versions that only permit one process buffer.
when_process_input(int type, int start)
{
	do_when_process_input(name_to_bufnum(PROCBUF), type, start);
}

when_process_output(int start, int end)
{
	do_when_process_output(name_to_bufnum(PROCBUF), start, end);
}

// The process is now ready for or has just been sent some input.
do_when_process_input(int buf, int type, int start)
{
	save_var bufnum = buf;
	save_var point = start;
	if (type == PROCESS_INPUT_LINE) {
		if (opsys == OS_UNIX)	// Our only opportunity to color.
			set_character_color(give_begin_line(), start,
								color_class process_prompt);
		create(PROC_CMDS_BUF);
		process_cmds_to_end();
		nl_forward();
		if (point > start + 1)		// don't store empty (just \n) cmds
			xfer(PROC_CMDS_BUF, start, point);
		process_cmds_to_end();
	} else if (type == PROCESS_INPUT_CHAR)
		set_character_color(start, start + 1, color_class process_input);
	else if (!type) {		// Got a request for input (might now wait).
		if (spot_to_buffer(process_input_starts_at) <= 0)
			process_input_starts_at = alloc_spot();
		*process_input_starts_at = start;
		point = start;
		to_begin_line();
		set_character_color(point, start, color_class process_prompt);
		try_grab_directory_name(point, start);
	}
}

color_ansi_output_section(int cnt)
{
	char val[20], *colortrans = "\0\4\2\6\1\5\3\7";
	int i, color, matches[4];
	int fore, back, bold = 0, wanted, have, tcolor;

	tcolor = alter_color(color_class process_output, -1);
	fore = tcolor & 0xf;		// Get colors for normal text in buffer.
	back = (tcolor / 16) & 0xf;
	for (i = 1; i <= cnt; i++) {	// Parse color spec.
		if (find_group(i, 0) - find_group(i, 1) > sizeof(val) - 2)
			return;				// Don't touch this odd one.
		grab(find_group(i, 1), find_group(i, 0), val);
		color = numtoi(val);
		if (color >= 30 && color <= 37)		// Set the foreground.
			fore = colortrans[color - 30];
		else if (color >= 40 && color <= 47)	// Background.
			back = colortrans[color - 40];
		else if (color == 1)				// Set bold.
			bold = 1;
	}
	wanted = fore + back * 16 + bold * 8;
	matches[0] = matches[1] = matches[2] = matches[3] = -1;
	for (i = 0; i < number_of_color_classes(); i++) {
		have = alter_color(i, -1);	// Look for approx desired color.
		if (matches[0] == -1 && have == wanted)
			matches[0] = i;		// Pretty good match.
		if (matches[1] == -1 && (have & 0x77) == (wanted & 0x77))
			matches[1] = i;		// Only boldness doesn't match.
		if (matches[2] == -1 && (have & 0x7) == (wanted & 0x7))
			matches[2] = i;		// Only foreground matches.
		if (matches[3] == -1 && (have & 0xf0) == (tcolor & 0xf0)
			&& (have & 0xf) != (tcolor & 0xf))
			matches[3] = i;		// A suitable default -- same bg,
	}							// different fg as normal text.
	for (i = 4; --i >= 0; )		// Find the best option.
		if (matches[i] != -1)
			color = matches[i];

	if (get_character_color(find_group(cnt, 0)) == color_class process_output)
		set_character_color(matchstart, matchend, color);
	delete(find_group(cnt + 1, 1), find_group(cnt + 1, 0));
	delete(matchstart, find_group(cnt, 0));	// Delete color specs.
}

color_ansi_output(int start)
{
	save_var point = start - 100;
	while (re_search(1, "\x1B%[([0-9]+);([0-9]+);([0-9]+m)[^\n\x1B]*(\x1B%[0*m)"))
		color_ansi_output_section(3);
	point = start - 100;
	while (re_search(1, "\x1B%[([0-9]+);([0-9]+m)[^\n\x1B]*(\x1B%[0*m)"))
		color_ansi_output_section(2);
	point = start - 100;
	while (re_search(1, "\x1B%[([0-9]+m)[^\n\x1B]*(\x1B%[0*m)"))
		color_ansi_output_section(1);
	point = start - 100;
	while (re_search(1, "\x1B%[0*m"))	// Remove stray resets.
		delete(matchstart, matchend);
	point = start - 1;	// For Unix, color user input after system echos it.
	if ((get_character_color(point) == color_class process_prompt
		 || get_character_color(point) == color_class process_input)
		  && curchar() != '\n')
		set_character_color(start, give_end_line(),
							color_class process_input);
}

// If the current line would be off the bottom of the window, adjust
// the window so it's on the last line instead.  (If we didn't,
// redisplay would center the window around this line.)

line_up_to_bottom()
{
	int new_window_start = prev_screen_line(text_height() - 1);

	if (new_window_start > window_start)
		window_start = new_window_start;
}

// The process has just produced some output.

do_when_process_output(int buf, int start, int end)
{
	save_var bufnum = buf;
	set_character_color(start, end, color_class process_output);
	if (opsys == OS_UNIX)
		color_ansi_output(start);
	if (window_bufnum == buf && point == size()
		&& end > window_end && process_output_to_window_bottom)
		line_up_to_bottom();
}

command process_enter()
{
	if (process_enter_whole_line == 2 && point < type_point) {
		char line[FNAMELEN];

		to_begin_line();
		point += parse_string(1, "[^>$#%]*[>$#%] *");
		parse_string(1, ".*", line);
		point = size();	// grab current line excluding prompt
		stuff(line);	// and copy to the end
		return;
	}
	if (process_enter_whole_line && point >= type_point)
		to_end_line();
	enter_key();
	if (point > type_point + 1 && (spot_to_buffer(error_spot) != bufnum
								   || point < *error_spot))
		set_error_spot();
	_last_was_grep = 0;
	if (point >= window_end && process_output_to_window_bottom)
		line_up_to_bottom();
}

process_get_previous_cmd(int down)
{
	int buf = bufnum;

	point = size();
	if (!exist(PROC_CMDS_BUF))
		return;
	if (spot_to_buffer(process_input_starts_at) > 0
		&& !lines_between(*process_input_starts_at, point))
		delete(*process_input_starts_at, point);
	else {
		if (spot_to_buffer(process_input_starts_at) <= 0)
			process_input_starts_at = alloc_spot();
		*process_input_starts_at = point;
	}
	save_var bufname = PROC_CMDS_BUF;
	down_or_up_lines(down);
	buf_xfer(buf, give_begin_line(), give_end_line());
}

command filter_region()
{
	int in_place = has_arg, b, width, orig = bufnum;
	char cmd[FNAMELEN];

	iter = 0;
	get_str_auto_def(cmd, in_place ? "Send region to command" : 
			   "Filter region through command");
	b = zap("filter-output");
	if (region_type() == REGRECT) {
		width = extract_rectangle(b, 0);
	} else {
		save_spot point, mark;
		fix_region();		// handle other types of regions
		buf_xfer(b, point, mark);
	}
	if (!buf_pipe_text(b, b, cmd, "", PIPE_CLEAR_BUF | (in_place ? PIPE_SYNCH : 0))) {
		if (bufnum != b)
			buf_delete(b);
		file_error(errno, "During exec", "Couldn't exec");
		quick_abort();
	}
	if (in_place) {
		if (region_type() == REGRECT) {
			save_var bufnum = b;
			xfer_rectangle(orig, width, 1);
		} else {
			delete(point, mark);
			restore_vars();
			grab_buffer(b);
		}
	} else
		to_buffer_num(b);
	highlight_off();
}

#define LEFTD	"[({"
#define RIGHTD	"])}"

command forward_level()
{
	if (iter < 0) {
		iter = -iter;
		backward_level();
	}
	while (iter-- > 0)
		move_level(1, LEFTD, RIGHTD, 1, 0);
}

command backward_level()
{
	if (iter < 0) {
		iter = -iter;
		forward_level();
	}
	while (iter-- > 0)
		move_level(-1, RIGHTD, LEFTD, 1, 0);
}

command find_delimiter()
{
	int orig=point;

	say("");
	iter=0;
	if (in_macro() || key_from_macro)
		return;
	if (move_level(-1, RIGHTD, LEFTD, 1, 0)) {
		show_line();
		point = orig;
	}
}

move_level(int dir, char *findch, char *otherch, int show, int stop_on_key)
{
	int res;

	if (mode_move_level)
		res = (*mode_move_level)(dir, stop_on_key);
	else
		res = default_move_level(dir, findch, otherch);
	if (res == -1) {
		if (show)
			say("Unmatched delimiter");
		return 0;
	}
	point = res;
	if (res == -2)
		return -2;
	return 1;
}

init_auto_show_delimiter()
{
	if (!show_matching_start_spot) {	// Initialize.
		show_matching_start_spot = alloc_spot(1);
		show_matching_end_spot = alloc_spot(1);
		if (modify_region(SHOW_MATCHING_REGION, MRTYPE, -1) != -1)
			remove_region(SHOW_MATCHING_REGION);
		add_region(show_matching_start_spot, show_matching_start_spot,
				   color_class show_matching_start, 0,
				   SHOW_MATCHING_REGION);
		add_region(show_matching_end_spot, show_matching_end_spot,
				   color_class show_matching_end, 0,
				   SHOW_MATCHING_REGION);
		modify_region(SHOW_MATCHING_REGION, MRCONTROL,
					  find_index("is_current_window"));
	}
}

try_auto_show_delimiter(int dir, char *near, char *far)
{
	int orig, there, res;

	save_var point;
	if (dir > 0) {	// Only go one line forward, and not too far back.
		save_var narrow_start = give_begin_line();
		save_var narrow_end = size() - (point + c_look_back);
	} else {		// Only go one line back, and not too far forward.
		save_var narrow_start = ++point - c_look_back;
		save_var narrow_end = size() - give_end_line();
	}
	orig = point;
	res = move_level(dir, near, far, 0, 1);
	if (res != 1)
		return 0;
	there = point;
	res = move_level(-dir, far, near, 0, 1);
	if (res != 1 || point != orig)
		return 0;
	*show_matching_end_spot = there - (there > point);
	*show_matching_start_spot = point - (there < point);
	return 1;
}

hide_auto_show_delimiter()
{
	if (show_matching_start_spot)	// Remove existing highlight.
		modify_region(SHOW_MATCHING_REGION, MRTYPE, 0);
}

int maybe_auto_show_delimiter()
{
	char *p, i, rightside, adjacent = 0;

	if (show_matching_start_spot)	// Remove existing highlight.
		modify_region(SHOW_MATCHING_REGION, MRTYPE, 0);
	if (!auto_show_matching_characters || num_of_popups() > 0
		  || is_key_repeating())
		return 0;
	p = index(auto_show_matching_characters, curchar());
	if (!p && auto_show_adjacent_delimiter) {
		adjacent = 1;	// Check prev character, maybe it's a delim.
		save_var point--;
		p = index(auto_show_matching_characters, curchar());
	}
	if (!p)
		return 1;				// Not a delimiter we can match.
	i = p - auto_show_matching_characters;		// Index of char.
	rightside = i * 2 >= strlen(auto_show_matching_characters);
	if (adjacent && !(auto_show_adjacent_delimiter & (rightside ? 1 : 2)))
		return 1;	// Maybe reject some adjacent delimiters.
	save_var point, matchstart, matchend, abort_searching = 0;
	init_auto_show_delimiter();
	if (rightside ? try_auto_show_delimiter(-1, RIGHTD, LEFTD)
				  : try_auto_show_delimiter(1, LEFTD, RIGHTD)) {
		modify_region(SHOW_MATCHING_REGION, MRTYPE, REGINCL);
		return 3;			// Show the two regions.
	}
	return 2;
}

to_comment_column()	/* replace whitespace here with comment indentation */
{
	int this;

	delete_horizontal_space();
	this = current_column();
	if (!this && !comment_column)
		return;
	else if (this >= comment_column)
		stuff(" ");	/* code extends past comment col */
	else if (!this && indenter && indent_comment_as_code)
		(*indenter)();
	else
		insert_to_column(this, comment_column);
}

	/* s_code: where to start searching from */
#define FHERE	1	/* from right here */
#define FORIG	2	/* from starting position */
#define FMATCH	3	/* from last match */
#define FMADD	4	/* same, but indicates we added a char this time */
#define FMREGEX	5	/* same, but don't assume too much about pattern */

search_read(trystr, prmpt, flags)
char *trystr, *prmpt;
{
	int lastok, goodchars, oldflags, mstart, origwin = window_handle;
	int editbuf, pbuf, pwin, editwin, s_code, okpoint, orig, ostart;
	int oreg_type, old_mark = -1;
	char tmpbuf[FNAMELEN];

	if (_doing_input == DI_SEARCH)
		error_if_input(0);
	if (is_highlight_on() && point != mark && ABS(point - mark) < 200
		  && !*trystr && typing_deletes_highlight) {
		old_mark = mark;	// Use this as the initial search string.
		highlight_off();
	}
	save_var iter, has_arg, this_cmd, prev_cmd;
	save_var _doing_input = DI_SEARCH;
	save_var last_index;
	save_var mark = point, _highlight_control;
	save_var postpone_asynchronous_notify = 1;
	save_var macro_runs_immediately = 0;	// Make special keys work in macros.
	oreg_type = region_type();
	set_region_type(REGNORM);
	flags &= ~SEARCH_EMPTY;
	orig = okpoint = mstart = point;
	ostart = window_start;
	goodchars = lastok = 0;	/* 2 versions of len of last good string */
				/* (only lastok is set by getting default) */

	editbuf = tmp_buf();		/* make buffer for cmd line editing */
	pwin = add_popup(0, echo_line, screen_cols - 1, 1, 0,
					 pbuf = tmp_buf());	/* prompt in window */
	stuff(trystr);
	trystr = malloc(FNAMELEN);
	display_column = 0;
	system_window = 1;	/* don't let user switch to it */
	text_color = color_class echo_area;

	editwin = add_popup(1, echo_line, screen_cols - 1, 1,
						0, editbuf);	/* window on top of prompt window */
	text_color = color_class echo_area;
	_display_class = _echo_disp_class;
	display_column = 0;

	if (old_mark != -1) { // Start out with highlighted region.
		window_handle = origwin;
		buf_xfer(editbuf, old_mark, point);
		window_handle = editwin;
		point = 0;
		if (flags & REGEX)	// Quote special chars.
			string_replace("[[%.!#()*+|?^$<]", "%#0", REGEX);
		point = size();
		highlight_on();		// Mark it so user can delete by typing.
	}

	for (;;) {
		do {
			show_search_prompt(prmpt, flags, origwin,
							   pwin, editwin);
			getkey();
		} while (key == MOUSE_MOVE);
		if (IS_MOUSE_KEY(key))
			if (mouse_y == echo_line)
				flags &= ~INCR;
			else {
				flags |= SONCE;
				ungot_key = key;
				break;
			}
		if (key == CTRL('^'))
			full_getkey("", CTRLIFY_KEY);
		window_handle = editwin;
		s_code = 0;
		oldflags = flags;
		flags &= ~(BAD | FAILING | SONCE);	/* assume ok */
		if (is_search_dir()) {
			window_handle = origwin;
			point = okpoint;
			window_handle = editwin;
			if ((key == CTRL('R')) != ((flags & REVERSE) != 0)) {
				flags ^= REVERSE;	/* switch dir */
				if (goodchars)
					flags |= SONCE;
				lastok = size();
			} else if (!size()) {
				if (flags & UNKNOWN)
					flags = known_flags(flags);
get_defaults:			stuff(default_search_string(flags));
						lastok = size();
			} else if (oldflags & FAILING) {
				if (search_wraps) {
					flags |= (flags & SEARCH_WRAPPED) ? SEARCH_OVERWRAPPED
						: SEARCH_WRAPPED;
					window_handle = origwin; /* Wrap to other end of buffer. */
					point = (flags & REVERSE) ? size() : 0;
					window_handle = editwin;
					s_code = FHERE;			/* And search again. */
				} else
					flags |= FAILING; /* no more matches, stop */
			} else
				flags |= SONCE;
			if ((flags & (INCR | SONCE)) && !(flags & FAILING))
				flags |= SONCE, s_code = FHERE;
		} else if (set_flag_modes(&flags)) {
			if ((flags & INCR) && size())
				s_code = FMATCH; /* if modes changed, search again */
		} else if (key == CTRL('O')) {
			flags ^= INCR;
			point = size();
			if (flags & INCR)
				s_code = FMATCH;
		} else if (reg_tab[key] == (short) help)
			help_on_command(help_on_search(flags));
		else if (IS_ENTER_KEY(key)) {
			if (oldflags & SONCE)
				flags |= SONCE;
			break;
		} else if (reg_tab[key] == (short) backward_delete_character
				   && (flags & INCR)) {
			run_topkey();
			window_handle = editwin;
			if (!(oldflags & FAILING) || size() <= lastok)
				s_code = FORIG;
			else		/* don't bother searching */
				flags |= FAILING;
		} else if (key == abort_key && (oldflags &
										((flags & INCR) ? FAILING : SONCE))) {
			if (flags & INCR)
				delete(goodchars, size());
		} else if (comp_tab[key] == (short) inp_recall
				   && (IS_ALT_KEY(key) || !(flags & INCR))) {
			flags = pick_prev_search(flags) & ~INCR;
			if (user_abort)
				break;
		} else if (user_abort || (flags & INCR) && exit_incr())
			break;
		else {
			flags &= ~UNKNOWN;
			if ((comp_tab[key] == (short) inp_grab_word
				 || comp_tab[key] == (short) inp_grab_line)
				  && (IS_ALT_KEY(key) /*|| !(flags & INCR) */ )) {
				if (!(oldflags & FAILING)) {
					if (grab_search_word(flags, origwin,
										 (comp_tab[key] == (short) inp_grab_line))) {
						window_handle = origwin;	// Move origin
						mstart = orig = point;		// to start of word.
						window_handle = editwin;
						s_code = FORIG;
					} else
						s_code = (flags & REVERSE) ? FHERE : FMREGEX;
				}
			} else if (key == '\t')
				normal_character();
			else
				run_topkey();
			window_handle = editwin;
			if (flags & INCR)
				if (flags & (REGEX | WORD))
					s_code = FMREGEX;
				else if (oldflags & FAILING)
					flags |= FAILING;
				else
					s_code = FMADD;
		}
		_doing_input = DI_SEARCH;
		if (!is_window(origwin) || !is_window(editwin)
			  || !is_window(pwin)) {	// user deleted our window
			user_abort = 1;
			goto end;
		}
		user_abort = 0;
		grab_expanding(0, size(), &trystr, 256);
		if (!s_code)
			continue;
		window_handle = origwin;
		if (s_code == FORIG || s_code == FMREGEX)
			point = orig;
		else if (s_code >= FMATCH) {
			point = mstart;
			if (flags & REVERSE)
				point++;
		}
		_highlight_control = 0;
		switch (do_searching(flags, trystr)) {
			case DSBAD:
				flags = BAD | (flags & ~INCR);
			case 0:	flags |= FAILING;
					point = okpoint;
					if (in_macro())
						goto end;
					else if (!(oldflags & FAILING))
						maybe_ding(bell_on_search);
					break;
			case 1:	okpoint = point;
					mark = mstart = matchstart;
					highlight_on();
					if ((flags & SEARCH_WRAPPED) && (point > orig) == !(flags & REVERSE))
						flags |= SEARCH_OVERWRAPPED;
					window_handle = editwin;
					goodchars = lastok = size();
					break;
			case DSABORT:
				point = okpoint;
				window_handle = editwin;
				if ((flags & INCR) && s_code == FMADD)
					delete(size() - 1, size());
				break;
		}
	}
	window_handle = origwin;
	if (key == abort_key || user_abort)
		point = orig, window_start = ostart;
	else {
		window_handle = editwin;
		if (size()) {
			_last_was_regex = ((flags & REGEX) != 0);
			*(_last_was_regex ? &_default_regex_flags
							  : &_default_flags) = flags;
			grab_expanding(0, size(), &trystr, 256);
			if (_last_was_regex)
				grab_expanding(0, size(), &_default_regex_search, 256);
			else
				grab_expanding(0, size(), &_default_search, 256);
			save_search_recall(flags, trystr);
		} else
			flags |= SEARCH_EMPTY;
		if ((flags & INCR) && !IS_ENTER_KEY(key) && key != ESC)
			ungot_key = key;
	}
end:
	strncpy(tmpbuf, trystr, FNAMELEN - 1);
	free(trystr);
	if (is_window(origwin))
		window_handle = origwin;
	set_region_type(oreg_type);
	remove_window(editwin);
	remove_window(pwin);
	buf_delete(editbuf);
	buf_delete(pbuf);
	if ((flags & FAILING) && in_macro())
		error("%s: not found", tmpbuf);
	check_abort();
	say("");
	restore_vars();
	maybe_refresh();	/* put cursor back in prev window */
	return flags;
}

save_search_recall(int flags, char *str)
{
	char *srch;
	int buf = tmp_buf();

	save_var bufnum = buf;
	bprintf("%s%s%s",
			!(flags & MODFOLD) ? "" : (flags & FOLD) ? "Fold " : "Nofold ",
			(flags & WORD) ? "Word " : "",
			(flags & REGEX) ? "Regex " : "");
	if (character(point - 1) == ' ')
		delete(point - 1, point);
	bprintf(": %s", str);
	simple_re_replace(1, "%<NL>", "%<NL>");	// Put a % before actual <NL> strings.
	simple_re_replace(1, "\n", "<NL>");	// Convert newlines to <NL>.
	srch = malloc(size() + 1);
	grab(0, size(), srch);
	restore_vars();
	buf_delete(buf);
	save_recall(srch, "search");
	free(srch);
}

get_search_string(pr, flags)	/* prompt for search string & return flags */
char *pr;
{
	return search_read("", pr, default_fold(flags));
}

default_fold(flags)		/* initialize flag from buffer variable */
{
	if (case_fold)
		flags |= FOLD;
	if (case_fold != case_fold.default)
		flags |= MODFOLD;
	return flags;
}

// Return the most recent search string.  For functions that may wish
// to write short amounts to these, we ensure there's some room.
char *default_search_string(int flags)
{
	if (flags & REGEX) {
		if (!_default_regex_search)
			_default_regex_search = malloc(FNAMELEN);
	} else {
		if (!_default_search)
			_default_search = malloc(FNAMELEN);
	}
	return (flags & REGEX) ? _default_regex_search : _default_search;
}

gen_replace(flags)	/* get input, then do replace */
{
	char *str, with[FNAMELEN];

	if (has_arg)
		flags |= WORD;
	save_var point;
	flags = get_replace_text(flags, with);
	restore_vars();
	str = default_search_string(flags);
	if (flags != -1) {
		show_replace(str, with, flags);
		string_replace(str, with, flags | INCR);
	}
}

get_replace_text(int flags, char *with)
{
	char prompt[80], *str;

	iter = 0;
	flags = default_fold(flags);
	sprintf(prompt, "%s%sreplace string: ", (flags & FILEGREP) ? "file " :
			(flags & BUFGREP) ? "buffer " : "",
			(flags & QUERY) ? "query " : "");
	*prompt = toupper(*prompt);
	flags = search_read("", prompt, flags | REPLACE);
	flags &= ~(INCR | FAILING | BAD);
	if (flags & SEARCH_EMPTY)
		return -1;
	str = (flags & REGEX) ? _default_regex_replace
						  : _default_replace;
	last_index = find_index(help_on_search(flags));
	save_var recall_id = "replace";
	get_strnone(with, "with: ", str);
	strcpy(str, with);
	return flags;
}

string_replace(str, with, flags)
char *str, *with;
{
	spot orig, prev, oldmark;
	int skip = 0, show = 0, ret, evershow = 0, oldstart, null_detect = -1, new_null_detect;
	int perform_case_replace, this_case_replace;

	if (_buf_readonly)
		error("Buffer is read-only.");
	if (!*str)
		return 0;
	perform_case_replace = want_case_replace(str, with, flags);
	orig = alloc_spot();
	prev = alloc_spot();
	save_var postpone_asynchronous_notify = 1;
	replace_num_found = replace_num_changed = 0;
	for (;;) {
		skip = 0;
		*prev = point;
		oldstart = matchstart;
		ret = do_searching(flags, str);
		if (!ret || ret == DSBAD) {
			point = *orig;
			break;
		} else if (ret == DSABORT)
			break;
		new_null_detect = (flags & REVERSE) ? point : (size() - point);
		if (null_detect == new_null_detect) {
			if ((flags & REVERSE) ? (point-- <= 0) : (point++ >= size())) {
				point = *orig;
				break;	// Make sure replacing a nullable pattern like $
			}			// moves forward.
			continue;
		} else
			null_detect = new_null_detect;
		replace_num_found++;
ask:
		if (show) {
			show_replace(str, with, (flags & ~INCR));
			evershow = 1;
			show = 0;
		}
		if (!(flags & QUERY)) goto do_replace;
		if (!get_replace_key(flags, str, skip)) { // show match, then get key
			point = *orig;		// match went away (maybe flags changed)
			break;
		}
		if (key == '?' || key == 'h'
			  || root_keys[key] == (short) help) {
			help_on_command("query-replace");
			show = 1;
			point = *prev;
			continue;
		} else if (user_abort || key == abort_key) {
			point = *orig;
			ret = DSABORT;
			goto done;
		}
		switch(tolower(key)) {
			case '^': point = *prev; matchstart = oldstart;
			case '\b':
			case GREYBACK:
			case 'n': skip = 1;	/* go to the next match */
			case ' ':
			case 'y':		/* do the replace */
			case '!':
			case ',':
			case '.': break;
			case CTRL('R'):
				say("");
				oldmark = alloc_spot();
				*oldmark = mark;	/* save mark */
				mark = matchstart;
				/* set temporary mark before text */
				recursive_edit();
				if (spot_to_buffer(oldmark) < 0) {
					ret = DSABORT;	// user deleted buf
					goto done;
				}
				mark = *oldmark;	/* restore mark */
				free_spot(oldmark);
				show = 1;
				continue;
			default:	if (set_flag_modes(&flags)) {
							show = 1;
							goto ask;
						}
						if (!IS_ENTER_KEY(key))
							ungot_key = key;
			case ESC:	ret = 1; goto done;
		}
do_replace:
		if (!skip) {
			save_spot matchstart;
			if (perform_case_replace)
				this_case_replace = check_for_case_replace(matchstart, point);
			if (flags & REGEX)
				fromorig(with);
			else {
				delete(matchstart, point);
				stuff(with);
			}
			if (perform_case_replace)
				switch (this_case_replace) {
					case 1: do_uppercase_region(matchstart, point); break;
					case 2: do_capitalize_region(matchstart, point); break;
				}
			replace_num_changed++;
			restore_vars();
		}
		if (flags & QUERY)
			switch (key) {
				case ',': case '^':	skip = 1; goto ask;
				case '.':		ret = 1; goto done;
				case '!':		flags &= ~QUERY; show = 1;
			}
	}
done:
	if (ret == DSABORT)
		say("Replacement canceled");
	else if (ret == DSBAD)
		show_replace(str, with, (flags & ~INCR) | BAD);
	else if (!in_macro())
		if (evershow || (flags & INCR))
			say("Replaced %d of %d.", replace_num_changed,
				  replace_num_found);
		else if (evershow)
			say("");
	free_spot(orig);
	free_spot(prev);
	return ret;
}

struct find {
	char *find_text;
	char *replace_text;
	int flags;
} find_data;		// The find dialog looks at this variable directly.
char sbuf[FNAMELEN], rbuf[FNAMELEN];

setup_find_struct(replace)
{
	if (_last_was_regex)
		find_data.flags = _default_regex_flags;
	else
		find_data.flags = _default_flags;
	strncpy(sbuf, default_search_string(find_data.flags), sizeof(sbuf));
	find_data.find_text = sbuf;
	if (replace) {
		strcpy(rbuf, (find_data.flags & REGEX) ? _default_regex_replace
											   : _default_replace);
		find_data.replace_text = rbuf;
	} else
		find_data.replace_text = 0;
}

#define DEFSESSNAME	"epsilon.ses"
#define DEFSESSDIR	((opsys == OS_UNIX) ? "~/.epsilon" : "/")

give_session_file(file)
char *file;
{
	char *s, *p, dir[FNAMELEN];

	if (explicit_session_file) {
		strcpy(file, explicit_session_file);
		return;
	}
	s = cmd_line_session_file;
	if (!s)
		s = verenv("ESESSION");
	if (!s && *session_file_name)
		s = session_file_name;
	if (!s)
		s = DEFSESSNAME;
	if (look_up_tree(file, s, NULL, session_tree_root))
		return;
	strcpy(file, s);
	if (*session_default_directory)
		absolute(file, session_default_directory);
	else if (p = verenv("EPSPATH")) {
		strcpy(dir, p);
		p = index(dir, path_list_char);
		if (p)
			*p = 0;
		absolute(file, dir);
	} else
		absolute(file, DEFSESSDIR);
}

make_session(b, sesfile)
char *sesfile;
{
	int i, wins, owin = window_number;
	struct window_info w;
	char sdir[FNAMELEN];	// dir of session file
	char file[FNAMELEN];

	strcpy(sdir, sesfile);
	absolute(sdir);
	*get_tail(sdir, 0) = 0;
	buf_printf(b, SES_HDR "\n");
	save_buffer_list(sdir, b);
	buf_printf(b, "\n%d\n", _prev_num);
	for (i = 0; i < _prev_num; i++)
		buf_printf(b, "%s\n", give_buffer_name(_prev_old_buffers[i]));
	save_bookmark_session(b);

	wins = number_of_windows() - number_of_popups();
	buf_printf(b, "%d %d %d %d %d %d\n",
			   wins, screen_cols, screen_lines, is_gui, opsys,
			   buf_accessed_clock);
	for (i = 0; i < wins; i++) {
		get_window_info(i, &w);
		buf_printf(b, "%d %d %d %d\n",
				   w.left, w.top, w.right, w.bottom);
		buf_printf(b, "%d %d %d %d\n",
				   w.textcolor, w.hbordcolor, w.vbordcolor, w.titlecolor);
		buf_printf(b, "%d %d\n", w.borders, w.other);
		buf_printf(b, "%s\n", give_buffer_name(w.bufnum));
		buf_printf(b, "%s\n", give_buffer_name(w.prevbuf));
		buf_printf(b, "%d %d %d\n", w.point, w.dcolumn, w.dpoint);
	}
	buf_printf(b, "%d %d %d %d %d 0 0\n", owin, echo_line,
			   permanent_menu, avoid_top_lines, avoid_bottom_lines);
	buf_printf(b, "%d %d %d\n",
			   _default_flags, _default_regex_flags, _last_was_regex);
	buf_printf(b, "%s" SES_DELIM "%s" SES_DELIM,
			   _default_search ? _default_search : "",
			   _default_regex_search ? _default_regex_search : "");
	buf_printf(b, "%s" SES_DELIM "%s" SES_DELIM,
			   _default_replace, _default_regex_replace);
	buf_printf(b, "%s" SES_DELIM "%s" SES_DELIM,
			   push_cmd, _region_file);
	buf_printf(b, "%s" SES_DELIM "\n", _grep_files);
	make_session_hook(b);
	save_recall_session(b);
	getcd(file);
	buf_printf(b, "CWD: %s\n", file);
	buf_printf(b, "OPENCWD: %s\n", common_open_curdir);
}

remember_this_buffer()	/* should we record this buffer in session file? */
{
	if (*bufname == '-' || is_dired_buf() || !size() || !*filename)
		return 0;
	if (is_process_buffer(bufnum) || buffer_not_saveable)
		return 0;
	if (file_info.year && file_info.check_type != CHECK_FILE)
		return 0;
	if (is_remote_file(filename))
		return 0;
	return 1;
}

load_this_session(file)		/* return 1 if session was loaded */
char *file;
{
	int b, err, old = bufnum;

	bufnum = b = create(SES_BNAME);
	err = file_read(file, 0);
	if (!err) {
		if (explicit_session_file)
			free(explicit_session_file);
		explicit_session_file = strsave(file);
		maybe_refresh();
		err = restore_session(b);
		switching_to_buffer();
		if (buf_in_window(b) == -1)
			buf_delete(b);
		if (!err)
			note("");
		else if (err != 100)
			say("Invalid format, code %d, in session %s",
				  err, file);
		return 1;
	} else if (err != 2) {
		file_error(err, file, "couldn't read session");
		maybe_ding(bell_on_read_error);
	}
	bufnum = old;
	buf_delete(b);
	return 0;
}

restore_session(b)	/* if error in session file, return error code # */
{			/* for debugging purposes, else 0 */
	int nums[10], i, j, wins, err, readerrs = 0;
	int def_buf = 0;
	char buf[FNAMELEN], file[FNAMELEN];
	char sdir[FNAMELEN];	// dir of session file

	give_session_file(sdir);
	absolute(sdir);
	*get_tail(sdir, 0) = 0;
	bufnum = b;
	point = 0;
	if (!grab_line(b, buf) || strcmp(buf, SES_HDR))
		return 1;
	while (grab_line(b, buf)) {
		grab_line(b, file);
		if (grab_numbers(b, nums) < 3)
			return 2;
		if (session_restore_files)
			bufnum = create(buf);
		if (!def_buf) {
			if (is_gui)
				note("Restoring session...");
			else
				noteput("Restoring session...");
			def_buf = bufnum;
		}
		if (session_restore_files)
			filename = file;
		if (*file && session_restore_files) {
			absolute(file, sdir);
			i = do_file_read(file, nums[2]);
			if (user_abort || i == EREADABORT)
				return 0;
			if (!i || i == 2) {
				if (!i)
					set_readonly_from_file();
				window_bufnum = bufnum;		// make suffix- kbd macros work
				call_mode(filename);
				make_mode();
			} else if (!readerrs++) {
				file_error(i, file, "read error");
				maybe_ding(bell_on_read_error);
			} else
				note("%d files could not be read", readerrs);
		}
		if (session_restore_files) {
			if (bufnum != b)	/* same tmp name as session buffer */
				point = nums[0];
			mark = nums[1];
			translation_type = nums[2];
		}
		if (grab_numbers(b, nums) < 4)
			return 3;
		if (session_restore_files) {
			over_mode = nums[0];
			fill_mode = nums[1];
			indent_with_tabs = nums[2];
			margin_right = nums[3];
		}
		if ((i = grab_numbers(b, nums)) < 5)
			return 4;
		if (session_restore_files) {
			tab_size = nums[0];
			case_fold = nums[1]; // nums[2] var was removed
			want_warn = nums[3];
			if (nums[4] == 1)
				set_read_only(1);
			buf_accessed = i > 5 ? nums[5] : 0;
			file_io_converter = 0;
			if (i > 6 && nums[6]) {
				file_io_converter = oem_file_converter;
				file_convert_read();
			}
			undo_mainloop();
		}
	}
	if (grab_numbers(b, nums) != 1)
		return 12;
	j = nums[0];
	if (session_restore_files)
		_prev_num = j;
	for (i = 0; i < j; i++) {
		grab_line(b, buf);
		if (session_restore_files)
			_prev_old_buffers[i] = name_to_bufnum(buf);
	}
	if (restore_bookmark_session(b))
		return 13;
	i = grab_numbers(b, nums);
	if (i < 3)
		return 5;
	wins = nums[0];
	if (((has_feature & FEAT_EEL_RESIZE_SCREEN))
//	if (((has_feature & FEAT_EEL_RESIZE_SCREEN) || is_unix == IS_UNIX_XWIN)
		  && !want_lines && !want_cols)
		try_set_screen_size(nums[2], nums[1], "");
	if (i > 5)
		buf_accessed_clock = nums[5];
	fix_buf_accessed_clock();
	err = rest_sess_wins(b, wins, !session_restore_files, def_buf,
						 nums[2], nums[1]);
	if (err) {
		def_buf = give_prev_buf();
		if (def_buf)
			to_buffer_num(def_buf);
	}
	if (grab_numbers(b, nums) >= 3) {
		_default_flags = nums[0];
		_default_regex_flags = nums[1];
		_last_was_regex = nums[2];
		grab_string_expanding(b, &_default_search, SES_DELIM, FNAMELEN);
		grab_string_expanding(b, &_default_regex_search, SES_DELIM, FNAMELEN);
		grab_string(b, _default_replace, SES_DELIM);
		grab_string(b, _default_regex_replace, SES_DELIM);
		grab_string(b, push_cmd, SES_DELIM);
		grab_string(b, _region_file, SES_DELIM);
		grab_string(b, _grep_files, SES_DELIM);
		restore_session_hook(b);
		restore_recall(b);
		grab_line(b, file);		// skip \n after recall buffer
		grab_line(b, file);
		if (!strncmp(file, "CWD: ", 5)) {
			switch (session_restore_directory) {
				default:	if (directory_flags & DIR_CWD_RESTORE)
				case 1:			chdir(file + 5);
				case 0:		break;
			}
			grab_line(b, file);
			if (!strncmp(file, "OPENCWD: ", 9))
				common_open_curdir = file + 9;
		}
	} else
		err = 11;
	return err ? err : readerrs ? 100 : 0;
}

command write_state()
{
	char fname[FNAMELEN], *p;

	build_filename(fname, "%x%f", default_state_file_name);
	if (opsys == OS_UNIX && *state_file && (strcmp(state_file, fname)
											|| get_file_read_only(state_file) == 1)) {
				// Suggest first directory of EPSPATH.
		if (p = verenv("EPSPATH")) {
			strcpy(state_file, p);
			p = strchr(state_file, path_list_char);
			if (p)
				*p = 0;
		} else		// Or if none, off home dir.
			strcpy(state_file, "~/.epsilon");
		absolute(state_file);		// Strip off any trailing /.
		sprintf(state_file + strlen(state_file), "/%s",
				default_state_file_name);
	} else if (!*state_file)
		strcpy(state_file, default_state_file_name);
	get_file(fname, "Write current state on file", state_file);
	if (!*fname)
		return;

	do_save_state(fname);
	strcpy(state_file, fname);
	iter = 0;
}

command create_file_associations()
{
	int buf = zap("File Associations");
	char ext[FNAMELEN], cmd[FNAMELEN], dir[FNAMELEN], tmp[FNAMELEN];

	save_var window_bufnum;
	to_buffer_num(buf);
	stuff("# Associate Epsilon with the following extensions:\n");
	stuff("# Delete or add lines as required, then type Ctrl-X Ctrl-Z\n");
	stuff("# (the exit-level command) to proceed.  This command cannot\n");
	stuff("# remove existing Epsilon associations, only add new ones.\n");
	stuff("\n.c\n.cpp\n.h\n.e\n.txt\n");
	recursive_edit();
	if (strcmp(bufname, "File Associations"))
		error("Canceled.");
	point = 0;
	make_registration_entry("Epsilon", "Epsilon");
	get_executable_directory(dir);
	strcpy(tmp, argv[0]);
	absolute(tmp, dir);
	if (is_gui == IS_WIN31)
		sprintf(cmd, "%s %%1", tmp);
	else
		sprintf(cmd, "\"%s\" \"%%1\"", tmp);
	make_registration_entry("Epsilon\\shell\\open\\command", cmd);
	make_registration_entry("Epsilon\\shell\\open\\ddeexec", "\"%1\"");
	make_registration_entry("Epsilon\\shell\\open\\ddeexec\\application",
							"Epsilon");
	make_registration_entry("Epsilon\\shell\\open\\ddeexec\\topic",
							"Open");
	while (point < size() - narrow_end) {
		grab_line(bufnum, ext);
		if (*ext == '.')
			make_registration_entry(ext, "Epsilon");
		else if (*ext && *ext != '#')
			say("Ignoring invalid extension \"%s\"", ext);
	}
	restore_vars();
	buf_delete(buf);
	say("File associations created.");
}

export_colors_one_scheme(int i)
{
	char *nm;
	int j, k, fg, bg;

	nm = name_name(i);
	noteput("Working...%s", nm);
	bprintf("color_scheme \"%s\" {\n", nm);
	save_var selected_color_scheme = i;
	for (j = 0; j < number_of_color_classes(); j++) {
		k = get_foreground_color(j, 1);
		if (k & ECOLOR_UNKNOWN)
			continue;
		bprintf("\tcolor_class %s ", name_color_class(j));
		if (k & ECOLOR_COPY) {
			bprintf("= color_class %s;\n", name_color_class(COLOR_STRIP_ATTR(k)));
			continue;
		}
		fg = get_foreground_color(j, 0);
		bg = get_background_color(j, 0);
		bprintf("MAKE_RGB(%d, %d, %d)",
				GETRED(fg), GETGREEN(fg), GETBLUE(fg));
		if (!j || !(bg & ETRANSPARENT)
			  && bg != get_background_color(0))
			bprintf(" on MAKE_RGB(%d, %d, %d)",
					GETRED(bg), GETGREEN(bg), GETBLUE(bg));
		stuff(";\n");
	}
	stuff("};\n\n");
}

command export_colors()
{
	char name[FNAMELEN];
	int i, max = final_index();

	iter = 0;
	strcpy(name, "mycolors.e");
	absolute(name);
	if (warn_existing_file(name))
		return;
	do_find(name, FILETYPE_AUTO);
	buf_zap(bufnum);
	stuff("// Automatically generated by export-colors.\n\n");
	stuff("#include \"eel.h\"\n\n");
	if (has_arg) {
		for (i = 1; i <= max; i++) {
			check_abort();
			if (name_type(i) == NT_COLSCHEME)
				export_colors_one_scheme(i);
		}
	} else
		export_colors_one_scheme(selected_color_scheme);
	restore_vars();
	point = 0;
	for (i = 0; i < 10; i++) {	// Assume class names have no more than 10 -'s.
		noteput("Working...%d", i);
		string_replace("(color_class .*)-", "#1_", REGEX);
		if (!replace_num_changed)	// Convert -'s in class names to _'s.
			break;
	}
	substitute_color_names();
	say("Done.");
}

command load_changes()
{
	char name[FNAMELEN], *tmp;
	int i;

	get_file(name, "Load changes from file", "changed");
	tmp = temp_buf();
	to_buffer(tmp);
	if (read_file(name, FILETYPE_MSDOS))
		quick_abort();
	point = 0;
	string_replace("%+(maxmem|minmem|m?colors|normal-cursor"
				   "|-display-characters|buf-accessed-clock|c-look-back"
				   "|-bookmark-.*|-num-kill|-cur-kill-buf"
				   "|-errors-in-cmd-file|-prev-kbd-extended|eel-version) .*\n",
				   "", REGEX);
	if (re_search(1, "^%&.*\n"))
		bprintf("# COLOR SETTINGS IGNORED: use import-colors\n");
	point = 0;
	string_replace("^%&.*\n", "", REGEX);	// discard color info
	save_var _abort_load_on_error = 0;
	parse_cmds();
	point = 0;
	i = *get_color_scheme_variable();
	if (name_type(i) == NT_COLSCHEME)
		selected_color_scheme = i;
}

short *keyseq;		/* sequence of key codes, in format used by macros */

load_other()
{
	char name[80], junk[20];
	int i;

	parse_string(1, "[^ :]+", name);
	i = find_index(name);
	if (parse_string(1, ": macro ", junk)) {
		get_keyseq();
		if (i > 0)
			if (name_type(i) == NT_MACRO || !strcmp(name, "last-kbd-macro"))
				drop_name(name);
			else
				init_error("%s is already defined.  Use Alt-x delete-name "
						   "to overwrite.", name);
		name_macro(name, keyseq);
	} else if (parse_string(1, ": table", junk)) {
		if (i > 0) {
			if (name_type(i) == NT_TABLE)
				return;
			drop_name(name);
		}
		new_table(name);
	} else if (parse_string(1, ": command", junk)) {
		if (i <= 0 || name_type(i) != NT_COMMAND
			  && name_type(i) != NT_AUTOLOAD)
			init_error("%s is not a currently defined command",
					   name);
	} else if (parse_string(1, ": subroutine", junk)) {
		if (i <= 0 || name_type(i) != NT_SUBR
			  && name_type(i) != NT_AUTOSUBR)
			init_error("%s is not a currently defined subroutine",
					   name);
	} else
		init_error("%s: unrecognized syntax", name);
}

list_color_scheme(i)
{
	char colorpair[100];
	int j, fg, bg;

	save_var selected_color_scheme = i;
	for (j = 0; j < number_of_color_classes(); j++) {
		fg = get_foreground_color(j);
		if (fg & ETRANSPARENT)
			fg = get_foreground_color(0);
		bg = get_background_color(j);
		if (bg & ETRANSPARENT)
			bg = get_background_color(0);
		if (fg == attr_to_rgb(rgb_to_attr(fg))
			  && bg == attr_to_rgb(rgb_to_attr(bg)))
			give_color_combo(colorpair, alter_color(j, -1));
		else
			sprintf(colorpair, "[0x%x on 0x%x]", fg, bg);
		bprintf("&%s color class for %s: %s\n",
				name_name(i), name_color_class(j), colorpair);
	}
}

zeroed char tags_from_bsc;

do_save_tags()		/* save tags to their file if unsaved */
{
	int oldbuf = bufnum;

	if (exist("-tags")) {
		bufnum = _tags_buffer;
		if (modified) {
			if (size() > 2000000)
				sayput("Saving tags...");
			do_save_file(1, 1, 1);
		}
		bufnum = oldbuf;
	}
}

char *tag_match(s, flags) 
char *s;
{
	char tmp[TAGLEN];

	if (tags_from_bsc) {
		strcpy(_this_match, s);
		return (flags & STARTMATCH) ? s : 0;
	}
	save_var bufnum;
	save_var abort_searching = 0;
	bufnum = _tags_buffer;
	save_var case_fold = !tag_case_sensitive;
	if (flags & STARTMATCH)
		point = 0;
	if (*s) {
		sprintf(tmp, "^([^\t\n]+(::|'))?%s", s);
		do {
			if (!search(1, s))
				return 0;
		} while (!parse_string(-1, tmp)
				 || (flags & EXACTONLY) && curchar() != '\t');
		to_begin_line();
	} else if (!nl_forward() || point == size())
		return 0;
	parse_string(1, "[^\t\n]+", _this_match);
	to_end_line();
	return _this_match;
}

	/* make list of matches for s in mbuf */
tag_lister(char *s, char *(*finder)(), int flags, int mbuf)
{
	char pat[TAGLEN];
	int sorted;

	finder = finder;	/* silence eel's warning */
	flags = flags;
	save_var bufnum;
	save_var abort_searching = 0;
	if (tags_from_bsc) {
		buf_printf(mbuf, "%s", s);
		return;
	}
	if (want_sorted_tags && !*s)
		sort_tags();
	bufnum = _tags_buffer;
	save_var case_fold = !tag_case_sensitive;
	sorted = are_tags_sorted();	/* also goes to top */
	if (*s) {
		sprintf(pat, "^([^\t\n]+(::|'))?%q", s);
		while (search(1, s)) {
			if (parse_string(-1, pat)
				  && (!tag_list_exact_only || curchar() == '\t')) {
				to_end_line();
				buf_xfer(mbuf, matchend, point + 1);
			}
		}
	} else {
		nl_forward();
		buf_xfer(mbuf, point, size());
	}
	bufnum = mbuf;
	if (want_sorted_tags && !sorted && !user_abort) {
		abort_searching = ABORT_ERROR;
		sort_another(bufnum_to_name(mbuf), 0, 0);
	}
	point = 0;
	tab_size = 30;
	goal_column = display_column = 0;
}

tag_searcher_c(char *tag)
{
	char classname[FNAMELEN], fulltag[FNAMELEN], pr[FNAMELEN];
	int err, cnt = 0, selected = 0, try = 1;

	if (parse_string(-1, "-%>|%.[ \t\n]"))	// Ignore func's class.
		*classname = 0;
	else
		find_c_func_info(NULL, classname, NULL, 0);
again:
	strcpy(fulltag, tag);
	if (!strchr(tag, ':')) {		// Class not known yet.
		if (*classname && strcmp(classname, tag)) {		// See if current class 
			sprintf(fulltag, "%s::%s", classname, tag);	// has such a member.
			if (!(err = go_tag(fulltag, 1)))
				return err;
			bufnum = window_bufnum;
		}			// Is there more than one function by that name in any class?
		*fulltag = 0;
		bufnum = window_bufnum;
		if (tag_match(tag, STARTMATCH | EXACTONLY)) {
			do {
				cnt++;
			} while (tag_match(tag, EXACTONLY));
			if (cnt != 1) {
				sprintf(pr, "%d matches for %s: ", cnt, tag);
				save_var menu_width = 60, completion_lister = tag_lister;
				save_var insert_default_response = 2, tag_list_exact_only = 1;
				ungot_key = '?';
				comp_read(fulltag, pr, tag_match, (tag_case_sensitive ? 0 : COMP_FOLD)
						  | MUST_MATCH | NONE_OK | CAUTIOUS, tag);
				selected = 1;
			} else
				strcpy(fulltag, tag_match(tag, STARTMATCH | EXACTONLY));
		} else
			strcpy(fulltag, tag);
	}
	err = go_tag(fulltag, 1);
	strcpy(_last_tag, tag);
	if (err && !selected) {		// Try retagging current file before giving up.
		bufnum = window_bufnum;
		sprintf(pr, "Tag %s has moved, retag file %s? ",
				fulltag, filename);
		if (!tag_ask_before_retagging || try > 1
			  || ask_yn("Retag file", pr, "Yes", "No", 1)) {
			do_retag_file(filename);
			err = go_tag(fulltag, 1);
			do_save_tags();
			if (err && try++ < 2)
				goto again;
			if (!err)
				say("Found %s in this file.", tag);
		}
	}
	if (!err && !selected && strcmp(tag, fulltag))
		say("Searched for %s, found %s", tag, fulltag);
	report_tag_error(err);
}

// Adjust the name of a tag to indicate what we'll really search for.
tag_prompter_c(char *tag)
{
	char *p = _last_tag, *q;

	for (;;) {
		if ((q = strstr(p, "::")) && q[2])
			p = q + 2;		// Remove classname:: prefix.
		else if ((q = strstr(p, "'")) && q[1])
			p = q + 1;		// Remove classname' prefix for Perl.
		else
			break;
	}
	strcpy(tag, p);
}

// Search for another instance of the last tag (1==next instance,
// -1==previous, 0==same as before.  Return nonzero if we couldn't find
// any such tag, zero if could (and move to it).

tag_to_next_c(char *pat, int n_fwd)
{
	char raw_tag[FNAMELEN];

	tag_prompter_c(raw_tag);		// strip class names
	sprintf(pat, "^([^\t\n]+(::|'))?%q\t", raw_tag);
	return !tag_search_by_offset(pat, n_fwd);
}

modal_goto_tag(char *tag)
{
	char tag_searcher[FNAMELEN], fulltag[FNAMELEN], pr[FNAMELEN];
	int i, err;

	quiet_set_bookmark();
	sprintf(tag_searcher, "tag_searcher_%s", major_mode);
	i = find_index(tag_searcher);
	if (*tag && !strchr(tag, '\t'))		// If not yet fully specified,
		switch (name_type(i)) {		// Call mode-specific version.
			case NT_SUBR: case NT_COMMAND:
			case NT_AUTOSUBR: case NT_AUTOLOAD:
				(*(int (*)())i)(tag);
				return;
		}
	strcpy(fulltag, tag);
	err = go_tag(fulltag, 1);
	bufnum = window_bufnum;
	if (err && can_tag_a_file(filename)) {
		sprintf(pr, "Tag %s has moved, retag file %s? ", fulltag, filename);
		if (!tag_ask_before_retagging
			  || ask_yn("Retag file", pr, "Yes", "No", 1)) {
			do_retag_file(filename);
			err = go_tag(fulltag, 1);
			do_save_tags();
			if (!err)
				say("Found %s in this file.", fulltag);
		}
	}
	report_tag_error(err);	// Default behavior.
}

command goto_tag()
{
	char tag[TAGLEN], pr[FNAMELEN], look_for[FNAMELEN], tag_prompter[FNAMELEN];
	int i;

	tiled_only();
	init_tags();
	iter = 0;
	*tag = 0;
	strcpy(look_for, _last_tag);
	sprintf(tag_prompter, "tag_prompter_%s", major_mode);
	i = find_index(tag_prompter);
	switch (name_type(i)) {		// Call mode-specific version.
		case NT_SUBR: case NT_COMMAND:
		case NT_AUTOSUBR: case NT_AUTOLOAD:
			(*(int (*)())i)(look_for);
		}
	if (!has_arg) {
		if (!*_last_tag)
			sprintf(pr, "Find tag: ");
		else if (tags_from_bsc)
			sprintf(pr, "Find tag [next %s]: ", look_for);
		else
			sprintf(pr, "Find tag [next %s of %d]: ",
					look_for, count_tags(look_for));
		if (*_last_tag)
			save_completion(_last_tag, tag_match);
		get_tag(tag, pr);
	}
	modal_goto_tag(tag);
}

go_tag(s, n_fwd)
char *s;
{
	char msg[FNAMELEN];
	short err;

	if (!*s && !*_last_tag)
		error("No current tag.");
	if (tags_from_bsc)
		return go_bsc_tag(s);
	err = do_go_tag(s, n_fwd);
	if (err != 2)
		return err;
	if (narrow_start || narrow_end) {
		say("Tag not found in narrowed buffer, removing narrowing.");
		narrow_start = narrow_end = 0;
		make_mode();
		err = do_go_tag(_last_tag, n_fwd);
		if (err != 2)
			return err;
	}
	if (can_tag_a_file(_last_tag_file)) {
		sprintf(msg, "Tag %s has moved, retag file %s? ",
				_last_tag, _last_tag_file);
		if (tag_ask_before_retagging)
			if (!ask_yn("Retag file", msg, "Yes", "No", 1))
				return 0;
		do_retag_file(_last_tag_file);		// Tag has moved, so retag.
		do_save_tags();
	}
	return do_go_tag(_last_tag, n_fwd);
}

count_tags(char *s)
{
	char pat[FNAMELEN], *p, tag[FNAMELEN], fast_pat[FNAMELEN];
	int cnt = 0;

	strcpy(tag, s);
	if (p = index(tag, '\t'))
		*p = 0;		/* remove file name from tag spec */
	sprintf(pat, "^([^\t\n]+(::|'))?%q\t", tag);
	sprintf(fast_pat, "%s\t", tag);
	save_var bufnum = _tags_buffer;
	save_var case_fold = !tag_case_sensitive;
	save_var point = 0;
	while (search(1, fast_pat))
		if (parse_string(-1, pat))
			cnt++;
	return cnt;
}

do_go_tag(s, n_fwd)
char *s;
{
	char pat[FNAMELEN], tdir[FNAMELEN], *file, *p, modal_tag_next[FNAMELEN];
	int pos, oldbuf = bufnum, i;

	sprintf(modal_tag_next, "tag_to_next_%s", major_mode);
	bufnum = _tags_buffer;
	save_var case_fold = !tag_case_sensitive;
	if (*s) {
		if (p = index(s, '\t')) {
			strcpy(_last_tag_file, p + 1);
			*p = 0;		/* remove file name from s */
			if (p = index(_last_tag_file, '\t'))
				*p = 0;
		} else
			*_last_tag_file = 0;
		strcpy(_last_tag, s);
		if (!*_last_tag)	/* no last tag */
			return 0;
		if (*_last_tag_file)
			sprintf(pat, "^%q\t%q\t",
				_last_tag, _last_tag_file);
		else
			sprintf(pat, "^%q\t", _last_tag);
		point = 0;
		if (!re_search(1, pat))		/* look for 1st */
			return 1;
	} else {		/* find next matching tag */
		pos = point;
		sprintf(pat, "^%q\t", _last_tag);
		i = find_index(modal_tag_next);
		switch (name_type(i)) {		// Call mode-specific version.
			case NT_SUBR: case NT_COMMAND:
			case NT_AUTOSUBR: case NT_AUTOLOAD:
				if ((*(int (*)())i)(pat, n_fwd))
					return 1;
				break;
			default:
				if (!tag_search_by_offset(pat, n_fwd))
					return 1;
		}
	}
	grab(give_begin_line(), give_end_line(), pat);	/* tag, file, pos */
	file = index(pat, '\t');
	*file++ = 0;

	p = index(file, '\t');		/* find start of pos */
	pos = strtoi(p + 1, 10);
	*p = 0;
	p = index(p + 1, '\t');		/* if p, p+1 has line's text */
	strcpy(_last_tag_file, file);
	put_directory(tdir);
	bufnum = oldbuf;
	absolute(_last_tag_file, tdir);
	locate_window("", _last_tag_file);
	find_it(_last_tag_file, default_translation_type);
	sprintf(tdir, "%q[^a-zA-Z0-9_]", _last_tag);
	point = pos;
	if (!parse_string(1, tdir, NULL))
		if (!p || !prox_line_search(p + 1))	/* search by text */
			return 2;
	to_begin_line();
	window_start = prev_screen_line(show_tag_line);
	return 0;
}

command untag_files()
{
	int t, p, count;
	char this[FNAMELEN], resp[FNAMELEN], msg[FNAMELEN];

	init_tags();
	if (tags_from_bsc)
		error("Can't modify a .BSC file.");
	t = zap(TAGGED_FILES_BUF);
	get_tagged_file_names(t);

	save_var bufnum, window_bufnum;
	to_buffer_num(t);
	p = tmp_buf();
	buf_xfer(p, 0, size());
	point = 0;
	stuff("# Press Ctrl-X Ctrl-Z to untag all files not named below.\n");
	stuff("# Only files remaining in this list will keep their tags.\n\n");
	recursive_edit();
	if (!buf_exist(t) || !buf_exist(p)) {
		say("No files untagged.");
		return;
	}
	to_buffer_num(t);
	simple_re_replace(1, "^(# .*)?\n", "");
	restore_vars();
	do_compare_sorted(t, p, NULL, "-untag-these-files", NULL);
	buf_delete(p);

	save_var bufname = "-untag-these-files";
	count = lines_between(0, size(), 0);
	restore_vars();
	sprintf(msg, (count == 1) ? " Untag this %d file? "
							  : " Untag these %d files? ", count);
	if (!(is_gui && want_gui_prompts))
		say("%s", msg + 1);
	else
		say("");
	if (count) {
		save_var _view_title = msg;
		save_var paging_retains_view = 1;
		view_buffer("-untag-these-files", 0);
		if (is_gui && want_gui_prompts && key == abort_key)
			count = 0;		// User clicked Cancel.
		else if (is_gui && want_gui_prompts) {	// Already prompted so don't
			if (toupper(key) != 'Y' && !IS_ENTER_KEY(key) // ask again.
				  && toupper(key) != 'O')
				count = 0;
			ungot_key = -1;
		} else {
			get_string(resp, msg + 1);
			if (toupper(*resp) != 'Y')
				count = 0;
		}
		user_abort = 0;
	}
	if (count) {
		save_var bufname = "-untag-these-files";
		for (point = 0; point < size(); nl_forward()) {
			grab(give_begin_line(), give_end_line(), this);
			if (size() > 1000)
				noteput("Deleting tags: %2d%%...", muldiv(point, 100, size()));
			do_delete_tags(this);
		}
		do_save_tags();
		say("%d file%s untagged.", count, count == 1 ? "" : "s");
	} else
		say("No files untagged.");

	restore_vars();
	delete_buffer("-untag-these-files");
	buf_delete(t);
}

command tag_files()
{
	char pat[FNAMELEN], *s;
	int aborted = 0;

	init_tags();
	if (tags_from_bsc)
		error("Must tag files using the BSCMAKE program.");
	if (has_arg)
		save_var tag_declarations = 3;
	get_file(pat, "Add/update tags for files matching", filename);
	iter = 0;
	if (!(s = do_file_match(pat, STARTMATCH | EXACTONLY | FM_NO_DIRS)))
		error("No matches");
	to_another_buffer("-tag-errors");
	delete_buffer("-tag-errors");
	save_var tag_batch_mode = 1;
	for (; s; s = do_file_match(pat, EXACTONLY | FM_NO_DIRS)) {
		if (aborted = do_retag_file(s))
			break;
	}
	if (!aborted) {
		do_save_tags();
		say("%s tagged.", pat);
	}
	if (exist("-tag-errors")) {
		to_buffer("-tag-errors");
		discardable_buffer = 1;
	}
}

can_tag_a_file(s)
char *s;
{
	char subr[FNAMELEN], def[FNAMELEN], *pattern = "tag-suffix-%s";

	s = get_extension(s);
	sprintf(subr, pattern, *s ? (s + 1) : "none");
	sprintf(def, pattern, "default");
	return find_index(subr) || find_index(def);
}

good_c_tag()	// tag name at point if a valid c tag
{		// return 0 to go back to orig point before searching again
	char func[TAGLEN], tmp[TAGLEN];
	int start = point, i = 1;

	if (!parse_string(1, "[a-zA-Z0-9_]+", func))
		return 0;
	else if (!strcmp(func, "struct") || !strcmp(func, "union"))
		return tag_c_struct(0);		// maybe struct tag
	else if (!strcmp(func, "class"))
		return tag_c_struct(1);		// or similar class def
	else if (!strcmp(func, "enum"))
		return tag_c_struct(2);		// or similar enum def
	else if (!strcmp(func, "namespace"))
		return tag_c_struct(3);		// or namespace def
	else if (!strcmp(func, "operator") && parse_string(1, CPP_OPLIST)) {
		grab(matchstart, matchend, func + strlen(func));
		point = matchend;
	} else if (!strcmp(func, "extern")) {
		tag_extern_decl = 1;	// next vars are just declarations
		return 1;
	} else if (!strcmp(func, "__declspec")) {
		return 1;
	} else if (parse_string(-1, "^[ \t]*#[^#\n]*"))
		return tag_c_define(func);	// do preproc line
	c_fwd_space();
	if (curchar() == '_' && parse_string(1, "(_ANSI_ARGS_|__P)</word>")) {
		point = matchend;	// skip over arg-hiding macro
		c_fwd_space();
	}
	if (curchar() == '(') {
		if (matches_at(start, -1, "~[ \t]*")) {
			point = matchend;
			parse_string(1, "~[ \t]*[a-zA-Z0-9_]+", func);
		}
		i = tag_c_func(1);
	} else if (curchar() == ':' && parse_string(1, "::[ \t\n]*"
												"(_?(near|far)[ \t\n]+)?([a-zA-Z0-9_~]+|" CPP_OPSPEC ") *%(")) {
		strcat(func, "::");	// make raw class::func w/o spaces
		grab(find_group(3, 1), find_group(3, 0), func + strlen(func));
		i = tag_c_func(1);
	} else if (tag_c_variable() && ((tag_declarations & 2)
									|| !tag_extern_decl))
		i = 2;
	if (i == 2 && !isdigit(*func)) {
		if (*c_tagging_class && !index(func, ':')) {
			strcpy(tmp, func);	// put class:: before func name
			sprintf(func, "%s::%s", c_tagging_class, tmp);
		}
		add_tag(func, start);
	}
	return i;
}


tag_c_skip_before_body(int show)
{
	if (parse_string(1, "#.*(\\\n.*)*")) {
		point = matchend;
		return 1;
	}
	if (parse_string(1, "(try|const|volatile)![^_A-Za-z0-9]")) {
		point = matchend;
		return 1;
	}
	if (parse_string(1, "throws[ \t]")) {	// for java
		point = matchend;
		skip_identifier_list();
		return 1;
	}
	if (parse_string(1, "throw[ \t]*!%(")) {	// for C++
		point = matchend;
		if (skip_c_delims('(', ')', 1)) {
			if (show)
				buffer_printf("-tag-errors", "Couldn't parse %s at line %d\n",
							  filename, lines_between(0, point, 0) + 1);
			return 0;
		}
		return 1;
	}
	return 0;
}

tag_c_func(show) // tag this, if it's a function definition, or maybe decl
{		// return 0: go back & try again, 1: continue, 2: also tag
	int ret = 2;

	if (skip_c_delims('(', ')', 1)) {
		if (show)
			buffer_printf("-tag-errors", "Couldn't parse %s at line %d\n",
						  filename, lines_between(0, point, 0) + 1);
		return 0;	/* after identifier, skip over arg list */
	}
	c_fwd_space();
	while (tag_c_skip_before_body(show))
		c_fwd_space();
	if (parse_string(1, "on[ \t]")) {	// eel command
		search(1, "\n{");
		point--;
		ret = 2;
	} else if (parse_string(1, "[A-Za-z{]")) // func definition
		ret = skip_param_decls();
	else if (curchar() == ':')		// C++ initializer
		ret = skip_cpp_init();
	else if (curchar() == '=')		// C++ function using =0.
		return 2;
	else if (!parse_string(1, "[,;]"))	// not even a declaration
		ret = (point >= size());	// Skip parens if it looks like a macro.
	else if (!(tag_declarations & 1))	// a declaration, don't tag it?
		ret = 1;
	if (ret)
		tag_extern_decl = 0;
	return ret;
}

int skip_identifier_list()
{
	int cnt = 0;
	for (;; point++) {
		c_fwd_space();
		if (!parse_string(1, "[a-zA-Z0-9_.]+"))
			break;
		point = matchend;
		cnt++;
		c_fwd_space();
		if (curchar() != ',')
			break;
	}
	return cnt;
}

// Tag the following structure/class/enum if we're defining a tag for it.
// Flavor: 0=struct/union, 1=class, 2=enum, 3=namespace.
tag_c_struct(int flavor)
{
	char func[TAGLEN];
	int start;

	c_fwd_space();
	start = point;
	if (!parse_string(1, "[a-zA-Z0-9_]+", func)) {
		if (flavor == 3)	// namespace doesn't require a name
			*func = 0;
		else
			return 1;
	}
	c_fwd_space();	// skip compiler-specific junk betw "class" & name
	if (flavor == 1 && !is_java_buffer() && parse_string(1, "[a-zA-Z0-9_]+")) {
		parse_string(1, "[a-zA-Z0-9_]+", func);
		c_fwd_space();
	}
	if (curchar() != '{' && (flavor != 1 || !parse_other_class()))
		return 1;	// classes can have other stuff before {
	if (flavor == 1 || flavor == 3 || flavor == 0) {
		point++;	// skip over { so we do stuff within
		strcpy(c_tagging_class, func);	// remember, now in class
	} else if (flavor == 2)
		tag_c_enum();
	if (*func)
		add_tag(func, start);
	return 1;
}

/* We've parsed "class foo" but there's no { character right after.
 * See if there's some inheritance information we can skip past to find
 * the { character.
 * Return 1 if we found ": foo {" or similar (C++).
 * Return 2 if we found "extends foo implements bar {" or similar.
 * In either case, move before the final { character.  Otherwise return
 * zero.
 */
parse_other_class()
{
	if (curchar() == ':') {
		point++;
		for (;;) {
			c_fwd_space();
			if (!parse_string(1, "[a-zA-Z0-9_]+"))
				break;
			point = matchend;
			if (curchar() == '<')
				point += parse_string(1, "%<[a-zA-Z0-9_, \n\t]+%>");
		}
		c_fwd_space();
	} else if (is_java_buffer()) {
		while (strchr("ei", curchar())
			   && parse_string(1, "(extends|implements)</word>")) {
			point = matchend;
			skip_identifier_list();
		}
	}
	return curchar() == '{';
}

is_java_buffer()
{
	return !stricmp(".java", get_extension(filename));
}

add_tag(func, pos)
char *func;
{
	char rel[FNAMELEN], *file = filename, tdir[FNAMELEN];

	if (tag_relative) {		/* use relative version instead */
		put_tag_directory(tdir);
		relative(file, rel, tdir);
		file = rel;
	}
	if (tag_show_percent == 2)
		noteput("%s: adding %s...", file, func);
	else if (tag_show_percent == 1)
		noteput("Working %2d%%...", muldiv(point, 100, size()));
	if (tag_by_text) {
		int start;

		save_var point;
		point = pos;
		to_begin_line();
		start = point;
		to_end_line();
		buf_printf(_tags_buffer, "%s\t%s\t%d\t",
				   func, file, pos);
		buf_xfer(_tags_buffer, start, point);
		buf_printf(_tags_buffer, "\n");
	} else
		buf_printf(_tags_buffer, "%s\t%s\t%d\n", func, file, pos);
}

do_retag_file(file)	/* takes abs pathname, retags it */
char *file;
{
	char rel[FNAMELEN];

	relative(file, rel);
	delete_tags(file);
	if (tag_batch_mode)
		noteput("%s: searching for tags...", rel);
	return tag_a_file(file);
}

delete_tags(file)	/* delete all tags pointing to file (abs name) */
char *file;
{
	char rel[FNAMELEN], tdir[FNAMELEN];

	save_var abort_searching = 0;
	put_tag_directory(tdir);
	relative(file, rel, tdir);
//	noteput("%s: deleting old tags...", rel);
	do_delete_tags(tag_relative ? rel : file);
}

undo_set_flag(int flag)
{
	if (undo_count(0) <= 0)
		undo_flag = flag;
}

undo_group_movements(is_undo)
{
	int ret, last, i, cnt, orig_modif = modified, last_cnt = -1;

	ret = last = 0;
	for (; i = undo_op(is_undo); ret |= last = i) {
		if (i & UNDO_FLAG) {
			switch (undo_flag) {
				case UNDO_READ_FILE:
				case UNDO_WRITE_FILE:
				case UNDO_UNMODIFIED:
					if (!last)
						return i;
					undo_op(!is_undo);
					return ret;
			}
			i &= ~UNDO_FLAG;
		}
		if (!i || (i & (UNDO_CHANGES | UNDO_END)))
			break;	/* repeat until buffer changes */
		orig_modif = modified;
		cnt = undo_count(!is_undo);
		if (cnt == last_cnt)	// Don't get stuck at end.
			return ret;
		last_cnt = cnt;
	}
	if (!ret)
		ret = i;
	if (last && (i & UNDO_CHANGES)) {
		do {		/* then reverse change */
			undo_op(!is_undo);
		} while (undo_count(!is_undo) > cnt);
		modified = orig_modif;
	}
	return ret;
}

undo_it(is_undo, group_movements)
{
	int ret, before_count;
	char msg[200], *name = is_undo ? "un" : "re", *spec = 0;
	int orig_nar_start = narrow_start;
	int orig_nar_end = narrow_end;

	if (undo_count(is_undo) < 1)
		error("Nothing to %sdo.", name);
	before_count = undo_count(0);
	if (!before_count)
		_buffer_saved_here = -1;
	if (!undo_keeps_narrowing)
		narrow_start = narrow_end = 0;
	*name = tolower(*name);
	if (group_movements)
		ret = undo_group_movements(is_undo);
	else					/* plain undo */
		ret = undo_op(is_undo);
	narrow_start = orig_nar_start;
	narrow_end = orig_nar_end;
	if ((point < orig_nar_start || point > size() - orig_nar_end)
		  && !undo_keeps_narrowing) {
		say("Undoing outside narrowed region, removing narrowing.");
		narrow_start = narrow_end = 0;
	}
	*name = toupper(*name);
	if (ret & UNDO_FLAG)
		switch (undo_flag) {
			case UNDO_READ_FILE:	spec = "Buffer read from disk";
									break;
			case UNDO_WRITE_FILE:	spec = "Buffer written to disk";
									break;
			case UNDO_UNMODIFIED:	spec = "Buffer was marked unmodified";
									break;
		}
	if (spec) {
		sprintf(msg, "%s, ", spec);
		if (_buffer_saved_here == -1)
			_buffer_saved_here = undo_count(0);
		if (undo_count(0) == _buffer_saved_here || before_count == _buffer_saved_here)
			modified = 0;
	} else if (ret & (UNDO_CHANGES | UNDO_MOVE | UNDO_REDISP | UNDO_MAINLOOP))
		sprintf(msg, "%sdid %s%s%s%s%s%s%s",
				name,
				(ret & UNDO_END ? "Partial " : ""),
				(ret & UNDO_MAINLOOP ? "Command, " : ""),
				(ret & UNDO_REDISP ? "Display, " : ""),
				(ret & UNDO_MOVE ? "Move, " : ""),
				(ret & UNDO_INSERT ? "Insert, " : ""),
				(ret & UNDO_DELETE ? "Delete, " : ""),
				(ret & UNDO_REPLACE ? "Replace, " : ""));
	else
		sprintf(msg, "%sdid, ", name);
	note("%s%d bytes remain", msg, undo_count(is_undo));
	return ret;
}

short _video_adapter;
#define IS_EGA		(_video_adapter == 1)
#define IS_VGA		(_video_adapter == 2)

dos_find_outside()	/* set variables for screen size outside of epsilon */
{
	_last_video_mode = screen_mode;
	switch (screen_mode) {
		case 2: case 3: case 7:
			if (screen_lines != 25 || screen_cols != 80)
				_last_video_mode = -1;
	}
	_outside_size = MAKE_SIZE(screen_cols, screen_lines);
	if (restore_color_on_exit)
		alter_color(color_class after_exiting, orig_screen_color());
	if (is_win32 == IS_WIN32_CONSOLE) {
		selectable_colors = 256;
		return;
	}
	_video_adapter = isega();
	if (IS_EGA || IS_VGA)
		selectable_colors = 256;
	save_var load_fail_ok = 1;
	if (have_uvision())	// use only Ultravision modes if installed
		init_uvision();	// load ultravision support & initialize
	else if (have_vesa())	// else use vesa modes (+regular) if installed
		init_vesa();
}

int finger_activity();

command finger()
{
	char response[FNAMELEN], username[FNAMELEN], hostname[FNAMELEN], *p;
	char finger_bufname[FNAMELEN];

	inet_only();
	tiled_only();
	get_str_auto_def(response, "Finger user@host");	// Prompt for a string.

	if ((p = rindex(response, '@')) == 0){		// Parse the string.
		strcpy(hostname, response);		// List users.
		*username = 0;
	} else {
		strcpy(hostname, p+1);			// Show details for one user.
		strncpy(username, response, p - response);
	}
	if (!*hostname)
		return;

	sprintf(finger_bufname, "Finger %s", response);
	zap(finger_bufname);
	to_buffer(finger_bufname);
	discardable_buffer = 1;
	buffer_not_saveable = 1;
	when_net_activity = finger_activity;
	finger_user(username, hostname, finger_bufname);
}

telnet_activity(int activity, int buf, int from, int to)
{
	if (!buf_exist(buf))
		return;
	save_var iter, has_arg;
	save_var bufnum = buf;
	switch (activity) {
		case NET_DONE:
			stuff("Connection closed.\n");
			refresh();
			telnet_id = 0;
			break;
		case NET_RECV:
			set_character_color(from, to, color_class process_output);
			save_var point = from - 2;
			while (re_search(1, "_\b.|o\b%+")) {
				delete(point - 3, point - 1);
				set_character_color(point - 1, point, color_class process_prompt);
			}
			point = to;
			save_var case_fold = 1;
			if (parse_string(-1, "Password:[ \t]*") && ungot_key == -1
				  && recognize_password_prompt) {
				ungot_key = WIN_HELP_REQUEST;	// Make Epsilon run this cmd:
				menu_command = "telnet-password-prompt";
			}
			break;
	}
}

command telnet()
{
	char hostname[FNAMELEN], buf[FNAMELEN], *p;
	int port = 23, i = 1;

	inet_only();
	tiled_only();
	if (has_arg){
		port = iter;
		iter = 0;
	}
	*hostname = 0;
	get_str_auto_def(hostname, "Host");
	if (!*hostname)
		return;
	sprintf(buf, "%s", hostname);
	p = buf + strlen(buf);
	for (;;) {		// Find an unused buffer.
		if (!exist(buf))
			break;
		bufname = buf;
		if (!telnet_id)
			break;
		sprintf(p, " %d", i++);
	}
	do_telnet(hostname, port, buf);
}

command show_connections()
{
	char msg[500], *s;

	inet_only();
	tiled_only();
	make_connect_list();
	if (num_of_popups() > 0 && !strcmp(bufname, CONNECT_LIST_BUF))
		return;
	save_var menu_width = 60;
	*msg = 0;
	if (get_choice(name_to_bufnum(CONNECT_LIST_BUF), msg,
				   "Remote Connections", NULL, "Go to", "Close", "")) {
		s = strstr(msg, ": ");
		if (s) {
			*s = 0;
			if (exist(msg))
				to_buffer(msg);
		}
	}
	user_abort = 0;
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

command tex_math_escape()
{
	iter = 0;
	tex_insert_pair("$$");
}

command tex_left_brace()
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

command tex_small_caps() on tex_tab[ALT('C')]
{
	tex_insert_cmd(latex_2e_or_3 ? "\\textsc{" : "{\\sc ", "}", 0);
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

command tex_environment()
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
	if (parse_string(-1, "[^\\]%%.*"))	// In comments, don't break lines.
		return 1;
	return maybe_break_this_line();
}

int color_tex_range(), recolor_tex_from_here();

command tex_mode()
{
	mode_keys = tex_tab;		/* Use these keys. */
	compile_buffer_cmd = compile_tex_cmd;
	tex_tab['}'] = Matchdelim ? (short) show_matching_delimiter : 0;
	tex_tab[']'] = Matchdelim ? (short) show_matching_delimiter : 0;
	tex_tab[')'] = Matchdelim ? (short) show_matching_delimiter : 0;
	tex_paragraphs = 1;
	buffer_maybe_break_line = tex_maybe_break_line;
	if (tex_force_latex == 2){		// Determine if it's LaTeX.
		save_var point = 0;
		tex_force_latex = search(1, "\\begin{document}");
	}
	major_mode = tex_force_latex ? _latex_mode_name : _tex_mode_name;
	strcpy(comment_start, "[^\\]%%[ \t\f]*");
	strcpy(comment_pattern, "[^\\]%%.*$");
	strcpy(comment_begin, "% ");
	strcpy(comment_end, "");
	recolor_range = color_tex_range;	// set up coloring rules
	recolor_from_here = recolor_tex_from_here;
	if (want_code_coloring)		// maybe turn on coloring
		when_setting_want_code_coloring();
	idle_coloring_size = 3000;	// Do bigger bunches.
	if (auto_show_tex_delimiters)
		auto_show_matching_characters = tex_auto_show_delim_chars;
	try_calling("tex-mode-hook");
	drop_all_colored_regions();
	make_mode();
}

#define C_COMMENT_FILLER		"[^0-9a-zA-Z\x80-\xFF_(\n]*"
#define C_COMMENT_PREFIX		"^" C_COMMENT_FILLER

command fill_c_comment()
{
	int pbuf, width = 1000, i, old_lines, new_lines, orig_lines;
	int col, col2, orig = bufnum, type, generic = strcmp(major_mode, "C");
	char last_prefix[FNAMELEN], orig_prefix[FNAMELEN], pat[FNAMELEN], comm[30];

	iter = 0;
	if (has_arg)
		save_var margin_right = current_column() + 1;
	save_spot point;
	type = locate_c_comment();	// 1 if block comment, 2 if one-line
	if (!type)					// comment, or 0 if not a comment.
		error("Can't fill comment here, not in a comment.");
	point += parse_string(1, C_COMMENT_FILLER);	// Past 1st line's prefix.
	sprintf(pat, "[ \t]*%s[^0-9a-z_\n]*", generic ? comment_start : "/[*/]");
	grab(point, point - parse_string(-1, pat), orig_prefix);
	save_var narrow_start = point;		// Narrow to the paragraph.
	point = mark;
	if (!generic)
		point -= parse_string(-1, "<*>/");
	save_var narrow_end = size() - point + 1;

	if (type == 1 && !generic)		// Combine adjacent block comments.
		simple_re_replace(1, "[ \t]*<*>/[ \t]*\n?[ \t]*/<*>[ \t]*", " ");
	point = 0;
	while (nl_forward()) {	// Find width of narrowest prefix.
		i = parse_string(1, C_COMMENT_PREFIX);
		col = get_column(point + i);
		width = MIN(width, col);
	}
	pbuf = tmp_buf();
	point = 0;
	strcpy(comm, generic ? comment_begin : "//");
	while (strlen(comm) > 0 && comm[strlen(comm) - 1] == ' ')
		comm[strlen(comm) - 1] = 0;	// Remove trailing spaces.
	sprintf(pat, "[ \t]*%s", comm);
	while (nl_forward()) {	// Move each prefix to our temp buffer.
		i = parse_string(1, C_COMMENT_PREFIX);
		col = get_column(point + i);
		if (col > width)	// Make sure it's not too wide.
			col = width;
		if (type == 2) {	// But if it's made of one-line comments,
			i = parse_string(1, pat);
			col2 = get_column(point + i);
			if (col < col2)		// each prefix must include a "//".
				col = col2;
		}
		i = column_to_pos(col);
		buf_xfer(pbuf, point - 1, i);
		delete(point, i);
	}
	if (width == 1000)	// No prefix, so use default.
		width = 3;
	orig_lines = old_lines = lines_between(0, size(), 0) + 1;
	region_fill_first_line(narrow_start, size() - narrow_end,
						   MAX(margin_right, 20),
						   MAX(margin_right - width, 20));
	new_lines = lines_between(0, size(), 0) + 1;
	point = 0;
	bufnum = pbuf;
	point = 0;
	*last_prefix = 0;	// Now copy the prefixes back.
	for (; new_lines > 0 && old_lines > 0; old_lines--, new_lines--) {
		grab(point, give_end_line(), last_prefix);
		buf_xfer(orig, point, give_end_line());
		nl_forward();
		bufnum = orig;
		nl_forward();
		bufnum = pbuf;
	}
	if (orig_lines < 2) {		// Default for new lines if 1 line originally.
		strcpy(last_prefix, orig_prefix);
		if (type == 2 && !strstr(last_prefix, comm))
			sprintf(last_prefix, "%s ", comm);
		else if (type == 1 && !generic)
			if (!strstr(last_prefix, "/*"))
				strcpy(last_prefix, " * ");
			else
				*strchr(last_prefix, '/') = ' ';
	}
	bufnum = orig;
	for (; new_lines > 0; new_lines--) {	// More lines than before.
		stuff(last_prefix);			// Add some prefixes.
		nl_forward();
	}
	buf_delete(pbuf);
	if (display_column > 0)
		display_column = 0;
	fix_window_start();	/* win shouldn't start in middle of line */
}

int locate_c_comment()
{
	int com, type = 1, generic = strcmp(major_mode, "C");

	save_spot narrow_start, narrow_end;
	com = in_c_comment(c_look_back);	// Comment?  If so, what type?
	if (com == IN_OLD_COMMENT || !com && !generic && parse_string(1, "[ \t]*/<*>"))
		narrow_to_block_comment();
	else if (narrow_to_new_comment())
		type = 2;
	else
		return 0;
	to_begin_line();
	if (parse_string(1, C_COMMENT_PREFIX "$"))
		point--;		// If on line right after a parag, go back.
	to_begin_line();
	if (parse_string(1, C_COMMENT_PREFIX "$")) // If no text on line,
		if (!re_search(-1, "[^ \t\n]"))	// Find a line with text.
			re_search(1, "[^ \t\n]");

	re_search(1, C_COMMENT_PREFIX "$");	// Find "blank" line w/only filler.
	if (parse_string(-1, C_COMMENT_PREFIX "$"))
		to_begin_line();	// And move to its start.
	re_search(-1, "[^ \t\n]");	// Find text of some parag before it.
	nl_forward();
	mark = point;
	point--;
	re_search(-1, C_COMMENT_PREFIX "$");	// Find "blank" line before.
	if (parse_string(1, C_COMMENT_PREFIX "\n"))
		nl_forward();
	return type;
}

narrow_to_block_comment()
{
	save_var point;
	do {
		search(1, "*/");
	} while (parse_string(1, "[ \t]*\n?[ \t]*/<*>"));
	narrow_end = size() - point;
	do {
		search(-1, "/*");
	} while (parse_string(-1, "<*>/[ \t]*\n?[ \t]*"));
	narrow_start = point;
}

// Narrow to a block of adjacent lines that that start with one-line
// C++ comments like the one we assume we're starting in.  If this one
// doesn't start with such a comment, return 0, else 1.  We attempt to
// handle non-C++ one-line comments too.

int narrow_to_new_comment()
{
	char pat[50];

	if (strcmp(major_mode, "C"))
		sprintf(pat, "[ \t]*%s", comment_start);
	else
		strcpy(pat, "[ \t]*//");
	save_var point;
	to_begin_line();
	if (!parse_string(1, pat)) {
		narrow_start = point;	// This line doesn't start with one.
		restore_vars();
		to_end_line();
		if (!re_search(-1, pat))
			return 0;		// Can't find comment start.
		narrow_start = point;
	}
	while (nl_forward())		// Find the last such line.
		if (!parse_string(1, pat))
			break;
	narrow_end = size() - point;
	do {						// Find the first such line.
		point--;
		to_begin_line();
		if (!parse_string(1, pat)) {
			nl_forward();
			break;
		}
	} while (point > narrow_start);
	narrow_start = point;
	return 1;
}

c_break_line_here(int comm, int starts_with_comm, int starts_in_comm,
				  int comm_start, spot next_ends, spot after, char *fill)
{
	int offset, generic = strcmp(major_mode, "C");
	char rest[FNAMELEN], *p, *new_comm;

	delete_horizontal_space();
	insert('\n');
	if (display_column > 0)	// Horizontally scroll back to left margin.
		display_column = 0;
	if (key == '\n')	// User might be trying to break line elsewhere as
		key = ' ';		// we're breaking it here.  Prevent a mess.

	if (comm == IN_NEW_COMMENT) {		// A //-style C++ comment.
		new_comm = generic ? comment_begin : "// ";
		if (starts_with_comm)	// This line began with a comment, so just
			stuff(fill);		// repeat its prefix (indentation and such).
		else if (next_ends && get_column(comm_start) > get_column(*next_ends)) {
			grab(point, give_end_line(), rest);	// Continue it on the next line
			offset = give_end_line() - *after;	// since there's no comment
			delete(point - 1, give_end_line());	// there.
			point = *next_ends;
			to_column(get_column(comm_start) - 2);
			bprintf("%s%s%s", isspace(character(point - 1)) ? "" : " ",
					new_comm, rest);
			*after = point - offset;	// Point might be in the middle of moved text.
		} else {			// Make a new line after the commented code line we
			stuff(new_comm);	// broke.
			point -= 3;
			indent_to_column(c_compute_indent());
		}
	} else {			/* Old-style K&R comment. */
		if (strstr(fill, "*/"))
			*fill = 0;
		if (starts_in_comm)		// Just repeat the *'s or whatever at start of
			stuff(fill);		// old line.
		else if (starts_with_comm) {
			if (!strcmp(fill, "/**"))	// A Javadoc comment.
				fill = " * ";
			p = strchr(fill, '/');	// Like above, but convert that first /*.
			if (p)
				*p = ' ';
			stuff(fill);
		} else {
			delete(point - 1, point);	// Delete the \n we just inserted.
			stuff(" */\n/* ");			// And put this instead.
			to_begin_line();
			indent_to_column(c_compute_indent());
		}
	}
}

int c_maybe_break_line(int mode)
{
	int comm, res = 1, starts_with_comm, starts_in_comm, after_prefix;
	int comm_start = -1, break_block_comment = 0;
	int generic = strcmp(major_mode, "C");
	char fill[FNAMELEN], pat[FNAMELEN], raw_comm[FNAMELEN];
	spot after, next_ends = 0;

	switch (mode) {
		case 0:
		case 1:
			c_auto_fill_mode = (mode != 0);
			return 0;
		case 2:
			return c_auto_fill_mode;
	}
	if (!c_auto_fill_mode)		// We're not in auto-fill mode.
		return 1;
	delete_if_highlighted();

	// Various reasons we might want not want to fill right now.
	if (give_end_line() - give_begin_line() > FNAMELEN - 10)
		return 1;			// The line's too long for us.
	if (current_column() + 1 <= margin_right) {
		if (IS_ENTER_KEY(key) && in_c_comment(c_look_back) == IN_OLD_COMMENT)
			break_block_comment = 1, res = 0;
		else
			return 1;		// We're not past the margin.
	}
	comm = in_c_comment(c_look_back);
	if (!(comm & IN_COMMENT))
		return 1;			// We're not in a comment.

	// Collect info on the situation.
	if (key == ' ') {		// Insert <Space> now, then remember not
		insert(key);		// to later, so we can break here.
		res = 0;
	}
	after = alloc_spot(1);	// Remember where we should end up.
	to_begin_line();	// See if a comment's the first thing on this line.
	strcpy(raw_comm, generic ? comment_begin : "//");
	while (strlen(raw_comm) > 0 && raw_comm[strlen(raw_comm) - 1] == ' ')
		raw_comm[strlen(raw_comm) - 1] = 0;	// Remove trailing spaces.
	sprintf(pat, "[ \t]*%s", generic ? raw_comm : "/[*/]");
	starts_with_comm = parse_string(1, pat);	// Yes.
	starts_in_comm = in_c_comment(c_look_back);	// Does this line start with one?
	sprintf(pat, "[ \t%s]*", generic ? raw_comm : "*/");
	parse_string(1, pat, fill);	// Repeat this prefix on new lines.
	after_prefix = point;
	if (!starts_in_comm) {		// Find where this line's comment starts.
		sprintf(pat, ".*%s", generic ? raw_comm : comm == IN_NEW_COMMENT ? "//" : "/%*");
		point += parse_string(1, pat);
		comm_start = point;
	}
	if (nl_forward()) {		// Remember the end of the next line, unless
		to_end_line();		// there's a comment there.
		if (!in_c_comment(c_look_back))
			next_ends = alloc_spot(0);
	}

	// Look for a breaking point.
	point = *after;
	if (break_block_comment ||
		  (c_auto_fill_mode != 1 || starts_with_comm || starts_in_comm)
		  && pick_break(margin_right) && point > after_prefix
		  && point > comm_start)
		c_break_line_here(comm, starts_with_comm, starts_in_comm,
						  comm_start, next_ends, after, fill);
	point = *after;
	free_spot(after);
	if (next_ends)
		free_spot(next_ends);
	return res;
}


save_screen(p)		/* save current window info in p */
struct screen_info *p;	/* on first call with p, p->wins must be 0 */
{
	int i, oldroom = 0, nwins = number_of_windows() - number_of_popups();

	p->lines = screen_lines, p->cols = screen_cols;
	p->cur_window = window_number;
	p->echo_line = echo_line;
	p->avoid_top = avoid_top_lines;
	p->avoid_bottom = avoid_bottom_lines;
	p->permanent_menu = permanent_menu;
	if (p->wins)
		oldroom = ptrlen(p->wins) / sizeof(struct window_info);
	if (oldroom < nwins) {
		if (p->wins)
			free(p->wins);
		p->wins = (struct window_info *) malloc(nwins
												* sizeof(struct window_info));
	}
	for (i = 0; i < nwins; i++)
		get_window_info(i, p->wins + i);
	p->num = i;
}

restore_screen(p)	/* restore windows from data in p */
struct screen_info *p;
{
	int i, origbuf, origpt;

	bufnum = origbuf = window_bufnum;
	origpt = point;
//	if (screen_lines != p->lines || screen_cols != p->cols)
//		error("Screen is in wrong mode for restore.");
	for (i = 0; i < p->num; i++)
		window_create(!i, p->wins + i);
	echo_line = p->echo_line;
	select_low_window(p->cur_window, p->avoid_top, p->avoid_bottom,
					  p->lines, p->cols);
	restore_menu(p->permanent_menu);
	if (bufnum == origbuf)
		point = origpt;
}


// Load the new default color settings.

color_class text white on black;
color_class highlight white on dark_green;
color_class echo_area yellow on black;
color_class mode_line cyan;
color_class horiz_border cyan;
color_class vert_border = color_class horiz_border;

color_class popup_title dark_red on grey;
color_class popup_border dark_red on grey;

color_class after_exiting grey on black;
color_class debug_text dark_blue on grey;
color_class debug_highlight grey on dark_blue;
color_class default dark_red on grey;

color_class overlap_even dark_cyan on dark_blue;
color_class overlap_odd = color_class default;	// No longer used.
color_class screen_border = color_class text;

color_class viewed_text dark_blue on grey;
color_class viewed_border dark_red on grey;
color_class viewed_link green on grey;
color_class selected_link red on grey;

color_class menu dark_blue on grey;
color_class menu_highlight dark_blue on dark_cyan;
color_class menu_bar black on dark_cyan;
color_class menu_bar_highlight dark_blue on grey;
color_class submenu black on dark_cyan;
color_class submenu_highlight dark_blue on grey;

color_class c_comment white;
color_class c_preprocessor grey;
color_class c_keyword green;
color_class c_function yellow;
color_class c_identifier black;
color_class c_string cyan;
color_class c_charconst = color_class c_string;
color_class c_number = color_class text;
color_class c_punctuation = color_class text;

color_class ident_completion white on dark_cyan;
color_class show_matching_start black on green;
color_class show_matching_end black on cyan;

color_class html_text = color_class c_function;
color_class html_tag = color_class c_function;
color_class html_attribute = color_class c_string;
color_class html_value = color_class c_preprocessor;
color_class html_comment = color_class c_comment;
color_class html_entity = color_class c_comment;
color_class html_punctuation = color_class html_attribute;

color_class dired_normal = color_class text;
color_class dired_file_name = color_class c_function;
color_class dired_dir_name = color_class c_comment;
color_class dired_header = color_class c_string;
color_class dired_deleted red;
color_class dired_moved = color_class c_preprocessor;
color_class dired_copied = color_class c_comment;

color_class grep_text = color_class text;
color_class grep_match = color_class dired_copied;
color_class grep_filename = color_class dired_file_name;
color_class grep_header = color_class c_string;

color_class diff_added black on yellow;
color_class diff_removed black on light_red;

color_class process_output = color_class text;
color_class process_input = color_class c_function;
color_class process_prompt = color_class c_comment;

color_class tex_text = color_class text;
color_class tex_comment = color_class c_comment;
color_class tex_curly_brace = color_class c_function;
color_class tex_square_bracket = color_class c_string;
color_class tex_math = color_class c_string;
color_class tex_literal = color_class html_attribute;
color_class tex_command = color_class c_preprocessor;
color_class tex_begin_end = color_class c_function;
color_class tex_section = ocher;

color_class perl_comment = color_class c_comment;
color_class perl_string = color_class c_string;
color_class perl_keyword = color_class c_preprocessor;
color_class perl_function = color_class c_punctuation;
color_class perl_variable = color_class c_function;
color_class perl_constant = color_class html_tag;

color_class asm_keyword = color_class html_attribute;
color_class asm_register = color_class c_function;
color_class asm_identifier = color_class c_punctuation;

color_class makefile_comment = color_class html_comment;
color_class makefile_preproc = color_class html_value;
color_class makefile_macro = color_class html_tag;
color_class makefile_target = color_class c_string;

color_class inifile_comment = color_class html_comment;
color_class inifile_section = color_class html_text;
color_class inifile_definition = color_class html_attribute;

color_class man_underlined = color_class inifile_section;
color_class man_bold = color_class inifile_comment;

color_class conf_comment = color_class html_comment;
color_class conf_attribute = color_class html_attribute;
color_class conf_value = color_class html_value;

color_class gams_string = color_class html_text;
color_class gams_comment = color_class c_comment;
color_class gams_control = color_class c_preprocessor;
color_class gams_keyword = color_class c_string;
color_class gams_variable = color_class c_identifier;

color_class postscript_comment = color_class html_comment;
color_class postscript_text = color_class html_text;
color_class postscript_literal = color_class html_tag;

// Wipe out specific color selections so they can use our new defaults.

when_loading()
{
	int i;

	save_var selected_color_scheme;
	for (i = final_index(); i > 0; i--) {
		if (name_type(i) != NT_COLSCHEME || !strcmp(name_name(i), "color-defaults"))
			continue;
		selected_color_scheme = i;
		set_color_pair(color_class tex_section, ECOLOR_UNKNOWN, 0);
		set_color_pair(color_class perl_variable, ECOLOR_UNKNOWN, 0);
		set_color_pair(color_class perl_constant, ECOLOR_UNKNOWN, 0);
		set_color_pair(color_class inifile_section, ECOLOR_UNKNOWN, 0);
		set_color_pair(color_class man_underlined, ECOLOR_UNKNOWN, 0);
	}
}

// Change those colors with new defaults, but try not to disturb other
// user-set colors.

color_scheme "standard-gui" {
	color_class tex_literal = color_class html_tag;
	color_class ident_completion black on MAKE_RGB(192, 224, 192);
	color_class html_tag bluish_purple;
	color_class perl_constant ECOLOR_UNKNOWN;
	color_class makefile_macro ECOLOR_UNKNOWN;
	color_class inifile_section ECOLOR_UNKNOWN;
	color_class gams_string ECOLOR_UNKNOWN;
	color_class postscript_literal ECOLOR_UNKNOWN;
	color_class tex_section ECOLOR_UNKNOWN;
	color_class man_underlined ECOLOR_UNKNOWN;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant = color_class html_tag;
};

color_scheme "visual-c" {
	color_class tex_math = color_class html_value;
	color_class tex_section ECOLOR_UNKNOWN;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
};

color_scheme "other-grey" {
	color_class tex_square_bracket = color_class html_value;
	color_class tex_section ECOLOR_UNKNOWN;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
};

color_scheme "standard-color" {
	color_class tex_section ECOLOR_UNKNOWN;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
};

color_scheme "standard-mono" {
	color_class tex_section = color_class c_string;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
	color_class diff_added = black on white;
	color_class diff_removed = black on grey;
};

color_scheme "xterm-color" {
	color_class tex_section magenta;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
};

color_scheme "night-light" {
	color_class tex_math = red;
	color_class tex_section ECOLOR_UNKNOWN;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
};

color_scheme "yellow-on-blue" {
	color_class tex_section ECOLOR_UNKNOWN;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
};

color_scheme "white-on-blue" {
	color_class tex_section ECOLOR_UNKNOWN;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
};

color_scheme "blue-on-cyan" {
	color_class tex_section ECOLOR_UNKNOWN;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
};

color_scheme "white-background" {
	color_class tex_math = color_class c_keyword;
	color_class tex_section ECOLOR_UNKNOWN;
	color_class perl_variable ECOLOR_UNKNOWN;
	color_class perl_constant ECOLOR_UNKNOWN;
};

// For updating autoloaded files.
// If cmd isn't NULL, and names a command in the state file, then load
// the bytecode file (because its commands were already in the state file).
// Otherwise, autoload the bytecode file again.

update_autoload(char *cmd, char *file)
{
	char full[FNAMELEN], *s;

	strcpy(full, file);
	strcpy(get_extension(full), byte_extension);
	if (check_file(full))
		s = full;
	else
		s = lookpath(full);
	if (!s)
		error("Can't find %s", full);
	if (*cmd && name_type(find_index(cmd)) == NT_COMMAND)
		load_commands(s);
	else
		autoload_commands(s);
}


/*
Load this file to update your Epsilon state file from 10 B1 or later to
this version.
*/

when_loading()
{
	int i;
	char *upper, *lower;

	if (state_file && get_file_read_only(state_file) == 1) {
		save_var bufnum = zap(HELPBUF);
		if (strcmp(eel_version, EEL_MINOR_VERSION))
			bprintf("%s is read-only.\n"
					"Therefore it cannot be updated.\n"
					"The above state file is for Epsilon version %s.\n"
					"This Epsilon executable is from Epsilon version %s.\n"
					"Perhaps EPSPATH is set incorrectly?\n",
					state_file, eel_version, EEL_MINOR_VERSION);
		else
			bprintf("%s is read-only.\n"
					"Therefore it cannot be updated.\n"
					"But this Epsilon executable is from version %s,\n"
					"and so is the above state file.\n"
					"Therefore it appears no update is needed.\n",
					state_file, eel_version);
		view_help(" Update Not Performed ", 0);
		return;
	}

	// Load or autoload these as appropriate.
	update_autoload("asm-mode", "asm");
	update_autoload("brief-keyboard", "brief");
	update_autoload("info", "info");
	update_autoload("perl-mode", "perl");
	update_autoload("list-changes", "diff");

	for (i = 0; i < 256; i++)
		_def_ansi_case_map[i] = _def_ansi_srch_case_map[i] = i;
	upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞ";
	lower = "abcdefghijklmnopqrstuvwxyzàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþ";
	for (; *upper && *lower; upper++, lower++) {
		_def_ansi_char_class[*lower] = C_LOWER;
		_def_ansi_char_class[*upper] = C_UPPER;
		_def_ansi_case_map[*lower] = _def_ansi_srch_case_map[*lower] = *upper;
		_def_ansi_case_map[*upper] = *lower;
	}		

	if (!strcmp(ignore_file_extensions, "|.obj|.exe|.b|.b2|.bu|"))
		strcpy(ignore_file_extensions, "|.obj|.exe|.o|.b|"); // new def
	if (strcmp("10b4", eel_version) >= 0) {
		latex_2e_or_3 = 1;		// Only update when going from 10b4 or earlier.
		reindent_after_perl_yank = 0;
	}
	if (strcmp("10b5", eel_version) >= 0) {
		tab_size.default = 8;	// Only update when going from 10b5 or earlier.
		c_tab_override = 4;
		strcpy(grep_ignore_file_extensions,
		       "|.obj|.exe|.o|.b|.dll|.lib|");
		start_make_in_buffer_directory = 2;
	}
	if (strcmp("10b8c", eel_version) >= 0) {
	// Only update when going from 10b8c or earlier.
		auto_show_adjacent_delimiter = 3;
	}
	view_tab[' '] = (short) inp_next_page;
	menu_tab[' '] = (short) inp_next_page;
	if (!strstr(mode_end, "%f"))
		strcat(mode_end, "%f");
	drop_name("delete-tags-for-file");	// renamed to untag-files
	drop_name("matches-previous-color-class");	// deleted subr
	drop_name("ini-tab");	// deleted key table
	drop_name("info-epsilon-look-up");	// delete old names
	drop_name("info-epsilon-manual");
	drop_name("new-file-io-converter");
	drop_name("cursor-blink-rate");

	drop_name("process-complete");	// removed broken command
	process_tab['\t'] = 0;

	drop_name("is-identifier-char");	// remove id completion for now
	drop_name("ident-complete-after-normal-character");
	drop_name("auto-complete-identifier");
	drop_name("discard-buffer-completions");
	drop_name("look-for-some-completions");
	drop_name("look-for-file-completions");
	drop_name("look-for-conditional-completions");
	drop_name("interpret-completion-conditional");
	drop_name("shrink-completion");
	drop_name("look-for-completion");
	drop_name("find-buffer-prefix");
	drop_name("make-completion-list");
	drop_name("complete-identifier");
	drop_name("make-c-completion-list");
	drop_name("c-ok-to-complete");
	drop_name("completion-sources");
	drop_name("completion-minimum-start");
	drop_name("completion-minimum-add");
	drop_name("auto-complete");
	drop_name("-doing-ident-completion");
	reg_tab[ALT('=')] = 0;

	drop_name("plain-insert-key");	// deleted subr
	if (find_index("want-display-function-name")) {	// renamed variable
		drop_name("display-definition");
		replace_name("want-display-function-name", "display-definition");
	}
	strcpy(eel_version, EEL_MINOR_VERSION);

	delay(1, COND_KEY);	// Make sure the X window is up.
	refresh();
	sayput("Update complete, preparing to write state file...");
	delay(300, COND_KEY);	// Give the user a chance to abort.
	check_abort();
	if (!*state_file)
		write_state();		// Prompt for name.
	else
		do_save_state(state_file);	// Rewrite current state file.
	exit();
}
