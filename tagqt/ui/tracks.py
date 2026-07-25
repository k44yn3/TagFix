from PySide6.QtWidgets import QTreeWidget, QAbstractItemView, QTreeWidgetItem, QHeaderView, QTreeWidgetItemIterator, QMenu, QStyledItemDelegate
from PySide6.QtCore import Qt, Signal, QRect
from PySide6.QtGui import QAction, QPainter, QColor, QBrush
import os
from tagqt.core.tags import MetadataHandler
from tagqt.ui.theme import Theme

MISSING_ROLE = Qt.UserRole + 1
TEXT_OFFSET = 20  # px offset for filename text to make room for dot


class MissingFieldDelegate(QStyledItemDelegate):
    """Draws a colored dot for rows missing critical metadata fields."""

    DOT_SIZE = 7
    DOT_LEFT = 6

    def paint(self, painter, option, index):
        # Draw everything as normal but shifted right
        adjusted = option.rect.adjusted(TEXT_OFFSET, 0, 0, 0)
        from PySide6.QtWidgets import QStyleOptionViewItem
        new_option = QStyleOptionViewItem(option)
        new_option.rect = adjusted
        super().paint(painter, new_option, index)

        missing = index.data(MISSING_ROLE)
        if missing and missing > 0:
            color = QColor(Theme.RED) if missing >= 2 else QColor(Theme.YELLOW)
            painter.save()
            painter.setRenderHint(QPainter.Antialiasing)
            painter.setBrush(QBrush(color))
            painter.setPen(Qt.NoPen)
            y = option.rect.y() + (option.rect.height() - self.DOT_SIZE) // 2
            painter.drawEllipse(QRect(option.rect.x() + self.DOT_LEFT, y, self.DOT_SIZE, self.DOT_SIZE))
            painter.restore()

    def sizeHint(self, option, index):
        hint = super().sizeHint(option, index)
        hint.setWidth(hint.width() + TEXT_OFFSET)
        return hint
import logging

logger = logging.getLogger(__name__)

