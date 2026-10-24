#!/usr/bin/env python3
"""MaiaLinux RG353V Starter GUI App (Tkinter) optimized for 640x480 screen."""

import platform
import subprocess
import tkinter as tk


def toggle_keyboard():
    subprocess.Popen(["/usr/local/bin/maialinux-keyboard-toggle"])


def main():
    root = tk.Tk()
    root.title("MaiaLinux Dev Pad (640x480)")
    root.geometry("600x400")
    root.configure(bg="#1e1e2e")

    header = tk.Label(
        root,
        text=f"MaiaLinux RG353V ({platform.machine()}) - Python {platform.python_version()}",
        bg="#1e1e2e",
        fg="#89b4fa",
        font=("DejaVu Sans", 10, "bold"),
    )
    header.pack(pady=6)

    editor = tk.Text(
        root,
        height=14,
        width=68,
        bg="#181825",
        fg="#cdd6f4",
        insertbackground="#cdd6f4",
        font=("DejaVu Sans Mono", 9),
    )
    editor.insert("1.0", "# Digite seu codigo aqui usando o Touchscreen ou Teclado Virtual (Y/Select)!\nprint('Ola do Anbernic RG353V!')\n")
    editor.pack(padx=8, pady=4, fill=tk.BOTH, expand=True)

    btn_frame = tk.Frame(root, bg="#1e1e2e")
    btn_frame.pack(fill=tk.X, padx=8, pady=6)

    tk.Button(
        btn_frame,
        text="Teclado Virtual (Select/F12)",
        command=toggle_keyboard,
        bg="#89b4fa",
        fg="#11111b",
        font=("DejaVu Sans", 9, "bold"),
    ).pack(side=tk.LEFT, padx=4)

    tk.Button(
        btn_frame,
        text="Fechar",
        command=root.destroy,
        bg="#f38ba8",
        fg="#11111b",
        font=("DejaVu Sans", 9, "bold"),
    ).pack(side=tk.RIGHT, padx=4)

    root.mainloop()


if __name__ == "__main__":
    main()
