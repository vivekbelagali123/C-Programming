/************************************************************************
* "Epsilon" is a registered trademark licensed to Lugaru Software, Ltd. *
*		"EEL" and "Lugaru" are trademarks of Lugaru Software, Ltd.		*
*																		*
*  Copyright (C) 1988, 1999 Lugaru Software Ltd.  All rights reserved.	*
*																		*
* Limited permission is hereby granted to reproduce and modify this		*
* copyrighted material provided that the resulting code is used only in *
* conjunction with Lugaru products and that this notice is retained in	*
* any such reproduction or modification.								*
************************************************************************/

// This file compares windows line-by-line.

#include "eel.h"
#include "diff.h"
#include "colcode.h"

command diff()
{
	diff_style(0);
}

command merge_diff()
{
	char var[FNAMELEN];
	int obuf = bufnum;

	tiled_only();
	if (number_of_user_windows() < 2)
		error("Only one window");
	get_strdef(var, "Merge using an #ifdef variable named", merge_diff_var);
	if (!*var)
		return;
	strcpy(merge_diff_var, var);
	diff_style(MERGE_DIFF_STYLE);
	safe_copy_buffer_variables(bufnum, obuf);
}

visual_diff_mode()
{
	mode_keys = visual_diff_tab;
	major_mode = _visual_diff_mode_name;
	make_mode();
}

command visual_diff()
{
	diff_style(VISUAL_DIFF_STYLE);
	visual_diff_mode();
}

move_to_difference(int rev)
{
	int new, old;

	if (rev)
		nl_reverse();
	to_begin_line();
	old = get_character_color(point, NULL, NULL);
	if (old != color_class diff_removed && old != color_class diff_added)
		old = color_class text;
	new = old;
	while (new == old && (rev ? nl_reverse() : nl_forward())) {
		check_abort();
		to_begin_line();
		get_character_color(point, NULL, NULL);
		new = get_character_color(point, NULL, NULL);
		if (new != color_class diff_removed && new != color_class diff_added)
			new = color_class text;
	}
	if (rev && point > 0)
		nl_forward();
}

command next_difference() on visual_diff_tab[ALT(']')],
							 visual_diff_tab[NUMALT(KEYDOWN)]
{
	move_to_difference(0);
}

command previous_difference() on visual_diff_tab[ALT('[')],
								 visual_diff_tab[NUMALT(KEYUP)]
{
	move_to_difference(1);
}

diff_style(int style)
{
	char newbuf[FNAMELEN];

	tiled_only();
	if (number_of_user_windows() < 2)
		error("Only one window");
	get_buf(newbuf, "List differences to buffer", "diff");
	do_diff(newbuf, style);
	locate_window(newbuf, "");
	point = 0;
}

do_diff(char *buf, int style)
{
	int start;

	strcpy(_diff_buffer, buf);
	delete_user_buffer(_diff_buffer);
	zap(_diff_buffer);
	diff_check_malloc();	/* see if we need to make room for data */
	_diff_line1 = _diff_line2 = 1;
	set_points(0, 0);
	do {
		start = point;
		diff_same();
		if (style == VISUAL_DIFF_STYLE)	// Found identical lines.
			visual_diff_copy(0, "  ", 0, start, point);
		else if (style == MERGE_DIFF_STYLE)
			visual_diff_copy(-1, "", 0, start, point);
	} while (resync_lines(style));
	say("Done.");
}

diff_same()		/* advance both windows while lines match */
{
	int i1, i2, i, j;
	char buf1[MAXONE], buf2[MAXONE];

	for (;;) {
		i1 = point;
		nl_forward();
		if (i = (point > i1 + MAXONE - 1)) /* if too big, */
			point = i1 + MAXONE - 1;   /* break into pieces */
		grab(i1, point, buf1);
		next_user_window(1);
		i2 = point;
		nl_forward();
		if (j = (point > i2 + MAXONE - 1))
			point = i2 + MAXONE - 1;
		grab(i2, point, buf2);
		next_user_window(-1);	/* buf1 has i1..point chars */
		if (i != j || point == i1)
			break;	/* either mismatch, or hit end of both */ 
		else if (strlen(buf1) == point - i1)
			j = strfcmp(buf1, buf2); /* no nulls, do fast */
		else			/* must compare char-by-char */
			for (j = point - i1; j > 0; j--)
				if (charfcmp(buf1[j - 1], buf2[j - 1]))
					break;
		if (j)			/* mismatch */
			break;
		else if (!i) {
			++_diff_line1, ++_diff_line2;
			if (_diff_line1 % 100 == 0)
				noteput("Lines %d and %d match...",
						_diff_line1, _diff_line2);
		}
		check_abort();
	}
	set_points(i1, i2);	/* go to start of mismatched lines */
}

