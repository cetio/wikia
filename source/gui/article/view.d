module gui.article.view;

import gtk.box;
import gtk.label;
import gtk.button;
import gtk.scrolled_window;
import gtk.overlay;
import gtk.types : Orientation, Align, PolicyType;

import gui.article.infobox : Infobox;

class ArticleView : Overlay
{
    private Infobox infobox;
    private ScrolledWindow scroller;
    private Box articleBox;
    private Box textColumn;
    private Label placeholderLabel;

    void delegate() onGoHome;

    this()
    {
        super();
        hexpand = true;
        vexpand = true;

        scroller = new ScrolledWindow();
        scroller.addCssClass("article-scroll");
        scroller.hexpand = true;
        scroller.vexpand = true;
        scroller.setPolicy(PolicyType.Never, PolicyType.Automatic);

        articleBox = new Box(Orientation.Horizontal, 0);
        articleBox.addCssClass("article-body");
        articleBox.hexpand = true;
        articleBox.valign = Align.Start;

        textColumn = new Box(Orientation.Vertical, 0);
        textColumn.hexpand = true;
        textColumn.valign = Align.Start;

        placeholderLabel = new Label("Select a compound to view details");
        placeholderLabel.addCssClass("article-placeholder");
        placeholderLabel.halign = Align.Start;
        placeholderLabel.valign = Align.Start;
        textColumn.append(placeholderLabel);

        articleBox.append(textColumn);

        infobox = new Infobox();
        articleBox.append(infobox);

        scroller.setChild(articleBox);
        setChild(scroller);

        Button homeBtn = new Button();
        homeBtn.iconName = "go-home-symbolic";
        homeBtn.tooltipText = "Back to home";
        homeBtn.addCssClass("home-button");
        homeBtn.connectClicked(&onHomeClicked);
        homeBtn.widthRequest = 48;
        homeBtn.heightRequest = 48;
        homeBtn.halign = Align.End;
        homeBtn.valign = Align.End;
        homeBtn.marginEnd = 24;
        homeBtn.marginBottom = 24;

        addOverlay(homeBtn);
    }

    @property Infobox getInfobox()
    {
        return infobox;
    }

    void setPlaceholder(string text)
    {
        placeholderLabel.label = text;
    }

    private void onHomeClicked()
    {
        if (onGoHome !is null)
            onGoHome();
    }
}
