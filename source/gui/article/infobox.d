module gui.article.infobox;

import std.conv : to;
import std.math : isNaN;
import std.stdio : writeln;

import gtk.box;
import gtk.event_controller_motion;
import gtk.gesture_click;
import gtk.label;
import gtk.overlay;
import gtk.types : Align, Orientation;
import gtk.widget : Widget;

import gui.article.viewer;
import gui.background : Background;
import wikia.pubchem;
import wikia.psychonaut : Dosage, DosageResult;

class Infobox : Overlay
{
    private Label compoundNameLabel;
    private Label cidLabel;
    private Label formulaLabel;
    private Label weightLabel;
    private Label massLabel;
    private Label chargeLabel;
    private Label tpsaLabel;
    private Label xlogpLabel;
    private Label smilesLabel;
    private MoleculeViewer moleculeViewer;
    private Compound currentCompound;
    private Box chemicalSection;
    private Box dosageSection;
    private Box loadingDotsBox;
    private Box content;

    void delegate() onViewerClick;

    this()
    {
        super();
        addCssClass("infobox");
        valign = Align.Start;
        halign = Align.End;
        widthRequest = 80;
        hexpand = false;

        content = new Box(Orientation.Vertical, 0);
        content.addCssClass("infobox-content");
        content.widthRequest = 240;

        compoundNameLabel = new Label("Select");
        compoundNameLabel.addCssClass("infobox-title");
        compoundNameLabel.wrap = true;
        compoundNameLabel.maxWidthChars = 10;
        compoundNameLabel.hexpand = true;
        content.append(compoundNameLabel);

        moleculeViewer = new MoleculeViewer(false);
        moleculeViewer.setContentWidth(88);
        moleculeViewer.setContentHeight(88);
        moleculeViewer.setBaseZoom(10.0);
        moleculeViewer.addCssClass("infobox-viewer-frame");

        GestureClick viewerClick = new GestureClick();
        viewerClick.connectReleased(&onViewerClicked);
        moleculeViewer.addController(viewerClick);

        content.append(moleculeViewer);

        chemicalSection = new Box(Orientation.Vertical, 0);
        chemicalSection.hexpand = true;
        chemicalSection.halign = Align.Fill;
        cidLabel = new Label("--");
        formulaLabel = new Label("--");
        smilesLabel = new Label("--");
        weightLabel = new Label("--");
        massLabel = new Label("--");
        chargeLabel = new Label("--");
        tpsaLabel = new Label("--");
        xlogpLabel = new Label("--");
        buildChemicalSection();
        content.append(chemicalSection);

        loadingDotsBox = buildLoadingDots();
        loadingDotsBox.visible = false;
        content.append(loadingDotsBox);

        dosageSection = new Box(Orientation.Vertical, 0);
        dosageSection.hexpand = true;
        dosageSection.halign = Align.Fill;
        dosageSection.visible = false;
        content.append(dosageSection);

        // Background bg = new Background(
        //     6,      // maxSplotches
        //     120,    // msPerFrame
        //     10.0,   // spawnMargin
        //     25.0,   // minRadius
        //     65.0,   // maxRadius
        //     0.55,   // minAlpha
        //     0.85,   // maxAlpha
        //     "infobox-background", // cssClass
        //     true    // paintBase
        // );
        // bg.hexpand = true;
        // bg.vexpand = true;
        // setChild(bg);

        addOverlay(content);
        setMeasureOverlay(content, true);
        setClipOverlay(content, true);
    }

