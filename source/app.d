module app;

import std.conv : to;
import std.file : exists, readText;
import std.stdio : writeln;
import std.algorithm;
import std.array;
import core.thread;

import gio.types : ApplicationFlags;
import gtk.application;
import gtk.application_window;
import gtk.header_bar;
import gtk.label;
import gtk.button;
import gtk.box;
import gtk.overlay;
import gtk.stack;
import gtk.css_provider;
import gtk.style_context;
import gtk.style_provider;
import gdk.display;
import gtk.types : Orientation, Align, PolicyType, STYLE_PROVIDER_PRIORITY_APPLICATION, EventControllerScrollFlags;

import wikia.pubchem;
import wikia.psychonaut : DosageResult, getDosage;

import gui.background : Background;
import gui.home : Homepage;
import gui.article : ArticleView, Infobox, MoleculeViewer;

immutable string cssPath = "resources/style.css";

class WikiaWindow : gtk.application_window.ApplicationWindow
{
    private Homepage homepage;
    private ArticleView articleView;
    private Compound lastSearchCompound;
    private Box fullscreenBox;
    private MoleculeViewer fullscreenViewer;
    private Overlay windowOverlay;
    private Stack contentStack;
    private Label titleLabel;

    this(gtk.application.Application app)
    {
        super(app);
        setDefaultSize(1200, 800);
        setTitle("Wikia");

        HeaderBar header = new HeaderBar();
        header.showTitleButtons = true;
        titleLabel = new Label("Wikia");
        header.titleWidget = titleLabel;
        setTitlebar(header);

        windowOverlay = new Overlay();
        windowOverlay.hexpand = true;
        windowOverlay.vexpand = true;

        contentStack = new Stack();
        contentStack.hexpand = true;
        contentStack.vexpand = true;

        homepage = new Homepage();
        homepage.onSearch = &doSearch;
        homepage.onCompoundSelected = &onCompoundSelected;
        contentStack.addNamed(homepage, "homepage");

        articleView = new ArticleView();
        articleView.onGoHome = &showHome;
        articleView.getInfobox().onViewerClick = &onMoleculeViewerClick;
        articleView.getInfobox().setCompound(null);
        contentStack.addNamed(articleView, "article");

        contentStack.visibleChildName = "homepage";

        Box rootBox = new Box(Orientation.Vertical, 0);
        rootBox.addCssClass("root-container");
        rootBox.hexpand = true;
        rootBox.vexpand = true;
        rootBox.append(contentStack);
        windowOverlay.setChild(rootBox);

        buildFullscreenOverlay();
        setChild(windowOverlay);
    }

    private void buildFullscreenOverlay()
    {
        fullscreenBox = new Box(Orientation.Vertical, 0);
        fullscreenBox.addCssClass("fullscreen-bg");
        fullscreenBox.hexpand = true;
        fullscreenBox.vexpand = true;
        fullscreenBox.visible = false;

        fullscreenViewer = new MoleculeViewer();
        fullscreenViewer.hexpand = true;
        fullscreenViewer.vexpand = true;

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

        Overlay viewerOverlay = new Overlay();
        viewerOverlay.setChild(fullscreenViewer);
        viewerOverlay.addOverlay(closeBtn);
        viewerOverlay.hexpand = true;
        viewerOverlay.vexpand = true;

        fullscreenBox.append(viewerOverlay);
        windowOverlay.addOverlay(fullscreenBox);
    }

    private void onCloseFullscreen()
    {
        fullscreenBox.visible = false;
    }

    private void onMoleculeViewerClick()
    {
        if (lastSearchCompound !is null 
            && lastSearchCompound.conformer3D !is null 
            && lastSearchCompound.conformer3D.isValid())
        {
            fullscreenViewer.setConformer(lastSearchCompound.conformer3D);
            fullscreenViewer.setBackgroundName(lastSearchCompound.name);
            fullscreenBox.visible = true;
        }
    }

