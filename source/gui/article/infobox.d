module gui.article.infobox;

import std.conv : to;
import std.math : isNaN;
import std.stdio : writeln;

import gtk.box;
import gtk.event_controller_motion;
import gtk.gesture_click;
import gtk.label;
import gtk.button;
import gtk.overlay;
import gtk.types : Align, Orientation;
import gtk.widget : Widget;

import gui.conformer.view;
import gui.background : Background;
import wikia.pubchem;
import wikia.psychonaut : Dosage, DosageResult;

class Infobox : Overlay
{
private:
    Label titleLabel;
    Label cidLabel;
    Label formulaLabel;
    Label weightLabel;
    Label massLabel;
    Label chargeLabel;
    Label tpsaLabel;
    Label xlogpLabel;
    Label smilesLabel;
    Label dosageLabel;
    Box secChemical;
    Box secDosage;
    Box loadingDots;

public:
    Box subject;
    Box details;
    Compound compound;
    MoleculeView moleculeView;

    this(MoleculeView moleculeView)
    {
        super();
        addCssClass("infobox");
        valign = Align.Start;
        halign = Align.End;
        widthRequest = 80;
        hexpand = false;

        subject = new Box(Orientation.Vertical, 0);
        subject.addCssClass("infobox-subject");
        subject.heightRequest = 2;

        titleLabel = new Label("Unknown");
        titleLabel.addCssClass("infobox-title");
        titleLabel.wrap = true;
        titleLabel.maxWidthChars = 10;
        titleLabel.hexpand = true;
        subject.append(titleLabel);

        this.moleculeView = moleculeView;
        moleculeView.setContentHeight(88);
        moleculeView.setContentWidth(88);
        setupMView();

        details = new Box(Orientation.Vertical, 0);
        details.addCssClass("infobox-details");
        details.widthRequest = 240;

        secChemical = new Box(Orientation.Vertical, 0);
        secChemical.hexpand = true;
        secChemical.halign = Align.Fill;
        cidLabel = new Label("--");
        formulaLabel = new Label("--");
        weightLabel = new Label("--");
        massLabel = new Label("--");
        chargeLabel = new Label("--");
        tpsaLabel = new Label("--");
        xlogpLabel = new Label("--");
        smilesLabel = new Label("--");
        buildChemicalSection();
        details.append(secChemical);

        loadingDots = buildLoadingDots();
        loadingDots.visible = false;
        details.append(loadingDots);

        secDosage = new Box(Orientation.Vertical, 0);
        secDosage.hexpand = true;
        secDosage.halign = Align.Fill;
        secDosage.visible = false;
        details.append(secDosage);
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

        Box root = new Box(Orientation.Vertical, 0);
        root.append(subject);
        root.append(details);
        
        setChild(root);
    }

    void update(Compound compound)
    {
        writeln("[Infobox] update called");
        if (compound is null)
            return;

        writeln("[Infobox] Compound: ", compound.name);
        this.compound = compound;
        moleculeView.setCompound(compound);

        titleLabel.label = compound.name;
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

    final void setupMView()
    {
        moleculeView.setBaseZoom(10.0);
        moleculeView.addCssClass("Y");
        moleculeView.hexpand = false;
        moleculeView.vexpand = false;
        moleculeView.disableMotionControl();
        subject.append(moleculeView);
    }

    void reset()
    {
        titleLabel.label = "Select";
        cidLabel.label = "--";
        formulaLabel.label = "--";
        weightLabel.label = "--";
        massLabel.label = "--";
        chargeLabel.label = "--";
        tpsaLabel.label = "--";
        xlogpLabel.label = "--";
        smilesLabel.label = "--";

        compound = null;
        moleculeView.setCompound(null);
        hideLoading();
        clearBox(secDosage);
        secDosage.visible = false;
    }

    void showLoading()
    {
        clearBox(secDosage);
        secDosage.visible = false;
        loadingDots.visible = true;
    }

    void hideLoading()
    {
        loadingDots.visible = false;
    }

    void setDosage(DosageResult result)
    {
        writeln("[Infobox] setDosage called, ",
            result.dosages.length, " routes, source=",
            result.source ? result.source.name : "primary");

        hideLoading();
        clearBox(secDosage);

        if (result.dosages.length == 0)
        {
            secDosage.visible = false;
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

        secDosage.append(hdrBox);

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
            secDosage.append(buildCollapsibleSubheading(d.route, routeContent));
            secDosage.append(routeContent);
        }

        secDosage.visible = true;
    }

    private void buildChemicalSection()
    {
        Label sectionHdr = new Label("Chemical");
        sectionHdr.addCssClass("infobox-section-header");
        sectionHdr.halign = Align.Fill;
        sectionHdr.xalign = 0;
        secChemical.append(sectionHdr);

        Box idContent = new Box(Orientation.Vertical, 0);
        idContent.hexpand = true;
        idContent.halign = Align.Fill;
        appendLabelRow(idContent, "CID", cidLabel);
        appendLabelRow(idContent, "Formula", formulaLabel);
        // appendLabelRow(idContent, "SMILES", smilesLabel);
        secChemical.append(buildCollapsibleSubheading("Identifiers", idContent));
        secChemical.append(idContent);

        Box propContent = new Box(Orientation.Vertical, 0);
        propContent.hexpand = true;
        propContent.halign = Align.Fill;
        appendLabelRow(propContent, "Weight", weightLabel);
        appendLabelRow(propContent, "Mass", massLabel);
        appendLabelRow(propContent, "Charge", chargeLabel);
        appendLabelRow(propContent, "TPSA", tpsaLabel);
        appendLabelRow(propContent, "XLogP", xlogpLabel);
        secChemical.append(buildCollapsibleSubheading("Properties", propContent));
        secChemical.append(propContent);
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
}
