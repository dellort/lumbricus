#ifndef _sdlrwops_tools_h_
#define _sdlrwops_tools_h_

#include <stdio.h>
#include <stdarg.h>
#include <SDL/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

int sdlrw_fprintf(SDL_RWops *stream, const char* str, ...);
int sdlrw_fputc(int c, SDL_RWops *stream);
int sdlrw_fputs(char* s, SDL_RWops *stream);

#ifdef __cplusplus
};
#endif

#endif
