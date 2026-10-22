#!/usr/bin/env python3
"""MaiaLinux RG353V Starter Pygame App (640x480) with Touch & Gamepad support."""

import pygame
import sys


def main():
    pygame.init()
    pygame.joystick.init()
    joysticks = [pygame.joystick.Joystick(i) for i in range(pygame.joystick.get_count())]
    for joy in joysticks:
        joy.init()

    screen = pygame.display.set_mode((640, 480))
    pygame.display.set_caption("MaiaLinux Pygame RG353V (640x480)")
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("dejavusansmono", 16)

    x, y = 320, 240
    speed = 5
    running = True

    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                running = False
            elif event.type == pygame.MOUSEBUTTONDOWN:
                x, y = event.pos

        keys = pygame.key.get_pressed()
        if keys[pygame.K_LEFT]:
            x -= speed
        if keys[pygame.K_RIGHT]:
            x += speed
        if keys[pygame.K_UP]:
            y -= speed
        if keys[pygame.K_DOWN]:
            y += speed

        x = max(25, min(615, x))
        y = max(25, min(455, y))

        screen.fill((24, 24, 37))
        pygame.draw.circle(screen, (166, 227, 161), (int(x), int(y)), 25)

        txt = font.render("Touch screen or use D-Pad/Stick to move | ESC to exit", True, (205, 214, 244))
        screen.blit(txt, (24, 16))

        pygame.display.flip()
        clock.tick(60)

    pygame.quit()
    sys.exit(0)


if __name__ == "__main__":
    main()