diff_check_malloc()	/* see if we need to make room in arrays */
{
	int newsize = (diff_mismatch_lines + diff_match_lines) * sizeof(int);
	int local;

	_diff_data.local = local = (newsize <= (MAXLINES * sizeof(int)));
	if (_diff_data.start1 && (newsize > _diff_data.size || local)) {
		free(_diff_data.start1);	/* if already exists, and */
		free(_diff_data.end1);		/* it's either too small, */
		free(_diff_data.start2);	/* or not needed, free it */
		free(_diff_data.end2);
	}	
	if (!local && (newsize > _diff_data.size || !_diff_data.start1)) {
		_diff_data.start1 = (int *) malloc(newsize);
		_diff_data.end1 = (int *) malloc(newsize);
		_diff_data.start2 = (int *) malloc(newsize);
		_diff_data.end2 = (int *) malloc(newsize);
	}
	_diff_data.size = newsize;
}

/* Attempt to resynchronize, give error if we couldn't. */
/* Return 0 when both have reached end. */

resync_lines(style)
{
	int i, reach, t;
	int *start1, *end1, *start2, *end2;	/* ranges of lines */
	int loc_start1[MAXLINES], loc_end1[MAXLINES];	/* local versions */
	int loc_start2[MAXLINES], loc_end2[MAXLINES];

	if (_diff_data.local) {
		start1 = loc_start1, end1 = loc_end1;
		start2 = loc_start2, end2 = loc_end2;
	} else {	/* must use already-allocated globals from struct */
		start1 = _diff_data.start1, end1 = _diff_data.end1;
		start2 = _diff_data.start2, end2 = _diff_data.end2;
	}
	for (reach = 0; reach < diff_mismatch_lines; reach++) {
		start1[reach] = point;		/* get info on next range */
		end1[reach] = extent_end();	/* of lines */
		next_user_window(1);
		start2[reach] = point;
		end2[reach] = extent_end();
		next_user_window(-1);
		for (i = 0; i <= reach; i++) {
			if (line_matches(start1[reach], end1[reach],
						start2[i], end2[i]))
				t = reach, reach = i, i = t;	/* swap */
			else if (!line_matches(start1[i], end1[i],
						start2[reach], end2[reach]))
				continue;
			set_points(start1[i], start2[reach]);
			if (!i && !reach)	/* found a match */
				return 0;
			note_change(start1[0], start1[i], _diff_line1, i,
				start2[0], start2[reach], _diff_line2, reach, style);
			_diff_line1 += i;
			_diff_line2 += reach;
			return 1;
		}
		if (reach > 10) {
			noteput("Searching...%d", reach);
			check_abort();
		}
	}
	set_points(start1[0], start2[0]);
	note_error(_diff_line1, _diff_line2);
}

extent_end()	/* return start of the line diff_match_lines lines after */
{		/* point, and go to start of next line after point */
	int second, i, final;

	nl_forward();
	second = point;
	for (i = diff_match_lines - 1; i > 0; i--)
		if (!nl_forward())
			break;
	final = point;
	point = second;
	return final;
}