    private void doSearch(string query)
    {
        writeln("[App] doSearch called with query: ", query);
        lastSearchCompound = getProperties(query);
        
        if (lastSearchCompound is null)
        {
            writeln("[App] No compound found");
            homepage.displayResults(query, lastSearchCompound);
            return;
        }
        
        writeln("[App] Displaying primary result");
        homepage.displayResults(query, lastSearchCompound, null);
        
        // Spawn thread for similarity search
        auto similarSearchThread = new Thread({
            try
            {
                auto similarCompounds = similaritySearch(lastSearchCompound.cid, 85, 10);
                
                // Filter out duplicates and limit results
                Compound[] filtered;
                foreach (compound; similarCompounds)
                {
                    if (compound.cid != lastSearchCompound.cid)
                        filtered ~= compound;
                }
                
                if (filtered.length > 4)
                    filtered = filtered[0..4];
                
                // Small delay to ensure UI is ready
                Thread.sleep(100.msecs);
                
                // Update UI
                writeln("[App] Adding ", filtered.length, " similar compounds");
                homepage.addSimilarResults(filtered);
            }
            catch (Exception e)
            {
                writeln("[App] Similarity search failed: ", e.msg);
            }
        });
        similarSearchThread.start();
    }

    private void onCompoundSelected(int index, Compound compound)
    {
        writeln("[App] onCompoundSelected called with index: ", index, ", CID: ", compound.cid);
        if (compound is null)
        {
            writeln("[App] No compound selected");
            return;
        }

        lastSearchCompound = compound;
        Conformer3D conformer;
        try
            conformer = getConformer3D!"cid"(compound.cid)[0];
        catch (Exception e)
            writeln("[App] Failed to get conformer: ", e.msg);
        
        updateArticleView(compound, conformer, compound.name);
        showArticle();
        articleView.getInfobox().showLoading();

        auto dosageThread = new Thread({
            try
            {
                writeln("[App] Fetching dosage for CID ", compound.cid);
                auto result = getDosage(compound);
                writeln("[App] Dosage result: ", result.dosages.length,
                    " routes, source=", result.source ? result.source.name : "primary");
                articleView.getInfobox().setDosage(result);
            }
            catch (Exception e)
                writeln("[App] Dosage fetch failed: ", e.msg);
        });
        dosageThread.start();

        writeln("[App] onCompoundSelected completed");
    }

    private void updateArticleView(Compound compound, Conformer3D conformer, string name)
    {
        writeln("[App] updateArticleView called");
        articleView.getInfobox().setCompound(compound);
        articleView.getInfobox().setConformer(conformer);
        articleView.getInfobox().update(compound, conformer, name);
        writeln("[App] updateArticleView completed");
    }

    private void showArticle()
    {
        contentStack.visibleChildName = "article";
    }

    private void showHome()
    {
        titleLabel.label = "Wikia";
        contentStack.visibleChildName = "homepage";
        lastSearchCompound = null;
        articleView.getInfobox().setConformer(null);
        articleView.getInfobox().setCompound(null);
        articleView.getInfobox().reset();
        homepage.clearResults();
    }

}

class WikiaApp : gtk.application.Application
{
    private CssProvider cssProvider;

    this()
    {
        super("org.wikia.pubchem", ApplicationFlags.DefaultFlags);
        connectActivate(&onActivate);
    }

    private void applyCss()
    {
        cssProvider = new CssProvider();
        if (cssPath.exists)
        {
            string css = cssPath.readText;
            cssProvider.loadFromString(css);
        }
        else
            writeln("Warning: CSS file not found at "~cssPath);

        Display display = Display.getDefault();
        StyleContext.addProviderForDisplay(display, cssProvider, STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    private void onActivate()
    {
        applyCss();
        WikiaWindow window = new WikiaWindow(this);
        window.present();
    }
}

void main(string[] args)
{
    WikiaApp app = new WikiaApp();
    app.run(args);
}