    void update(Compound compound)
    {
        writeln("[Infobox] update called");
        if (compound is null)
        {
            writeln("[Infobox] Compound is null, returning");
            return;
        }

        currentCompound = compound;
        moleculeViewer.setConformer(compound.conformer3D);

        compoundNameLabel.label = compound.name;
        cidLabel.label = compound.cid > 0 ? compound.cid.to!string : "--";
        formulaLabel.label = compound.properties.formula.length > 0
            ? compound.properties.formula : "--";
        weightLabel.label = compound.properties.weight > 0
            ? compound.properties.weight.to!string : "--";
        massLabel.label = !isNaN(compound.properties.mass) && compound.properties.mass > 0
            ? compound.properties.mass.to!string : "--";
        chargeLabel.label = compound.properties.formula.length > 0
            ? compound.properties.charge.to!string : "--";
        tpsaLabel.label = !isNaN(compound.properties.tpsa)
            ? compound.properties.tpsa.to!string : "--";
        xlogpLabel.label = !isNaN(compound.properties.xlogp)
            ? compound.properties.xlogp.to!string : "--";
        smilesLabel.label = compound.smiles.length > 0
            ? compound.smiles : "--";
    }

    void reset()
    {
        compoundNameLabel.label = "Select";
        cidLabel.label = "--";
        formulaLabel.label = "--";
        weightLabel.label = "--";
        massLabel.label = "--";
        chargeLabel.label = "--";
        tpsaLabel.label = "--";
        xlogpLabel.label = "--";
        smilesLabel.label = "--";

        currentCompound = null;
        moleculeViewer.setConformer(null);
        hideLoading();
        clearBox(dosageSection);
        dosageSection.visible = false;
    }

    void showLoading()
    {
        clearBox(dosageSection);
        dosageSection.visible = false;
        loadingDotsBox.visible = true;
    }

    void hideLoading()
    {
        loadingDotsBox.visible = false;
    }

    void setDosage(DosageResult result)
    {
        writeln("[Infobox] setDosage called, ",
            result.dosages.length, " routes, source=",
            result.source ? result.source.name : "primary");

        hideLoading();
        clearBox(dosageSection);

        if (result.dosages.length == 0)
        {
            dosageSection.visible = false;
            return;
        }

        Box hdrBox = new Box(Orientation.Horizontal, 4);
        hdrBox.addCssClass("infobox-section-header");
        hdrBox.halign = Align.Fill;

        Label hdr = new Label("Dosage");
        hdr.halign = Align.Start;
        hdr.hexpand = true;
        hdr.xalign = 0;
        hdrBox.append(hdr);

        if (result.source !is null)
        {
            Label sourceLabel = new Label(result.source.name);
            sourceLabel.addCssClass("dosage-similar-warning");
            sourceLabel.halign = Align.End;
            sourceLabel.tooltipText = "Sourced from a similar compound";
            hdrBox.append(sourceLabel);
        }

        dosageSection.append(hdrBox);

        foreach (d; result.dosages)
        {
            Box routeContent = new Box(Orientation.Vertical, 0);
            routeContent.hexpand = true;
            routeContent.halign = Align.Fill;
            appendRow(routeContent, "Bioavail.", d.bioavailability);
            appendRow(routeContent, "Threshold", d.threshold);
            appendRow(routeContent, "Light", d.light);
            appendRow(routeContent, "Common", d.common);
            appendRow(routeContent, "Strong", d.strong);
            appendRow(routeContent, "Heavy", d.heavy);
            dosageSection.append(buildCollapsibleSubheading(d.route, routeContent));
            dosageSection.append(routeContent);
        }

        dosageSection.visible = true;
    }

    private void buildChemicalSection()
    {
        Label sectionHdr = new Label("Chemical");
        sectionHdr.addCssClass("infobox-section-header");
        sectionHdr.halign = Align.Fill;
        sectionHdr.xalign = 0;
        chemicalSection.append(sectionHdr);

        Box idContent = new Box(Orientation.Vertical, 0);
        idContent.hexpand = true;
        idContent.halign = Align.Fill;
        appendLabelRow(idContent, "CID", cidLabel);
        appendLabelRow(idContent, "Formula", formulaLabel);
        // appendLabelRow(idContent, "SMILES", smilesLabel);
        chemicalSection.append(buildCollapsibleSubheading("Identifiers", idContent));
        chemicalSection.append(idContent);

        Box propContent = new Box(Orientation.Vertical, 0);
        propContent.hexpand = true;
        propContent.halign = Align.Fill;
        appendLabelRow(propContent, "Weight", weightLabel);
        appendLabelRow(propContent, "Mass", massLabel);
        appendLabelRow(propContent, "Charge", chargeLabel);
        appendLabelRow(propContent, "TPSA", tpsaLabel);
        appendLabelRow(propContent, "XLogP", xlogpLabel);
        chemicalSection.append(buildCollapsibleSubheading("Properties", propContent));
        chemicalSection.append(propContent);
    }