line_matches(pos1, end1, pos2, end2)
{
	int orig1, orig2, i, len1 = end1 - pos1, len2 = end2 - pos2;
	char buf1[MAXMANY], buf2[MAXMANY];

	if (len1 != len2)
		return 0;
	if (i = (len1 < MAXMANY - 1)) {		/* fits in buf1? */
		grab(pos1, end1, buf1);
		next_user_window(1);
		if (i = (len2 < MAXMANY - 1))	/* and buf2? */
			grab(pos2, end2, buf2);
		next_user_window(-1);
	}
	if (i)				/* yes, they fit */
		return memfcmp(buf1, buf2, len1) == 0;
	orig1 = point, point = pos1;
	next_user_window(1);
	orig2 = point, point = pos2;
	next_user_window(-1);
	do_compare_windows();		/* if compare-windows stops */
	i = (point >= end1);		/* after end1, */
	point = orig1;
	next_user_window(1);
	i = (i && point >= end2);	/* and end2, */
	point = orig2;
	next_user_window(-1);		/* the regions match */
	return i;
}

// Record a difference.
// Chars s1..e1 (lcount1 lines at lstart1) become s2..e2.

note_change(s1, e1, lstart1, lcount1, s2, e2, lstart2, lcount2, style)
{
	char msg[80], *s;

	if (style == VISUAL_DIFF_STYLE) {
		if (lcount1)
			visual_diff_copy(color_class diff_removed, "< ", 0, s1, e1);
		if (lcount2)
			visual_diff_copy(color_class diff_added, "> ", 1, s2, e2);
		return;
	}
	if (style == MERGE_DIFF_STYLE) {
		merge_note_msg(lcount1 ? "#ifndef %s" : "#ifdef %s");
		if (lcount1)
			visual_diff_copy(-1, "", 0, s1, e1);
		if (lcount1 && lcount2)
			merge_note_msg("#else // %s");
		if (lcount2)
			visual_diff_copy(-1, "", 1, s2, e2);
		merge_note_msg(lcount2 ? "#endif // %s" : "#endif // not %s");
		return;
	}
	s = msg + diff_range(msg, lstart1, lcount1);
	*s++ = !lcount1 ? 'a' : !lcount2 ? 'd' : 'c';
	s += diff_range(s, lstart2, lcount2);
	note_msg(msg);
	if (lcount1)
		visual_diff_copy(0, "< ", 0, s1, e1);
	if (lcount1 && lcount2)
		note_msg("---");
	if (lcount2)
		visual_diff_copy(0, "> ", 1, s2, e2);
}

diff_range(s, lstart, count)
char *s;
{
	if (count > 1)
		return sprintf(s, "%d,%d", lstart, lstart + count - 1);
	else
		return sprintf(s, "%d", lstart + count - 1);
}

// Copy text from window, format & maybe color it.
// Color may be 0 for normal, -1 for no coloring, or a color class.

visual_diff_copy(color, prefix, winoff, start, end)
char *prefix;
{
	int tab, pos;

	save_var bufnum;
	next_user_window(winoff);
	if (!color && want_code_coloring && recolor_range)
		recolor_buffer_range(start, end);		// Color in place, then copy.
	buf_xfer_colors(name_to_bufnum(_diff_buffer), start, end);
	tab = tab_size;
	next_user_window(-winoff);
	bufname = _diff_buffer;
	point = pos = size() - (end - start);
	if (*prefix) {		// Untabify copied text.
		tab_size = tab;
		tab_convert(point, size(), 0);
		point = pos;
	}
	if (color > 0)		// Make it all one color.
		set_character_color(point, size(), color);
	if (*prefix) {		// Put this before each line.
		while (re_search(1, "^!(.|\n)")) {
			stuff(prefix);
			set_character_color(point - strlen(prefix), point,
								(color > 0) ? color : -1);
		}
	}
	point = size();
	if (character(point - 1) != '\n')
		insert('\n');	// Buffer didn't end with \n, pretend it did.
}

note_error(l1, l2)
{
	char msg[60];

	sprintf(msg, "Couldn't resynchronize at %d and %d...", l1, l2);
	note_msg(msg);
	error("%s", msg);
}

// Put a msg in the diff buffer, replacing %s with merge var name.
merge_note_msg(char *s)
{
	char buf[200];
	sprintf(buf, s, merge_diff_var);
	note_msg(buf);
}

note_msg(s)
char *s;
{
	char *orig = bufname;

	bufname = _diff_buffer;
	stuff(s);
	insert('\n');
	set_character_color(point - (strlen(s) + 1), point, -1);
	bufname = orig;
}

