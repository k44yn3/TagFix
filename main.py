import sys
import os
from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QIcon, QFont, QFontDatabase
from tagqt.ui.main import MainWindow
from tagqt.ui.theme import Theme


def get_asset(relative_path: str) -> str:
    """
    Resolve asset paths for both PyInstaller binaries and source runs.
    PyInstaller extracts assets to sys._MEIPASS at runtime.
    """
    if hasattr(sys, '_MEIPASS'):
        base = sys._MEIPASS
    else:
        base = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(base, relative_path)


def main():
    QApplication.setDesktopFileName("io.github.near-link.tagqt")
    app = QApplication(sys.argv)

    # Load bundled JetBrains Mono font
    font_dir = get_asset(os.path.join("assets", "fonts"))
    for font_file in ("JetBrainsMono-Regular.ttf", "JetBrainsMono-Bold.ttf"):
        font_path = os.path.join(font_dir, font_file)
        if os.path.exists(font_path):
            QFontDatabase.addApplicationFont(font_path)

    app.setFont(QFont("JetBrains Mono", 10))
    app.setStyleSheet(Theme.current_stylesheet())

    # Set application icon — load all sizes, Qt picks the best one
    icon = QIcon()
    for size in [16, 32, 48, 64, 128, 256, 512]:
        p = get_asset(f'assets/icons/logo_{size}.png')
        if os.path.exists(p):
            icon.addFile(p)

    app.setWindowIcon(icon)

    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