    private void appendLabelRow(Box parent, string label, Label value)
    {
        Box rowBox = new Box(Orientation.Horizontal, 8);
        rowBox.addCssClass("infobox-row");
        rowBox.hexpand = true;
        rowBox.halign = Align.Fill;

        Label labelWidget = new Label(label);
        labelWidget.addCssClass("infobox-label");
        labelWidget.halign = Align.Start;
        labelWidget.valign = Align.Start;

        value.addCssClass("infobox-value");
        value.halign = Align.End;
        value.hexpand = true;
        value.wrap = true;
        value.maxWidthChars = 8;

        rowBox.append(labelWidget);
        rowBox.append(value);
        parent.append(rowBox);
    }

    private void appendRow(Box parent, string label, string value)
    {
        if (value is null || value.length == 0)
            return;

        Box rowBox = new Box(Orientation.Horizontal, 8);
        rowBox.addCssClass("infobox-row");
        rowBox.hexpand = true;
        rowBox.halign = Align.Fill;

        Label labelWidget = new Label(label);
        labelWidget.addCssClass("infobox-label");
        labelWidget.halign = Align.Start;
        labelWidget.valign = Align.Start;

        Label valueWidget = new Label(value);
        valueWidget.addCssClass("infobox-value");
        valueWidget.halign = Align.End;
        valueWidget.hexpand = true;
        valueWidget.wrap = true;
        valueWidget.maxWidthChars = 8;

        rowBox.append(labelWidget);
        rowBox.append(valueWidget);
        parent.append(rowBox);
    }

    private void clearBox(Box box)
    {
        Widget child = box.getFirstChild();
        while (child !is null)
        {
            Widget next = child.getNextSibling();
            box.remove(child);
            child = next;
        }
    }

    private Box buildLoadingDots()
    {
        Box dots = new Box(Orientation.Horizontal, 1);
        dots.addCssClass("loading-dots");
        dots.halign = Align.Center;
        dots.marginTop = 8;
        dots.marginBottom = 8;

        auto dot1 = new Label(".");
        dot1.addCssClass("dot");
        auto dot2 = new Label(".");
        dot2.addCssClass("dot");
        auto dot3 = new Label(".");
        dot3.addCssClass("dot");

        dots.append(dot1);
        dots.append(dot2);
        dots.append(dot3);
        return dots;
    }

    private Label buildCollapsibleSubheading(string title, Box contentBox)
    {
        Label header = new Label(title);
        header.addCssClass("dosage-route-header");
        header.halign = Align.Start;
        header.xalign = 0;

        contentBox.visible = false;

        GestureClick click = new GestureClick();
        click.connectReleased((int nPress, double x, double y) {
            contentBox.visible = !contentBox.visible;
            header.halign = contentBox.visible ? Align.Fill : Align.Start;
        });
        header.addController(click);

        auto motion = new EventControllerMotion();
        motion.connectMotion((double x, double y) {
            if (!header.hasCssClass("collapsible-hover"))
                header.addCssClass("collapsible-hover");
        });
        motion.connectLeave(() {
            header.removeCssClass("collapsible-hover");
        });
        header.addController(motion);

        return header;
    }

    private void onViewerClicked(int nPress, double x, double y)
    {
        if (onViewerClick !is null)
            onViewerClick();
    }
}