set_points(p1, p2)	/* set points for both windows */
{
	point = p1;
	next_user_window(1);
	point = p2;
	next_user_window(-1);
}

command list_changes()
{
	char before[FNAMELEN], after[FNAMELEN];
	int t1, t2, t3;

	get_file(before, "List changes from", "before");
	bufnum = t1 = tmp_buf();
	if (read_file(before, FILETYPE_MSDOS))
		quick_abort();
	save_var case_fold = 1;
	get_file(after, "To", "after");
	bufnum = t2 = tmp_buf();
	if (read_file(after, FILETYPE_MSDOS))
		quick_abort();
	save_var case_fold = 1;
	noteput("Sorting...");
	do_buffer_sort(bufnum_to_name(t3 = tmp_buf()), 0, 0);
	buf_zap(t2);
	do_compare_sorted(t1, t3, (char *)0, bufnum_to_name(t2), (char *)0);
	to_buffer_num(t2);
	one_window();
	buf_delete(t1);
	buf_delete(t3);
	set_buffer_filename("changed");
	file_info.check_type = 0;
	say("These changes were made.");
}

command compare_sorted_windows()
{
	int b2;

	tiled_only();
	if (number_of_user_windows() < 2)
		error("Only one window");
	next_user_window(1), b2 = bufnum, next_user_window(-1);
	do_compare_sorted(bufnum, b2, "only1", "only2", "inboth");
	locate_window("only1", "");
}

/* compare two sorted buffers, copying lines that appear in only
   the first, only the second, or in both to other buffers */

#define MAXONE		200	/* maximum line length to read at once */
#define MSGCOUNT	100	/* say where we are every MSGCOUNT compares */

do_compare_sorted(b1, b2, only1, only2, both)
char *only1, *only2, *both;
{
	char buf[2][MAXONE + 1], *tobuf;
	int need[2], len[2], i[2], j[2], big[2], pt[2], line[2], w;
	int complen, diff, count = 0;

	save_var bufnum;
	if (only1) zap(only1);
	if (only2) zap(only2);
	if (both) zap(both);
	for (w = 0; w < 2; w++) {	/* do init */
		need[w] = 1;
		line[w] = 0;
		bufnum = w ? b2 : b1;
		save_var point = 0;
	}
	do {
		for (w = 0; w < 2; w++) {	/* get next lines */
			if (need[w]) {
				bufnum = w ? b2 : b1;
				i[w] = point;
				nl_forward();
				line[w]++;
				len[w] = (pt[w] = point) - i[w];
				big[w] = (len[w] > MAXONE);
				if (big[w])	/* too big, take 1st part */
					pt[w] = i[w] + MAXONE;
				grab(i[w], pt[w], buf[w]);
				need[w] = 0;
			}
		}
		complen = MIN(len[0], len[1]);
again:		if (complen)
			diff = memfcmp(buf[0], buf[1], MIN(complen, MAXONE));
		else
			diff = len[0] ? -1 : len[1] ? 1 : 0;
		if (diff == 0 && (big[0] || big[1]))	/* equal so far */
			if (big[0] && big[1]) {		/* both too big */
				for (w = 0; w < 2; w++) {	/* get more */
					bufnum = w ? b2 : b1;
					j[w] = point;
					big[w] = (j[w] - pt[w] > MAXONE);
					if (big[w])
						j[w] = pt[w] + MAXONE;
					grab(pt[w], j[w], buf[w]);
					pt[w] = j[w];
					need[w] = 1;
				}
				goto again;	/* till we find diff */
			} else		/* only one was too big */
				diff = big[0];
		if (diff >= 0) {	/* now transfer results */
			tobuf = diff ? only2 : both;
			if (tobuf) {
				bufnum = b2;
				xfer(tobuf, i[1], i[1] + len[1]);
			}
			need[1] = 1;
			if (!diff)
				need[0] = 1;
		} else {
			if (only1) {
				bufnum = b1;
				xfer(only1, i[0], i[0] + len[0]);
			}
			need[0] = 1;
		}
		check_abort();
		if (++count % MSGCOUNT == 0)
			noteput("Comparing lines %d and %d...", line[0], line[1]);
	} while (len[0] > 0 || len[1] > 0);
	say("Done.");
}