class FileList(QTreeWidget):
    files_dropped = Signal(list)

    def __init__(self):
        super().__init__()
        self.setAcceptDrops(True)
        self.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.setDragDropMode(QAbstractItemView.DropOnly)
        self.setAlternatingRowColors(True)
        self.setRootIsDecorated(False)
        
        self.column_names = ["Filename", "Title", "Artist", "Album", "Album Artist", "Year", "Genre", "Disc", "Track"]
        self.setHeaderLabels(self.column_names)
        
        header = self.header()
        header.setStretchLastSection(False)
        header.setContextMenuPolicy(Qt.CustomContextMenu)
        header.customContextMenuRequested.connect(self.show_header_menu)
        
        # Set resize modes
        for i in range(len(self.column_names)):
            header.setSectionResizeMode(i, QHeaderView.Interactive)
            header.setMinimumSectionSize(80)
        
        header.setSectionResizeMode(1, QHeaderView.Stretch) # Title stretches
        header.resizeSection(0, 200) # Filename default width

        self.all_files = []
        self.path_to_item = {} # filepath -> QTreeWidgetItem
        self.current_mode = "File"

        self._missing_delegate = MissingFieldDelegate(self)
        self.setItemDelegateForColumn(0, self._missing_delegate)

    def show_header_menu(self, pos):
        menu = QMenu(self)
        for i, name in enumerate(self.column_names):
            if i == 0:
                continue
            action = QAction(name, self)
            action.setCheckable(True)
            action.setChecked(not self.isColumnHidden(i))
            action.triggered.connect(lambda checked, col=i: self.setColumnHidden(col, not checked))
            menu.addAction(action)
        menu.exec_(self.header().mapToGlobal(pos))

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dragMoveEvent(self, event):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event):
        files = []
        for url in event.mimeData().urls():
            path = url.toLocalFile()
            if os.path.isfile(path):
                if path.lower().endswith(('.mp3', '.flac', '.ogg', '.m4a', '.wav')):
                    files.append(path)
        
        if files:
            self.files_dropped.emit(files)
            event.acceptProposedAction()
        else:
            event.ignore()

    def add_file(self, path):
        try:
            meta = MetadataHandler(path)
            self.all_files.append((path, meta))
            self.refresh_view()
        except Exception as e:
            logger.warning("Error adding file %s: %s", path, e)

    def add_files(self, data):
        """Accepts either a list of paths or a list of (path, metadata) tuples/lists."""
        for item in data:
            try:
                if isinstance(item, (list, tuple)) and len(item) == 2:
                    path, meta = item
                else:
                    path = item
                    meta = MetadataHandler(path)
                self.all_files.append((path, meta))
            except Exception as e:
                logger.warning("Error adding file: %s", e)
        self.refresh_view()

    def clear_files(self):
        self.all_files = []
        self.path_to_item = {}
        self.clear()

    def set_display_mode(self, mode):
        self.current_mode = mode
        self.refresh_view()

    def set_filter(self, text):
        text = text.lower().strip()
        iterator = QTreeWidgetItemIterator(self)
        while iterator.value():
            item = iterator.value()
            if item.data(0, Qt.UserRole):  # Only filter actual file items
                filename = item.text(0).lower()
                title = item.text(1).lower()
                artist = item.text(2).lower()
                album = item.text(3).lower()
                match = (not text or 
                         text in filename or 
                         text in title or 
                         text in artist or 
                         text in album)
                item.setHidden(not match)
            iterator += 1

    def _update_item_columns(self, item, path, meta):
        """Updates the text of a QTreeWidgetItem in-place."""
        item.setText(0, os.path.basename(path))
        item.setText(1, meta.title or "")
        item.setText(2, meta.artist or "")
        item.setText(3, meta.album or "")
        item.setText(4, meta.album_artist or "")
        item.setText(5, meta.year or "")
        item.setText(6, meta.genre or "")
        item.setText(7, meta.disc_number or "")
        item.setText(8, meta.track_number or "")
        item.setData(0, Qt.UserRole, path)
        item.setData(0, MISSING_ROLE, self._calc_missing(meta))
        
        item.setTextAlignment(5, Qt.AlignCenter)  # Year
        item.setTextAlignment(7, Qt.AlignCenter)  # Disc
        item.setTextAlignment(8, Qt.AlignCenter)  # Track

    def refresh_view(self):
        """Rebuild the tree view from internal data using current display mode."""
        self.setUpdatesEnabled(False)
        try:
            self._do_refresh_view()
        finally:
            self.setUpdatesEnabled(True)

    def _do_refresh_view(self):
        """Internal refresh without update guard."""
        self.clear()
        self.path_to_item = {}
        
        if self.current_mode == "File":
            self.headerItem().setText(0, "Filename")
            self.setRootIsDecorated(False)
            for path, meta in self.all_files:
                item = QTreeWidgetItem()
                self._update_item_columns(item, path, meta)
                self.addTopLevelItem(item)
                self.path_to_item[path] = item
                
        elif self.current_mode in ["Album", "Artist", "Album Artist"]:
            self.headerItem().setText(0, self.current_mode)
            self.setRootIsDecorated(True)
            groups = {}
            
            for path, meta in self.all_files:
                key = "Unknown"
                if self.current_mode == "Album":
                    key = meta.album or "Unknown Album"
                elif self.current_mode == "Artist":
                    key = meta.artist or "Unknown Artist"
                elif self.current_mode == "Album Artist":
                    key = meta.album_artist or meta.artist or "Unknown Artist"
                
                if key not in groups:
                    groups[key] = []
                groups[key].append((path, meta))
            
            for key in sorted(groups.keys()):
                group_item = QTreeWidgetItem([key])
                group_item.setExpanded(True)
                self.addTopLevelItem(group_item)
                
                for path, meta in groups[key]:
                    item = QTreeWidgetItem()
                    self._update_item_columns(item, path, meta)
                    group_item.addChild(item)
                    self.path_to_item[path] = item

    def update_file(self, path):
        # Update internal data
        for i, (fpath, meta) in enumerate(self.all_files):
            if fpath == path:
                try:
                    new_meta = MetadataHandler(path)
                    self.all_files[i] = (path, new_meta)
                    
                    # Update UI in-place if possible
                    if path in self.path_to_item:
                        item = self.path_to_item[path]
                        self._update_item_columns(item, path, new_meta)
                        
                        # If in grouped mode, we might need a full refresh if the grouping key changed
                        # but for simple tag updates, in-place is fine for now.
                        # MainWindow will trigger a full refresh if needed.
                    else:
                        self.refresh_view()
                except Exception as e:
                    logger.warning("Error updating file %s: %s", path, e)
                break

    @staticmethod
    def _calc_missing(meta):
        """Return count of missing critical fields (title, artist, album)."""
        count = 0
        if not meta.title:
            count += 1
        if not meta.artist:
            count += 1
        if not meta.album:
            count += 1
        return count

    def update_missing_indicators(self):
        """Recalculate missing-field dots for all visible rows."""
        for path, meta in self.all_files:
            item = self.path_to_item.get(path)
            if item:
                item.setData(0, MISSING_ROLE, self._calc_missing(meta))
        self.viewport().update()

    def rename_file(self, old_path, new_path):
        # Update internal data
        for i, (fpath, meta) in enumerate(self.all_files):
            if fpath == old_path:
                try:
                    new_meta = MetadataHandler(new_path)
                    self.all_files[i] = (new_path, new_meta)
                    
                    # Update UI in-place
                    if old_path in self.path_to_item:
                        item = self.path_to_item[old_path]
                        del self.path_to_item[old_path]
                        self._update_item_columns(item, new_path, new_meta)
                        self.path_to_item[new_path] = item
                    else:
                        self.refresh_view()
                except Exception as e:
                    logger.warning("Error loading renamed file %s: %s", new_path, e)
                break

    def remove_files(self, paths):
        """Remove files from internal data and UI without full refresh."""
        path_set = set(paths)
        self.all_files = [(p, m) for p, m in self.all_files if p not in path_set]
        for path in paths:
            item = self.path_to_item.pop(path, None)
            if item:
                parent = item.parent()
                if parent:
                    parent.removeChild(item)
                else:
                    idx = self.indexOfTopLevelItem(item)
                    if idx >= 0:
                        self.takeTopLevelItem(idx)
