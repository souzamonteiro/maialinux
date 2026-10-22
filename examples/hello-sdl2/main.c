#include <SDL2/SDL.h>
#include <stdbool.h>
#include <stdio.h>

#define SCREEN_W 640
#define SCREEN_H 480

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) < 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window *win = SDL_CreateWindow(
        "MaiaLinux SDL2 Demo (640x480)",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        SCREEN_W, SCREEN_H, SDL_WINDOW_SHOWN
    );
    if (!win) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_Renderer *ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE);
    SDL_Rect box = { SCREEN_W / 2 - 30, SCREEN_H / 2 - 30, 60, 60 };
    int vx = 4, vy = 3;
    bool running = true;

    while (running) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) running = false;
            if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_ESCAPE) running = false;
            if (e.type == SDL_MOUSEBUTTONDOWN) {
                box.x = e.button.x - box.w / 2;
                box.y = e.button.y - box.h / 2;
            }
        }

        box.x += vx;
        box.y += vy;
        if (box.x <= 0 || box.x + box.w >= SCREEN_W) vx = -vx;
        if (box.y <= 0 || box.y + box.h >= SCREEN_H) vy = -vy;

        SDL_SetRenderDrawColor(ren, 24, 24, 37, 255);
        SDL_RenderClear(ren);

        SDL_SetRenderDrawColor(ren, 137, 180, 250, 255);
        SDL_RenderFillRect(ren, &box);

        SDL_RenderPresent(ren);
        SDL_Delay(16);
    }

    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}
