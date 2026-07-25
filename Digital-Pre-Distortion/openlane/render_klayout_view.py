import pya

gds_path = pya.Application.instance().get_config("gds_path")
png_path = pya.Application.instance().get_config("png_path")

mw = pya.MainWindow.instance()
mw.load_layout(gds_path, 1)
view = mw.current_view()
view.max_hier()
view.zoom_fit()
view.save_image(png_path, 2400, 3000)
mw.close_all()
