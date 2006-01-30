#include "sdlrwops_tools.h"

/* no vasprintf in mingw :( */
int vasprintf_custom (char **ptr, const char *str, va_list va)
{
    /* Guess we need no more than 100 chars of space. */
    int size = 100;
    *ptr = (char *) malloc (size);
    if (*ptr == NULL)
        return 0;

    /* Try to print in the allocated space. */
    int nchars = vsnprintf (*ptr, size, str, va);
    if (nchars >= size)
    {
        /* Reallocate buffer now that we know
           how much space is needed. */
        *ptr = (char *) realloc (*ptr, nchars + 1);

        if (*ptr != NULL)
            /* Try again. */
            vsnprintf (*ptr, size, str, va);
    }
    /* The last call worked, return the string. */
    return nchars;
}

int sdlrw_fprintf(SDL_RWops *stream, const char* str, ...)
{
    va_list marker;
    va_start(marker, str);

    char *buf;
    int len = vasprintf_custom(&buf, str, marker);

    stream->write(stream, buf, len, 1);

    free(buf);

    va_end(marker);
}

int sdlrw_fputc(int c, SDL_RWops *stream)
{
    if (stream->write(stream, &c, 1, 1)>=0)
      return c;
    else
      return EOF;
}

int sdlrw_fputs(char* s, SDL_RWops *stream)
{
    if (stream->write(stream, s, strlen(s), 1)>=0)
      return 0;
    else
      return EOF;
}


