app_path = defines["app_path"]
app_name = defines["app_name"]
icon_path = defines["icon_path"]
background_path = defines["background_path"]

volume_name = app_name
format = "UDZO"
files = [app_path]
symlinks = {"Applications": "/Applications"}
hide_extensions = [f"{app_name}.app"]
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_tab_view = False
include_icon_view_settings = True
arrange_by = None
icon_size = 128
text_size = 14
label_pos = "bottom"
window_rect = ((120, 620), (640, 360))
background = background_path
icon = icon_path
icon_locations = {
    f"{app_name}.app": (170, 170),
    "Applications": (470, 170),
}
