from pathlib import Path

application = Path(defines["app"])

format = "UDZO"
files = [str(application)]
symlinks = {"Applications": "/Applications"}
icon = str(application / "Contents/Resources/AppIcon.icns")
background = "Resources/DMG/background.tiff"
window_rect = ((160, 160), (640, 400))
default_view = "icon-view"
icon_locations = {application.name: (170, 195), "Applications": (470, 195)}
icon_size = 96
text_size = 14
grid_spacing = 80
