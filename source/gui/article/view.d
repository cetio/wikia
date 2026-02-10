module gui.article.view;

import std.conv : to;
import std.stdio : writeln;
import core.thread : Thread;

import gtk.box;
import gtk.label;
import gtk.button;
import gtk.scrolled_window;
import gtk.overlay;
import gtk.gesture_click;
import gtk.event_controller_motion;
import gtk.types : Orientation, Align, PolicyType;
import gtk.widget : Widget;

import gui.article.infobox;
import gui.conformer.view;
import wikia.pubchem;
import wikia.page : Page, Section, cleanWikitext;
import wikia.psychonaut : DosageResult, getReports, getPagesByTitle;

class Expander : Box
{
private:
    Label header;
    bool expanded;
    bool firstExpandFired;
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

        header = new Label(title);
        header.addCssClass("expander-header");
        header.halign = Align.Fill;
        header.xalign = 0;

        GestureClick click = new GestureClick();
        click.connectReleased((int nPress, double x, double y) {
            expanded = !expanded;
            content.visible = expanded;
            header.label = (expanded ? "▾ " : "▸ ")~_title;
            if (expanded && !firstExpandFired)
            {
                firstExpandFired = true;
                if (onFirstExpand !is null)
                    onFirstExpand();
            }
        });
        header.addController(click);

        auto motion = new EventControllerMotion();
        motion.connectMotion((double x, double y) {
            if (!header.hasCssClass("expander-header-hover"))
                header.addCssClass("expander-header-hover");
        });
        motion.connectLeave(() {
            header.removeCssClass("expander-header-hover");
        });
        header.addController(motion);

        header.label = "▸ "~title;
        append(header);

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
}

class ArticleView : Overlay
{
private:
    ScrolledWindow scroller;
    Box root;
    Box content;
    Box navBar;

    MoleculeView moleculeView;
    Overlay screenOverlay;

    Expander reportsExpander;
    Compound currentCompound;

    // Report view state
    bool inReportView;
    Page[] fetchedReports;
    Page activeReport;
    Box reportView;

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

        root = new Box(Orientation.Horizontal, 0);
        root.addCssClass("article");
        root.hexpand = true;
        root.valign = Align.Start;

        content = new Box(Orientation.Vertical, 0);
        content.addCssClass("article-content");
        content.hexpand = true;
        content.vexpand = true;
        root.append(content);

        moleculeView = new MoleculeView();
        GestureClick viewerClick = new GestureClick();
        viewerClick.connectReleased(&onViewerClicked);
        moleculeView.addController(viewerClick);

        scroller.setChild(root);
        setChild(scroller);

        buildOverlay();
    }

    void fromCompound(Compound compound)
    {
        clearArticle();
        moleculeView.setCompound(compound);

        navBar = new Box(Orientation.Horizontal, 0);
        navBar.addCssClass("article-nav");
        navBar.hexpand = true;
        navBar.halign = Align.Fill;
        navBar.valign = Align.Start;

        Label navTitle = new Label(compound.name);
        navTitle.addCssClass("article-nav-title");
        navTitle.halign = Align.Start;
        navTitle.hexpand = true;
        navTitle.xalign = 0;
        navBar.append(navTitle);

        Button homeBtn = new Button();
        homeBtn.iconName = "go-home-symbolic";
        homeBtn.tooltipText = "Back to home";
        homeBtn.addCssClass("nav-home-button");
        homeBtn.connectClicked(() {
            if (onGoHome !is null) onGoHome();
        });
        homeBtn.halign = Align.End;
        homeBtn.valign = Align.Center;
        navBar.append(homeBtn);
        content.append(navBar);

        currentCompound = compound;
        reportsExpander = new Expander("Reports");
        reportsExpander.onFirstExpand = &onReportsExpand;
        content.append(reportsExpander);

        infobox = new Infobox(moleculeView, compound);
        root.append(infobox);
    }

    void addSection(string title, Widget child)
    {
        auto expander = new Expander(title);
        expander.addContent(child);
        content.append(expander);
    }

    void clearArticle()
    {
        if (inReportView)
            hideReport();

        if (infobox !is null)
        {
            infobox.subject.remove(moleculeView);
            root.remove(infobox);
            infobox = null;
        }

        if (navBar !is null)
        {
            content.remove(navBar);
            navBar = null;
        }

        // Remove any expanders
        Widget child = content.getFirstChild();
        while (child !is null)
        {
            Widget next = child.getNextSibling();
            content.remove(child);
            child = next;
        }

        fetchedReports = null;
        currentCompound = null;
        moleculeView.setCompound(null);
    }

