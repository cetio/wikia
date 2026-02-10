module gui.loading;

import gtk.box;
import gtk.label;
import gtk.types : Orientation, Align;

Box makeLoadingDots()
{
    Box dots = new Box(Orientation.Horizontal, 1);
    dots.addCssClass("loading-dots");
    dots.halign = Align.Start;

    Label d1 = new Label(".");
    d1.addCssClass("dot");
    Label d2 = new Label(".");
    d2.addCssClass("dot");
    Label d3 = new Label(".");
    d3.addCssClass("dot");

    dots.append(d1);
    dots.append(d2);
    dots.append(d3);

    return dots;
}
