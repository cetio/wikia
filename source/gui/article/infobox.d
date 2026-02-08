module gui.article.infobox;

import std.conv : to;
import std.stdio : writeln;

import gtk.box;
import gtk.label;
import gtk.button;
import gtk.gesture_click;
import gtk.widget : Widget;
import gtk.types : Orientation, Align;

import wikia.pubchem;
import gui.article.viewer;

class Infobox : Box
{
    private Label compoundNameLabel;
    private Label cidLabel;
    private Label formulaLabel;
    private Label weightLabel;
    private Label smilesLabel;
    private Box dosageSection;
    private MoleculeViewer moleculeViewer;
    private Compound currentCompound;

    void delegate() onViewerClick;

    this()
    {
        super(Orientation.Vertical, 0);
        addCssClass("infobox");
        valign = Align.Start;
        halign = Align.End;
        widthRequest = 90;
        hexpand = false;

        compoundNameLabel = new Label("Select");
        compoundNameLabel.addCssClass("infobox-title");
        compoundNameLabel.wrap = true;
        compoundNameLabel.maxWidthChars = 10;
        compoundNameLabel.hexpand = false;
        append(compoundNameLabel);

        moleculeViewer = new MoleculeViewer();
        moleculeViewer.setContentWidth(88);
        moleculeViewer.setContentHeight(88);
        moleculeViewer.setBaseZoom(10.0);
        moleculeViewer.addCssClass("infobox-viewer-frame");

        GestureClick viewerClick = new GestureClick();
        viewerClick.connectReleased(&onViewerClicked);
        moleculeViewer.addController(viewerClick);

        append(moleculeViewer);

        append(buildSection("Identifiers", ["CID", "Formula", "SMILES"],
            [cidLabel = new Label("--"), formulaLabel = new Label("--"), smilesLabel = new Label("--")]));

        append(buildSection("Properties", ["Weight"], [weightLabel = new Label("--")]));

        dosageSection = new Box(Orientation.Vertical, 0);
        append(dosageSection);
    }

    @property MoleculeViewer getViewer()
    {
        return moleculeViewer;
    }

    void setCompound(Compound compound)
    {
        currentCompound = compound;
        //updateDosage();
    }

    void setConformer(Conformer3D conformer)
    {
        moleculeViewer.setConformer(conformer);
    }

    void update(Compound compound, Conformer3D conformer, string name)
    {
        writeln("[Infobox] update called, name: ", name);
        if (conformer is null || compound is null)
        {
            writeln("[Infobox] Conformer or compound is null, returning");
            return;
        }

        compoundNameLabel.label = name;
        cidLabel.label = compound.cid > 0 ? compound.cid.to!string : "--";
        formulaLabel.label = compound.properties.formula.length > 0 ? compound.properties.formula : "--";
        weightLabel.label = compound.properties.weight > 0 ? compound.properties.weight.to!string : "--";
        smilesLabel.label = compound.smiles.length > 0 ? compound.smiles : "--";

        // updateDosage();
    }

    void reset()
    {
        compoundNameLabel.label = "Select";
        cidLabel.label = "--";
        formulaLabel.label = "--";
        weightLabel.label = "--";
        smilesLabel.label = "--";

        Widget child = dosageSection.getFirstChild();
        while (child !is null)
        {
            dosageSection.remove(child);
            child = dosageSection.getFirstChild();
        }

        currentCompound = null;
        moleculeViewer.setConformer(null);
    }

    // private void updateDosage()
    // {
    //     writeln("[Infobox] updateDosage called");
    //     while (dosageSection.getFirstChild() !is null)
    //     {
    //         dosageSection.remove(dosageSection.getFirstChild());
    //     }

    //     if (currentCompound is null)
    //     {
    //         writeln("[Infobox] No compound, showing no data");
    //         Label noDataLabel = new Label("No dosage data available");
    //         noDataLabel.addCssClass("infobox-value");
    //         dosageSection.append(noDataLabel);
    //         return;
    //     }

    //     writeln("[Infobox] Checking dosage, compound: ", currentCompound.title);
    //     auto dosages = currentCompound.dosage();
    //     if (dosages.length == 0)
    //     {
    //         writeln("[Infobox] No dosage data");
    //         Label noDataLabel = new Label("No dosage data available");
    //         noDataLabel.addCssClass("infobox-value");
    //         dosageSection.append(noDataLabel);
    //         return;
    //     }

    //     writeln("[Infobox] Processing ", dosages.length, " dosages");
    //     foreach (d; dosages)
    //     {
    //         if (d.threshold is null && d.light is null && d.common is null &&
    //             d.strong is null && d.heavy is null)
    //             continue;

    //         string r = d.route !is null ? d.route : "Unknown";
    //         writeln("[Infobox] Adding route: ", r);

    //         Label hdr = new Label(r);
    //         hdr.addCssClass("infobox-section-header");
    //         hdr.halign = Align.Fill;
    //         hdr.xalign = 0;
    //         dosageSection.append(hdr);

    //         if (d.threshold !is null)
    //             dosageSection.append(buildDosageRow("Threshold", d.threshold));
    //         if (d.light !is null)
    //             dosageSection.append(buildDosageRow("Light", d.light));
    //         if (d.common !is null)
    //             dosageSection.append(buildDosageRow("Common", d.common));
    //         if (d.strong !is null)
    //             dosageSection.append(buildDosageRow("Strong", d.strong));
    //         if (d.heavy !is null)
    //             dosageSection.append(buildDosageRow("Heavy", d.heavy));
    //     }
    //     writeln("[Infobox] updateDosage completed");
    // }

    // private Box buildDosageRow(string label, string value)
    // {
    //     Box rowBox = new Box(Orientation.Horizontal, 8);
    //     rowBox.addCssClass("infobox-row");

    //     Label labelWidget = new Label(label);
    //     labelWidget.addCssClass("infobox-label");
    //     labelWidget.halign = Align.Start;
    //     labelWidget.valign = Align.Start;

    //     Label valueWidget = new Label(value);
    //     valueWidget.addCssClass("infobox-value");
    //     valueWidget.halign = Align.End;
    //     valueWidget.hexpand = true;
    //     valueWidget.wrap = true;
    //     valueWidget.maxWidthChars = 8;

    //     rowBox.append(labelWidget);
    //     rowBox.append(valueWidget);

    //     return rowBox;
    // }

    private void onViewerClicked(int nPress, double x, double y)
    {
        if (onViewerClick !is null)
            onViewerClick();
    }

    private Box buildSection(string title, string[] labels, Label[] values)
    {
        Box section = new Box(Orientation.Vertical, 0);

        Label hdr = new Label(title);
        hdr.addCssClass("infobox-section-header");
        hdr.halign = Align.Fill;
        hdr.xalign = 0;
        section.append(hdr);

        foreach (i, label; labels)
        {
            Box rowBox = new Box(Orientation.Horizontal, 8);
            rowBox.addCssClass("infobox-row");

            Label labelWidget = new Label(label);
            labelWidget.addCssClass("infobox-label");
            labelWidget.halign = Align.Start;
            labelWidget.valign = Align.Start;

            values[i].addCssClass("infobox-value");
            values[i].halign = Align.End;
            values[i].hexpand = true;
            values[i].wrap = true;
            values[i].maxWidthChars = 8;

            rowBox.append(labelWidget);
            rowBox.append(values[i]);
            section.append(rowBox);
        }

        return section;
    }
}
