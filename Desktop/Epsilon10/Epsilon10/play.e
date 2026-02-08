#include "eel.h"

int i=1;

command play_order_ncx()
{

	while(re_search(1,"playOrder=\".+\"<min>"))

	{
		delete(matchstart,matchend);
		bprintf("playOrder=\"%d\"",i++);
	}

	i=1;
}


