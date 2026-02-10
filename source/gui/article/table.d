module gui.article.table;

import gtk.box;
import gtk.label;
import gtk.types : Orientation, Align;
import gtk.widget : Widget;

/// Standalone table widget built from Box containers.
/// Independent of the renderer, accepts pre-built cell widgets.
class Table : Box
{
    this()
    {
        super(Orientation.Vertical, 0);
        addCssClass("article-table");
        hexpand = true;
    }

    /// Set the table caption. If markup is true, text is Pango markup.
    void setCaption(string text, bool markup = false)
    {
        Label caption = new Label(text);
        caption.addCssClass("article-table-caption");
        caption.halign = Align.Start;
        caption.xalign = 0;
        caption.wrap = true;
        if (markup)
            caption.useMarkup = true;
        append(caption);
    }

    void addRow(Widget[] cells, bool isHeader)
    {
        Box row = new Box(Orientation.Horizontal, 0);
        row.addCssClass(isHeader ? "article-table-header-row" : "article-table-row");
        row.hexpand = true;
        row.halign = Align.Fill;
        row.homogeneous = true;

        foreach (cell; cells)
        {
            cell.hexpand = true;
            cell.vexpand = true;
            cell.halign = Align.Fill;
            cell.valign = Align.Fill;
            row.append(cell);
        }

        append(row);
    }
}
