from PySide6.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QFormLayout, QLineEdit, 
    QPushButton, QLabel, QTreeWidget, QTreeWidgetItem, QHeaderView, 
    QDialogButtonBox, QWidget
)
from PySide6.QtCore import Qt, QThread, Signal, QObject
from PySide6.QtGui import QPixmap
from tagqt.ui.theme import Theme
from tagqt.ui import dialogs
import requests


class ImageLoaderWorker(QObject):
    finished = Signal(bytes)
    
    def __init__(self, url):
        super().__init__()
        self.url = url
    
    def run(self):
        try:
            response = requests.get(self.url, timeout=10)
            response.raise_for_status()
            self.finished.emit(response.content)
        except Exception:
            self.finished.emit(b"")


class SearchWorker(QObject):
    finished = Signal(list)
    error = Signal(str)
    
    def __init__(self, callback, args):
        super().__init__()
        self.callback = callback
        self.args = args
    
    def run(self):
        try:
            results = self.callback(*self.args)
            self.finished.emit(results or [])
        except Exception as e:
            self.error.emit(str(e))

class UnifiedSearchDialog(QDialog):
    def __init__(self, parent=None, mode="lyrics", initial_artist="", initial_title="", initial_album="", fetcher_callback=None):
        super().__init__(parent)
        from PySide6.QtWidgets import QApplication
        self.setWindowIcon(QApplication.instance().windowIcon())
        self.setWindowTitle(f"Get {mode.capitalize()}{'s' if mode == 'cover' else ''}")
        self.resize(900 if mode == "cover" else 800, 600)
        self.setStyleSheet(Theme.current_stylesheet())
        
        self.mode = mode
        self.fetcher_callback = fetcher_callback
        self.selected_result = None
        self._loader_thread = None
        self._search_thread = None
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(15)
        

        input_group = QWidget()
        input_layout = QFormLayout(input_group)
        input_layout.setContentsMargins(0, 0, 0, 0)
        
        self.artist_edit = QLineEdit(initial_artist)
        self.album_edit = QLineEdit(initial_album)
        self.title_edit = QLineEdit(initial_title)
        
        input_layout.addRow("Artist:", self.artist_edit)
        if mode == "lyrics":
            input_layout.addRow("Title:", self.title_edit)
        input_layout.addRow("Album:", self.album_edit)
        
        layout.addWidget(input_group)
        
        # Search Button
        self.search_btn = QPushButton("Search")
        self.search_btn.setProperty("class", "primary")
        self.search_btn.setCursor(Qt.PointingHandCursor)
        self.search_btn.clicked.connect(self.perform_search)
        layout.addWidget(self.search_btn)
        

        if mode == "cover":
            results_layout = QHBoxLayout()
            results_layout.setSpacing(20)
            
            # Tree on left
            self.tree = QTreeWidget()
            self.tree.setHeaderLabels(["Album", "Artist", "Source", "Size"])
            self.tree.header().setSectionResizeMode(QHeaderView.ResizeToContents)
            self.tree.header().setSectionResizeMode(0, QHeaderView.Stretch)
            self.tree.setRootIsDecorated(False)
            self.tree.itemDoubleClicked.connect(self.accept_selection)
            results_layout.addWidget(self.tree, stretch=2)
            
            # Preview on right
            preview_container = QVBoxLayout()
            preview_container.setSpacing(10)
            
            preview_label = QLabel("Preview")
            preview_label.setStyleSheet(f"color: {Theme.SUBTEXT0}; font-weight: bold;")
            preview_container.addWidget(preview_label)
            
            self.preview_image = QLabel()
            self.preview_image.setFixedSize(200, 200)
            self.preview_image.setAlignment(Qt.AlignCenter)
            self.preview_image.setStyleSheet(f"""
                QLabel {{
                    background-color: {Theme.SURFACE0};
                    border: 1px solid {Theme.SURFACE1};
                    border-radius: {Theme.CORNER_RADIUS};
                }}
            """)
            self.preview_image.setText("Pick a cover to preview it")
            preview_container.addWidget(self.preview_image)
            preview_container.addStretch()
            
            results_layout.addLayout(preview_container)
            layout.addLayout(results_layout)
        else:
            self.tree = QTreeWidget()
            self.tree.setHeaderLabels(["Title", "Artist", "Album", "Duration", "Type"])
            self.tree.header().setSectionResizeMode(QHeaderView.ResizeToContents)
            self.tree.header().setSectionResizeMode(0, QHeaderView.Stretch)
            self.tree.setRootIsDecorated(False)
            self.tree.itemDoubleClicked.connect(self.accept_selection)
            layout.addWidget(self.tree)
        

        buttons = QDialogButtonBox(QDialogButtonBox.Cancel)
        buttons.rejected.connect(self.reject)
        
        self.select_btn = QPushButton("Select")
        self.select_btn.setProperty("class", "primary")
        self.select_btn.setCursor(Qt.PointingHandCursor)
        self.select_btn.clicked.connect(self.accept_selection)
        self.select_btn.setEnabled(False)
        
        buttons.addButton(self.select_btn, QDialogButtonBox.AcceptRole)
        layout.addWidget(buttons)
        
        self.tree.itemSelectionChanged.connect(self.on_selection_changed)

    def perform_search(self):
        artist = self.artist_edit.text()
        title = self.title_edit.text()
        album = self.album_edit.text()
        
        if not artist:
            dialogs.show_warning(self, "Missing Info", "An artist name is needed to search.")
            return
            
        if self.mode == "lyrics" and not title:
            dialogs.show_warning(self, "Missing Info", "A song title is needed to find lyrics.")
            return
             
        self.tree.clear()
        self.select_btn.setEnabled(False)
        if self.mode == "cover":
            self.preview_image.clear()
            self.preview_image.setText("Pick a cover to preview it")
        
        self.search_btn.setText("Searching...")
        self.search_btn.setEnabled(False)
        
        # Clean up previous search thread
        if self._search_thread and self._search_thread.isRunning():
            self._search_thread.quit()
            self._search_thread.wait(2000)
        
        if self.mode == "lyrics":
            args = (artist, title, album)
        else:
            args = (artist, album)
        
        self._search_thread = QThread()
        self._search_worker = SearchWorker(self.fetcher_callback, args)
        self._search_worker.moveToThread(self._search_thread)
        self._search_thread.started.connect(self._search_worker.run)
        self._search_worker.finished.connect(self._on_search_done)
        self._search_worker.error.connect(self._on_search_error)
        self._search_worker.finished.connect(self._search_thread.quit)
        self._search_worker.finished.connect(self._search_worker.deleteLater)
        self._search_worker.error.connect(self._search_thread.quit)
        self._search_worker.error.connect(self._search_worker.deleteLater)
        self._search_thread.finished.connect(self._search_thread.deleteLater)
        self._search_thread.finished.connect(self._on_search_thread_done)
        self._search_thread.start()

    def _on_search_done(self, results):
        self.search_btn.setText("Search")
        self.search_btn.setEnabled(True)
        if not results:
            dialogs.show_info(self, "No Results", "No matches found.")
        else:
            self.populate_results(results)

    def _on_search_error(self, error_msg):
        self.search_btn.setText("Search")
        self.search_btn.setEnabled(True)
        dialogs.show_error(self, "Search Failed", f"Couldn't get results. {error_msg}")

    def _on_search_thread_done(self):
        self._search_thread = None
        self._search_worker = None

    def populate_results(self, results):
        for res in results:
            if self.mode == "lyrics":
                duration_str = self.format_duration(res.get("duration", 0))
                synced = res.get("syncedLyrics") or ""
                if res.get("isSynced") and "<" in synced:
                    type_str = "Word Synced"
                elif res.get("isSynced"):
                    type_str = "Synced"
                else:
                    type_str = "Plain"
                
                item = QTreeWidgetItem([
                    res.get("trackName", ""),
                    res.get("artistName", ""),
                    res.get("albumName", ""),
                    duration_str,
                    type_str
                ])
            else:
                item = QTreeWidgetItem([
                    res.get("album", ""),
                    res.get("artist", ""),
                    res.get("source", ""),
                    res.get("size", "")
                ])
            
            item.setData(0, Qt.UserRole, res)
            self.tree.addTopLevelItem(item)

    def format_duration(self, seconds):
        if not seconds: return ""
        m, s = divmod(int(seconds), 60)
        return f"{m:02d}:{s:02d}"

    def on_selection_changed(self):
        has_selection = len(self.tree.selectedItems()) > 0
        self.select_btn.setEnabled(has_selection)
        
        if self.mode == "cover" and has_selection:
            item = self.tree.currentItem()
            if item:
                res = item.data(0, Qt.UserRole)
                url = res.get("url", "")
                if url:
                    self.load_preview(url)

    def load_preview(self, url):
        """Load a cover art preview image in a background thread."""
        self.preview_image.setText("Loading…")
        
        # Clean up any existing loader thread
        self._cleanup_loader()
        
        self._loader_thread = QThread()
        self._loader_worker = ImageLoaderWorker(url)
        self._loader_worker.moveToThread(self._loader_thread)
        self._loader_thread.started.connect(self._loader_worker.run)
        self._loader_worker.finished.connect(self.on_preview_loaded)
        self._loader_worker.finished.connect(self._loader_thread.quit)
        self._loader_worker.finished.connect(self._loader_worker.deleteLater)
        self._loader_thread.finished.connect(self._loader_thread.deleteLater)
        self._loader_thread.finished.connect(self._on_loader_finished)
        self._loader_thread.start()

    def _on_loader_finished(self):
        """Clear references after loader thread finishes."""
        self._loader_thread = None
        self._loader_worker = None

    def _cleanup_loader(self):
        """Safely stop and clean up the preview loader thread."""
        if self._loader_thread and self._loader_thread.isRunning():
            self._loader_thread.quit()
            self._loader_thread.wait(2000)

    def on_preview_loaded(self, data):
        if data:
            pixmap = QPixmap()
            pixmap.loadFromData(data)
            if not pixmap.isNull():
                self.preview_image.setPixmap(pixmap.scaled(200, 200, Qt.KeepAspectRatio, Qt.SmoothTransformation))
                return
        self.preview_image.setText("Couldn't load preview")

    def accept_selection(self):
        item = self.tree.currentItem()
        if item:
            self.selected_result = item.data(0, Qt.UserRole)
            self.accept()

    def closeEvent(self, event):
        """Clean up threads on dialog close."""
        self._cleanup_loader()
        if self._search_thread and self._search_thread.isRunning():
            self._search_thread.quit()
            self._search_thread.wait(2000)
        event.accept()
        super().closeEvent(event)