private:
    void onReportsExpand()
    {
        Thread reportThread = new Thread(&fetchReports);
        reportThread.start();
    }

    void fetchReports()
    {
        Label loadingLabel = new Label("Loading reports...");
        loadingLabel.addCssClass("expander-detail");
        loadingLabel.halign = Align.Start;
        reportsExpander.addContent(loadingLabel);

        try
        {
            Page[] pages = getPagesByTitle!"psychonaut"(currentCompound.name);
            Page[] reports;
            if (pages.length > 0)
                reports = getReports(pages[0]);

            populateReports(reports);
        }
        catch (Exception e)
        {
            writeln("[ArticleView] Reports fetch failed: ", e.msg);
            populateReports(null);
        }

        reportsExpander.content.remove(loadingLabel);
    }

    void populateReports(Page[] reports)
    {
        if (reports is null || reports.length == 0)
        {
            Label noResults = new Label("No reports found.");
            noResults.addCssClass("expander-detail");
            noResults.halign = Align.Start;
            reportsExpander.addContent(noResults);
            return;
        }

        fetchedReports = reports;

        foreach (report; reports)
        {
            Box reportRow = new Box(Orientation.Horizontal, 0);
            reportRow.addCssClass("report-row");
            reportRow.hexpand = true;

            Label titleLabel = new Label(report.title);
            titleLabel.addCssClass("report-title");
            titleLabel.tooltipText = report.url;
            titleLabel.halign = Align.Start;
            titleLabel.xalign = 0;
            titleLabel.hexpand = true;
            titleLabel.wrap = true;
            reportRow.append(titleLabel);

            GestureClick rowClick = new GestureClick();
            // Stupid bullshit closure bug so we wrap the delegate in a lambda and call that with the instance variable.
            // It's super confusing but actually it makes sense because we're making a new scope with the lambda.
            rowClick.connectReleased(((r) => (int n, double x, double y) {
                fromReport(r);
            })(report));
            reportRow.addController(rowClick);

            reportsExpander.addContent(reportRow);
        }
    }

    void fromReport(Page report)
    {
        inReportView = true;
        activeReport = report;

        // Swap scroller child to report view
        scroller.setChild(null);

        reportView = new Box(Orientation.Vertical, 0);
        reportView.addCssClass("article");
        reportView.hexpand = true;
        reportView.vexpand = true;

        // Report nav bar
        auto rNavBar = new Box(Orientation.Horizontal, 0);
        rNavBar.addCssClass("article-nav");
        rNavBar.hexpand = true;
        rNavBar.halign = Align.Fill;
        rNavBar.valign = Align.Start;

        Button backBtn = new Button();
        backBtn.iconName = "go-previous-symbolic";
        backBtn.tooltipText = "Back to compound";
        backBtn.addCssClass("nav-home-button");
        backBtn.connectClicked(&hideReport);
        backBtn.halign = Align.Start;
        backBtn.valign = Align.Center;
        rNavBar.append(backBtn);

        Label reportTitle = new Label(report.title);
        reportTitle.addCssClass("article-nav-title");
        reportTitle.halign = Align.Start;
        reportTitle.hexpand = true;
        reportTitle.xalign = 0;
        reportTitle.wrap = true;
        reportTitle.maxWidthChars = 60;
        reportTitle.marginStart = 8;
        rNavBar.append(reportTitle);

        Button homeBtn = new Button();
        homeBtn.iconName = "go-home-symbolic";
        homeBtn.tooltipText = "Back to home";
        homeBtn.addCssClass("nav-home-button");
        homeBtn.connectClicked(() {
            if (onGoHome !is null) onGoHome();
        });
        homeBtn.halign = Align.End;
        homeBtn.valign = Align.Center;
        rNavBar.append(homeBtn);

        reportView.append(rNavBar);

        // Report body container
        auto reportBody = new Box(Orientation.Vertical, 0);
        reportBody.addCssClass("report-body");
        reportBody.hexpand = true;

        auto loadingLabel = new Label("Loading report...");
        loadingLabel.addCssClass("report-body-text");
        loadingLabel.halign = Align.Start;
        reportBody.append(loadingLabel);

        reportView.append(reportBody);
        scroller.setChild(reportView);

        // Fetch and render root in background
        Thread fetchThread = new Thread({
            try
            {
                string raw = report.raw;
                if (raw is null || raw.length == 0)
                {
                    reportBody.remove(loadingLabel);
                    writeln(report.url);
                    auto noContent = new Label("No content available.");
                    noContent.addCssClass("report-body-text");
                    noContent.halign = Align.Start;
                    reportBody.append(noContent);
                    return;
                }

                reportBody.remove(loadingLabel);

                // Preamble
                string preamble = report.preamble;
                if (preamble.length > 0)
                {
                    auto preLabel = new Label(preamble);
                    preLabel.addCssClass("report-body-text");
                    preLabel.halign = Align.Start;
                    preLabel.xalign = 0;
                    preLabel.wrap = true;
                    preLabel.hexpand = true;
                    preLabel.selectable = true;
                    reportBody.append(preLabel);
                }

                // Sections
                Section[] secs = report.sections;
                foreach (sec; secs)
                {
                    auto secHeading = new Label(sec.heading);
                    secHeading.addCssClass("report-section-heading");
                    secHeading.halign = Align.Start;
                    secHeading.xalign = 0;
                    reportBody.append(secHeading);

                    string cleaned = cleanWikitext(sec.content);
                    if (cleaned.length > 0)
                    {
                        auto secContent = new Label(cleaned);
                        secContent.addCssClass("report-body-text");
                        secContent.halign = Align.Start;
                        secContent.xalign = 0;
                        secContent.wrap = true;
                        secContent.hexpand = true;
                        secContent.selectable = true;
                        reportBody.append(secContent);
                    }
                }
            }
            catch (Exception e)
            {
                reportBody.remove(loadingLabel);
                auto errLabel = new Label("Failed to load report.");
                errLabel.addCssClass("report-body-text");
                errLabel.halign = Align.Start;
                reportBody.append(errLabel);
            }
        });
        fetchThread.start();
    }

    void hideReport()
    {
        inReportView = false;
        activeReport = null;

        // Swap back to compound view
        scroller.setChild(root);
        reportView = null;
    }

    void addPropRow(Box parent, string label, string value)
    {
        Box row = new Box(Orientation.Horizontal, 8);
        row.addCssClass("expander-row");
        row.hexpand = true;
        row.halign = Align.Fill;

        Label lbl = new Label(label);
        lbl.addCssClass("expander-row-label");
        lbl.halign = Align.Start;
        lbl.valign = Align.Start;

        Label val = new Label(value);
        val.addCssClass("expander-row-value");
        val.halign = Align.End;
        val.hexpand = true;
        val.wrap = true;
        val.maxWidthChars = 40;
        val.selectable = true;

        row.append(lbl);
        row.append(val);
        parent.append(row);
    }

    void buildOverlay()
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

    void onCloseFullscreen()
    {
        screenOverlay.setChild(null);
        screenOverlay.visible = false;

        if (infobox !is null)
            infobox.setupMView();
    }

    void onViewerClicked()
    {
        if (infobox is null || infobox.compound is null || screenOverlay.getChild() is moleculeView)
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
