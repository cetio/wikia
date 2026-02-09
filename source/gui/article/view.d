module gui.article.view;

import std.stdio : writeln;
import gtk.box;
import gtk.label;
import gtk.button;
import gtk.scrolled_window;
import gtk.overlay;
import gtk.gesture_click;
import gtk.types : Orientation, Align, PolicyType;

import gui.article.infobox;
import gui.conformer.view;
import wikia.pubchem;
import wikia.psychonaut : DosageResult;

class ArticleView : Overlay
{
private:
    ScrolledWindow scroller;
    Box content;
    Box textColumn;
    Label placeholderLabel;
    
    MoleculeView moleculeView;
    Overlay screenOverlay;

public:
    Infobox infobox;
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

        content = new Box(Orientation.Horizontal, 0);
        content.addCssClass("article-content");
        content.hexpand = true;
        content.valign = Align.Start;

        textColumn = new Box(Orientation.Vertical, 0);
        textColumn.hexpand = true;
        textColumn.valign = Align.Start;

        placeholderLabel = new Label("Select a compound to view details");
        placeholderLabel.addCssClass("article-placeholder");
        placeholderLabel.halign = Align.Start;
        placeholderLabel.valign = Align.Start;
        textColumn.append(placeholderLabel);

        content.append(textColumn);

        GestureClick viewerClick = new GestureClick();
        viewerClick.connectReleased(&onViewerClicked);

        moleculeView = new MoleculeView();
        moleculeView.addController(viewerClick);

        infobox = new Infobox(moleculeView);
        content.append(infobox);

        scroller.setChild(content);
        setChild(scroller);

        // TODO: Nav pane.
        Button homeBtn = new Button();
        homeBtn.iconName = "go-home-symbolic";
        homeBtn.tooltipText = "Back to home";
        homeBtn.addCssClass("home-button");
        homeBtn.connectClicked(() {
            if (onGoHome !is null) onGoHome();
        });
        homeBtn.widthRequest = 48;
        homeBtn.heightRequest = 48;
        homeBtn.halign = Align.End;
        homeBtn.valign = Align.End;
        homeBtn.marginEnd = 24;
        homeBtn.marginBottom = 24;

        addOverlay(homeBtn);
        buildOverlay();
    }

    private void buildOverlay()
    {
        screenOverlay = new Overlay();
        screenOverlay.hexpand = true;
        screenOverlay.vexpand = true;
        screenOverlay.visible = false;

        Button closeBtn = new Button();
        closeBtn.iconName = "window-close-symbolic";
        closeBtn.tooltipText = "Close";
        closeBtn.addCssClass("fullscreen-close");
        closeBtn.connectClicked(&onCloseFullscreen);
        closeBtn.widthRequest = 40;
        closeBtn.heightRequest = 40;
        closeBtn.halign = Align.End;
        closeBtn.valign = Align.Start;
        closeBtn.marginTop = 12;
        closeBtn.marginEnd = 12;

        screenOverlay.addOverlay(closeBtn);
        addOverlay(screenOverlay);
    }

    private void onCloseFullscreen()
    {
        screenOverlay.setChild(null);
        screenOverlay.visible = false;

        infobox.setupMView();
    }

    void onViewerClicked()
    {
        if (infobox.compound is null || screenOverlay.getChild() is moleculeView)
            return;

        infobox.subject.remove(moleculeView);
        moleculeView.hexpand = true;
        moleculeView.vexpand = true;
        moleculeView.setBaseZoom(40.0);
        moleculeView.enableMotionControl();
        
        screenOverlay.setChild(moleculeView);
        screenOverlay.visible = true;
    }
}
