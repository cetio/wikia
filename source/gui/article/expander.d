module gui.article.expander;

import std.uni : toUpper;

import gtk.box;
import gtk.label;
import gtk.gesture_click;
import gtk.event_controller_motion;
import gtk.types : Orientation, Align;
import gtk.widget : Widget;

import gui.loading : makeLoadingDots;

class Expander : Box
{
private:
    Label header;
    Box headerBox;
    Box dotsBox;
    bool expanded;
    bool firstExpandFired;
    bool _loading;
    string _title;

public:
    Box content;
    void delegate() onFirstExpand;

    this(string title)
    {
        super(Orientation.Vertical, 0);
        _title = title;
        addCssClass("expander");
        hexpand = true;
        halign = Align.Fill;

        headerBox = new Box(Orientation.Horizontal, 4);
        headerBox.addCssClass("expander-header");
        headerBox.halign = Align.Fill;
        headerBox.hexpand = true;

        header = new Label("▸ "~title.toUpper);
        header.halign = Align.Start;
        header.xalign = 0;
        header.hexpand = true;
        headerBox.append(header);

        GestureClick click = new GestureClick();
        click.connectReleased((int nPress, double x, double y) {
            expanded = !expanded;
            content.visible = expanded;
            header.label = (expanded ? "▾ " : "▸ ")~_title.toUpper;
            if (expanded && !firstExpandFired)
            {
                firstExpandFired = true;
                if (onFirstExpand !is null)
                    onFirstExpand();
            }
        });
        headerBox.addController(click);

        EventControllerMotion motion = new EventControllerMotion();
        motion.connectMotion((double x, double y) {
            if (!headerBox.hasCssClass("expander-header-hover"))
                headerBox.addCssClass("expander-header-hover");
        });
        motion.connectLeave(() {
            headerBox.removeCssClass("expander-header-hover");
        });
        headerBox.addController(motion);

        append(headerBox);

        content = new Box(Orientation.Vertical, 0);
        content.addCssClass("expander-root");
        content.hexpand = true;
        content.visible = false;
        append(content);
    }

    void addContent(Widget child)
    {
        content.append(child);
    }

    void setTitle(string title)
    {
        _title = title;
        header.label = (expanded ? "▾ " : "▸ ")~_title.toUpper;
        if (_loading)
            setLoading(false);
    }

    void setLoading(bool loading)
    {
        _loading = loading;
        if (loading)
        {
            header.visible = false;
            dotsBox = makeLoadingDots();
            headerBox.append(dotsBox);
        }
        else
        {
            header.visible = true;
            if (dotsBox !is null)
            {
                headerBox.remove(dotsBox);
                dotsBox = null;
            }
        }
    }
}