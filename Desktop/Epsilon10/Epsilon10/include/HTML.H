/************************************************************************
* "Epsilon" is a registered trademark licensed to Lugaru Software, Ltd. *
*		"EEL" and "Lugaru" are trademarks of Lugaru Software, Ltd.		*
*																		*
*  Copyright (C) 1996, 1997 Lugaru Software Ltd.  All rights reserved.  *
*																		*
* Limited permission is hereby granted to reproduce and modify this		*
* copyrighted material provided that the resulting code is used only in *
* conjunction with Lugaru products and that this notice is retained in	*
* any such reproduction or modification.								*
************************************************************************/

char _html_mode_name[] = "Html";
keytable html_tab;			/* key table for html mode */

user char html_auto_show_delim_chars[20] = "<>";
user char html_javascript_coloring = 1;
user int color_html_look_back = 50000;

color_class html_text;
color_class html_tag;
color_class html_attribute;
color_class html_value;
color_class html_comment;
color_class html_entity;
color_class html_punctuation;
