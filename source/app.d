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

import gui.background;
import gui.home;
import gui.article;
import gui.conformer.view;

immutable string cssPath = "resources/style.css";

class WikiaWindow : gtk.application_window.ApplicationWindow
{
private:
    Stack stack;
    Homepage homepage;
    ArticleView article;

    Compound lastSearchCompound;
    Overlay windowOverlay;
    Label titleLabel;

public:
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

        stack = new Stack();
        stack.hexpand = true;
        stack.vexpand = true;

        homepage = new Homepage();
        homepage.onSearch = &doSearch;
        homepage.onCompoundSelected = &onCompoundSelected;
        stack.addNamed(homepage, "homepage");

        article = new ArticleView();
        article.onGoHome = &showHome;
        stack.addNamed(article, "article");

        stack.visibleChildName = "homepage";

        Box root = new Box(Orientation.Vertical, 0);
        root.addCssClass("root-container");
        root.hexpand = true;
        root.vexpand = true;
        root.append(stack);
        windowOverlay.setChild(root);

        setChild(windowOverlay);
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
        
        writeln("[App] Displaying primary dosage");
        homepage.displayResults(query, lastSearchCompound, null);
        
        // Spawn thread for similarity search
        Thread similarSearchThread = new Thread({
            try
            {
                Compound[] similarCompounds = similaritySearch(lastSearchCompound.cid, 85, 10);
                
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
                writeln("[App] Similarity search failed: ", e.msg);
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
        article.infobox.update(compound);
        article.infobox.showLoading();
        showArticle();

        Thread dosageThread = new Thread({
            try
            {
                writeln("[App] Fetching dosage for CID ", compound.cid);
                DosageResult dosage = getDosage(compound);
                writeln("[App] Dosage dosage: ", dosage.dosages.length,
                    " routes, source=", dosage.source ? dosage.source.name : "primary");
                article.infobox.setDosage(dosage);
            }
            catch (Exception e)
                writeln("[App] Dosage fetch failed: ", e.msg);
        });
        dosageThread.start();

        writeln("[App] onCompoundSelected completed");
    }

    private void showArticle()
    {
        stack.visibleChildName = "article";
    }

    private void showHome()
    {
        titleLabel.label = "Wikia";
        stack.visibleChildName = "homepage";
        lastSearchCompound = null;
        article.infobox.reset();
        homepage.clearResults();
    }

}

class WikiaApp : gtk.application.Application
{
private:
    CssProvider cssProvider;


    void applyCss()
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

    void onActivate()
    {
        applyCss();
        WikiaWindow window = new WikiaWindow(this);
        window.present();
    }

public:
    this()
    {
        super("org.wikia.pubchem", ApplicationFlags.DefaultFlags);
        connectActivate(&onActivate);
    }
}

void main(string[] args)
{
    WikiaApp app = new WikiaApp();
    app.run(args);
}
